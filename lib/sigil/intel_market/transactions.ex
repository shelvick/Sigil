defmodule Sigil.IntelMarket.Transactions do
  @moduledoc """
  Transaction builders and submission helpers for intel marketplace operations.
  """

  alias Sigil.Cache
  alias Sigil.Diplomacy
  alias Sigil.Diplomacy.ObjectCodec
  alias Sigil.Intel.IntelListing
  alias Sigil.IntelMarket
  alias Sigil.IntelMarket.{PendingOps, Support}
  alias Sigil.Sui.{GasRelay, TransactionBuilder, TxIntelMarket}

  @sui_client Application.compile_env!(:sigil, :sui_client)

  @doc "Builds unsigned transaction bytes for creating a public intel listing."
  @spec build_create_listing_tx(map(), IntelMarket.options()) ::
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
  @spec build_create_restricted_listing_tx(map(), IntelMarket.options()) ::
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

  @doc "Builds pseudonymous listing transaction bytes with relay-sponsored gas."
  @spec build_pseudonym_create_listing_tx(map(), IntelMarket.options()) ::
          {:ok,
           %{tx_bytes: String.t(), relay_signature: String.t(), client_nonce: non_neg_integer()}}
          | {:error, :missing_pseudonym | :missing_sender | term()}
  def build_pseudonym_create_listing_tx(params, opts) when is_map(params) and is_list(opts) do
    with {:ok, pseudonym_address} <- require_pseudonym_address(opts),
         {:ok, sender} <- require_sender(opts),
         {:ok, listing_kind_opts, pending, client_nonce} <-
           build_pseudonym_listing_kind(params, pseudonym_address, opts),
         {:ok, %{tx_bytes: tx_bytes, relay_signature: relay_signature}} <-
           listing_kind_opts
           |> GasRelay.prepare_sponsored(pseudonym_address, opts)
           |> map_relay_prepare_result() do
      store_pending_tx(opts, sender, tx_bytes, {:create_listing, pending})

      {:ok, %{tx_bytes: tx_bytes, relay_signature: relay_signature, client_nonce: client_nonce}}
    else
      {:error, _reason} = error -> error
    end
  end

  @doc "Builds unsigned transaction bytes for purchasing an active listing."
  @spec build_purchase_tx(String.t(), IntelMarket.options()) ::
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
         %IntelListing{} = listing <- IntelMarket.get_listing(listing_id, opts),
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
  @spec build_cancel_listing_tx(String.t(), IntelMarket.options()) ::
          {:ok, %{tx_bytes: String.t()}}
          | {:error, :missing_sender | :listing_not_found | :listing_not_active | term()}
  def build_cancel_listing_tx(listing_id, opts) when is_binary(listing_id) and is_list(opts) do
    with {:ok, sender} <- require_sender(opts),
         %IntelListing{} = listing <- IntelMarket.get_listing(listing_id, opts),
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

  @doc "Builds pseudonymous cancel-listing bytes when the active pseudonym owns the listing."
  @spec build_pseudonym_cancel_listing_tx(String.t(), IntelMarket.options()) ::
          {:ok, %{tx_bytes: String.t(), relay_signature: String.t()}}
          | {:error,
             :missing_pseudonym
             | :missing_sender
             | :listing_not_found
             | :listing_not_active
             | :not_listing_owner
             | :relay_failed
             | term()}
  def build_pseudonym_cancel_listing_tx(listing_id, opts)
      when is_binary(listing_id) and is_list(opts) do
    with {:ok, pseudonym_address} <- require_pseudonym_address(opts),
         {:ok, sender} <- require_sender(opts),
         %IntelListing{} = listing <- IntelMarket.get_listing(listing_id, opts),
         :ok <- ensure_active_listing(listing),
         :ok <- ensure_listing_owner(listing, pseudonym_address),
         {:ok, listing_ref} <- resolve_listing_ref(listing_id, opts),
         {:ok, %{tx_bytes: tx_bytes, relay_signature: relay_signature}} <-
           build_pseudonym_cancel_sponsored(listing_ref, pseudonym_address, opts) do
      store_pending_tx(opts, sender, tx_bytes, {:cancel_listing, %{listing_id: listing.id}})
      {:ok, %{tx_bytes: tx_bytes, relay_signature: relay_signature}}
    else
      nil -> {:error, :listing_not_found}
      {:error, _reason} = error -> error
    end
  end

  @doc "Submits a wallet-signed transaction and applies the cached pending operation on success."
  @spec submit_signed_transaction(String.t(), String.t(), IntelMarket.options()) ::
          {:ok, %{digest: String.t(), effects_bcs: String.t() | nil}} | {:error, term()}
  def submit_signed_transaction(tx_bytes, signature, opts)
      when is_binary(tx_bytes) and is_binary(signature) and is_list(opts) do
    client = Keyword.get(opts, :client, @sui_client)
    req_options = Keyword.get(opts, :req_options, [])

    case client.execute_transaction(tx_bytes, [signature], req_options) do
      {:ok, %{"status" => "SUCCESS", "digest" => digest} = effects} ->
        with {:ok, sender} <- require_sender(opts),
             operation when not is_nil(operation) <- get_pending_tx(opts, sender, tx_bytes),
             {:ok, _result} <- PendingOps.apply(opts, operation, effects, digest) do
          clear_pending_tx(opts, sender, tx_bytes)
          {:ok, %{digest: digest, effects_bcs: effects["effectsBcs"]}}
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

  @doc "Submits a pseudonym+relay signed transaction and reconciles the pending marketplace op."
  @spec submit_pseudonym_transaction(String.t(), String.t(), String.t(), IntelMarket.options()) ::
          {:ok, %{digest: String.t(), effects_bcs: String.t() | nil}}
          | {:error, :relay_submit_failed | :missing_sender | term()}
  def submit_pseudonym_transaction(tx_bytes, pseudonym_signature, relay_signature, opts)
      when is_binary(tx_bytes) and is_binary(pseudonym_signature) and is_binary(relay_signature) and
             is_list(opts) do
    with {:ok, sender} <- require_sender(opts),
         operation when not is_nil(operation) <- get_pending_tx(opts, sender, tx_bytes),
         {:ok, %{digest: digest, effects_bcs: effects_bcs, effects: effects}} <-
           GasRelay.submit_sponsored(tx_bytes, pseudonym_signature, relay_signature, opts),
         {:ok, _result} <- PendingOps.apply(opts, operation, effects, digest) do
      clear_pending_tx(opts, sender, tx_bytes)
      {:ok, %{digest: digest, effects_bcs: effects_bcs}}
    else
      nil -> {:error, :relay_submit_failed}
      {:error, _reason} = error -> error
    end
  end

  @doc "Submits wallet-signed feedback transactions without pending-op reconciliation."
  @spec submit_feedback_transaction(String.t(), String.t(), IntelMarket.options()) ::
          {:ok, %{digest: String.t(), effects_bcs: String.t() | nil}} | {:error, term()}
  def submit_feedback_transaction(tx_bytes, signature, opts)
      when is_binary(tx_bytes) and is_binary(signature) and is_list(opts) do
    client = Keyword.get(opts, :client, @sui_client)
    req_options = Keyword.get(opts, :req_options, [])

    case client.execute_transaction(tx_bytes, [signature], req_options) do
      {:ok, %{"status" => "SUCCESS", "digest" => digest} = effects} ->
        {:ok, %{digest: digest, effects_bcs: effects["effectsBcs"]}}

      {:ok, effects} ->
        {:error, {:tx_failed, effects}}

      {:error, _reason} = error ->
        error
    end
  end

  @doc "Resolves a listing shared-object reference from opts, cache, or chain."
  @spec resolve_listing_ref(String.t(), IntelMarket.options()) ::
          {:ok, IntelMarket.listing_ref()} | {:error, term()}
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

  @spec build_pseudonym_listing_kind(map(), String.t(), IntelMarket.options()) ::
          {:ok, TransactionBuilder.kind_opts(), IntelMarket.pending_create_listing(),
           non_neg_integer()}
          | {:error, :no_active_custodian | :missing_tribe_id | term()}
  defp build_pseudonym_listing_kind(params, pseudonym_address, opts) do
    client_nonce = System.unique_integer([:positive])
    builder_params = build_listing_params(params, client_nonce)
    restricted_tribe_id = Map.get(params, :restricted_to_tribe_id)

    listing_kind_opts =
      case restricted_tribe_id do
        tribe_id when is_integer(tribe_id) and tribe_id >= 0 ->
          with {:ok, custodian_ref} <- require_custodian_ref(opts, tribe_id) do
            TxIntelMarket.build_create_restricted_listing(custodian_ref, builder_params, [])
          end

        _other ->
          TxIntelMarket.build_create_listing(builder_params, [])
      end

    case listing_kind_opts do
      {:error, _reason} = error ->
        error

      kind_opts when is_list(kind_opts) ->
        pending =
          builder_params
          |> Map.merge(%{
            intel_report_id: Map.get(params, :intel_report_id),
            seller_address: pseudonym_address,
            restricted_to_tribe_id: restricted_tribe_id
          })

        {:ok, kind_opts, pending, client_nonce}
    end
  end

  @spec build_pseudonym_cancel_sponsored(
          IntelMarket.listing_ref(),
          String.t(),
          IntelMarket.options()
        ) ::
          {:ok, %{tx_bytes: String.t(), relay_signature: String.t()}}
          | {:error, :relay_failed | term()}
  defp build_pseudonym_cancel_sponsored(listing_ref, pseudonym_address, opts) do
    listing_ref
    |> TxIntelMarket.build_cancel_listing([])
    |> GasRelay.prepare_sponsored(pseudonym_address, opts)
    |> map_relay_prepare_result()
  end

  @spec map_relay_prepare_result(
          {:ok, %{tx_bytes: String.t(), relay_signature: String.t()}}
          | {:error, term()}
        ) ::
          {:ok, %{tx_bytes: String.t(), relay_signature: String.t()}}
          | {:error, :relay_failed | term()}
  defp map_relay_prepare_result({:ok, %{tx_bytes: tx_bytes, relay_signature: relay_signature}})
       when is_binary(tx_bytes) and is_binary(relay_signature) do
    {:ok, %{tx_bytes: tx_bytes, relay_signature: relay_signature}}
  end

  defp map_relay_prepare_result({:error, reason})
       when reason in [:no_gas_coins, :insufficient_gas],
       do: {:error, :relay_failed}

  defp map_relay_prepare_result({:error, reason}), do: {:error, reason}

  @spec build_purchase_bytes(IntelListing.t(), IntelMarket.listing_ref(), IntelMarket.options()) ::
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

  @spec require_custodian_ref(IntelMarket.options(), non_neg_integer()) ::
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

  @spec require_sender(IntelMarket.options()) :: {:ok, String.t()} | {:error, :missing_sender}
  defp require_sender(opts) do
    case Keyword.get(opts, :sender) do
      sender when is_binary(sender) -> {:ok, sender}
      _other -> {:error, :missing_sender}
    end
  end

  @spec require_tribe_id(IntelMarket.options()) ::
          {:ok, non_neg_integer()} | {:error, :missing_tribe_id}
  defp require_tribe_id(opts) do
    case Keyword.get(opts, :tribe_id) do
      tribe_id when is_integer(tribe_id) and tribe_id >= 0 -> {:ok, tribe_id}
      _other -> {:error, :missing_tribe_id}
    end
  end

  @spec require_pseudonym_address(IntelMarket.options()) ::
          {:ok, String.t()} | {:error, :missing_pseudonym}
  defp require_pseudonym_address(opts) do
    case Keyword.get(opts, :pseudonym_address) do
      pseudonym_address when is_binary(pseudonym_address) -> {:ok, pseudonym_address}
      _other -> {:error, :missing_pseudonym}
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

  @spec ensure_listing_owner(IntelListing.t(), String.t()) :: :ok | {:error, :not_listing_owner}
  defp ensure_listing_owner(%IntelListing{seller_address: seller_address}, pseudonym_address)
       when seller_address == pseudonym_address,
       do: :ok

  defp ensure_listing_owner(%IntelListing{}, _pseudonym_address), do: {:error, :not_listing_owner}

  @spec ensure_matching_tribe(non_neg_integer(), non_neg_integer()) ::
          :ok | {:error, :restricted_listing_requires_matching_tribe}
  defp ensure_matching_tribe(tribe_id, tribe_id), do: :ok

  defp ensure_matching_tribe(_buyer_tribe_id, _restricted_tribe_id),
    do: {:error, :restricted_listing_requires_matching_tribe}

  @spec store_pending_tx(IntelMarket.options(), String.t(), String.t(), term()) :: :ok
  defp store_pending_tx(opts, sender, tx_bytes, operation) do
    Cache.put(Support.market_table(opts), {:pending_tx, sender, tx_bytes}, operation)
  end

  @spec get_pending_tx(IntelMarket.options(), String.t(), String.t()) :: term() | nil
  defp get_pending_tx(opts, sender, tx_bytes) do
    Cache.get(Support.market_table(opts), {:pending_tx, sender, tx_bytes})
  end

  @spec clear_pending_tx(IntelMarket.options(), String.t(), String.t()) :: :ok
  defp clear_pending_tx(opts, sender, tx_bytes) do
    Cache.delete(Support.market_table(opts), {:pending_tx, sender, tx_bytes})
  end

  @spec decode_seal_id!(String.t() | binary()) :: binary()
  defp decode_seal_id!("0x" <> hex), do: Base.decode16!(hex, case: :mixed)
  defp decode_seal_id!(value) when is_binary(value), do: value

  @spec encode_blob_id(String.t() | binary()) :: binary()
  defp encode_blob_id(value) when is_binary(value), do: value
end
