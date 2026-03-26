defmodule Sigil.IntelMarket do
  @moduledoc """
  Intel marketplace context for cache-backed listing discovery and transaction handling.
  """

  import Ecto.Query

  alias Sigil.Cache
  alias Sigil.Diplomacy
  alias Sigil.Diplomacy.ObjectCodec
  alias Sigil.Intel.IntelListing
  alias Sigil.IntelMarket.{Listings, PendingOps, Support}
  alias Sigil.Repo
  alias Sigil.Sui.{Client, TransactionBuilder, TxIntelMarket}

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
  def build_create_listing_tx(params, opts) when is_map(params) and is_list(opts) do
    with {:ok, sender} <- require_sender(opts) do
      client_nonce = System.unique_integer([:positive])
      builder_params = build_listing_params(params, client_nonce)

      tx_bytes =
        builder_params
        |> TxIntelMarket.build_create_listing([])
        |> TransactionBuilder.build_kind!()
        |> Base.encode64()

      pending =
        builder_params
        |> Map.merge(%{
          intel_report_id: Map.get(params, :intel_report_id),
          seller_address: sender,
          restricted_to_tribe_id: nil
        })

      store_pending_tx(opts, sender, tx_bytes, {:create_listing, pending})
      {:ok, %{tx_bytes: tx_bytes, client_nonce: client_nonce}}
    end
  end

  @doc "Builds unsigned transaction bytes for creating a tribe-restricted intel listing."
  @spec build_create_restricted_listing_tx(map(), options()) ::
          {:ok, %{tx_bytes: String.t(), client_nonce: non_neg_integer()}}
          | {:error,
             :missing_sender
             | :missing_tribe_id
             | :no_active_custodian
             | term()}
  def build_create_restricted_listing_tx(params, opts) when is_map(params) and is_list(opts) do
    with {:ok, sender} <- require_sender(opts),
         {:ok, tribe_id} <- require_tribe_id(opts),
         {:ok, custodian_ref} <- require_custodian_ref(opts, tribe_id) do
      client_nonce = System.unique_integer([:positive])
      builder_params = build_listing_params(params, client_nonce)

      tx_bytes =
        TxIntelMarket.build_create_restricted_listing(custodian_ref, builder_params, [])
        |> TransactionBuilder.build_kind!()
        |> Base.encode64()

      pending =
        builder_params
        |> Map.merge(%{
          intel_report_id: Map.get(params, :intel_report_id),
          seller_address: sender,
          restricted_to_tribe_id: tribe_id
        })

      store_pending_tx(opts, sender, tx_bytes, {:create_listing, pending})
      {:ok, %{tx_bytes: tx_bytes, client_nonce: client_nonce}}
    end
  end

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
  def build_purchase_tx(listing_id, opts) when is_binary(listing_id) and is_list(opts) do
    with {:ok, sender} <- require_sender(opts),
         %IntelListing{} = listing <- get_listing(listing_id, opts),
         :ok <- ensure_active_listing(listing),
         :ok <- ensure_not_self_purchase(listing, sender),
         {:ok, listing_ref} <- resolve_listing_ref(listing_id, opts),
         {:ok, tx_bytes} <- build_purchase_bytes(listing, listing_ref, opts) do
      store_pending_tx(
        opts,
        sender,
        tx_bytes,
        {:purchase, %{listing_id: listing.id, buyer_address: sender}}
      )

      {:ok, %{tx_bytes: tx_bytes}}
    else
      nil -> {:error, :listing_not_found}
      {:error, _reason} = error -> error
    end
  end

  @doc "Builds unsigned transaction bytes for cancelling an active listing."
  @spec build_cancel_listing_tx(String.t(), options()) ::
          {:ok, %{tx_bytes: String.t()}}
          | {:error, :missing_sender | :listing_not_found | :listing_not_active | term()}
  def build_cancel_listing_tx(listing_id, opts) when is_binary(listing_id) and is_list(opts) do
    with {:ok, sender} <- require_sender(opts),
         %IntelListing{} = listing <- get_listing(listing_id, opts),
         :ok <- ensure_active_listing(listing),
         {:ok, listing_ref} <- resolve_listing_ref(listing_id, opts) do
      tx_bytes =
        listing_ref
        |> TxIntelMarket.build_cancel_listing([])
        |> TransactionBuilder.build_kind!()
        |> Base.encode64()

      store_pending_tx(opts, sender, tx_bytes, {:cancel_listing, %{listing_id: listing.id}})
      {:ok, %{tx_bytes: tx_bytes}}
    else
      nil -> {:error, :listing_not_found}
      {:error, _reason} = error -> error
    end
  end

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
  def submit_signed_transaction(tx_bytes, signature, opts)
      when is_binary(tx_bytes) and is_binary(signature) and is_list(opts) do
    client = Keyword.get(opts, :client, @sui_client)
    req_options = Keyword.get(opts, :req_options, [])

    case client.execute_transaction(tx_bytes, [signature], req_options) do
      {:ok, %{"status" => "SUCCESS", "transaction" => %{"digest" => digest}} = effects} ->
        with {:ok, sender} <- require_sender(opts),
             operation when not is_nil(operation) <- get_pending_tx(opts, sender, tx_bytes),
             {:ok, _result} <- PendingOps.apply(opts, operation, effects, digest) do
          clear_pending_tx(opts, sender, tx_bytes)
          {:ok, %{digest: digest, effects_bcs: effects["bcs"]}}
        else
          nil -> {:error, :pending_tx_not_found}
          {:error, _reason} = error -> error
        end

      {:ok, effects} ->
        {:error, {:tx_failed, effects}}

      {:error, _reason} = error ->
        error
    end
  end

  @doc "Resolves a listing shared-object reference from opts, cache, or chain."
  @spec resolve_listing_ref(String.t(), options()) :: {:ok, listing_ref()} | {:error, term()}
  def resolve_listing_ref(listing_id, opts) when is_binary(listing_id) and is_list(opts) do
    table = Support.market_table(opts)

    case Cache.get(table, {:listing_ref, listing_id}) do
      listing_ref when is_map(listing_ref) ->
        {:ok, listing_ref}

      nil ->
        client = Keyword.get(opts, :client, @sui_client)
        req_options = Keyword.get(opts, :req_options, [])

        with {:ok, %{json: object}} <- client.get_object_with_ref(listing_id, req_options),
             version when is_integer(version) <- ObjectCodec.parse_shared_version(object) do
          listing_ref = %{
            object_id: ObjectCodec.hex_to_bytes(listing_id),
            initial_shared_version: version
          }

          Cache.put(table, {:listing_ref, listing_id}, listing_ref)
          {:ok, listing_ref}
        else
          nil -> {:error, :listing_not_found}
          {:error, _reason} = error -> error
        end
    end
  end

  @spec build_listing_params(map(), non_neg_integer()) :: TxIntelMarket.listing_params()
  defp build_listing_params(params, client_nonce) do
    %{
      seal_id: decode_seal_id!(Map.fetch!(params, :seal_id)),
      encrypted_blob_id: encode_blob_id(Map.fetch!(params, :encrypted_blob_id)),
      client_nonce: client_nonce,
      price: Map.fetch!(params, :price),
      report_type: Map.fetch!(params, :report_type),
      solar_system_id: Map.fetch!(params, :solar_system_id),
      description: Map.fetch!(params, :description)
    }
  end

  @spec build_purchase_bytes(IntelListing.t(), listing_ref(), options()) ::
          {:ok, String.t()}
          | {:error,
             :restricted_listing_requires_matching_tribe
             | :missing_tribe_id
             | :no_active_custodian}
  defp build_purchase_bytes(listing, listing_ref, opts) do
    tx_bytes =
      case listing.restricted_to_tribe_id do
        nil ->
          listing_ref
          |> TxIntelMarket.build_purchase(listing.price_mist, [])
          |> TransactionBuilder.build_kind!()
          |> Base.encode64()

        restricted_tribe_id ->
          with {:ok, tribe_id} <- require_tribe_id(opts),
               :ok <- ensure_matching_tribe(tribe_id, restricted_tribe_id),
               {:ok, custodian_ref} <- require_custodian_ref(opts, tribe_id) do
            listing_ref
            |> TxIntelMarket.build_purchase_restricted(custodian_ref, listing.price_mist, [])
            |> TransactionBuilder.build_kind!()
            |> Base.encode64()
          end
      end

    case tx_bytes do
      {:error, _reason} = error -> error
      encoded when is_binary(encoded) -> {:ok, encoded}
    end
  end

  @spec require_custodian_ref(options(), non_neg_integer()) ::
          {:ok, TxIntelMarket.custodian_ref()} | {:error, :no_active_custodian | term()}
  defp require_custodian_ref(opts, tribe_id) do
    case Diplomacy.get_active_custodian(opts) do
      %{object_id_bytes: object_id_bytes, initial_shared_version: initial_shared_version} ->
        {:ok, %{object_id: object_id_bytes, initial_shared_version: initial_shared_version}}

      nil ->
        case Diplomacy.discover_custodian(tribe_id, opts) do
          {:ok,
           %{object_id_bytes: object_id_bytes, initial_shared_version: initial_shared_version}} ->
            {:ok, %{object_id: object_id_bytes, initial_shared_version: initial_shared_version}}

          {:ok, nil} ->
            {:error, :no_active_custodian}

          {:error, _reason} = error ->
            error
        end
    end
  end

  @spec require_sender(options()) :: {:ok, String.t()} | {:error, :missing_sender}
  defp require_sender(opts) do
    case Keyword.get(opts, :sender) do
      sender when is_binary(sender) -> {:ok, sender}
      _other -> {:error, :missing_sender}
    end
  end

  @spec require_tribe_id(options()) :: {:ok, non_neg_integer()} | {:error, :missing_tribe_id}
  defp require_tribe_id(opts) do
    case Keyword.get(opts, :tribe_id) do
      tribe_id when is_integer(tribe_id) and tribe_id >= 0 -> {:ok, tribe_id}
      _other -> {:error, :missing_tribe_id}
    end
  end

  @spec ensure_active_listing(IntelListing.t()) :: :ok | {:error, :listing_not_active}
  defp ensure_active_listing(%IntelListing{status: :active}), do: :ok
  defp ensure_active_listing(%IntelListing{}), do: {:error, :listing_not_active}

  @spec ensure_not_self_purchase(IntelListing.t(), String.t()) ::
          :ok | {:error, :cannot_purchase_own_listing}
  defp ensure_not_self_purchase(%IntelListing{seller_address: seller_address}, sender)
       when seller_address == sender,
       do: {:error, :cannot_purchase_own_listing}

  defp ensure_not_self_purchase(_listing, _sender), do: :ok

  @spec ensure_matching_tribe(non_neg_integer(), non_neg_integer()) ::
          :ok | {:error, :restricted_listing_requires_matching_tribe}
  defp ensure_matching_tribe(tribe_id, tribe_id), do: :ok

  defp ensure_matching_tribe(_buyer_tribe_id, _restricted_tribe_id),
    do: {:error, :restricted_listing_requires_matching_tribe}

  @spec store_pending_tx(options(), String.t(), String.t(), term()) :: :ok
  defp store_pending_tx(opts, sender, tx_bytes, operation) do
    Cache.put(Support.market_table(opts), {:pending_tx, sender, tx_bytes}, operation)
  end

  @spec get_pending_tx(options(), String.t(), String.t()) :: term() | nil
  defp get_pending_tx(opts, sender, tx_bytes) do
    Cache.get(Support.market_table(opts), {:pending_tx, sender, tx_bytes})
  end

  @spec clear_pending_tx(options(), String.t(), String.t()) :: :ok
  defp clear_pending_tx(opts, sender, tx_bytes) do
    Cache.delete(Support.market_table(opts), {:pending_tx, sender, tx_bytes})
  end

  @spec decode_seal_id!(String.t() | binary()) :: binary()
  defp decode_seal_id!("0x" <> hex), do: Base.decode16!(hex, case: :mixed)
  defp decode_seal_id!(value) when is_binary(value), do: value

  @spec encode_blob_id(String.t() | binary()) :: binary()
  defp encode_blob_id(value) when is_binary(value), do: value
end
