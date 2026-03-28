defmodule Sigil.Reputation.Scoring do
  @moduledoc """
  Pure scoring helpers for reputation events.
  """

  @typedoc "Standing tier used for scoring inputs and outputs."
  @type standing() :: 0..4

  @typedoc "Reputation score clamped to the supported persistence range."
  @type score() :: -1000..1000

  @typedoc "Tier boundary values used to map score to standing tiers."
  @type thresholds() :: %{
          hostile_max: integer(),
          unfriendly_max: integer(),
          friendly_min: integer(),
          allied_min: integer()
        }

  @typedoc "Derived standing tier from a score."
  @type tier() :: 0..4

  @threshold_keys [:hostile_max, :unfriendly_max, :friendly_min, :allied_min]

  @doc """
  Computes a kill score delta from standings and event multipliers.
  """
  @spec compute_kill_score(standing(), standing(), boolean(), boolean()) :: integer()
  def compute_kill_score(our_standing_of_killer, our_standing_of_victim, aggressor?, on_our_grid?) do
    base_delta = (our_standing_of_killer - our_standing_of_victim) * 12.5

    multiplier =
      1.0
      |> maybe_apply_multiplier(aggressor?, 3.0)
      |> maybe_apply_multiplier(on_our_grid?, 2.0)

    trunc(base_delta * multiplier)
  end

  @doc """
  Returns the flat score delta for a gate jump event.
  """
  @spec compute_jump_score() :: pos_integer()
  def compute_jump_score, do: 5

  @doc """
  Applies exponential decay toward zero over elapsed hours.
  """
  @spec apply_decay(integer(), non_neg_integer(), float()) :: integer()
  def apply_decay(current_score, hours_elapsed, decay_rate \\ 0.002075)

  def apply_decay(0, _hours_elapsed, _decay_rate), do: 0

  def apply_decay(current_score, hours_elapsed, decay_rate) do
    decayed = current_score * :math.pow(1.0 - decay_rate, hours_elapsed)

    decayed
    |> trunc()
    |> clamp_score()
  end

  @doc """
  Computes one-hop transitive reputation adjustment from standing graphs.
  """
  @spec compute_transitive_score(map(), map(), float()) :: integer()
  def compute_transitive_score(our_standings_map, their_standings_of_target, weight \\ 0.25)
      when is_map(our_standings_map) and is_map(their_standings_of_target) do
    our_standings_map
    |> Enum.reduce(0, fn {tribe_id, our_standing_of_tribe}, acc ->
      case Map.fetch(their_standings_of_target, tribe_id) do
        {:ok, their_standing_of_target_tribe} ->
          influence = (our_standing_of_tribe - 2) * (their_standing_of_target_tribe - 2)
          acc + influence

        :error ->
          acc
      end
    end)
    |> Kernel.*(weight)
    |> round()
  end

  @doc """
  Evaluates a score into the 0..4 standing tier.
  """
  @spec evaluate_tier(integer(), thresholds() | map() | nil) :: tier()
  def evaluate_tier(score, thresholds \\ default_thresholds())

  def evaluate_tier(score, nil), do: evaluate_tier(score, default_thresholds())

  def evaluate_tier(score, thresholds) when is_map(thresholds) do
    normalized = normalize_thresholds(thresholds)

    cond do
      score <= normalized.hostile_max -> 0
      score <= normalized.unfriendly_max -> 1
      score <= normalized.friendly_min - 1 -> 2
      score <= normalized.allied_min - 1 -> 3
      true -> 4
    end
  end

  def evaluate_tier(score, _invalid_thresholds), do: evaluate_tier(score, default_thresholds())

  @spec normalize_thresholds(map()) :: thresholds()
  defp normalize_thresholds(thresholds) do
    defaults = default_thresholds()

    Enum.reduce(@threshold_keys, defaults, fn key, acc ->
      case fetch_threshold(thresholds, key) do
        value when is_integer(value) -> Map.put(acc, key, value)
        _other -> acc
      end
    end)
  end

  @spec fetch_threshold(map(), atom()) :: term()
  defp fetch_threshold(thresholds, key) do
    case Map.fetch(thresholds, key) do
      {:ok, value} -> value
      :error -> Map.get(thresholds, Atom.to_string(key))
    end
  end

  @doc """
  Returns default tier thresholds.
  """
  @spec default_thresholds() :: thresholds()
  def default_thresholds do
    %{
      hostile_max: -700,
      unfriendly_max: -200,
      friendly_min: 200,
      allied_min: 700
    }
  end

  @doc """
  Returns whether the aggressor window has expired.
  """
  @spec aggressor_expired?(DateTime.t() | nil, DateTime.t()) :: boolean()
  def aggressor_expired?(nil, _now), do: true

  def aggressor_expired?(last_aggression_time, now) do
    DateTime.diff(now, last_aggression_time, :second) > 30 * 60
  end

  @spec maybe_apply_multiplier(float(), boolean(), float()) :: float()
  defp maybe_apply_multiplier(multiplier, true, factor), do: multiplier * factor
  defp maybe_apply_multiplier(multiplier, false, _factor), do: multiplier

  @spec clamp_score(integer()) :: score()
  defp clamp_score(score) when score > 1000, do: 1000
  defp clamp_score(score) when score < -1000, do: -1000
  defp clamp_score(score), do: score
end
