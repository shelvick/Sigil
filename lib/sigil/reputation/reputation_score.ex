defmodule Sigil.Reputation.ReputationScore do
  @moduledoc """
  Ecto schema for persisted tribe-pair reputation scores.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @typedoc "Persisted reputation score for one source/target tribe pair."
  @type t() :: %__MODULE__{
          id: integer() | nil,
          source_tribe_id: integer() | nil,
          target_tribe_id: integer() | nil,
          score: integer() | nil,
          pinned: boolean() | nil,
          pinned_standing: integer() | nil,
          last_event_at: DateTime.t() | nil,
          last_decay_at: DateTime.t() | nil,
          tier_thresholds: Sigil.Reputation.Scoring.thresholds() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @all_fields [
    :source_tribe_id,
    :target_tribe_id,
    :score,
    :pinned,
    :pinned_standing,
    :last_event_at,
    :last_decay_at,
    :tier_thresholds
  ]
  @score_fields [:score, :last_event_at, :last_decay_at]
  @threshold_keys [:hostile_max, :unfriendly_max, :friendly_min, :allied_min]

  schema "reputation_scores" do
    field :source_tribe_id, :integer
    field :target_tribe_id, :integer
    field :score, :integer, default: 0
    field :pinned, :boolean, default: false
    field :pinned_standing, :integer
    field :last_event_at, :utc_datetime_usec
    field :last_decay_at, :utc_datetime_usec
    field :tier_thresholds, :map

    timestamps(type: :utc_datetime_usec)
  end

  @doc "Builds the full changeset used for insert/update operations."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(reputation_score, attrs) do
    reputation_score
    |> cast(attrs, @all_fields)
    |> validate_required([:source_tribe_id, :target_tribe_id])
    |> validate_score()
    |> validate_pinned_standing_range()
    |> normalize_thresholds()
    |> validate_thresholds_shape()
    |> unique_constraint(:source_tribe_id, name: :reputation_scores_tribe_pair_idx)
  end

  @doc "Builds the restricted changeset for score update operations."
  @spec score_changeset(t(), map()) :: Ecto.Changeset.t()
  def score_changeset(reputation_score, attrs) do
    reputation_score
    |> cast(attrs, @score_fields)
    |> validate_score()
  end

  @doc "Builds the changeset used for pin and unpin operations."
  @spec pin_changeset(t(), map()) :: Ecto.Changeset.t()
  def pin_changeset(reputation_score, attrs) do
    reputation_score
    |> cast(attrs, [:pinned, :pinned_standing])
    |> normalize_unpinned_standing()
    |> validate_required_when_pinned()
    |> validate_pinned_standing_range()
  end

  @spec validate_score(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp validate_score(changeset) do
    validate_number(changeset, :score,
      greater_than_or_equal_to: -1000,
      less_than_or_equal_to: 1000
    )
  end

  @spec validate_pinned_standing_range(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp validate_pinned_standing_range(changeset) do
    validate_number(changeset, :pinned_standing,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 4
    )
  end

  @spec normalize_unpinned_standing(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp normalize_unpinned_standing(changeset) do
    case get_field(changeset, :pinned) do
      false -> put_change(changeset, :pinned_standing, nil)
      _other -> changeset
    end
  end

  @spec validate_required_when_pinned(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp validate_required_when_pinned(changeset) do
    if get_field(changeset, :pinned) do
      validate_required(changeset, [:pinned_standing])
    else
      changeset
    end
  end

  @spec normalize_thresholds(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp normalize_thresholds(changeset) do
    case get_change(changeset, :tier_thresholds) do
      nil ->
        changeset

      thresholds when is_map(thresholds) ->
        normalized =
          Enum.reduce(@threshold_keys, %{}, fn key, acc ->
            case fetch_threshold(thresholds, key) do
              value when is_integer(value) -> Map.put(acc, key, value)
              _other -> acc
            end
          end)

        put_change(changeset, :tier_thresholds, normalized)

      _other ->
        changeset
    end
  end

  @spec validate_thresholds_shape(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp validate_thresholds_shape(changeset) do
    case get_change(changeset, :tier_thresholds) do
      nil ->
        changeset

      thresholds when is_map(thresholds) ->
        changeset
        |> validate_threshold_keys_present(thresholds)
        |> validate_threshold_order(thresholds)

      _other ->
        add_error(changeset, :tier_thresholds, "must be a map")
    end
  end

  @spec validate_threshold_keys_present(Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  defp validate_threshold_keys_present(changeset, thresholds) do
    if Enum.all?(@threshold_keys, &Map.has_key?(thresholds, &1)) do
      changeset
    else
      add_error(
        changeset,
        :tier_thresholds,
        "must include hostile_max, unfriendly_max, friendly_min, allied_min"
      )
    end
  end

  @spec validate_threshold_order(Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  defp validate_threshold_order(changeset, thresholds) do
    with true <- Enum.all?(@threshold_keys, &Map.has_key?(thresholds, &1)),
         true <- thresholds.hostile_max <= thresholds.unfriendly_max,
         true <- thresholds.unfriendly_max < thresholds.friendly_min,
         true <- thresholds.friendly_min <= thresholds.allied_min do
      changeset
    else
      _other ->
        add_error(
          changeset,
          :tier_thresholds,
          "must satisfy hostile_max <= unfriendly_max < friendly_min <= allied_min"
        )
    end
  end

  @spec fetch_threshold(map(), atom()) :: term()
  defp fetch_threshold(thresholds, key) do
    case Map.fetch(thresholds, key) do
      {:ok, value} -> value
      :error -> Map.get(thresholds, Atom.to_string(key))
    end
  end
end
