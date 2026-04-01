defmodule Sigil.Diplomacy.LocalSigner do
  @moduledoc """
  Server-side transaction signing for localnet development.

  On localnet, wallet-based signing doesn't work (Slush can't resolve
  gas coins on local networks). This module builds full transactions
  from kind bytes, signs them with a locally-configured private key,
  and submits via JSON-RPC.

  Used only when `EVE_WORLD=localnet` and `SUI_LOCALNET_SIGNER_KEY` is set.
  On testnet/mainnet, the wallet handles signing via `Transaction.fromKind()`.
  """

  alias Sigil.Sui.{BCS, Base58, Signer, TransactionBuilder.PTB}
  alias Sigil.Worlds

  require Logger

  @typedoc "Result of a local sign-and-submit operation."
  @type submit_result :: {:ok, String.t()} | {:error, term()}

  @doc """
  Signs and submits a transaction locally using the configured signer key.

  Takes base64-encoded TransactionKind bytes, wraps them with sender/gas data,
  signs with the localnet private key, and submits via JSON-RPC.
  """
  @spec sign_and_submit(String.t(), keyword()) :: submit_result()
  def sign_and_submit(kind_bytes_b64, opts \\ [])
      when is_binary(kind_bytes_b64) and is_list(opts) do
    with {:ok, signer_key} <- fetch_signer_key(),
         {:ok, {privkey, pubkey}} <- parse_signer_key(signer_key) do
      sender_bytes = Signer.address_from_public_key(pubkey)
      sender_hex = Signer.to_sui_address(sender_bytes)

      with {:ok, gas_ref} <- fetch_gas_coin_ref(sender_hex, opts) do
        kind_bytes = Base.decode64!(kind_bytes_b64)

        tx_bytes =
          <<0x00>> <>
            kind_bytes <>
            BCS.encode_address(sender_bytes) <>
            PTB.encode_gas_data(%{
              payment: [gas_ref],
              owner: sender_bytes,
              price: 1_000,
              budget: 50_000_000
            }) <>
            PTB.encode_transaction_expiration(:none)

        tx_bytes_b64 = Base.encode64(tx_bytes)

        signature =
          tx_bytes
          |> Signer.sign(privkey)
          |> Signer.encode_signature(pubkey)
          |> Base.encode64()

        submit_via_rpc(tx_bytes_b64, signature, opts)
      end
    end
  end

  @doc "Returns the on-chain address derived from the localnet signer key, or nil."
  @spec signer_address() :: String.t() | nil
  def signer_address do
    case System.get_env("SUI_LOCALNET_SIGNER_KEY") do
      nil ->
        nil

      hex when byte_size(hex) == 64 ->
        with {:ok, privkey} <- Base.decode16(hex, case: :mixed) do
          {pubkey, _} = Signer.keypair_from_private_key(privkey)
          Signer.to_sui_address(Signer.address_from_public_key(pubkey))
        else
          _ -> nil
        end

      _ ->
        nil
    end
  end

  @doc """
  Fetches the initial_shared_version for a shared object via JSON-RPC.

  Falls back to 1 if RPC is unavailable.
  """
  @spec fetch_initial_shared_version(String.t(), keyword()) :: non_neg_integer()
  def fetch_initial_shared_version(object_id, opts \\ [])
      when is_binary(object_id) and is_list(opts) do
    url = rpc_url(opts)

    body = %{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => "sui_getObject",
      "params" => [object_id, %{"showOwner" => true}]
    }

    case Req.post(url, json: body, receive_timeout: 5_000) do
      {:ok,
       %{
         body: %{
           "result" => %{
             "data" => %{"owner" => %{"Shared" => %{"initial_shared_version" => v}}}
           }
         }
       }} ->
        v

      _ ->
        1
    end
  end

  # -- Private helpers --

  @spec fetch_signer_key() :: {:ok, String.t()} | {:error, :no_signer_key}
  defp fetch_signer_key do
    case System.get_env("SUI_LOCALNET_SIGNER_KEY") do
      nil -> {:error, :no_signer_key}
      key -> {:ok, key}
    end
  end

  @spec parse_signer_key(String.t()) :: {:ok, {binary(), binary()}} | {:error, :invalid_key}
  defp parse_signer_key(hex) when byte_size(hex) == 64 do
    case Base.decode16(hex, case: :mixed) do
      {:ok, <<_::binary-size(32)>> = privkey} ->
        {pubkey, _} = Signer.keypair_from_private_key(privkey)
        {:ok, {privkey, pubkey}}

      _ ->
        {:error, :invalid_key}
    end
  end

  defp parse_signer_key(_other), do: {:error, :invalid_key}

  @spec fetch_gas_coin_ref(String.t(), keyword()) ::
          {:ok, Sigil.Sui.Client.object_ref()} | {:error, :no_gas_coins}
  defp fetch_gas_coin_ref(sender, opts) when is_binary(sender) and is_list(opts),
    do: fetch_gas_coin_ref_via_rpc(rpc_url(opts), sender)

  @spec fetch_gas_coin_ref_via_rpc(String.t(), String.t()) ::
          {:ok, Sigil.Sui.Client.object_ref()} | {:error, :no_gas_coins}
  defp fetch_gas_coin_ref_via_rpc(url, sender) do
    body = %{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => "suix_getCoins",
      "params" => [sender, "0x2::sui::SUI", nil, 1]
    }

    case Req.post(url, json: body, receive_timeout: 5_000) do
      {:ok, %{status: 200, body: %{"result" => %{"data" => [coin | _]}}}} ->
        coin_id = coin["coinObjectId"]
        version = coin["version"] |> to_string() |> String.to_integer()
        digest_bytes = Base58.decode!(coin["digest"])

        padded = coin_id |> String.trim_leading("0x") |> String.pad_leading(64, "0")
        {:ok, id_bytes} = Base.decode16(padded, case: :mixed)

        {:ok, {id_bytes, version, digest_bytes}}

      _ ->
        {:error, :no_gas_coins}
    end
  end

  @spec submit_via_rpc(String.t(), String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  defp submit_via_rpc(tx_bytes_b64, signature, opts)
       when is_binary(tx_bytes_b64) and is_binary(signature) and is_list(opts) do
    body = %{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => "sui_executeTransactionBlock",
      "params" => [
        tx_bytes_b64,
        [signature],
        %{"showEffects" => true},
        "WaitForEffectsCert"
      ]
    }

    url = rpc_url(opts)

    case Req.post(url, json: body, receive_timeout: 10_000) do
      {:ok,
       %{
         status: 200,
         body: %{
           "result" => %{
             "digest" => digest,
             "effects" => %{"status" => %{"status" => "success"}}
           }
         }
       }} ->
        {:ok, digest}

      {:ok,
       %{
         status: 200,
         body: %{
           "result" => %{
             "digest" => _digest,
             "effects" => %{"status" => %{"status" => status} = status_detail}
           }
         }
       }} ->
        error_msg = Map.get(status_detail, "error", status)

        Logger.warning("[local_signer] transaction execution failed: #{inspect(error_msg)}")

        {:error, {:tx_failed, error_msg}}

      {:ok, %{status: 200, body: %{"error" => error}}} ->
        {:error, {:rpc_error, error["message"] || inspect(error)}}

      {:ok, resp} ->
        Logger.warning("[local_signer] unexpected RPC response: #{inspect(resp.body)}")
        {:error, :unexpected_response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec rpc_url(keyword()) :: String.t()
  defp rpc_url(opts) when is_list(opts) do
    opts
    |> Keyword.get(:world, Worlds.default_world())
    |> Worlds.rpc_url()
  end
end
