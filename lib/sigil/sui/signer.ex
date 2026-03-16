defmodule Sigil.Sui.Signer do
  @moduledoc """
  Ed25519 signing helpers for Sui intent messages.
  """

  @intent_prefix <<0, 0, 0>>
  @scheme_flag 0x00

  @typedoc "Raw Ed25519 public key bytes."
  @type public_key :: binary()

  @typedoc "Raw Ed25519 private key bytes."
  @type private_key :: binary()

  @typedoc "A public/private Ed25519 keypair."
  @type keypair :: {public_key(), private_key()}

  @typedoc "A raw Ed25519 signature."
  @type signature :: binary()

  @typedoc "A raw 32-byte Sui address."
  @type address :: binary()

  @doc "Generates a new Ed25519 keypair."
  @spec generate_keypair() :: keypair()
  def generate_keypair do
    :crypto.generate_key(:eddsa, :ed25519)
  end

  @doc "Derives the public key for a 32-byte private key."
  @spec keypair_from_private_key(private_key()) :: keypair()
  def keypair_from_private_key(<<_::binary-size(32)>> = private_key) do
    {public_key, _derived_private_key} = :crypto.generate_key(:eddsa, :ed25519, private_key)
    {public_key, private_key}
  end

  @doc "Signs the Blake2b-256 digest of the Sui intent-prefixed payload with Ed25519."
  @spec sign(binary(), private_key()) :: signature()
  def sign(data, <<_::binary-size(32)>> = private_key) when is_binary(data) do
    digest = Blake2.hash2b(intent_message(data), 32)
    :crypto.sign(:eddsa, :sha512, digest, [private_key, :ed25519])
  end

  @doc "Encodes a signature using Sui's scheme-byte format."
  @spec encode_signature(signature(), public_key()) :: binary()
  def encode_signature(<<_::binary-size(64)>> = signature, <<_::binary-size(32)>> = public_key) do
    <<@scheme_flag>> <> signature <> public_key
  end

  @doc "Verifies an Ed25519 signature against the Blake2b-256 digest of the Sui intent-prefixed payload."
  @spec verify(binary(), signature(), public_key()) :: boolean()
  def verify(data, <<_::binary-size(64)>> = signature, <<_::binary-size(32)>> = public_key)
      when is_binary(data) do
    digest = Blake2.hash2b(intent_message(data), 32)
    :crypto.verify(:eddsa, :sha512, digest, signature, [public_key, :ed25519])
  end

  @doc "Derives a raw 32-byte Sui address from a public key."
  @spec address_from_public_key(public_key()) :: address()
  def address_from_public_key(<<_::binary-size(32)>> = public_key) do
    Blake2.hash2b(<<@scheme_flag>> <> public_key, 32)
  end

  @doc "Formats a raw 32-byte address as a lowercase 0x-prefixed Sui address string."
  @spec to_sui_address(address()) :: String.t()
  def to_sui_address(<<_::binary-size(32)>> = address) do
    "0x" <> Base.encode16(address, case: :lower)
  end

  defp intent_message(data), do: @intent_prefix <> data
end
