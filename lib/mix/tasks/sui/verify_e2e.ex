defmodule Mix.Tasks.Sui.VerifyE2e do
  @moduledoc """
  Manual end-to-end verification of the Sui integration pipeline.

  Proves the read path (Client.HTTP.get_objects) and write path
  (TransactionBuilder build + Signer sign + Client.HTTP submit) work
  against the live Sui testnet.

  NOT part of the automated test suite.

  ## Usage

      SUI_TEST_PRIVATE_KEY=<hex-encoded-32-byte-key> mix sui.verify_e2e

  ## Prerequisites

  - A funded Sui testnet address (request from faucet: https://faucet.testnet.sui.io)
  """

  use Mix.Task

  alias Sigil.Sui.Client
  alias Sigil.Sui.Signer
  alias Sigil.Sui.TransactionBuilder

  @shortdoc "Manual E2E verification of Sui integration"

  @gas_budget 100_000_000

  @doc "Runs the E2E verification."
  @dialyzer {:nowarn_function, run: 1}
  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(_args) do
    {:ok, _apps} = Application.ensure_all_started(:req)

    info("Sui E2E Verification")
    info("====================")

    # Step 1: Derive key material
    private_key = read_private_key!()
    {public_key, _priv} = Signer.keypair_from_private_key(private_key)
    address = Signer.address_from_public_key(public_key)
    sui_address = Signer.to_sui_address(address)
    info("Address: #{sui_address}")
    info("")

    # Step 2: Read path — prove Client.HTTP can query the Sui GraphQL API
    info("Step 1: Read path (get_objects)...")

    case Client.HTTP.get_objects(
           [type: "0x2::coin::Coin<0x2::sui::SUI>", owner: sui_address, limit: 1],
           []
         ) do
      {:ok, %{data: coins}} ->
        info("  OK — Client.HTTP.get_objects returned #{length(coins)} coin(s)")

      {:error, reason} ->
        fail!("  Read path failed: #{inspect(reason)}")
    end

    # Step 3: Fetch coin with full ref data for gas payment
    info("")
    info("Step 2: Fetch coin object ref (get_object_with_ref)...")
    coin_ref = fetch_coin_ref!(sui_address)
    {coin_id, coin_version, _coin_digest} = coin_ref

    info("  OK — coin: 0x#{Base.encode16(coin_id, case: :lower)}, version: #{coin_version}")

    # Step 4: Write path — build, sign, submit a minimal PTB
    info("")
    info("Step 3: Write path (build + sign + submit)...")

    tx_opts = [
      sender: address,
      gas_payment: [coin_ref],
      gas_price: 1000,
      gas_budget: @gas_budget,
      inputs: [],
      commands: [
        {:move_call, <<0::248, 1::8>>, "vector", "empty", [:u8], []}
      ]
    ]

    case TransactionBuilder.execute(tx_opts, private_key, public_key) do
      {:ok, effects} ->
        digest = get_in(effects, ["transaction", "digest"]) || "unknown"
        status = effects["status"] || "unknown"
        info("  OK — Transaction submitted!")
        info("  Digest: #{digest}")
        info("  Status: #{inspect(status)}")

        gas_summary = get_in(effects, ["gasEffects", "gasSummary"])

        if gas_summary do
          info(
            "  Gas: computation=#{gas_summary["computationCost"]}, " <>
              "storage=#{gas_summary["storageCost"]}, " <>
              "rebate=#{gas_summary["storageRebate"]}"
          )
        end

      {:error, reason} ->
        fail!("  Write path failed: #{inspect(reason)}")
    end

    info("")
    info("====================")
    info("E2E verification PASSED.")
    :ok
  end

  @spec read_private_key!() :: binary()
  defp read_private_key! do
    case System.get_env("SUI_TEST_PRIVATE_KEY") do
      nil ->
        Mix.raise(
          "SUI_TEST_PRIVATE_KEY not set. " <>
            "Export a hex-encoded 32-byte Ed25519 private key."
        )

      hex ->
        case Base.decode16(hex, case: :mixed) do
          {:ok, key} when byte_size(key) == 32 -> key
          _ -> Mix.raise("SUI_TEST_PRIVATE_KEY must be 64 hex chars (32 bytes).")
        end
    end
  end

  @spec fetch_coin_ref!(String.t()) :: Client.object_ref()
  defp fetch_coin_ref!(sui_address) do
    coin_address =
      case Client.HTTP.get_objects(
             [type: "0x2::coin::Coin<0x2::sui::SUI>", owner: sui_address, limit: 1],
             []
           ) do
        {:ok, %{data: [coin | _]}} ->
          coin["id"] || fail!("  Coin JSON missing 'id' field")

        {:ok, %{data: []}} ->
          fail!(
            "  No SUI coins found. Fund this address on testnet: https://faucet.testnet.sui.io"
          )

        {:error, reason} ->
          fail!("  Failed to fetch coins: #{inspect(reason)}")
      end

    case Client.HTTP.get_object_with_ref(coin_address) do
      {:ok, %{ref: ref}} ->
        ref

      {:error, reason} ->
        fail!("  Failed to fetch coin ref: #{inspect(reason)}")
    end
  end

  @spec info(String.t()) :: :ok
  defp info(msg), do: Mix.shell().info(msg)

  @spec fail!(String.t()) :: no_return()
  defp fail!(msg) do
    Mix.shell().error(msg)
    Mix.raise("E2E verification FAILED.")
  end
end
