defmodule Sigil.Repo.Migrations.AddSealFieldsToIntelListings do
  @moduledoc false
  use Ecto.Migration

  @doc false
  def change do
    alter table(:intel_listings) do
      add :seal_id, :string
      add :encrypted_blob_id, :string
      remove :commitment_hash, :string
    end
  end
end
