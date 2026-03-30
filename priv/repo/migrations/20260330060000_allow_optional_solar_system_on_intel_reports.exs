defmodule Sigil.Repo.Migrations.AllowOptionalSolarSystemOnIntelReports do
  @moduledoc """
  Allows intel reports to be created without a solar system.
  """

  use Ecto.Migration

  @doc false
  def change do
    alter table(:intel_reports) do
      modify :solar_system_id, :integer, null: true
    end
  end
end
