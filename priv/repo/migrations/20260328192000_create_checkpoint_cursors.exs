defmodule Sigil.Repo.Migrations.CreateCheckpointCursors do
  @moduledoc """
  Creates durable cursor storage for the gRPC checkpoint stream.
  """

  use Ecto.Migration

  @doc false
  def change do
    create table(:checkpoint_cursors) do
      add :stream_id, :string, null: false
      add :cursor, :bigint, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:checkpoint_cursors, [:stream_id])
  end
end
