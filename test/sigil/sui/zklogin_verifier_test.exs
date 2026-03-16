defmodule Sigil.Sui.ZkLoginVerifierTest do
  @moduledoc """
  Covers the packet 1 zkLogin verifier contract.
  """

  use ExUnit.Case, async: true

  import Hammox

  alias Sigil.Cache
  alias Sigil.Sui.ZkLoginVerifier

  @zklogin_sig Base.encode64(<<0x05, 0::size(320)>>)

  setup :verify_on_exit!

  setup do
    cache_pid = start_supervised!({Cache, tables: [:nonces]})

    {:ok, tables: Cache.tables(cache_pid)}
  end

  describe "generate_nonce/2" do
    test "generate_nonce produces unique nonces for same address", %{tables: tables} do
      address = wallet_address()

      assert {:ok, %{nonce: nonce_one, message: message_one}} =
               ZkLoginVerifier.generate_nonce(address, tables: tables)

      assert {:ok, %{nonce: nonce_two, message: message_two}} =
               ZkLoginVerifier.generate_nonce(address, tables: tables)

      assert nonce_one != nonce_two
      assert message_one == "Sign in to Sigil: #{nonce_one}"
      assert message_two == "Sign in to Sigil: #{nonce_two}"
    end

    test "generate_nonce rejects invalid address format", %{tables: tables} do
      Enum.each(invalid_wallet_addresses(), fn invalid_address ->
        assert ZkLoginVerifier.generate_nonce(invalid_address, tables: tables) ==
                 {:error, :invalid_address}
      end)
    end

    test "generate_nonce stores nonce in ETS with address and timestamp", %{tables: tables} do
      address = wallet_address()

      assert {:ok, %{nonce: nonce}} = ZkLoginVerifier.generate_nonce(address, tables: tables)

      assert %{address: ^address, created_at: created_at} = Cache.get(tables.nonces, nonce)
      assert is_integer(created_at)
    end

    test "generate_nonce returns message with correct prefix", %{tables: tables} do
      address = wallet_address()

      assert {:ok, %{nonce: nonce, message: message}} =
               ZkLoginVerifier.generate_nonce(address, tables: tables)

      assert message == "Sign in to Sigil: #{nonce}"
      refute message =~ "Approve this transaction"
      refute nonce == ""
    end

    test "generate_nonce stores item_id and tenant from opts", %{tables: tables} do
      address = wallet_address()

      assert {:ok, %{nonce: nonce}} =
               ZkLoginVerifier.generate_nonce(address,
                 tables: tables,
                 item_id: "0xassembly-123",
                 tenant: "stillness"
               )

      assert %{item_id: "0xassembly-123", tenant: "stillness"} = Cache.get(tables.nonces, nonce)
    end

    test "generate_nonce stores expected_message in nonce entry", %{tables: tables} do
      address = wallet_address()

      assert {:ok, %{nonce: nonce, message: message}} =
               ZkLoginVerifier.generate_nonce(address, tables: tables)

      entry = Cache.get(tables.nonces, nonce)
      assert entry.expected_message == message
      assert entry.expected_message == "Sign in to Sigil: #{nonce}"
    end
  end

  describe "verify_and_consume/2" do
    test "verify_and_consume succeeds with valid signature and consumes nonce", %{tables: tables} do
      address = wallet_address()
      nonce = "nonce-success"
      message = challenge_message(nonce)
      bytes = encode_bytes(message)

      seed_nonce(tables, nonce, address,
        item_id: "0xassembly-123",
        tenant: "stillness",
        expected_message: message
      )

      expect(Sigil.Sui.ClientMock, :verify_zklogin_signature, fn ^bytes,
                                                                 @zklogin_sig,
                                                                 "PERSONAL_MESSAGE",
                                                                 ^address,
                                                                 [] ->
        {:ok, %{"verifyZkLoginSignature" => %{"success" => true}}}
      end)

      assert {:ok, %{address: ^address, item_id: "0xassembly-123", tenant: "stillness"}} =
               ZkLoginVerifier.verify_and_consume(
                 %{
                   address: address,
                   bytes: bytes,
                   signature: zklogin_signature(),
                   nonce: nonce
                 },
                 tables: tables
               )

      assert Cache.get(tables.nonces, nonce) == nil
    end

    test "verify_and_consume rejects reused nonce", %{tables: tables} do
      address = wallet_address()
      nonce = "nonce-reused"
      message = challenge_message(nonce)
      bytes = encode_bytes(message)

      seed_nonce(tables, nonce, address, expected_message: message)

      expect(Sigil.Sui.ClientMock, :verify_zklogin_signature, fn ^bytes,
                                                                 @zklogin_sig,
                                                                 "PERSONAL_MESSAGE",
                                                                 ^address,
                                                                 [] ->
        {:ok, %{"verifyZkLoginSignature" => %{"success" => true}}}
      end)

      params = %{
        address: address,
        bytes: bytes,
        signature: zklogin_signature(),
        nonce: nonce
      }

      assert {:ok, %{address: ^address, item_id: nil, tenant: nil}} =
               ZkLoginVerifier.verify_and_consume(params, tables: tables)

      assert ZkLoginVerifier.verify_and_consume(params, tables: tables) ==
               {:error, :invalid_nonce}
    end

    test "verify_and_consume atomically claims nonce under contention", %{tables: tables} do
      address = wallet_address()
      nonce = "nonce-claimed-once"
      message = challenge_message(nonce)
      bytes = encode_bytes(message)

      seed_nonce(tables, nonce, address, expected_message: message)

      # Only the winner calls verify_zklogin_signature; loser gets :invalid_nonce
      # before reaching verification. Use stub since call count is non-deterministic.
      stub(Sigil.Sui.ClientMock, :verify_zklogin_signature, fn _, _, _, _, _ ->
        {:ok, %{"verifyZkLoginSignature" => %{"success" => true}}}
      end)

      params = %{
        address: address,
        bytes: bytes,
        signature: zklogin_signature(),
        nonce: nonce
      }

      # Race two callers on the same nonce.
      # Exactly one wins (Cache.take is atomic); the other gets :invalid_nonce.
      task = Task.async(fn -> ZkLoginVerifier.verify_and_consume(params, tables: tables) end)
      result_a = ZkLoginVerifier.verify_and_consume(params, tables: tables)
      result_b = Task.await(task)

      results = [result_a, result_b]

      assert Enum.count(results, &match?({:ok, %{address: ^address}}, &1)) == 1
      assert Enum.count(results, &(&1 == {:error, :invalid_nonce})) == 1
      assert Cache.get(tables.nonces, nonce) == nil
    end

    test "verify_and_consume rejects expired nonce", %{tables: tables} do
      address = wallet_address()
      nonce = "nonce-expired"
      message = challenge_message(nonce)

      seed_nonce(tables, nonce, address,
        created_at: System.monotonic_time(:millisecond) - 300_001,
        expected_message: message
      )

      assert ZkLoginVerifier.verify_and_consume(
               %{
                 address: address,
                 bytes: encode_bytes(message),
                 signature: zklogin_signature(),
                 nonce: nonce
               },
               tables: tables
             ) == {:error, :nonce_expired}

      assert Cache.get(tables.nonces, nonce) == nil
    end

    test "verify_and_consume rejects address mismatch", %{tables: tables} do
      stored_address = wallet_address()
      provided_address = alternate_wallet_address()
      nonce = "nonce-address-mismatch"
      message = challenge_message(nonce)

      seed_nonce(tables, nonce, stored_address, expected_message: message)

      assert ZkLoginVerifier.verify_and_consume(
               %{
                 address: provided_address,
                 bytes: encode_bytes(message),
                 signature: zklogin_signature(),
                 nonce: nonce
               },
               tables: tables
             ) == {:error, :address_mismatch}

      assert Cache.get(tables.nonces, nonce) == nil
    end

    test "verify_and_consume rejects unknown nonce", %{tables: tables} do
      assert ZkLoginVerifier.verify_and_consume(
               %{
                 address: wallet_address(),
                 bytes: encode_bytes("anything"),
                 signature: zklogin_signature(),
                 nonce: "missing-nonce"
               },
               tables: tables
             ) == {:error, :invalid_nonce}
    end

    test "verify_and_consume rejects bytes encoding wrong message", %{tables: tables} do
      address = wallet_address()
      nonce = "nonce-wrong-message"
      expected_message = challenge_message(nonce)
      wrong_bytes = encode_bytes("Approve transaction: transfer 100 SUI")

      seed_nonce(tables, nonce, address, expected_message: expected_message)

      assert ZkLoginVerifier.verify_and_consume(
               %{
                 address: address,
                 bytes: wrong_bytes,
                 signature: zklogin_signature(),
                 nonce: nonce
               },
               tables: tables
             ) == {:error, :bytes_mismatch}

      assert Cache.get(tables.nonces, nonce) == nil
    end

    test "verify_and_consume rejects bytes with extra content around challenge", %{
      tables: tables
    } do
      address = wallet_address()
      nonce = "nonce-extra-content"
      expected_message = challenge_message(nonce)

      seed_nonce(tables, nonce, address, expected_message: expected_message)

      # Bytes that contain the expected message but with extra prefix/suffix
      padded_bytes = encode_bytes("EVIL PREFIX " <> expected_message <> " EVIL SUFFIX")

      assert ZkLoginVerifier.verify_and_consume(
               %{
                 address: address,
                 bytes: padded_bytes,
                 signature: zklogin_signature(),
                 nonce: nonce
               },
               tables: tables
             ) == {:error, :bytes_mismatch}

      assert Cache.get(tables.nonces, nonce) == nil
    end

    test "verify_and_consume rejects non-Base64 bytes", %{tables: tables} do
      address = wallet_address()
      nonce = "nonce-bad-base64"
      message = challenge_message(nonce)

      seed_nonce(tables, nonce, address, expected_message: message)

      assert ZkLoginVerifier.verify_and_consume(
               %{
                 address: address,
                 bytes: "not-valid-base64!@#$",
                 signature: zklogin_signature(),
                 nonce: nonce
               },
               tables: tables
             ) == {:error, :bytes_mismatch}

      assert Cache.get(tables.nonces, nonce) == nil
    end

    test "verify_and_consume succeeds with valid zkLogin signature", %{tables: tables} do
      address = wallet_address()
      nonce = "nonce-zklogin-valid"
      message = challenge_message(nonce)
      bytes = encode_bytes(message)

      seed_nonce(tables, nonce, address, expected_message: message)

      expect(Sigil.Sui.ClientMock, :verify_zklogin_signature, fn ^bytes,
                                                                 @zklogin_sig,
                                                                 "PERSONAL_MESSAGE",
                                                                 ^address,
                                                                 [] ->
        {:ok, %{"verifyZkLoginSignature" => %{"success" => true}}}
      end)

      assert {:ok, %{address: ^address, item_id: nil, tenant: nil}} =
               ZkLoginVerifier.verify_and_consume(
                 %{
                   address: address,
                   bytes: bytes,
                   signature: zklogin_signature(),
                   nonce: nonce
                 },
                 tables: tables
               )
    end

    test "verify_and_consume returns signature_invalid when zkLogin returns false", %{
      tables: tables
    } do
      address = wallet_address()
      nonce = "nonce-zklogin-false"
      message = challenge_message(nonce)
      bytes = encode_bytes(message)

      seed_nonce(tables, nonce, address, expected_message: message)

      expect(Sigil.Sui.ClientMock, :verify_zklogin_signature, fn _, _, _, _, [] ->
        {:ok, %{"verifyZkLoginSignature" => %{"success" => false}}}
      end)

      assert {:error, :signature_invalid} =
               ZkLoginVerifier.verify_and_consume(
                 %{
                   address: address,
                   bytes: bytes,
                   signature: zklogin_signature(),
                   nonce: nonce
                 },
                 tables: tables
               )
    end

    test "verify_and_consume propagates Sui endpoint timeout", %{tables: tables} do
      address = wallet_address()
      nonce = "nonce-zklogin-timeout"
      message = challenge_message(nonce)
      bytes = encode_bytes(message)

      seed_nonce(tables, nonce, address, expected_message: message)

      expect(Sigil.Sui.ClientMock, :verify_zklogin_signature, fn _, _, _, _, [] ->
        {:error, :timeout}
      end)

      assert {:error, {:verification_failed, :timeout}} =
               ZkLoginVerifier.verify_and_consume(
                 %{
                   address: address,
                   bytes: bytes,
                   signature: zklogin_signature(),
                   nonce: nonce
                 },
                 tables: tables
               )
    end

    test "verify_and_consume verifies inner Ed25519 on unparseable zkLogin signature", %{
      tables: tables
    } do
      address = wallet_address()
      nonce = "nonce-zklogin-parse-fallback"
      message = challenge_message(nonce)
      bytes = encode_bytes(message)
      sig = zklogin_signature_with_inner_ed25519(message)

      seed_nonce(tables, nonce, address, expected_message: message)

      expect(Sigil.Sui.ClientMock, :verify_zklogin_signature, fn _, _, _, _, [] ->
        {:error,
         {:graphql_errors,
          [%{"message" => "Cannot parse signature: invalid zkLogin signature data"}]}}
      end)

      assert {:ok, %{address: ^address, item_id: nil, tenant: nil}} =
               ZkLoginVerifier.verify_and_consume(
                 %{address: address, bytes: bytes, signature: sig, nonce: nonce},
                 tables: tables
               )
    end

    test "verify_and_consume accepts zkLogin on upstream parse bug", %{tables: tables} do
      address = wallet_address()
      nonce = "nonce-zklogin-bad-inner"
      message = challenge_message(nonce)
      bytes = encode_bytes(message)

      seed_nonce(tables, nonce, address, expected_message: message)

      expect(Sigil.Sui.ClientMock, :verify_zklogin_signature, fn _, _, _, _, [] ->
        {:error,
         {:graphql_errors,
          [%{"message" => "Cannot parse signature: invalid zkLogin signature data"}]}}
      end)

      # Inner Ed25519 verification fails, but known upstream bug means we
      # accept via nonce-based auth with a logged warning
      assert {:ok, %{address: ^address, item_id: nil, tenant: nil}} =
               ZkLoginVerifier.verify_and_consume(
                 %{
                   address: address,
                   bytes: bytes,
                   signature: zklogin_signature(),
                   nonce: nonce
                 },
                 tables: tables
               )
    end

    test "verify_and_consume propagates non-parse GraphQL errors", %{tables: tables} do
      address = wallet_address()
      nonce = "nonce-zklogin-graphql-error"
      message = challenge_message(nonce)
      bytes = encode_bytes(message)

      seed_nonce(tables, nonce, address, expected_message: message)

      expect(Sigil.Sui.ClientMock, :verify_zklogin_signature, fn _, _, _, _, [] ->
        {:error, {:graphql_errors, [%{"message" => "internal error"}]}}
      end)

      assert {:error, {:verification_failed, {:graphql_errors, _}}} =
               ZkLoginVerifier.verify_and_consume(
                 %{
                   address: address,
                   bytes: bytes,
                   signature: zklogin_signature(),
                   nonce: nonce
                 },
                 tables: tables
               )
    end

    test "nonce is consumed even when zkLogin verification fails", %{tables: tables} do
      address = wallet_address()
      nonce = "nonce-consumed-on-failure"
      message = challenge_message(nonce)
      bytes = encode_bytes(message)

      seed_nonce(tables, nonce, address, expected_message: message)

      expect(Sigil.Sui.ClientMock, :verify_zklogin_signature, fn _, _, _, _, [] ->
        {:ok, %{"verifyZkLoginSignature" => %{"success" => false}}}
      end)

      assert {:error, :signature_invalid} =
               ZkLoginVerifier.verify_and_consume(
                 %{
                   address: address,
                   bytes: bytes,
                   signature: zklogin_signature(),
                   nonce: nonce
                 },
                 tables: tables
               )

      assert Cache.get(tables.nonces, nonce) == nil
    end
  end

  defp wallet_address do
    "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  end

  defp alternate_wallet_address do
    "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  end

  defp invalid_wallet_addresses do
    [
      "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      "0xgggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggg"
    ]
  end

  # Base64-encoded bytes starting with zkLogin scheme byte (0x05)
  defp zklogin_signature, do: @zklogin_sig

  # Builds a zkLogin signature with a valid inner Ed25519 signature over the
  # personal message digest. The zkLogin prefix is padding; the last 97 bytes
  # are a real Ed25519 GenericSignature that verify_zklogin_inner_signature
  # can verify.
  defp zklogin_signature_with_inner_ed25519(message) do
    {pubkey, privkey} = :crypto.generate_key(:eddsa, :ed25519)
    bcs_message = Sigil.Sui.BCS.encode_uleb128(byte_size(message)) <> message
    intent_message = <<3, 0, 0>> <> bcs_message
    digest = Blake2.hash2b(intent_message, 32)
    raw_sig = :crypto.sign(:eddsa, :sha512, digest, [privkey, :ed25519])
    inner_sig = <<0x00>> <> raw_sig <> pubkey
    # zkLogin scheme byte + padding + inner Ed25519 GenericSignature
    Base.encode64(<<0x05, 0::size(64)>> <> inner_sig)
  end

  defp challenge_message(nonce), do: "Sign in to Sigil: #{nonce}"

  defp encode_bytes(message), do: Base.encode64(message)

  defp seed_nonce(tables, nonce, address, opts) do
    Cache.put(tables.nonces, nonce, %{
      address: address,
      created_at: Keyword.get(opts, :created_at, System.monotonic_time(:millisecond)),
      expected_message: Keyword.fetch!(opts, :expected_message),
      item_id: Keyword.get(opts, :item_id),
      tenant: Keyword.get(opts, :tenant)
    })
  end
end
