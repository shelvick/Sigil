defmodule Sigil.Reputation.ReputationScoreTest do
  @moduledoc """
  Covers packet 4 reputation score schema and migration contracts.
  """

  use Sigil.DataCase, async: true

  @compile {:no_warn_undefined, Sigil.Reputation.ReputationScore}

  alias Sigil.Repo
  alias Sigil.Reputation.ReputationScore

  describe "changeset/2" do
    test "accepts valid attributes" do
      changeset = ReputationScore.changeset(new_reputation_score_struct(), valid_params())

      assert changeset.valid?
      assert get_change(changeset, :source_tribe_id) == 101
      assert get_change(changeset, :target_tribe_id) == 202
      assert get_change(changeset, :score) == 350
    end

    test "rejects score outside valid range" do
      low_changeset =
        ReputationScore.changeset(new_reputation_score_struct(), valid_params(%{score: -1001}))

      high_changeset =
        ReputationScore.changeset(new_reputation_score_struct(), valid_params(%{score: 1001}))

      refute low_changeset.valid?
      refute high_changeset.valid?
      assert errors_on(low_changeset).score == ["must be greater than or equal to -1000"]
      assert errors_on(high_changeset).score == ["must be less than or equal to 1000"]
    end

    test "normalizes string-key threshold overrides" do
      thresholds = %{
        "hostile_max" => -650,
        "unfriendly_max" => -250,
        "friendly_min" => 250,
        "allied_min" => 750
      }

      changeset =
        ReputationScore.changeset(
          new_reputation_score_struct(),
          valid_params(%{tier_thresholds: thresholds})
        )

      assert changeset.valid?

      assert get_change(changeset, :tier_thresholds) == %{
               hostile_max: -650,
               unfriendly_max: -250,
               friendly_min: 250,
               allied_min: 750
             }
    end

    test "rejects malformed threshold overrides" do
      missing_key_changeset =
        ReputationScore.changeset(
          new_reputation_score_struct(),
          valid_params(%{
            tier_thresholds: %{
              hostile_max: -700,
              unfriendly_max: -200,
              friendly_min: 200
            }
          })
        )

      invalid_order_changeset =
        ReputationScore.changeset(
          new_reputation_score_struct(),
          valid_params(%{
            tier_thresholds: %{
              hostile_max: -100,
              unfriendly_max: -200,
              friendly_min: 200,
              allied_min: 700
            }
          })
        )

      refute missing_key_changeset.valid?
      refute invalid_order_changeset.valid?

      assert "must include hostile_max, unfriendly_max, friendly_min, allied_min" in errors_on(
               missing_key_changeset
             ).tier_thresholds

      assert "must satisfy hostile_max <= unfriendly_max < friendly_min <= allied_min" in errors_on(
               invalid_order_changeset
             ).tier_thresholds
    end
  end

  describe "pin_changeset/2" do
    test "sets pinned flag and standing tier" do
      changeset =
        ReputationScore.pin_changeset(new_reputation_score_struct(), %{
          pinned: true,
          pinned_standing: 4
        })

      assert changeset.valid?
      assert get_change(changeset, :pinned) == true
      assert get_change(changeset, :pinned_standing) == 4
    end

    test "clears pinned_standing on unpin" do
      score =
        new_reputation_score_struct()
        |> Map.put(:pinned, true)
        |> Map.put(:pinned_standing, 3)

      changeset = ReputationScore.pin_changeset(score, %{pinned: false})

      assert changeset.valid?
      assert get_change(changeset, :pinned) == false
      assert get_change(changeset, :pinned_standing) == nil
    end

    test "rejects pinned without standing tier" do
      changeset = ReputationScore.pin_changeset(new_reputation_score_struct(), %{pinned: true})

      refute changeset.valid?
      assert errors_on(changeset).pinned_standing == ["can't be blank"]
    end
  end

  describe "score_changeset/2" do
    test "updates score and temporal fields only" do
      now = ~U[2026-03-28 12:00:00Z]

      score =
        new_reputation_score_struct()
        |> Map.put(:source_tribe_id, 101)
        |> Map.put(:target_tribe_id, 202)
        |> Map.put(:score, 0)
        |> Map.put(:pinned, true)
        |> Map.put(:pinned_standing, 3)

      changeset =
        ReputationScore.score_changeset(score, %{
          score: 125,
          last_event_at: now,
          last_decay_at: now,
          pinned: false
        })

      assert changeset.valid?

      assert Map.keys(changeset.changes) |> Enum.sort() == [
               :last_decay_at,
               :last_event_at,
               :score
             ]

      assert changeset.changes.score == 125
      assert DateTime.compare(changeset.changes.last_event_at, now) == :eq
      assert DateTime.compare(changeset.changes.last_decay_at, now) == :eq
    end
  end

  describe "repo integration" do
    test "unique index rejects duplicate tribe pair" do
      assert {:ok, _first} =
               new_reputation_score_struct()
               |> ReputationScore.changeset(valid_params())
               |> Repo.insert()

      assert {:error, duplicate_changeset} =
               new_reputation_score_struct()
               |> ReputationScore.changeset(valid_params(%{score: 500}))
               |> Repo.insert()

      assert errors_on(duplicate_changeset).source_tribe_id == ["has already been taken"]
    end

    test "reputation_scores table supports insert and query" do
      columns =
        Repo.query!("""
        SELECT column_name
        FROM information_schema.columns
        WHERE table_schema = current_schema()
          AND table_name = 'reputation_scores'
        ORDER BY ordinal_position
        """).rows
        |> List.flatten()

      indexes =
        Repo.query!("""
        SELECT indexname
        FROM pg_indexes
        WHERE schemaname = current_schema()
          AND tablename = 'reputation_scores'
        ORDER BY indexname
        """).rows
        |> List.flatten()

      assert columns == [
               "id",
               "source_tribe_id",
               "target_tribe_id",
               "score",
               "pinned",
               "pinned_standing",
               "last_event_at",
               "last_decay_at",
               "tier_thresholds",
               "inserted_at",
               "updated_at"
             ]

      assert "reputation_scores_source_tribe_id_index" in indexes
      assert "reputation_scores_tribe_pair_idx" in indexes

      assert {:ok, inserted} =
               new_reputation_score_struct()
               |> ReputationScore.changeset(
                 valid_params(%{
                   source_tribe_id: 999,
                   target_tribe_id: 111,
                   score: -250,
                   pinned: false,
                   pinned_standing: nil
                 })
               )
               |> Repo.insert()

      fetched = Repo.get!(ReputationScore, inserted.id)
      assert fetched.source_tribe_id == 999
      assert fetched.target_tribe_id == 111
      assert fetched.score == -250
    end
  end

  defp new_reputation_score_struct do
    apply(ReputationScore, :__struct__, [])
  end

  defp valid_params(overrides \\ %{}) do
    Map.merge(
      %{
        source_tribe_id: 101,
        target_tribe_id: 202,
        score: 350,
        pinned: false,
        pinned_standing: nil,
        last_event_at: ~U[2026-03-28 10:00:00Z],
        last_decay_at: ~U[2026-03-28 11:00:00Z],
        tier_thresholds: %{
          hostile_max: -700,
          unfriendly_max: -200,
          friendly_min: 200,
          allied_min: 700
        }
      },
      overrides
    )
  end
end
