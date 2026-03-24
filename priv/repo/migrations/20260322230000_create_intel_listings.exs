defmodule Sigil.Repo.Migrations.CreateIntelListings do
  @moduledoc false
  use Ecto.Migration

  @doc false
  def change do
    create table(:intel_listings, primary_key: false) do
      add :id, :string, primary_key: true
      add :seller_address, :string, null: false
      add :commitment_hash, :string, null: false
      add :client_nonce, :bigint, null: false
      add :price_mist, :bigint, null: false
      add :report_type, :integer, null: false
      add :solar_system_id, :integer, null: false
      add :description, :text
      add :status, :string, null: false, default: "active"
      add :buyer_address, :string
      add :restricted_to_tribe_id, :integer
      add :intel_report_id, :string
      add :on_chain_digest, :string

      timestamps(type: :utc_datetime_usec)
    end

    create index(:intel_listings, [:status])
    create index(:intel_listings, [:seller_address])
    create index(:intel_listings, [:solar_system_id])
    create index(:intel_listings, [:restricted_to_tribe_id])
  end
end
