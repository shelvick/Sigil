defmodule Sigil.Repo.Migrations.CreatePseudonyms do
  @moduledoc false
  use Ecto.Migration

  @doc false
  def change do
    create table(:pseudonyms) do
      add :account_address, :string, null: false
      add :pseudonym_address, :string, null: false
      add :encrypted_private_key, :binary, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:pseudonyms, [:account_address])
    create unique_index(:pseudonyms, [:pseudonym_address])
  end
end
