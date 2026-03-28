defmodule Sigil.Reputation.Engine.Persistence do
  @moduledoc """
  Repo persistence and hydration helpers for reputation score state.
  """

  require Logger

  alias Sigil.Cache
  alias Sigil.Reputation.Engine.ScoreState
  alias Sigil.Reputation.ReputationScore

  @doc "Flushes dirty score pairs from ETS to Postgres."
  @spec flush_dirty_scores(map()) :: map()
  def flush_dirty_scores(%{tables: nil} = state), do: state

  def flush_dirty_scores(state) do
    {persisted_pairs, failed_pairs} =
      Enum.reduce(state.dirty_scores, {MapSet.new(), MapSet.new()}, fn pair,
                                                                       {persisted_acc, failed_acc} ->
        case persist_pair(state, pair) do
          :ok -> {MapSet.put(persisted_acc, pair), failed_acc}
          :error -> {persisted_acc, MapSet.put(failed_acc, pair)}
        end
      end)

    if MapSet.size(failed_pairs) > 0 do
      Logger.error("Failed to persist #{MapSet.size(failed_pairs)} reputation score pairs")
    end

    remaining_dirty =
      state.dirty_scores
      |> MapSet.difference(persisted_pairs)
      |> MapSet.union(failed_pairs)

    %{state | dirty_scores: remaining_dirty}
  end

  @doc "Loads persisted reputation scores into ETS cache on startup."
  @spec load_scores_from_repo(map()) :: map()
  def load_scores_from_repo(%{tables: nil} = state), do: state

  def load_scores_from_repo(state) do
    scores = state.repo_module.all(ReputationScore)

    Enum.each(scores, fn %ReputationScore{} = score_record ->
      Cache.put(
        state.tables.reputation,
        {:reputation_score, score_record.source_tribe_id, score_record.target_tribe_id},
        %ReputationScore{
          score_record
          | tier_thresholds:
              ScoreState.normalize_thresholds(score_record.tier_thresholds, state.scoring_module)
        }
      )
    end)

    state
  rescue
    exception ->
      Logger.error("Failed to load reputation scores from repo: #{Exception.message(exception)}")
      state
  end

  @spec persist_pair(map(), {non_neg_integer(), non_neg_integer()}) :: :ok | :error
  defp persist_pair(state, {source_tribe_id, target_tribe_id}) do
    case Cache.get(state.tables.reputation, {:reputation_score, source_tribe_id, target_tribe_id}) do
      %ReputationScore{} = score_record ->
        attrs = %{
          source_tribe_id: source_tribe_id,
          target_tribe_id: target_tribe_id,
          score: score_record.score || 0,
          pinned: score_record.pinned || false,
          pinned_standing: score_record.pinned_standing,
          last_event_at: ensure_usec(score_record.last_event_at),
          last_decay_at: ensure_usec(score_record.last_decay_at),
          tier_thresholds:
            ScoreState.normalize_thresholds(score_record.tier_thresholds, state.scoring_module)
        }

        changeset = ReputationScore.changeset(%ReputationScore{}, attrs)

        case state.repo_module.insert(changeset,
               on_conflict: [
                 set: [
                   score: attrs.score,
                   pinned: attrs.pinned,
                   pinned_standing: attrs.pinned_standing,
                   last_event_at: attrs.last_event_at,
                   last_decay_at: attrs.last_decay_at,
                   tier_thresholds: attrs.tier_thresholds,
                   updated_at: DateTime.utc_now()
                 ]
               ],
               conflict_target: [:source_tribe_id, :target_tribe_id]
             ) do
          {:ok, _record} ->
            :ok

          {:error, changeset} ->
            Logger.error("Failed to upsert reputation score: #{inspect(changeset.errors)}")
            :error
        end

      _other ->
        :ok
    end
  rescue
    exception ->
      Logger.error("Exception persisting reputation score pair: #{Exception.message(exception)}")
      :error
  end

  @spec ensure_usec(DateTime.t() | nil) :: DateTime.t() | nil
  defp ensure_usec(nil), do: nil

  defp ensure_usec(%DateTime{} = datetime) do
    case datetime.microsecond do
      {_, 6} -> datetime
      {microsecond, _precision} -> %{datetime | microsecond: {microsecond, 6}}
    end
  end
end
