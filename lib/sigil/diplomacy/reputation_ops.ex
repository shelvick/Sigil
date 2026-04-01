defmodule Sigil.Diplomacy.ReputationOps do
  @moduledoc """
  Reputation pinning and score cache helpers for diplomacy flows.
  """

  alias Sigil.Cache
  alias Sigil.Repo
  alias Sigil.Diplomacy.ObjectCodec
  alias Sigil.Reputation.ReputationScore
  alias Sigil.Worlds

  @reputation_topic "reputation"

  @typedoc "Convenience alias for diplomacy options."
  @type options() :: Sigil.Diplomacy.options()

  @doc "Pins a reputation-derived standing override for a target tribe."
  @spec pin_standing(non_neg_integer(), Sigil.Diplomacy.standing_atom(), options()) ::
          :ok | {:error, term()}
  def pin_standing(target_tribe_id, standing, opts)
      when is_integer(target_tribe_id) and is_list(opts) do
    with :ok <- ensure_leader(opts),
         {:ok, reputation_table} <- fetch_reputation_table(opts),
         {:ok, standing_value} <- standing_atom_to_value(standing),
         {:ok, db_score} <- upsert_pin_state(target_tribe_id, true, standing_value, opts) do
      source_tribe = source_tribe_id(opts)

      updated_score =
        opts
        |> existing_reputation_score(target_tribe_id)
        |> put_if_missing(:score, db_score)
        |> normalize_reputation_score(source_tribe, target_tribe_id)
        |> Map.merge(%{
          tribe_id: source_tribe,
          target_tribe_id: target_tribe_id,
          pinned: true,
          pinned_standing: standing,
          updated_at: DateTime.utc_now()
        })

      Cache.put(
        reputation_table,
        {:reputation_score, source_tribe, target_tribe_id},
        updated_score
      )

      Phoenix.PubSub.broadcast(
        Keyword.get(opts, :pubsub, Sigil.PubSub),
        reputation_topic(opts),
        {:reputation_pinned, %{tribe_id: source_tribe, target_tribe_id: target_tribe_id}}
      )

      :ok
    end
  end

  @doc "Clears a pinned standing override for a target tribe."
  @spec unpin_standing(non_neg_integer(), options()) :: :ok | {:error, term()}
  def unpin_standing(target_tribe_id, opts) when is_integer(target_tribe_id) and is_list(opts) do
    with :ok <- ensure_leader(opts),
         {:ok, reputation_table} <- fetch_reputation_table(opts),
         {:ok, db_score} <- upsert_pin_state(target_tribe_id, false, nil, opts) do
      source_tribe = source_tribe_id(opts)

      updated_score =
        opts
        |> existing_reputation_score(target_tribe_id)
        |> put_if_missing(:score, db_score)
        |> normalize_reputation_score(source_tribe, target_tribe_id)
        |> Map.merge(%{
          tribe_id: source_tribe,
          target_tribe_id: target_tribe_id,
          pinned: false,
          pinned_standing: nil,
          updated_at: DateTime.utc_now()
        })

      Cache.put(
        reputation_table,
        {:reputation_score, source_tribe, target_tribe_id},
        updated_score
      )

      Phoenix.PubSub.broadcast(
        Keyword.get(opts, :pubsub, Sigil.PubSub),
        reputation_topic(opts),
        {:reputation_unpinned, %{tribe_id: source_tribe, target_tribe_id: target_tribe_id}}
      )

      :ok
    end
  end

  @doc "Returns true when a target tribe has a pinned standing override."
  @spec pinned?(non_neg_integer(), options()) :: boolean()
  def pinned?(target_tribe_id, opts) when is_integer(target_tribe_id) and is_list(opts) do
    case get_reputation_score(target_tribe_id, opts) do
      %{pinned: true} -> true
      _other -> false
    end
  end

  @doc "Returns the cached reputation score entry for a target tribe."
  @spec get_reputation_score(non_neg_integer(), options()) ::
          Sigil.Diplomacy.reputation_score() | nil
  def get_reputation_score(target_tribe_id, opts)
      when is_integer(target_tribe_id) and is_list(opts) do
    with {:ok, reputation_table} <- fetch_reputation_table(opts) do
      source_tribe = source_tribe_id(opts)

      Cache.get(reputation_table, {:reputation_score, source_tribe, target_tribe_id})
      |> normalize_reputation_score(source_tribe, target_tribe_id)
    else
      {:error, :reputation_table_unavailable} -> nil
    end
  end

  @doc "Lists all cached reputation score entries for the active source tribe."
  @spec list_reputation_scores(options()) :: [Sigil.Diplomacy.reputation_score()]
  def list_reputation_scores(opts) when is_list(opts) do
    with {:ok, reputation_table} <- fetch_reputation_table(opts) do
      source_tribe = source_tribe_id(opts)

      reputation_table
      |> Cache.match({{:reputation_score, source_tribe, :_}, :_})
      |> Enum.map(fn {{:reputation_score, ^source_tribe, target_tribe_id}, score_data} ->
        normalize_reputation_score(score_data, source_tribe, target_tribe_id)
      end)
    else
      {:error, :reputation_table_unavailable} -> []
    end
  end

  @spec fetch_reputation_table(options()) ::
          {:ok, Cache.table_id()} | {:error, :reputation_table_unavailable}
  defp fetch_reputation_table(opts) do
    case opts |> Keyword.fetch!(:tables) |> Map.fetch(:reputation) do
      {:ok, table} -> {:ok, table}
      :error -> {:error, :reputation_table_unavailable}
    end
  end

  @spec source_tribe_id(options()) :: non_neg_integer()
  defp source_tribe_id(opts) do
    case Keyword.fetch(opts, :tribe_id) do
      {:ok, tribe_id} -> tribe_id
      :error -> raise KeyError, key: :tribe_id, term: opts
    end
  end

  @spec standing_atom_to_value(Sigil.Diplomacy.standing_atom()) ::
          {:ok, Sigil.Diplomacy.standing_value()} | {:error, :invalid_standing}
  defp standing_atom_to_value(:hostile), do: {:ok, 0}
  defp standing_atom_to_value(:unfriendly), do: {:ok, 1}
  defp standing_atom_to_value(:neutral), do: {:ok, 2}
  defp standing_atom_to_value(:friendly), do: {:ok, 3}
  defp standing_atom_to_value(:allied), do: {:ok, 4}
  defp standing_atom_to_value(_invalid), do: {:error, :invalid_standing}

  @spec upsert_pin_state(
          non_neg_integer(),
          boolean(),
          Sigil.Diplomacy.standing_value() | nil,
          options()
        ) ::
          {:ok, integer()} | {:error, term()}
  defp upsert_pin_state(target_tribe_id, pinned, pinned_standing, opts) do
    source_tribe = source_tribe_id(opts)
    existing = get_reputation_score(target_tribe_id, opts)

    persisted_score =
      case Repo.get_by(ReputationScore,
             source_tribe_id: source_tribe,
             target_tribe_id: target_tribe_id
           ) do
        %ReputationScore{score: score} when is_integer(score) -> score
        _other -> 0
      end

    score = if(existing && is_integer(existing.score), do: existing.score, else: persisted_score)

    attrs = %{
      source_tribe_id: source_tribe,
      target_tribe_id: target_tribe_id,
      score: score,
      pinned: pinned,
      pinned_standing: pinned_standing
    }

    changeset = ReputationScore.changeset(%ReputationScore{}, attrs)

    case Repo.insert(changeset,
           on_conflict: [
             set: [
               pinned: pinned,
               pinned_standing: pinned_standing,
               updated_at: DateTime.utc_now()
             ]
           ],
           conflict_target: [:source_tribe_id, :target_tribe_id]
         ) do
      {:ok, row} -> {:ok, row.score || score}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec existing_reputation_score(options(), non_neg_integer()) :: map() | nil
  defp existing_reputation_score(opts, target_tribe_id) do
    with {:ok, reputation_table} <- fetch_reputation_table(opts) do
      Cache.get(reputation_table, {:reputation_score, source_tribe_id(opts), target_tribe_id})
    else
      _ -> nil
    end
  end

  @spec normalize_reputation_score(
          map() | ReputationScore.t() | nil,
          non_neg_integer(),
          non_neg_integer()
        ) :: Sigil.Diplomacy.reputation_score() | nil
  defp normalize_reputation_score(nil, _source_tribe_id, _target_tribe_id), do: nil

  defp normalize_reputation_score(score_data, source_tribe_id, target_tribe_id) do
    score_map = if(is_struct(score_data), do: Map.from_struct(score_data), else: score_data)
    score_value = score_map[:score] || 0
    pinned_standing_value = score_map[:pinned_standing]

    %{
      tribe_id: score_map[:tribe_id] || score_map[:source_tribe_id] || source_tribe_id,
      target_tribe_id: score_map[:target_tribe_id] || target_tribe_id,
      score: score_value,
      pinned: score_map[:pinned] || false,
      pinned_standing: maybe_standing_atom(pinned_standing_value),
      updated_at: score_map[:updated_at]
    }
  end

  @spec maybe_standing_atom(Sigil.Diplomacy.standing_atom() | integer() | nil) ::
          Sigil.Diplomacy.standing_atom() | nil
  defp maybe_standing_atom(nil), do: nil

  defp maybe_standing_atom(standing)
       when standing in [:hostile, :unfriendly, :neutral, :friendly, :allied],
       do: standing

  defp maybe_standing_atom(standing) when is_integer(standing),
    do: ObjectCodec.standing_to_atom(standing)

  defp maybe_standing_atom(_invalid), do: nil

  @spec put_if_missing(map() | nil, atom(), term()) :: map()
  defp put_if_missing(nil, key, value), do: %{key => value}

  defp put_if_missing(map, key, value) do
    if Map.has_key?(map, key) and not is_nil(map[key]) do
      map
    else
      Map.put(map, key, value)
    end
  end

  @spec ensure_leader(options()) :: :ok | {:error, :not_leader}
  defp ensure_leader(opts) do
    if Sigil.Diplomacy.leader?(opts), do: :ok, else: {:error, :not_leader}
  end

  @spec reputation_topic(options()) :: String.t()
  defp reputation_topic(opts) do
    Worlds.topic(Keyword.get(opts, :world, Worlds.default_world()), @reputation_topic)
  end
end
