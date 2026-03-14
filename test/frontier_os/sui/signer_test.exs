defmodule FrontierOS.Sui.SignerTest do
  @moduledoc """
  Defines the packet 2 signer contract tests before implementation exists.
  """

  use ExUnit.Case, async: true

  alias FrontierOS.Sui.Signer

  @intent_prefix <<0, 0, 0>>

  test "generates valid Ed25519 keypair with correct key sizes" do
    {public_key, private_key} = Signer.generate_keypair()

    assert byte_size(public_key) == 32
    assert byte_size(private_key) == 32
  end

  test "derives public key from private key" do
    {original_public_key, private_key} = Signer.generate_keypair()
    {derived_public_key, same_private_key} = Signer.keypair_from_private_key(private_key)
    signature = Signer.sign("packet-2", same_private_key)

    assert derived_public_key == original_public_key
    assert same_private_key == private_key
    assert Signer.verify("packet-2", signature, derived_public_key)
  end

  test "sign hashes intent-prefixed payload with Blake2b before Ed25519 signing" do
    {public_key, private_key} = Signer.generate_keypair()
    payload = <<1, 2, 3, 4>>

    digest = Blake2.hash2b(@intent_prefix <> payload, 32)

    assert Signer.sign(payload, private_key) ==
             :crypto.sign(:eddsa, :sha512, digest, [private_key, :ed25519])

    refute Signer.sign(payload, private_key) ==
             :crypto.sign(:eddsa, :sha512, @intent_prefix <> payload, [private_key, :ed25519])

    assert Signer.verify(payload, Signer.sign(payload, private_key), public_key)
  end

  test "encode_signature produces 97-byte output with scheme byte prefix" do
    {public_key, private_key} = Signer.generate_keypair()
    signature = Signer.sign("encode-me", private_key)
    encoded_signature = Signer.encode_signature(signature, public_key)

    assert byte_size(signature) == 64
    assert byte_size(encoded_signature) == 97
    assert <<0x00, encoded_signature_body::binary-size(96)>> = encoded_signature
    assert encoded_signature_body == signature <> public_key
  end

  test "sign then verify roundtrip succeeds" do
    {public_key, private_key} = Signer.generate_keypair()
    payload = <<9, 8, 7, 6>>
    signature = Signer.sign(payload, private_key)

    assert Signer.verify(payload, signature, public_key)
  end

  test "verify rejects signature with wrong public key" do
    {_signer_public_key, signer_private_key} = Signer.generate_keypair()
    {other_public_key, _other_private_key} = Signer.generate_keypair()
    signature = Signer.sign("wrong-key", signer_private_key)

    refute Signer.verify("wrong-key", signature, other_public_key)
  end

  test "derives correct Sui address from public key" do
    {public_key, _private_key} = Signer.generate_keypair()
    expected_address = Blake2.hash2b(<<0x00>> <> public_key, 32)

    assert Signer.address_from_public_key(public_key) == expected_address
    assert byte_size(Signer.address_from_public_key(public_key)) == 32
  end

  test "formats address as 0x-prefixed hex string" do
    address =
      <<0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24,
        25, 26, 27, 28, 29, 30, 31>>

    assert Signer.to_sui_address(address) ==
             "0x000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
  end

  test "rejects invalid key, signature, and address sizes" do
    assert_raise FunctionClauseError, fn -> Signer.keypair_from_private_key(<<1, 2, 3>>) end
    assert_raise FunctionClauseError, fn -> Signer.encode_signature(<<1, 2, 3>>, <<0::256>>) end
    assert_raise FunctionClauseError, fn -> Signer.encode_signature(<<0::512>>, <<1, 2, 3>>) end
    assert_raise FunctionClauseError, fn -> Signer.verify("payload", <<1, 2, 3>>, <<0::256>>) end
    assert_raise FunctionClauseError, fn -> Signer.verify("payload", <<0::512>>, <<1, 2, 3>>) end
    assert_raise FunctionClauseError, fn -> Signer.address_from_public_key(<<1, 2, 3>>) end
    assert_raise FunctionClauseError, fn -> Signer.to_sui_address(<<1, 2, 3>>) end
  end
end
