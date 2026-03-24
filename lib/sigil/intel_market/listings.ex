defmodule Sigil.IntelMarket.Listings do
  @moduledoc """
  Listing persistence, caching, and chain parsing helpers for the intel marketplace.
  """

  import Ecto.Query

  alias Sigil.Cache
  alias Sigil.Diplomacy.ObjectCodec
  alias Sigil.Intel.IntelListing
  alias Sigil.IntelMarket
  alias Sigil.IntelMarket.Support
  alias Sigil.Repo

  @doc "Caches marketplace metadata when discovery finds a singleton object."
  @spec maybe_cache_marketplace(IntelMarket.marketplace_info() | nil, IntelMarket.options()) ::
          IntelMarket.marketplace_info() | nil
  def maybe_cache_marketplace(nil, _opts), do: nil

  @doc false
  def maybe_cache_marketplace(marketplace, opts) do
    Cache.put(Support.market_table(opts), {:marketplace}, marketplace)
    marketplace
  end

  @doc "Parses marketplace singleton metadata from a raw chain object."
  @spec marketplace_from_object(map()) :: IntelMarket.marketplace_info() | nil
  def marketplace_from_object(object) do
    with object_id when is_binary(object_id) <- object["id"],
         version when is_integer(version) <- ObjectCodec.parse_shared_version(object) do
      %{
        object_id: object_id,
        object_id_bytes: ObjectCodec.hex_to_bytes(object_id),
        initial_shared_version: version,
        listing_count: Support.parse_integer(Map.get(object, "listing_count"), 0)
      }
    else
      _invalid -> nil
    end
  end

  @doc "Parses a raw listing object plus its shared-object reference."
  @spec parse_listing_object!(map()) :: %{
          listing: IntelListing.t(),
          ref: IntelMarket.listing_ref()
        }
  def parse_listing_object!(object) do
    id = Map.fetch!(object, "id")
    version = ObjectCodec.parse_shared_version(object)

    %{
      listing: %IntelListing{
        id: id,
        seller_address: Map.fetch!(object, "seller"),
        commitment_hash: to_string(Map.fetch!(object, "commitment")),
        client_nonce: Support.parse_integer(Map.fetch!(object, "client_nonce")),
        price_mist: Support.parse_integer(Map.fetch!(object, "price")),
        report_type: Support.parse_integer(Map.fetch!(object, "report_type")),
        solar_system_id: Support.parse_integer(Map.fetch!(object, "solar_system_id")),
        description: Map.get(object, "description"),
        status: Support.parse_listing_status(Map.get(object, "status")),
        buyer_address: Map.get(object, "buyer"),
        restricted_to_tribe_id:
          Support.parse_optional_integer(Map.get(object, "restricted_to_tribe_id"))
      },
      ref: %{object_id: ObjectCodec.hex_to_bytes(id), initial_shared_version: version}
    }
  end

  @doc "Upserts a chain-sourced listing while preserving local linkage metadata."
  @spec persist_chain_listing(%{listing: IntelListing.t(), ref: IntelMarket.listing_ref()}) ::
          IntelListing.t()
  def persist_chain_listing(%{listing: listing}) do
    persisted = Repo.get(IntelListing, listing.id)

    attrs = %{
      id: listing.id,
      seller_address: listing.seller_address,
      commitment_hash: listing.commitment_hash,
      client_nonce: listing.client_nonce,
      price_mist: listing.price_mist,
      report_type: listing.report_type,
      solar_system_id: listing.solar_system_id,
      description: listing.description,
      status: listing.status,
      buyer_address: listing.buyer_address,
      restricted_to_tribe_id: listing.restricted_to_tribe_id,
      intel_report_id: persisted && persisted.intel_report_id,
      on_chain_digest: persisted && persisted.on_chain_digest
    }

    target = persisted || %IntelListing{}

    target
    |> IntelListing.changeset(attrs)
    |> Repo.insert_or_update!()
  end

  @doc "Upserts a newly created listing that was reconciled after transaction submission."
  @spec persist_created_listing(map()) :: IntelListing.t()
  def persist_created_listing(attrs) do
    target = Repo.get(IntelListing, attrs.id) || %IntelListing{}

    target
    |> IntelListing.changeset(attrs)
    |> Repo.insert_or_update!()
  end

  @doc "Updates listing status fields after purchase or cancellation reconciliation."
  @spec update_listing_status(IntelListing.t(), map()) ::
          {:ok, IntelListing.t()} | {:error, Ecto.Changeset.t()}
  def update_listing_status(listing, attrs) do
    listing
    |> IntelListing.status_changeset(attrs)
    |> Repo.update()
  end

  @doc "Caches a listing and its shared-object reference in ETS."
  @spec cache_listing(IntelListing.t(), IntelMarket.options(), IntelMarket.listing_ref()) ::
          IntelListing.t()
  def cache_listing(listing, opts, listing_ref) do
    table = Support.market_table(opts)
    Cache.put(table, {:listing, listing.id}, listing)
    Cache.put(table, {:listing_ref, listing.id}, listing_ref)
    listing
  end

  @doc "Returns the cached listing reference or reconstructs a default object reference."
  @spec cached_listing_ref(IntelMarket.options(), String.t()) :: IntelMarket.listing_ref()
  def cached_listing_ref(opts, listing_id) do
    Cache.get(Support.market_table(opts), {:listing_ref, listing_id}) ||
      %{object_id: ObjectCodec.hex_to_bytes(listing_id), initial_shared_version: 0}
  end

  @doc "Clears cached listing data and removes stale persisted records absent from chain state."
  @spec remove_stale_listings(IntelMarket.options(), [String.t()]) :: :ok
  def remove_stale_listings(opts, chain_listing_ids) do
    stale_ids = stale_listing_ids(chain_listing_ids)

    Enum.each(stale_ids, fn listing_id ->
      Repo.delete_all(from listing in IntelListing, where: listing.id == ^listing_id)
      clear_listing_cache(opts, listing_id)
      Support.broadcast(opts, {:listing_removed, listing_id})
    end)
  end

  @doc "Clears a cached listing and its shared-object reference."
  @spec clear_listing_cache(IntelMarket.options(), String.t()) :: :ok
  def clear_listing_cache(opts, listing_id) do
    table = Support.market_table(opts)
    Cache.delete(table, {:listing, listing_id})
    Cache.delete(table, {:listing_ref, listing_id})
  end

  defp stale_listing_ids(chain_listing_ids) do
    cutoff = DateTime.utc_now() |> DateTime.add(-30, :second)

    existing_ids =
      Repo.all(
        from listing in IntelListing,
          where: listing.inserted_at < ^cutoff,
          select: listing.id
      )

    Enum.reject(existing_ids, &(&1 in chain_listing_ids))
  end
end
