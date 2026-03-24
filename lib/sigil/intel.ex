defmodule Sigil.Intel do
  @moduledoc """
  Tribe-scoped intel CRUD with ETS cache and PubSub fan-out.
  """

  import Ecto.Query

  alias Sigil.Cache
  alias Sigil.Intel.IntelReport
  alias Sigil.Repo

  @intel_topic_prefix "intel:"

  @typedoc "Options accepted by intel context functions."
  @type option() ::
          {:tables, %{intel: Cache.table_id()}}
          | {:pubsub, atom() | module()}
          | {:authorized_tribe_id, integer()}

  @type options() :: [option()]

  @typedoc "Delete authorization payload supplied by the caller."
  @type delete_params() :: %{
          required(:tribe_id) => integer(),
          required(:reported_by) => String.t(),
          required(:is_leader_or_operator) => boolean()
        }

  @doc "Creates or replaces a location report for a tribe assembly."
  @spec report_location(map(), options()) ::
          {:ok, IntelReport.t()} | {:error, Ecto.Changeset.t() | :unauthorized}
  def report_location(%{tribe_id: tribe_id} = params, opts) when is_list(opts) do
    with true <- authorized_tribe?(tribe_id, opts),
         changeset <- IntelReport.location_changeset(%IntelReport{}, params),
         {:ok, report} <-
           Repo.insert(changeset,
             on_conflict: :replace_all,
             conflict_target:
               {:unsafe_fragment,
                "(tribe_id, assembly_id) WHERE report_type = 'location' AND assembly_id IS NOT NULL"},
             returning: true
           ) do
      Cache.put(
        intel_table(opts),
        location_cache_key(report.tribe_id, report.assembly_id),
        report
      )

      broadcast(opts, report.tribe_id, {:intel_updated, report})
      {:ok, report}
    else
      false -> {:error, :unauthorized}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc "Creates a scouting report for a tribe."
  @spec report_scouting(map(), options()) ::
          {:ok, IntelReport.t()} | {:error, Ecto.Changeset.t() | :unauthorized}
  def report_scouting(%{tribe_id: tribe_id} = params, opts) when is_list(opts) do
    with true <- authorized_tribe?(tribe_id, opts),
         changeset <- IntelReport.scouting_changeset(%IntelReport{}, params),
         {:ok, report} <- Repo.insert(changeset) do
      broadcast(opts, report.tribe_id, {:intel_updated, report})
      {:ok, report}
    else
      false -> {:error, :unauthorized}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc "Returns the PubSub topic for a tribe's intel stream."
  @spec topic(integer()) :: String.t()
  def topic(tribe_id) when is_integer(tribe_id),
    do: @intel_topic_prefix <> Integer.to_string(tribe_id)

  @doc "Lists intel reports for the authorized tribe ordered newest first."
  @spec list_intel(integer(), options()) :: [IntelReport.t()]
  def list_intel(tribe_id, opts) when is_integer(tribe_id) and is_list(opts) do
    if authorized_tribe?(tribe_id, opts) do
      Repo.all(
        from report in IntelReport,
          where: report.tribe_id == ^tribe_id,
          order_by: [desc: report.updated_at, desc: report.inserted_at]
      )
    else
      []
    end
  end

  @doc "Returns a cached location report or loads it from Postgres on a cache miss."
  @spec get_location(integer(), String.t(), options()) :: IntelReport.t() | nil
  def get_location(tribe_id, assembly_id, opts)
      when is_integer(tribe_id) and is_binary(assembly_id) and is_list(opts) do
    if authorized_tribe?(tribe_id, opts) do
      key = location_cache_key(tribe_id, assembly_id)

      case Cache.get(intel_table(opts), key) do
        %IntelReport{} = report ->
          report

        nil ->
          case Repo.one(
                 from report in IntelReport,
                   where:
                     report.tribe_id == ^tribe_id and report.assembly_id == ^assembly_id and
                       report.report_type == :location
               ) do
            %IntelReport{} = report ->
              Cache.put(intel_table(opts), key, report)
              report

            nil ->
              nil
          end
      end
    else
      nil
    end
  end

  @doc "Deletes an intel report when the caller is authorized to remove it."
  @spec delete_intel(Ecto.UUID.t(), delete_params(), options()) ::
          :ok | {:error, :not_found | :unauthorized}
  def delete_intel(id, %{tribe_id: tribe_id, reported_by: reported_by} = params, opts)
      when is_binary(id) and is_integer(tribe_id) and is_binary(reported_by) and is_list(opts) do
    with %IntelReport{} = report <- Repo.get(IntelReport, id),
         true <- authorized_tribe?(tribe_id, opts),
         true <- report.tribe_id == tribe_id,
         true <- can_delete?(report, params),
         {:ok, %IntelReport{} = deleted_report} <- Repo.delete(report) do
      maybe_delete_cached_location(opts, deleted_report)
      broadcast(opts, deleted_report.tribe_id, {:intel_deleted, deleted_report})
      :ok
    else
      nil -> {:error, :not_found}
      false -> {:error, :unauthorized}
      {:error, _changeset} -> {:error, :not_found}
    end
  end

  @doc "Warms the location cache for the authorized tribe."
  @spec load_cache(integer(), options()) :: :ok
  def load_cache(tribe_id, opts) when is_integer(tribe_id) and is_list(opts) do
    if authorized_tribe?(tribe_id, opts) do
      Repo.all(
        from report in IntelReport,
          where: report.tribe_id == ^tribe_id and report.report_type == :location
      )
      |> Enum.each(fn report ->
        Cache.put(intel_table(opts), location_cache_key(tribe_id, report.assembly_id), report)
      end)
    end

    :ok
  end

  @doc "Exports an intel report into the deterministic fields used for commitment hashing."
  @spec export_for_commitment(IntelReport.t()) :: %{
          report_type: 1 | 2,
          solar_system_id: integer() | nil,
          assembly_id: String.t(),
          notes: String.t()
        }
  def export_for_commitment(%IntelReport{} = report) do
    %{
      report_type: export_report_type(report.report_type),
      solar_system_id: report.solar_system_id,
      assembly_id: normalize_assembly_id(report.assembly_id),
      notes: report.notes || ""
    }
  end

  @spec intel_table(options()) :: Cache.table_id()
  defp intel_table(opts) do
    opts |> Keyword.fetch!(:tables) |> Map.fetch!(:intel)
  end

  @spec authorized_tribe?(integer(), options()) :: boolean()
  defp authorized_tribe?(tribe_id, opts) do
    tribe_id == Keyword.fetch!(opts, :authorized_tribe_id)
  end

  @spec can_delete?(IntelReport.t(), delete_params()) :: boolean()
  defp can_delete?(report, %{
         reported_by: reported_by,
         is_leader_or_operator: is_leader_or_operator
       }) do
    report.reported_by == reported_by or is_leader_or_operator
  end

  @spec maybe_delete_cached_location(options(), IntelReport.t()) :: :ok
  defp maybe_delete_cached_location(opts, %IntelReport{
         report_type: :location,
         assembly_id: assembly_id,
         tribe_id: tribe_id
       })
       when is_binary(assembly_id) do
    case Keyword.fetch(opts, :tables) do
      {:ok, tables} ->
        if is_map(tables) and Map.has_key?(tables, :intel) do
          Cache.delete(intel_table(opts), location_cache_key(tribe_id, assembly_id))
        else
          :ok
        end

      _other ->
        :ok
    end
  end

  defp maybe_delete_cached_location(_opts, _report), do: :ok

  @spec location_cache_key(integer(), String.t()) :: {:location, integer(), String.t()}
  defp location_cache_key(tribe_id, assembly_id), do: {:location, tribe_id, assembly_id}

  @spec export_report_type(IntelReport.report_type()) :: 1 | 2
  defp export_report_type(:location), do: 1
  defp export_report_type(:scouting), do: 2

  @spec normalize_assembly_id(String.t() | nil) :: String.t()
  defp normalize_assembly_id(nil), do: ""

  defp normalize_assembly_id(assembly_id) do
    normalized = String.downcase(assembly_id)

    case normalized do
      "0x" <> suffix -> "0x" <> suffix
      _other -> "0x" <> normalized
    end
  end

  @spec broadcast(options(), integer(), term()) :: :ok | {:error, term()}
  defp broadcast(opts, tribe_id, event) do
    pubsub = Keyword.get(opts, :pubsub, Sigil.PubSub)
    Phoenix.PubSub.broadcast(pubsub, topic(tribe_id), event)
  end
end
