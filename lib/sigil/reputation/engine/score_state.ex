defmodule Sigil.Reputation.Engine.ScoreState do
  @moduledoc """
  Helpers for normalizing, clamping, and mutating reputation score records.
  """

  alias Sigil.Cache
  alias Sigil.Reputation.{ReputationScore, Scoring}

  @doc "Returns a normalized score record for a tribe pair from ETS or defaults."
  @spec fetch_score_record(
          Cache.table_id(),
          tuple(),
          non_neg_integer(),
          non_neg_integer(),
          module()
        ) :: ReputationScore.t()
  def fetch_score_record(
        reputation_table,
        score_key,
        source_tribe_id,
        target_tribe_id,
        scoring_module
      ) do
    case Cache.get(reputation_table, score_key) do
      %ReputationScore{} = score_record ->
        %ReputationScore{
          score_record
          | source_tribe_id: source_tribe_id,
            target_tribe_id: target_tribe_id,
            score: score_record.score || 0,
            pinned: score_record.pinned || false,
            tier_thresholds: normalize_thresholds(score_record.tier_thresholds, scoring_module)
        }

      _other ->
        %ReputationScore{
          source_tribe_id: source_tribe_id,
          target_tribe_id: target_tribe_id,
          score: 0,
          pinned: false,
          pinned_standing: nil,
          last_event_at: nil,
          last_decay_at: nil,
          tier_thresholds: scoring_module.default_thresholds()
        }
    end
  end

  @doc "Merges persisted threshold maps into scoring defaults."
  @spec normalize_thresholds(map() | nil, module()) :: Scoring.thresholds()
  def normalize_thresholds(nil, scoring_module), do: scoring_module.default_thresholds()

  def normalize_thresholds(thresholds, scoring_module) when is_map(thresholds) do
    defaults = scoring_module.default_thresholds()

    Enum.reduce([:hostile_max, :unfriendly_max, :friendly_min, :allied_min], defaults, fn key,
                                                                                          acc ->
      case Map.fetch(thresholds, key) do
        {:ok, value} when is_integer(value) ->
          Map.put(acc, key, value)

        _other ->
          case Map.get(thresholds, Atom.to_string(key)) do
            value when is_integer(value) -> Map.put(acc, key, value)
            _fallback -> acc
          end
      end
    end)
  end

  def normalize_thresholds(_invalid, scoring_module), do: scoring_module.default_thresholds()

  @doc "Converts score tier indices to standing atoms."
  @spec standing_atom(integer()) :: :hostile | :unfriendly | :neutral | :friendly | :allied
  def standing_atom(0), do: :hostile
  def standing_atom(1), do: :unfriendly
  def standing_atom(2), do: :neutral
  def standing_atom(3), do: :friendly
  def standing_atom(_tier), do: :allied

  @doc "Marks a source/target pair as dirty for DB flush."
  @spec mark_dirty(map(), non_neg_integer(), non_neg_integer()) :: map()
  def mark_dirty(state, source_tribe_id, target_tribe_id) do
    %{state | dirty_scores: MapSet.put(state.dirty_scores, {source_tribe_id, target_tribe_id})}
  end

  @doc "Clamps a score into the persisted -1000..1000 range."
  @spec clamp_score(integer()) :: -1000..1000
  def clamp_score(score) when score > 1000, do: 1000
  def clamp_score(score) when score < -1000, do: -1000
  def clamp_score(score), do: score
end
