defmodule Sigil.Sui.GasRelayTestClient do
  @moduledoc """
  Minimal client double that records gas relay requests inside the calling test.
  """

  @doc "Returns the configured coin lookup result after notifying the test process."
  @spec get_coins(String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def get_coins(owner, opts) do
    send(Keyword.fetch!(opts, :test_pid), {:get_coins, owner, opts})
    Keyword.fetch!(opts, :get_coins_result)
  end

  @doc "Returns the configured execute result after notifying the test process."
  @spec execute_transaction(String.t(), [String.t()], keyword()) ::
          {:ok, map()} | {:error, term()}
  def execute_transaction(tx_bytes, signatures, opts) do
    send(Keyword.fetch!(opts, :test_pid), {:execute_transaction, tx_bytes, signatures, opts})
    Keyword.fetch!(opts, :execute_result)
  end
end

defmodule Sigil.Sui.PseudonymListingFlow do
  @moduledoc """
  Minimal seller-facing flow wrapper used by the acceptance-style gas relay test.
  """

  alias Sigil.Sui.{GasRelay, Signer}

  @doc "Runs pseudonymous listing creation through the gas relay boundary."
  @spec create_listing(keyword()) ::
          {:ok, %{digest: String.t(), effects_bcs: String.t()}} | {:error, term()}
  def create_listing(opts) do
    pseudonym_keypair = Keyword.fetch!(opts, :pseudonym_keypair)

    pseudonym_address =
      pseudonym_keypair
      |> elem(0)
      |> Signer.address_from_public_key()
      |> Signer.to_sui_address()

    with {:ok, %{tx_bytes: tx_bytes_b64, relay_signature: relay_signature}} <-
           GasRelay.prepare_sponsored(
             Keyword.fetch!(opts, :kind_opts),
             pseudonym_address,
             Keyword.take(opts, [
               :client,
               :test_pid,
               :get_coins_result,
               :relay_keypair,
               :gas_budget,
               :key_path
             ])
           ) do
      pseudonym_signature =
        tx_bytes_b64
        |> Base.decode64!()
        |> Signer.sign(elem(pseudonym_keypair, 1))
        |> Signer.encode_signature(elem(pseudonym_keypair, 0))
        |> Base.encode64()

      GasRelay.submit_sponsored(
        tx_bytes_b64,
        pseudonym_signature,
        relay_signature,
        Keyword.take(opts, [:client, :test_pid, :execute_result])
      )
    end
  end
end

defmodule Sigil.Sui.GasRelayTest do
  @moduledoc """
  Captures the packet 2 gas relay contract before implementation.
  """

  use ExUnit.Case, async: true

  alias Sigil.Sui.GasRelay
  alias Sigil.Sui.{Signer, TransactionBuilder}

  @default_gas_budget 10_000_000
  @default_gas_price 1_000

  describe "prepare_sponsored/3" do
    test "prepare_sponsored builds full TransactionData with relay gas" do
      relay_keypair = relay_keypair()
      pseudonym_address = sui_address(0x91)
      gas_coin = coin(0x11, 0x21, 0x31, 12_000_000)

      assert {:ok, %{tx_bytes: tx_bytes_b64, relay_signature: relay_signature_b64}} =
               GasRelay.prepare_sponsored(kind_opts(), pseudonym_address,
                 client: Sigil.Sui.GasRelayTestClient,
                 test_pid: self(),
                 get_coins_result: {:ok, [gas_coin]},
                 relay_keypair: relay_keypair
               )

      assert_receive {:get_coins, relay_owner, client_opts}
      assert relay_owner == relay_address(relay_keypair)
      refute Keyword.has_key?(client_opts, :relay_keypair)

      expected_tx_bytes =
        expected_sponsored_tx_bytes(kind_opts(), pseudonym_address, relay_keypair, [gas_coin])

      assert Base.decode64!(tx_bytes_b64) == expected_tx_bytes
      assert byte_size(Base.decode64!(relay_signature_b64)) == 97
    end

    test "relay signature is verifiable against relay public key" do
      relay_keypair = relay_keypair()
      gas_coin = coin(0x12, 0x22, 0x32, 12_500_000)

      assert {:ok, %{tx_bytes: tx_bytes_b64, relay_signature: relay_signature_b64}} =
               GasRelay.prepare_sponsored(kind_opts(), sui_address(0x92),
                 client: Sigil.Sui.GasRelayTestClient,
                 test_pid: self(),
                 get_coins_result: {:ok, [gas_coin]},
                 relay_keypair: relay_keypair
               )

      tx_bytes = Base.decode64!(tx_bytes_b64)

      <<0, signature::binary-size(64), public_key::binary-size(32)>> =
        Base.decode64!(relay_signature_b64)

      assert public_key == elem(relay_keypair, 0)
      assert Signer.verify(tx_bytes, signature, public_key)
    end

    test "prepare_sponsored returns error when relay has no coins" do
      assert {:error, :no_gas_coins} =
               GasRelay.prepare_sponsored(kind_opts(), sui_address(0x93),
                 client: Sigil.Sui.GasRelayTestClient,
                 test_pid: self(),
                 get_coins_result: {:ok, []},
                 relay_keypair: relay_keypair()
               )
    end

    test "relay_keypair option overrides file-based keypair" do
      relay_keypair = relay_keypair()
      conflicting_keypair = pseudonym_keypair()

      temp_path =
        Path.join(
          System.tmp_dir!(),
          "sigil-gas-relay-tests-#{System.unique_integer([:positive])}-override.json"
        )

      on_exit(fn -> File.rm(temp_path) end)
      File.write!(temp_path, :erlang.term_to_binary(conflicting_keypair))

      assert {:ok, _sponsored} =
               GasRelay.prepare_sponsored(kind_opts(), sui_address(0x94),
                 client: Sigil.Sui.GasRelayTestClient,
                 test_pid: self(),
                 get_coins_result: {:ok, [coin(0x13, 0x23, 0x33, 11_000_000)]},
                 relay_keypair: relay_keypair,
                 key_path: temp_path
               )

      assert_receive {:get_coins, relay_owner, _client_opts}
      assert relay_owner == relay_address(relay_keypair)
      refute relay_owner == relay_address(conflicting_keypair)
      assert File.read!(temp_path) == :erlang.term_to_binary(conflicting_keypair)
    end

    test "prepare_sponsored returns insufficient_gas" do
      assert {:error, :insufficient_gas} =
               GasRelay.prepare_sponsored(kind_opts(), sui_address(0x95),
                 client: Sigil.Sui.GasRelayTestClient,
                 test_pid: self(),
                 get_coins_result:
                   {:ok, [coin(0x14, 0x24, 0x34, 4_000_000), coin(0x15, 0x25, 0x35, 5_000_000)]},
                 relay_keypair: relay_keypair(),
                 gas_budget: @default_gas_budget
               )
    end

    test "prepare_sponsored selects sufficient gas coins" do
      relay_keypair = relay_keypair()
      pseudonym_address = sui_address(0x96)

      gas_coins = [
        coin(0x16, 0x26, 0x36, 4_000_000),
        coin(0x17, 0x27, 0x37, 6_500_000),
        coin(0x18, 0x28, 0x38, 20_000_000)
      ]

      assert {:ok, %{tx_bytes: tx_bytes_b64}} =
               GasRelay.prepare_sponsored(kind_opts(), pseudonym_address,
                 client: Sigil.Sui.GasRelayTestClient,
                 test_pid: self(),
                 get_coins_result: {:ok, gas_coins},
                 relay_keypair: relay_keypair,
                 gas_budget: @default_gas_budget
               )

      expected_tx_bytes =
        expected_sponsored_tx_bytes(
          kind_opts(),
          pseudonym_address,
          relay_keypair,
          Enum.take(gas_coins, 2)
        )

      assert Base.decode64!(tx_bytes_b64) == expected_tx_bytes
    end
  end

  describe "submit_sponsored/4" do
    test "submit_sponsored forwards dual signatures" do
      execute_result = %{
        "status" => "SUCCESS",
        "digest" => "0xrelaydigest",
        "effectsBcs" => "effects-bcs"
      }

      assert {:ok, %{digest: "0xrelaydigest", effects_bcs: "effects-bcs"}} =
               GasRelay.submit_sponsored("tx-bytes", "pseudonym-signature", "relay-signature",
                 client: Sigil.Sui.GasRelayTestClient,
                 test_pid: self(),
                 execute_result: {:ok, execute_result}
               )

      assert_receive {:execute_transaction, "tx-bytes",
                      ["pseudonym-signature", "relay-signature"], _opts}
    end
  end

  describe "relay_address/1" do
    test "relay_address returns correct Sui address" do
      relay_keypair = relay_keypair()

      assert GasRelay.relay_address(relay_keypair: relay_keypair) == relay_address(relay_keypair)
    end
  end

  describe "relay key persistence" do
    test "missing key file generates relay keypair" do
      key_path =
        Path.join(
          System.tmp_dir!(),
          "sigil-gas-relay-tests-#{System.unique_integer([:positive])}-generate.json"
        )

      on_exit(fn -> File.rm(key_path) end)

      assert {:ok, _sponsored} =
               GasRelay.prepare_sponsored(kind_opts(), sui_address(0x97),
                 client: Sigil.Sui.GasRelayTestClient,
                 test_pid: self(),
                 get_coins_result: {:ok, [coin(0x19, 0x29, 0x39, 12_000_000)]},
                 key_path: key_path
               )

      assert File.exists?(key_path)
      assert GasRelay.relay_address(key_path: key_path) =~ ~r/^0x[0-9a-f]{64}$/
    end

    test "existing key file reuses relay keypair" do
      key_path =
        Path.join(
          System.tmp_dir!(),
          "sigil-gas-relay-tests-#{System.unique_integer([:positive])}-reuse.json"
        )

      on_exit(fn -> File.rm(key_path) end)

      assert {:ok, _first} =
               GasRelay.prepare_sponsored(kind_opts(), sui_address(0x98),
                 client: Sigil.Sui.GasRelayTestClient,
                 test_pid: self(),
                 get_coins_result: {:ok, [coin(0x1A, 0x2A, 0x3A, 12_000_000)]},
                 key_path: key_path
               )

      first_address = GasRelay.relay_address(key_path: key_path)

      assert {:ok, _second} =
               GasRelay.prepare_sponsored(kind_opts(), sui_address(0x99),
                 client: Sigil.Sui.GasRelayTestClient,
                 test_pid: self(),
                 get_coins_result: {:ok, [coin(0x1B, 0x2B, 0x3B, 12_000_000)]},
                 key_path: key_path
               )

      second_address = GasRelay.relay_address(key_path: key_path)

      assert first_address == second_address
    end

    test "invalid persisted key returns relay_key_not_found" do
      key_path =
        Path.join(
          System.tmp_dir!(),
          "sigil-gas-relay-tests-#{System.unique_integer([:positive])}-invalid.json"
        )

      on_exit(fn -> File.rm(key_path) end)
      File.write!(key_path, "not an erlang term")

      assert {:error, :relay_key_not_found} =
               GasRelay.prepare_sponsored(kind_opts(), sui_address(0x9A),
                 client: Sigil.Sui.GasRelayTestClient,
                 test_pid: self(),
                 get_coins_result: {:ok, [coin(0x1C, 0x2C, 0x3C, 12_000_000)]},
                 key_path: key_path
               )
    end

    test "key generation failure returns relay_key_not_found" do
      blocked_dir =
        Path.join(
          System.tmp_dir!(),
          "sigil-gas-relay-tests-#{System.unique_integer([:positive])}-blocked"
        )

      key_path = Path.join(blocked_dir, "relay.key")
      on_exit(fn -> File.rm(blocked_dir) end)
      File.write!(blocked_dir, "not a directory")

      assert {:error, :relay_key_not_found} =
               GasRelay.prepare_sponsored(kind_opts(), sui_address(0x9B),
                 client: Sigil.Sui.GasRelayTestClient,
                 test_pid: self(),
                 get_coins_result: {:ok, [coin(0x1D, 0x2D, 0x3D, 12_000_000)]},
                 key_path: key_path
               )
    end
  end

  @tag :acceptance
  test "seller-facing pseudonym listing flow reaches gas relay" do
    relay_keypair = relay_keypair()
    pseudonym_keypair = pseudonym_keypair()

    assert {:ok, %{digest: digest, effects_bcs: effects_bcs}} =
             Sigil.Sui.PseudonymListingFlow.create_listing(
               kind_opts: listing_kind_opts(),
               pseudonym_keypair: pseudonym_keypair,
               client: Sigil.Sui.GasRelayTestClient,
               test_pid: self(),
               get_coins_result: {:ok, [coin(0x1C, 0x2C, 0x3C, 12_000_000)]},
               relay_keypair: relay_keypair,
               execute_result:
                 {:ok,
                  %{
                    "status" => "SUCCESS",
                    "digest" => "0xlistingdigest",
                    "effectsBcs" => "effects-bcs"
                  }}
             )

    assert_receive {:get_coins, relay_owner, _opts}
    assert relay_owner == relay_address(relay_keypair)

    assert_receive {:execute_transaction, _tx_bytes, [_pseudonym_signature, _relay_signature],
                    _opts}

    assert digest == "0xlistingdigest"
    assert effects_bcs == "effects-bcs"
    refute is_nil(effects_bcs)
    refute digest =~ "error"
  end

  defp kind_opts do
    [
      inputs: [{:pure, <<1, 2, 3, 4>>}],
      commands: [
        {:move_call, address(0x50), "gas_relay", "sponsored_action", [], [{:input, 0}, :gas_coin]}
      ]
    ]
  end

  defp listing_kind_opts do
    [
      inputs: [{:pure, <<5, 6, 7, 8>>}],
      commands: [
        {:move_call, address(0x51), "intel_market", "create_listing", [], [{:input, 0}]}
      ]
    ]
  end

  defp expected_sponsored_tx_bytes(kind_opts, pseudonym_address, relay_keypair, gas_coins) do
    TransactionBuilder.build!(
      kind_opts ++
        [
          sender: decode_sui_address(pseudonym_address),
          gas_owner: relay_owner_bytes(relay_keypair),
          gas_payment: Enum.map(gas_coins, &coin_ref/1),
          gas_price: @default_gas_price,
          gas_budget: @default_gas_budget,
          expiration: :none
        ]
    )
  end

  defp relay_address({public_key, _private_key}) do
    public_key
    |> Signer.address_from_public_key()
    |> Signer.to_sui_address()
  end

  defp relay_owner_bytes({public_key, _private_key}) do
    Signer.address_from_public_key(public_key)
  end

  defp relay_keypair do
    Signer.keypair_from_private_key(:binary.copy(<<0x42>>, 32))
  end

  defp pseudonym_keypair do
    Signer.keypair_from_private_key(:binary.copy(<<0x24>>, 32))
  end

  defp coin(id_byte, version, digest_byte, balance) do
    %{
      object_id: address(id_byte),
      version: version,
      digest: address(digest_byte),
      balance: balance
    }
  end

  defp coin_ref(%{object_id: object_id, version: version, digest: digest}) do
    {object_id, version, digest}
  end

  defp sui_address(byte) do
    byte
    |> address()
    |> Signer.to_sui_address()
  end

  defp decode_sui_address("0x" <> hex) do
    hex
    |> String.pad_leading(64, "0")
    |> Base.decode16!(case: :mixed)
  end

  defp address(byte), do: :binary.copy(<<byte>>, 32)
end
