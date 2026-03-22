defmodule Sigil.Repo.Migrations.CreateAlerts do
  @moduledoc false
  use Ecto.Migration

  @doc false
  def change do
    create table(:alerts) do
      add :type, :string, null: false
      add :severity, :string, null: false
      add :status, :string, null: false, default: "new"
      add :assembly_id, :string, null: false
      add :assembly_name, :string, null: false
      add :account_address, :string, null: false
      add :tribe_id, :integer
      add :message, :string, null: false
      add :metadata, :map, null: false, default: %{}
      add :dismissed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:alerts, [:account_address, :status])
    create index(:alerts, [:tribe_id])
    create index(:alerts, [:inserted_at])

    create unique_index(:alerts, [:assembly_id, :type],
             where: "status IN ('new', 'acknowledged')",
             name: :alerts_active_unique_index
           )

    create table(:webhook_configs) do
      add :tribe_id, :integer, null: false
      add :webhook_url, :string, null: false
      add :service_type, :string, null: false, default: "discord"
      add :enabled, :boolean, null: false, default: true

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:webhook_configs, [:tribe_id])
  end
end
