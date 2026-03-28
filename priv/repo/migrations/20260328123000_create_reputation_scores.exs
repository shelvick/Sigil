defmodule Sigil.Repo.Migrations.CreateReputationScores do
  @moduledoc false
  use Ecto.Migration

  @doc false
  def change do
    create table(:reputation_scores) do
      add :source_tribe_id, :integer, null: false
      add :target_tribe_id, :integer, null: false
      add :score, :integer, null: false, default: 0
      add :pinned, :boolean, null: false, default: false
      add :pinned_standing, :integer
      add :last_event_at, :utc_datetime_usec
      add :last_decay_at, :utc_datetime_usec
      add :tier_thresholds, :map

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:reputation_scores, [:source_tribe_id, :target_tribe_id],
             name: :reputation_scores_tribe_pair_idx
           )

    create index(:reputation_scores, [:source_tribe_id])
  end
end
