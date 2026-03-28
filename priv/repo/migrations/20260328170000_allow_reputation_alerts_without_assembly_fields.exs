defmodule Sigil.Repo.Migrations.AllowReputationAlertsWithoutAssemblyFields do
  @moduledoc """
  Allows reputation alerts to persist without assembly context.
  """

  use Ecto.Migration

  @doc false
  def change do
    alter table(:alerts) do
      modify :assembly_id, :string, null: true
      modify :assembly_name, :string, null: true
    end
  end
end
