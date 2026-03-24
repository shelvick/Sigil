defmodule Sigil.Repo.Migrations.ScopeAlertDedupToAccount do
  @moduledoc """
  Scopes the active alert deduplication index to an account.
  """

  use Ecto.Migration

  @doc false
  def change do
    drop_if_exists index(:alerts, [:assembly_id, :type],
                     where: "status IN ('new', 'acknowledged')",
                     name: :alerts_active_unique_index
                   )

    create unique_index(
             :alerts,
             [:account_address, :assembly_id, :type],
             where: "status IN ('new', 'acknowledged')",
             name: :alerts_active_unique_index
           )
  end
end
