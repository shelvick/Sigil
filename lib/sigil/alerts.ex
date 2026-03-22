defmodule Sigil.Alerts do
  @moduledoc """
  Repo-backed alert lifecycle and webhook configuration context.
  """

  import Ecto.Query

  alias Sigil.Alerts.{Alert, WebhookConfig}
  alias Sigil.Repo

  @default_cooldown_ms 14_400_000

  @typedoc "Options accepted by alerts context functions."
  @type option() :: {:pubsub, atom() | module()} | {:cooldown_ms, non_neg_integer()}
  @type options() :: [option()]

  @doc "Creates a new alert unless an active duplicate or cooldown suppresses it."
  @spec create_alert(map(), options()) ::
          {:ok, Alert.t()} | {:ok, :duplicate} | {:ok, :cooldown} | {:error, Ecto.Changeset.t()}
  def create_alert(attrs, opts) when is_map(attrs) and is_list(opts) do
    assembly_id = attr(attrs, :assembly_id)
    type = attr(attrs, :type)

    case {missing_dedup_key?(assembly_id), missing_dedup_key?(type)} do
      {true, _} ->
        insert_alert(attrs, opts)

      {_, true} ->
        insert_alert(attrs, opts)

      {false, false} ->
        create_deduped_alert(attrs, assembly_id, type, opts)
    end
  end

  @doc "Lists alerts for the provided filters ordered newest first."
  @spec list_alerts(keyword(), options()) :: [Alert.t()]
  def list_alerts(filters, _opts) when is_list(filters) do
    filters
    |> alerts_query()
    |> order_by([a], desc: a.inserted_at, desc: a.id)
    |> limit(^Keyword.get(filters, :limit, 50))
    |> Repo.all()
  end

  @doc "Fetches a single alert by id."
  @spec get_alert(integer(), options()) :: Alert.t() | nil
  def get_alert(id, _opts) when is_integer(id) do
    Repo.get(Alert, id)
  end

  @doc "Acknowledges a new alert and broadcasts the lifecycle event."
  @spec acknowledge_alert(integer(), options()) :: {:ok, Alert.t()} | {:error, :not_found}
  def acknowledge_alert(id, opts) when is_integer(id) and is_list(opts) do
    case Repo.get(Alert, id) do
      nil ->
        {:error, :not_found}

      %Alert{status: "new"} = alert ->
        alert
        |> Alert.status_changeset(%{"status" => "acknowledged"})
        |> Repo.update()
        |> maybe_broadcast(:alert_acknowledged, opts)

      %Alert{} = alert ->
        {:ok, alert}
    end
  end

  @doc "Dismisses an alert, preserving the first dismissal timestamp."
  @spec dismiss_alert(integer(), options()) :: {:ok, Alert.t()} | {:error, :not_found}
  def dismiss_alert(id, opts) when is_integer(id) and is_list(opts) do
    case Repo.get(Alert, id) do
      nil ->
        {:error, :not_found}

      %Alert{status: "dismissed"} = alert ->
        {:ok, alert}

      %Alert{} = alert ->
        dismissed_at = DateTime.utc_now()

        alert
        |> Alert.status_changeset(%{"status" => "dismissed", "dismissed_at" => dismissed_at})
        |> Repo.update()
        |> maybe_broadcast(:alert_dismissed, opts)
    end
  end

  @doc "Counts unread alerts for an account."
  @spec unread_count(String.t(), options()) :: non_neg_integer()
  def unread_count(account_address, _opts) when is_binary(account_address) do
    from(a in Alert,
      where: a.account_address == ^account_address and a.status == "new",
      select: count(a.id)
    )
    |> Repo.one()
  end

  @doc "Returns true when an active alert exists for an assembly and type."
  @spec active_alert_exists?(String.t(), String.t(), options()) :: boolean()
  def active_alert_exists?(assembly_id, type, _opts)
      when is_binary(assembly_id) and is_binary(type) do
    from(a in Alert,
      where:
        a.assembly_id == ^assembly_id and a.type == ^type and
          a.status in ["new", "acknowledged"]
    )
    |> Repo.exists?()
  end

  @doc "Fetches a webhook configuration for a tribe."
  @spec get_webhook_config(integer(), options()) :: WebhookConfig.t() | nil
  def get_webhook_config(tribe_id, _opts) when is_integer(tribe_id) do
    Repo.get_by(WebhookConfig, tribe_id: tribe_id)
  end

  @doc "Creates or updates a tribe webhook configuration atomically."
  @spec upsert_webhook_config(integer(), map(), options()) ::
          {:ok, WebhookConfig.t()} | {:error, Ecto.Changeset.t()}
  def upsert_webhook_config(tribe_id, attrs, _opts) when is_integer(tribe_id) and is_map(attrs) do
    attrs = Map.put(attrs, "tribe_id", tribe_id)
    changeset = WebhookConfig.changeset(%WebhookConfig{}, attrs)

    if changeset.valid? do
      config = Ecto.Changeset.apply_changes(changeset)
      now = DateTime.utc_now()

      Repo.insert(changeset,
        on_conflict: [
          set: [
            webhook_url: config.webhook_url,
            service_type: config.service_type,
            enabled: config.enabled,
            updated_at: now
          ]
        ],
        conflict_target: [:tribe_id],
        returning: true
      )
    else
      {:error, changeset}
    end
  end

  @doc "Deletes dismissed alerts older than the provided day threshold."
  @spec purge_old_dismissed(non_neg_integer(), options()) :: {non_neg_integer(), nil}
  def purge_old_dismissed(days, _opts) when is_integer(days) and days >= 0 do
    cutoff = DateTime.add(DateTime.utc_now(), -days * 86_400, :second)

    from(a in Alert,
      where: a.status == "dismissed" and not is_nil(a.dismissed_at) and a.dismissed_at < ^cutoff
    )
    |> Repo.delete_all()
  end

  @spec create_deduped_alert(map(), String.t(), String.t(), options()) ::
          {:ok, Alert.t()} | {:ok, :duplicate} | {:ok, :cooldown} | {:error, Ecto.Changeset.t()}
  defp create_deduped_alert(attrs, assembly_id, type, opts) do
    case {active_alert_exists?(assembly_id, type, opts),
          cooldown_active?(assembly_id, type, cooldown_ms(opts))} do
      {true, _} -> {:ok, :duplicate}
      {false, true} -> {:ok, :cooldown}
      {false, false} -> insert_alert(attrs, opts)
    end
  end

  @spec insert_alert(map(), options()) ::
          {:ok, Alert.t()} | {:ok, :duplicate} | {:error, Ecto.Changeset.t()}
  defp insert_alert(attrs, opts) do
    attrs = Map.put(attrs, "status", "new")

    %Alert{}
    |> Alert.changeset(attrs)
    |> Repo.insert()
    |> maybe_broadcast(:alert_created, opts)
  rescue
    error in Ecto.ConstraintError ->
      if duplicate_constraint?(error) do
        {:ok, :duplicate}
      else
        reraise error, __STACKTRACE__
      end
  end

  @spec alerts_query(keyword()) :: Ecto.Query.t()
  defp alerts_query(filters) do
    Alert
    |> maybe_filter_account(Keyword.get(filters, :account_address))
    |> maybe_filter_status(Keyword.get(filters, :status))
    |> maybe_filter_type(Keyword.get(filters, :type))
    |> maybe_filter_tribe(Keyword.get(filters, :tribe_id))
    |> maybe_filter_before_id(Keyword.get(filters, :before_id))
  end

  @spec maybe_filter_account(Ecto.Queryable.t(), String.t() | nil) :: Ecto.Query.t()
  defp maybe_filter_account(query, nil), do: from(a in query)

  defp maybe_filter_account(query, account_address),
    do: from(a in query, where: a.account_address == ^account_address)

  @spec maybe_filter_status(Ecto.Queryable.t(), String.t() | [String.t()] | nil) :: Ecto.Query.t()
  defp maybe_filter_status(query, nil), do: from(a in query)

  defp maybe_filter_status(query, statuses) when is_list(statuses),
    do: from(a in query, where: a.status in ^statuses)

  defp maybe_filter_status(query, status), do: from(a in query, where: a.status == ^status)

  @spec maybe_filter_type(Ecto.Queryable.t(), String.t() | nil) :: Ecto.Query.t()
  defp maybe_filter_type(query, nil), do: from(a in query)
  defp maybe_filter_type(query, type), do: from(a in query, where: a.type == ^type)

  @spec maybe_filter_tribe(Ecto.Queryable.t(), integer() | nil) :: Ecto.Query.t()
  defp maybe_filter_tribe(query, nil), do: from(a in query)
  defp maybe_filter_tribe(query, tribe_id), do: from(a in query, where: a.tribe_id == ^tribe_id)

  @spec maybe_filter_before_id(Ecto.Queryable.t(), integer() | nil) :: Ecto.Query.t()
  defp maybe_filter_before_id(query, nil), do: from(a in query)
  defp maybe_filter_before_id(query, before_id), do: from(a in query, where: a.id < ^before_id)

  @spec maybe_broadcast(
          {:ok, Alert.t()} | {:ok, :duplicate} | {:error, Ecto.Changeset.t()},
          atom(),
          options()
        ) ::
          {:ok, Alert.t()} | {:ok, :duplicate} | {:error, Ecto.Changeset.t()}
  defp maybe_broadcast({:ok, %Alert{} = alert} = result, event, opts) do
    pubsub = Keyword.get(opts, :pubsub, Sigil.PubSub)
    Phoenix.PubSub.broadcast(pubsub, alert_topic(alert.account_address), {event, alert})
    result
  end

  defp maybe_broadcast(result, _event, _opts), do: result

  @spec alert_topic(String.t()) :: String.t()
  defp alert_topic(account_address), do: "alerts:#{account_address}"

  @spec cooldown_active?(String.t(), String.t(), non_neg_integer()) :: boolean()
  defp cooldown_active?(assembly_id, type, cooldown_ms) do
    case latest_dismissed_at(assembly_id, type) do
      %DateTime{} = dismissed_at ->
        DateTime.diff(DateTime.utc_now(), dismissed_at, :millisecond) < cooldown_ms

      nil ->
        false
    end
  end

  @spec latest_dismissed_at(String.t(), String.t()) :: DateTime.t() | nil
  defp latest_dismissed_at(assembly_id, type) do
    from(a in Alert,
      where: a.assembly_id == ^assembly_id and a.type == ^type and a.status == "dismissed",
      where: not is_nil(a.dismissed_at),
      order_by: [desc: a.dismissed_at, desc: a.id],
      limit: 1,
      select: a.dismissed_at
    )
    |> Repo.one()
  end

  @spec cooldown_ms(options()) :: non_neg_integer()
  defp cooldown_ms(opts), do: Keyword.get(opts, :cooldown_ms, @default_cooldown_ms)

  @spec attr(map(), atom()) :: term()
  defp attr(attrs, key), do: Map.get(attrs, Atom.to_string(key)) || Map.get(attrs, key)

  @spec missing_dedup_key?(term()) :: boolean()
  defp missing_dedup_key?(value), do: is_nil(value) or value == ""

  @spec duplicate_constraint?(Exception.t()) :: boolean()
  defp duplicate_constraint?(%Ecto.ConstraintError{constraint: constraint}) do
    constraint in ["alerts_active_unique_index", :alerts_active_unique_index]
  end
end
