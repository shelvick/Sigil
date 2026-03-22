defmodule Sigil.Repo.Migrations.CreateIntelReports do
  @moduledoc """
  Creates the intel_reports table for tribe-scoped intel persistence.
  """

  use Ecto.Migration

  def change do
    create table(:intel_reports, primary_key: false) do
      add :id, :string, primary_key: true
      add :tribe_id, :integer, null: false
      add :assembly_id, :string
      add :solar_system_id, :integer, null: false
      add :label, :string
      add :report_type, :string, null: false
      add :notes, :text
      add :reported_by, :string, null: false
      add :reported_by_name, :string
      add :reported_by_character_id, :string, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:intel_reports, [:tribe_id])

    create unique_index(:intel_reports, [:tribe_id, :assembly_id],
             where: "report_type = 'location' AND assembly_id IS NOT NULL",
             name: :intel_reports_tribe_assembly_location_idx
           )
  end
end
