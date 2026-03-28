defmodule Sigil.Repo.Migrations.AddActiveReputationAlertDedupIndex do
  @moduledoc """
  Adds an active-alert unique index for reputation threshold alerts scoped by
  account, alert type, and target tribe.
  """

  use Ecto.Migration

  @doc "Adds the active reputation alert deduplication index."
  def change do
    create unique_index(
             :alerts,
             [:account_address, :type, "(metadata->>'target_tribe_id')"],
             where:
               "status IN ('new', 'acknowledged') AND type = 'reputation_threshold_crossed' AND (metadata->>'target_tribe_id') IS NOT NULL",
             name: :alerts_active_reputation_unique_index
           )
  end
end
