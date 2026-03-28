defmodule Sigil.Sui.Client.HTTP.Codec do
  @moduledoc """
  Address, digest, and owner metadata decoding helpers for object refs.
  """

  alias Sigil.Sui.Base58

  @doc "Merges shared owner metadata into decoded object JSON maps."
  @spec merge_owner_metadata(map(), map()) :: map()
  def merge_owner_metadata(json, %{"owner" => %{"initialSharedVersion" => version}})
      when is_binary(version) or is_integer(version) do
    Map.put(json, "shared", %{"initialSharedVersion" => to_string(version)})
  end

  def merge_owner_metadata(json, _object), do: json

  @doc "Parses on-chain object versions from integer or decimal-string forms."
  @spec parse_version(term()) :: {:ok, non_neg_integer()} | :error
  def parse_version(version) when is_integer(version) and version >= 0, do: {:ok, version}

  def parse_version(version) when is_binary(version) do
    case Integer.parse(version) do
      {int, ""} when int >= 0 -> {:ok, int}
      _ -> :error
    end
  end

  def parse_version(_other), do: :error

  @doc "Decodes a Sui hex address into its 32-byte binary representation."
  @spec decode_sui_address(String.t()) :: {:ok, binary()} | {:error, :invalid_response}
  def decode_sui_address("0x" <> hex), do: decode_sui_address(hex)

  def decode_sui_address(hex) when is_binary(hex) do
    padded = String.pad_leading(hex, 64, "0")

    case Base.decode16(padded, case: :mixed) do
      {:ok, <<_::binary-size(32)>> = bytes} -> {:ok, bytes}
      _ -> {:error, :invalid_response}
    end
  end

  @doc "Decodes Base58 digests while normalizing decode failures."
  @spec base58_decode(String.t()) :: {:ok, binary()} | {:error, :invalid_response}
  def base58_decode(string) when is_binary(string) do
    case Base58.decode(string) do
      {:ok, _bytes} = ok -> ok
      {:error, :invalid_base58} -> {:error, :invalid_response}
    end
  end
end
