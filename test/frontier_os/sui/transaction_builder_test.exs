defmodule FrontierOS.Sui.TransactionBuilderTest do
  @moduledoc """
  Defines packet 2 public API tests for the transaction builder.
  """

  use ExUnit.Case, async: true

  import Hammox

  alias FrontierOS.Sui.Signer
  alias FrontierOS.Sui.TransactionBuilder
  alias FrontierOS.Sui.TransactionBuilder.PTB

  @reference_tx_hex "000001000401020304010050505050505050505050505050505050505050505050505050505050505050500467617465046a756d70000201000000a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a10110101010101010101010101010101010101010101010101010101010101010101100000000000000202020202020202020202020202020202020202020202020202020202020202020b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2e80300000000000080f0fa0200000000012a00000000000000"

  setup :verify_on_exit!

  describe "build!/1" do
    test "build! returns BCS binary for minimal MoveCall transaction" do
      opts = sample_build_opts()
      expected = expected_transaction_bytes(opts)
      built = TransactionBuilder.build!(opts)

      assert built == expected
      assert built |> binary_part(0, 2) == <<0x00, 0x00>>
    end

    test "build! defaults gas_owner to sender" do
      opts = sample_build_opts() |> Keyword.delete(:gas_owner)

      assert TransactionBuilder.build!(opts) == expected_transaction_bytes(opts)
    end

    test "build! accepts separate gas_owner for sponsored transactions" do
      opts = sample_build_opts(gas_owner: address(0xD4))

      assert TransactionBuilder.build!(opts) == expected_transaction_bytes(opts)
    end

    test "build! serializes multi-command PTB with result references" do
      opts =
        sample_build_opts(
          commands: [
            {:move_call, address(0x50), "gate", "borrow_cap", [], [:gas_coin]},
            {:move_call, address(0x51), "gate", "return_cap", [], [{:result, 0}]}
          ]
        )

      assert TransactionBuilder.build!(opts) == expected_transaction_bytes(opts)
    end

    test "build! raises ArgumentError when sender missing" do
      assert_raise ArgumentError, "sender is required", fn ->
        TransactionBuilder.build!(Keyword.delete(sample_build_opts(), :sender))
      end
    end

    test "build! raises ArgumentError when commands empty" do
      assert_raise ArgumentError, "at least one command is required", fn ->
        TransactionBuilder.build!(sample_build_opts(commands: []))
      end
    end

    test "build! raises ArgumentError when gas_payment empty" do
      assert_raise ArgumentError, "at least one gas payment coin is required", fn ->
        TransactionBuilder.build!(sample_build_opts(gas_payment: []))
      end
    end

    test "build! raises ArgumentError when gas_price missing" do
      assert_raise ArgumentError, "gas_price is required", fn ->
        TransactionBuilder.build!(Keyword.delete(sample_build_opts(), :gas_price))
      end
    end
  end

  describe "build/1" do
    test "build returns {:ok, binary} for valid transaction" do
      opts = sample_build_opts()

      assert TransactionBuilder.build(opts) == {:ok, expected_transaction_bytes(opts)}
    end

    test "build returns {:error, message} for invalid transaction" do
      assert TransactionBuilder.build(Keyword.delete(sample_build_opts(), :gas_price)) ==
               {:error, "gas_price is required"}
    end
  end

  describe "digest/1" do
    test "digest computes Blake2b-256 of intent-prefixed BCS bytes" do
      tx_bytes = expected_transaction_bytes(sample_build_opts())

      assert TransactionBuilder.digest(tx_bytes) == Blake2.hash2b(<<0, 0, 0>> <> tx_bytes, 32)
    end
  end

  describe "execute/3" do
    test "execute builds, signs, and submits transaction returning effects" do
      opts = sample_build_opts()
      tx_bytes = expected_transaction_bytes(opts)
      {public_key, private_key} = fixed_keypair()
      encoded_signature = expected_encoded_signature(tx_bytes, private_key, public_key)

      effects = %{"status" => "success", "digest" => "0xdeadbeef"}

      expect(FrontierOS.Sui.ClientMock, :execute_transaction, fn tx_bytes_b64,
                                                                 signatures_b64,
                                                                 [] ->
        assert tx_bytes_b64 == Base.encode64(tx_bytes)
        assert signatures_b64 == [Base.encode64(encoded_signature)]
        {:ok, effects}
      end)

      assert TransactionBuilder.execute(opts, private_key, public_key) == {:ok, effects}
    end

    test "execute propagates client error" do
      opts = sample_build_opts()
      tx_bytes = expected_transaction_bytes(opts)
      {public_key, private_key} = fixed_keypair()
      encoded_signature = expected_encoded_signature(tx_bytes, private_key, public_key)

      expect(FrontierOS.Sui.ClientMock, :execute_transaction, fn tx_bytes_b64,
                                                                 signatures_b64,
                                                                 [] ->
        assert tx_bytes_b64 == Base.encode64(tx_bytes)
        assert signatures_b64 == [Base.encode64(encoded_signature)]
        {:error, :rate_limited}
      end)

      assert TransactionBuilder.execute(opts, private_key, public_key) == {:error, :rate_limited}
    end
  end

  describe "reference vector" do
    test "build! output matches reference testnet transaction bytes" do
      assert TransactionBuilder.build!(reference_vector_opts()) ==
               Base.decode16!(@reference_tx_hex, case: :mixed)
    end
  end

  defp sample_build_opts(overrides \\ []) do
    Keyword.merge(
      [
        sender: address(0xA1),
        gas_owner: address(0xB2),
        gas_payment: [{address(0x10), 17, address(0x20)}],
        gas_price: 1_000,
        gas_budget: 50_000_000,
        inputs: [{:pure, <<1, 2, 3, 4>>}],
        commands: [{:move_call, address(0x50), "gate", "jump", [], [{:input, 0}, :gas_coin]}],
        expiration: {:epoch, 42}
      ],
      overrides
    )
  end

  defp reference_vector_opts do
    sample_build_opts()
  end

  defp expected_transaction_bytes(opts) do
    PTB.encode_transaction_data(expected_transaction_data(opts))
  end

  defp expected_transaction_data(opts) do
    sender = Keyword.fetch!(opts, :sender)

    %{
      kind: %{
        inputs: Keyword.get(opts, :inputs, []),
        commands: Keyword.fetch!(opts, :commands)
      },
      sender: sender,
      gas_data: %{
        payment: Keyword.fetch!(opts, :gas_payment),
        owner: Keyword.get(opts, :gas_owner, sender),
        price: Keyword.fetch!(opts, :gas_price),
        budget: Keyword.fetch!(opts, :gas_budget)
      },
      expiration: Keyword.get(opts, :expiration, :none)
    }
  end

  defp expected_encoded_signature(tx_bytes, private_key, public_key) do
    tx_bytes
    |> Signer.sign(private_key)
    |> Signer.encode_signature(public_key)
  end

  defp fixed_keypair do
    Signer.keypair_from_private_key(:binary.copy(<<0x42>>, 32))
  end

  defp address(byte) do
    :binary.copy(<<byte>>, 32)
  end
end
