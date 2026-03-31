defmodule Sigil.IntelMarket.PendingOps do
  @moduledoc """
  Applies cached marketplace operations after a signed transaction succeeds.
  """

  alias Sigil.Intel.IntelListing
  alias Sigil.IntelMarket
  alias Sigil.IntelMarket.{Listings, Support}
  alias Sigil.Repo

  @sui_client Application.compile_env!(:sigil, :sui_client)

  @typedoc "Internal marketplace operation cached until a wallet-signed transaction settles."
  @type pending_operation() ::
          {:create_listing, IntelMarket.pending_create_listing()}
          | {:purchase, %{listing_id: String.t(), buyer_address: String.t()}}
          | {:cancel_listing, %{listing_id: String.t()}}

  @doc "Applies a pending marketplace operation to persisted state using transaction effects."
  @spec apply(IntelMarket.options(), pending_operation(), map(), String.t()) ::
          {:ok, IntelListing.t() | nil} | {:error, term()}
  def apply(opts, {:create_listing, pending}, effects, digest) do
    with {:ok, listing} <- reconcile_created_listing(opts, pending, effects, digest) do
      Support.broadcast(opts, {:listing_created, listing})
      {:ok, listing}
    end
  end

  @doc false
  def apply(
        opts,
        {:purchase, %{listing_id: listing_id, buyer_address: buyer_address}},
        _effects,
        digest
      ) do
    with %IntelListing{} = listing <- Repo.get(IntelListing, listing_id),
         {:ok, updated} <-
           Listings.update_listing_status(listing, %{
             status: :sold,
             buyer_address: buyer_address,
             on_chain_digest: digest
           }) do
      Listings.cache_listing(updated, opts, Listings.cached_listing_ref(opts, listing_id))
      Support.broadcast(opts, {:listing_purchased, updated})
      {:ok, updated}
    else
      nil -> {:error, :listing_not_found}
      {:error, _reason} = error -> error
    end
  end

  @doc false
  def apply(opts, {:cancel_listing, %{listing_id: listing_id}}, _effects, digest) do
    with %IntelListing{} = listing <- Repo.get(IntelListing, listing_id),
         {:ok, updated} <-
           Listings.update_listing_status(listing, %{
             status: :cancelled,
             buyer_address: nil,
             on_chain_digest: digest
           }) do
      Listings.cache_listing(updated, opts, Listings.cached_listing_ref(opts, listing_id))
      Support.broadcast(opts, {:listing_cancelled, updated})
      {:ok, updated}
    else
      nil -> {:error, :listing_not_found}
      {:error, _reason} = error -> error
    end
  end

  defp reconcile_created_listing(opts, pending, _effects, digest) do
    reconcile_created_listing_from_chain(opts, pending, digest)
  end

  defp reconcile_created_listing_from_chain(opts, pending, digest) do
    client = Keyword.get(opts, :client, @sui_client)
    req_options = Keyword.get(opts, :req_options, [])

    with {:ok, objects} <-
           Support.list_objects(client, [type: Support.listing_type()], req_options),
         %{listing: listing, ref: ref} <-
           Enum.find_value(objects, fn object ->
             parsed = Listings.parse_listing_object!(object)

             if matching_pending_listing?(parsed.listing, pending) do
               parsed
             end
           end),
         persisted <-
           Listings.persist_created_listing(%{
             id: listing.id,
             seller_address: listing.seller_address,
             seal_id: listing.seal_id,
             encrypted_blob_id: listing.encrypted_blob_id,
             client_nonce: listing.client_nonce,
             price_mist: listing.price_mist,
             report_type: listing.report_type,
             solar_system_id: listing.solar_system_id,
             description: listing.description,
             status: listing.status,
             buyer_address: listing.buyer_address,
             restricted_to_tribe_id: listing.restricted_to_tribe_id,
             intel_report_id: pending.intel_report_id,
             on_chain_digest: digest
           }) do
      Listings.cache_listing(persisted, opts, ref)
      {:ok, persisted}
    else
      nil -> {:error, :listing_not_reconciled}
      {:error, _reason} = error -> error
    end
  end

  defp matching_pending_listing?(listing, pending) do
    listing.seller_address == pending.seller_address and
      listing.client_nonce == pending.client_nonce
  end
end
