defmodule Sigil.IntelMarket do
  @moduledoc """
  Intel marketplace context for cache-backed listing discovery and transaction handling.
  """

  import Ecto.Query

  alias Sigil.Cache
  alias Sigil.Intel.IntelListing
  alias Sigil.IntelMarket.{Listings, Reputation, Support, Transactions}
  alias Sigil.Repo
  alias Sigil.Sui.Client

  @sui_client Application.compile_env!(:sigil, :sui_client)
  @walrus_client Application.compile_env(:sigil, :walrus_client, Sigil.WalrusClient.HTTP)

  @marketplace_topic "intel_market"

  @typedoc "Marketplace singleton metadata cached for discovery and UI availability checks."
  @type marketplace_info() :: %{
          object_id: String.t(),
          object_id_bytes: <<_::256>>,
          initial_shared_version: non_neg_integer()
        }

  @typedoc "Shared object reference for an intel listing."
  @type listing_ref() :: %{
          object_id: <<_::256>>,
          initial_shared_version: non_neg_integer()
        }

  @typedoc "Options accepted by intel marketplace functions."
  @type option() ::
          {:tables,
           %{required(:intel_market) => Cache.table_id(), optional(atom()) => Cache.table_id()}}
          | {:pubsub, atom() | module()}
          | {:req_options, Client.request_opts()}
          | {:sender, String.t()}
          | {:tribe_id, non_neg_integer()}
          | {:client, module()}
          | {:walrus_client, module()}
          | {:stale_grace_ms, non_neg_integer()}
          | {:seal_config, map()}
          | {:sigil_package_id, String.t()}
          | {:pseudonym_address, String.t()}
          | {:reputation_registry_id, String.t()}

  @type options() :: [option()]

  @typedoc "Pending create-listing payload cached until the signed transaction returns."
  @type pending_create_listing() :: %{
          seal_id: binary(),
          encrypted_blob_id: binary(),
          client_nonce: non_neg_integer(),
          price: non_neg_integer(),
          report_type: non_neg_integer(),
          solar_system_id: non_neg_integer(),
          description: String.t(),
          intel_report_id: Ecto.UUID.t() | nil,
          seller_address: String.t(),
          restricted_to_tribe_id: non_neg_integer() | nil
        }

  @doc "Returns the PubSub topic for marketplace events."
  @spec topic() :: String.t()
  def topic, do: @marketplace_topic

  @doc "Builds the browser Seal/Walrus configuration payload for marketplace hooks."
  @spec build_seal_config(options()) :: %{
          required(String.t()) => String.t() | pos_integer() | [String.t()]
        }
  def build_seal_config(opts) when is_list(opts) do
    world = Application.fetch_env!(:sigil, :eve_world)
    worlds = Application.fetch_env!(:sigil, :eve_worlds)
    seal_config = Keyword.get(opts, :seal_config, Application.fetch_env!(:sigil, :seal))

    sigil_package_id =
      Keyword.get_lazy(opts, :sigil_package_id, fn ->
        %{sigil_package_id: id} = Map.fetch!(worlds, world)
        id
      end)

    %{
      "seal_package_id" => sigil_package_id,
      "key_server_object_ids" => Map.get(seal_config, :key_server_object_ids, []),
      "threshold" => Map.get(seal_config, :threshold, 1),
      "walrus_publisher_url" => Map.fetch!(seal_config, :walrus_publisher_url),
      "walrus_aggregator_url" => Map.fetch!(seal_config, :walrus_aggregator_url),
      "walrus_epochs" => Map.get(seal_config, :walrus_epochs, 15),
      "sui_rpc_url" => Map.fetch!(seal_config, :sui_rpc_url)
    }
  end

  @doc "Discovers the marketplace singleton, caches it, and broadcasts the result."
  @spec discover_marketplace(options()) ::
          {:ok, marketplace_info() | nil} | {:error, Client.error_reason()}
  def discover_marketplace(opts) when is_list(opts) do
    client = Keyword.get(opts, :client, @sui_client)
    req_options = Keyword.get(opts, :req_options, [])

    with {:ok, objects} <-
           Support.list_objects(client, [type: Support.marketplace_type()], req_options) do
      marketplace =
        objects
        |> Enum.find_value(&Listings.marketplace_from_object/1)
        |> Listings.maybe_cache_marketplace(opts)

      Support.broadcast(opts, {:marketplace_discovered, marketplace})
      {:ok, marketplace}
    end
  end

  @doc "Refreshes marketplace listings from chain data into Postgres and ETS."
  @spec sync_listings(options()) :: {:ok, [IntelListing.t()]} | {:error, term()}
  def sync_listings(opts) when is_list(opts) do
    client = Keyword.get(opts, :client, @sui_client)
    req_options = Keyword.get(opts, :req_options, [])

    with {:ok, objects} <-
           Support.list_objects(client, [type: Support.listing_type()], req_options) do
      parsed_listings = Enum.map(objects, &Listings.parse_listing_object!/1)
      chain_listing_ids = Enum.map(parsed_listings, & &1.listing.id)

      listings =
        Enum.map(parsed_listings, fn parsed ->
          listing = Listings.persist_chain_listing(parsed)
          Listings.cache_listing(listing, opts, parsed.ref)
        end)

      Listings.remove_stale_listings(opts, chain_listing_ids)
      {:ok, listings}
    end
  end

  @doc "Lists active marketplace listings ordered by newest first."
  @spec list_listings(options()) :: [IntelListing.t()]
  def list_listings(opts) when is_list(opts) do
    _opts = opts

    Repo.all(
      from listing in IntelListing,
        where: listing.status == :active,
        order_by: [desc: listing.inserted_at]
    )
  end

  @doc "Lists all listings created by the given seller ordered by newest first."
  @spec list_seller_listings(String.t(), options()) :: [IntelListing.t()]
  def list_seller_listings(seller, opts) when is_binary(seller) and is_list(opts) do
    Repo.all(
      from listing in IntelListing,
        where: listing.seller_address == ^seller,
        order_by: [desc: listing.inserted_at]
    )
  end

  @doc "Lists sold listings purchased by the given buyer ordered by newest first."
  @spec list_purchased_listings(String.t(), options()) :: [IntelListing.t()]
  def list_purchased_listings(buyer, opts) when is_binary(buyer) and is_list(opts) do
    Repo.all(
      from listing in IntelListing,
        where: listing.buyer_address == ^buyer and listing.status == :sold,
        order_by: [desc: listing.inserted_at]
    )
  end

  @doc "Returns a cached listing or loads it from Postgres on a cache miss."
  @spec get_listing(String.t(), options()) :: IntelListing.t() | nil
  def get_listing(listing_id, opts) when is_binary(listing_id) and is_list(opts) do
    table = Support.market_table(opts)

    case Cache.get(table, {:listing, listing_id}) do
      %IntelListing{} = listing ->
        listing

      nil ->
        case Repo.get(IntelListing, listing_id) do
          %IntelListing{} = listing ->
            Cache.put(table, {:listing, listing_id}, listing)
            listing

          nil ->
            nil
        end
    end
  end

  @doc "Builds unsigned transaction bytes for creating a public intel listing."
  @spec build_create_listing_tx(map(), options()) ::
          {:ok, %{tx_bytes: String.t(), client_nonce: non_neg_integer()}}
          | {:error, :missing_sender | term()}
  defdelegate build_create_listing_tx(params, opts), to: Transactions

  @doc "Builds unsigned transaction bytes for creating a tribe-restricted intel listing."
  @spec build_create_restricted_listing_tx(map(), options()) ::
          {:ok, %{tx_bytes: String.t(), client_nonce: non_neg_integer()}}
          | {:error,
             :missing_sender
             | :missing_tribe_id
             | :no_active_custodian
             | term()}
  defdelegate build_create_restricted_listing_tx(params, opts), to: Transactions

  @doc "Builds pseudonymous listing transaction bytes with relay-sponsored gas."
  @spec build_pseudonym_create_listing_tx(map(), options()) ::
          {:ok,
           %{tx_bytes: String.t(), relay_signature: String.t(), client_nonce: non_neg_integer()}}
          | {:error, :missing_pseudonym | :missing_sender | term()}
  defdelegate build_pseudonym_create_listing_tx(params, opts), to: Transactions

  @doc "Builds unsigned transaction bytes for purchasing an active listing."
  @spec build_purchase_tx(String.t(), options()) ::
          {:ok, %{tx_bytes: String.t()}}
          | {:error,
             :listing_not_found
             | :listing_not_active
             | :missing_sender
             | :cannot_purchase_own_listing
             | :restricted_listing_requires_matching_tribe
             | :no_active_custodian
             | term()}
  defdelegate build_purchase_tx(listing_id, opts), to: Transactions

  @doc "Builds unsigned transaction bytes for cancelling an active listing."
  @spec build_cancel_listing_tx(String.t(), options()) ::
          {:ok, %{tx_bytes: String.t()}}
          | {:error, :missing_sender | :listing_not_found | :listing_not_active | term()}
  defdelegate build_cancel_listing_tx(listing_id, opts), to: Transactions

  @doc "Builds pseudonymous cancel-listing bytes when the active pseudonym owns the listing."
  @spec build_pseudonym_cancel_listing_tx(String.t(), options()) ::
          {:ok, %{tx_bytes: String.t(), relay_signature: String.t()}}
          | {:error,
             :missing_pseudonym
             | :missing_sender
             | :listing_not_found
             | :listing_not_active
             | :not_listing_owner
             | :relay_failed
             | term()}
  defdelegate build_pseudonym_cancel_listing_tx(listing_id, opts), to: Transactions

  @doc "Returns whether the encrypted Walrus blob for a listing is still available."
  @spec blob_available?(String.t(), options()) :: boolean()
  def blob_available?(listing_id, opts) when is_binary(listing_id) and is_list(opts) do
    walrus_client = Keyword.get(opts, :walrus_client, @walrus_client)

    case get_listing(listing_id, opts) do
      %IntelListing{encrypted_blob_id: encrypted_blob_id}
      when is_binary(encrypted_blob_id) and encrypted_blob_id != "" ->
        walrus_client.blob_exists?(encrypted_blob_id, opts)

      _other ->
        false
    end
  end

  @doc "Submits a wallet-signed transaction and applies the cached pending operation on success."
  @spec submit_signed_transaction(String.t(), String.t(), options()) ::
          {:ok, %{digest: String.t(), effects_bcs: String.t() | nil}} | {:error, term()}
  defdelegate submit_signed_transaction(tx_bytes, signature, opts), to: Transactions

  @doc "Submits a pseudonym+relay signed transaction and reconciles the pending marketplace op."
  @spec submit_pseudonym_transaction(String.t(), String.t(), String.t(), options()) ::
          {:ok, %{digest: String.t(), effects_bcs: String.t() | nil}}
          | {:error, :relay_submit_failed | :missing_sender | term()}
  defdelegate submit_pseudonym_transaction(tx_bytes, pseudonym_signature, relay_signature, opts),
    to: Transactions

  @doc "Returns seller reputation counters for listing-card display."
  @spec get_reputation(String.t(), options()) ::
          {:ok, %{positive: non_neg_integer(), negative: non_neg_integer()}}
          | {:error, :reputation_unavailable}
  defdelegate get_reputation(seller_address, opts), to: Reputation

  @doc "Returns whether feedback for a listing is already recorded for the seller."
  @spec feedback_recorded?(String.t(), String.t(), options()) :: boolean()
  defdelegate feedback_recorded?(seller_address, listing_id, opts), to: Reputation

  @doc "Builds buyer feedback transaction bytes for a positive quality confirmation."
  @spec build_confirm_quality_tx(String.t(), options()) ::
          {:ok, %{tx_bytes: String.t()}}
          | {:error,
             :listing_not_found
             | :listing_not_sold
             | :already_reviewed
             | :reputation_unavailable
             | term()}
  defdelegate build_confirm_quality_tx(listing_id, opts), to: Reputation

  @doc "Builds buyer feedback transaction bytes for a negative quality report."
  @spec build_report_bad_quality_tx(String.t(), options()) ::
          {:ok, %{tx_bytes: String.t()}}
          | {:error,
             :listing_not_found
             | :listing_not_sold
             | :already_reviewed
             | :reputation_unavailable
             | term()}
  defdelegate build_report_bad_quality_tx(listing_id, opts), to: Reputation

  @doc "Lists listings across all supplied pseudonym seller addresses."
  @spec list_all_seller_listings([String.t()], options()) :: [IntelListing.t()]
  def list_all_seller_listings([], opts) when is_list(opts), do: []

  def list_all_seller_listings(pseudonym_addresses, opts)
      when is_list(pseudonym_addresses) and is_list(opts) do
    _opts = opts

    Repo.all(
      from listing in IntelListing,
        where: listing.seller_address in ^pseudonym_addresses,
        order_by: [desc: listing.inserted_at]
    )
  end

  @doc "Submits wallet-signed feedback transactions without pending-op reconciliation."
  @spec submit_feedback_transaction(String.t(), String.t(), options()) ::
          {:ok, %{digest: String.t(), effects_bcs: String.t() | nil}} | {:error, term()}
  defdelegate submit_feedback_transaction(tx_bytes, signature, opts), to: Transactions

  @doc "Resolves a listing shared-object reference from opts, cache, or chain."
  @spec resolve_listing_ref(String.t(), options()) :: {:ok, listing_ref()} | {:error, term()}
  defdelegate resolve_listing_ref(listing_id, opts), to: Transactions
end
