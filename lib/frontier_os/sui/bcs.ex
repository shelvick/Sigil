defmodule FrontierOS.Sui.BCS do
  @moduledoc """
  Binary Canonical Serialization helpers for Sui transaction data.
  """

  @type decoder(value) :: (binary() -> {value, binary()})
  @type encoder(value) :: (value -> binary())

  @max_u8 0xFF
  @max_u16 0xFFFF
  @max_u32 0xFFFFFFFF
  @max_u64 0xFFFFFFFFFFFFFFFF
  @max_u128 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
  @max_u256 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF

  @doc "Encodes an unsigned 8-bit integer."
  @spec encode_u8(non_neg_integer()) :: binary()
  def encode_u8(value) when is_integer(value) and value >= 0 and value <= @max_u8,
    do: <<value>>

  @doc "Encodes an unsigned 16-bit integer in little-endian order."
  @spec encode_u16(non_neg_integer()) :: binary()
  def encode_u16(value) when is_integer(value) and value >= 0 and value <= @max_u16,
    do: <<value::unsigned-little-integer-size(16)>>

  @doc "Encodes an unsigned 32-bit integer in little-endian order."
  @spec encode_u32(non_neg_integer()) :: binary()
  def encode_u32(value) when is_integer(value) and value >= 0 and value <= @max_u32,
    do: <<value::unsigned-little-integer-size(32)>>

  @doc "Encodes an unsigned 64-bit integer in little-endian order."
  @spec encode_u64(non_neg_integer()) :: binary()
  def encode_u64(value) when is_integer(value) and value >= 0 and value <= @max_u64,
    do: <<value::unsigned-little-integer-size(64)>>

  @doc "Encodes an unsigned 128-bit integer in little-endian order."
  @spec encode_u128(non_neg_integer()) :: binary()
  def encode_u128(value) when is_integer(value) and value >= 0 and value <= @max_u128,
    do: <<value::unsigned-little-integer-size(128)>>

  @doc "Encodes an unsigned 256-bit integer in little-endian order."
  @spec encode_u256(non_neg_integer()) :: binary()
  def encode_u256(value) when is_integer(value) and value >= 0 and value <= @max_u256,
    do: <<value::unsigned-little-integer-size(256)>>

  @doc "Encodes a non-negative integer using ULEB128."
  @spec encode_uleb128(non_neg_integer()) :: binary()
  def encode_uleb128(value) when is_integer(value) and value >= 0 do
    do_encode_uleb128(value, [])
  end

  @doc "Encodes a boolean as a single byte."
  @spec encode_bool(boolean()) :: binary()
  def encode_bool(false), do: <<0>>
  def encode_bool(true), do: <<1>>

  @doc "Encodes a UTF-8 string with a ULEB128 byte-length prefix."
  @spec encode_string(String.t()) :: binary()
  def encode_string(value) when is_binary(value) do
    unless String.valid?(value), do: raise(ArgumentError, "expected a valid UTF-8 string")
    encode_uleb128(byte_size(value)) <> value
  end

  @doc "Encodes a vector using the provided element encoder."
  @spec encode_vector(list(value), encoder(value)) :: binary() when value: var
  def encode_vector(values, encoder) when is_list(values) and is_function(encoder, 1) do
    encoded_values = values |> Enum.map(encoder) |> IO.iodata_to_binary()
    encode_uleb128(length(values)) <> encoded_values
  end

  @doc "Encodes an optional value using BCS option semantics."
  @spec encode_option(value | nil, encoder(value)) :: binary() when value: var
  def encode_option(nil, _encoder), do: <<0>>

  def encode_option(value, encoder) when is_function(encoder, 1) do
    <<1>> <> encoder.(value)
  end

  @doc "Encodes a 32-byte Sui address without a length prefix."
  @spec encode_address(binary()) :: binary()
  def encode_address(<<_::binary-size(32)>> = address), do: address

  @doc "Decodes an unsigned 8-bit integer."
  @spec decode_u8(binary()) :: {non_neg_integer(), binary()}
  def decode_u8(<<value, rest::binary>>), do: {value, rest}

  @doc "Decodes an unsigned 16-bit integer in little-endian order."
  @spec decode_u16(binary()) :: {non_neg_integer(), binary()}
  def decode_u16(<<value::unsigned-little-integer-size(16), rest::binary>>), do: {value, rest}

  @doc "Decodes an unsigned 32-bit integer in little-endian order."
  @spec decode_u32(binary()) :: {non_neg_integer(), binary()}
  def decode_u32(<<value::unsigned-little-integer-size(32), rest::binary>>), do: {value, rest}

  @doc "Decodes an unsigned 64-bit integer in little-endian order."
  @spec decode_u64(binary()) :: {non_neg_integer(), binary()}
  def decode_u64(<<value::unsigned-little-integer-size(64), rest::binary>>), do: {value, rest}

  @doc "Decodes an unsigned 128-bit integer in little-endian order."
  @spec decode_u128(binary()) :: {non_neg_integer(), binary()}
  def decode_u128(<<value::unsigned-little-integer-size(128), rest::binary>>), do: {value, rest}

  @doc "Decodes an unsigned 256-bit integer in little-endian order."
  @spec decode_u256(binary()) :: {non_neg_integer(), binary()}
  def decode_u256(<<value::unsigned-little-integer-size(256), rest::binary>>), do: {value, rest}

  @doc "Decodes a ULEB128-encoded non-negative integer."
  @spec decode_uleb128(binary()) :: {non_neg_integer(), binary()}
  def decode_uleb128(binary) when is_binary(binary) do
    do_decode_uleb128(binary, 0, 0)
  end

  @doc "Decodes a BCS boolean."
  @spec decode_bool(binary()) :: {boolean(), binary()}
  def decode_bool(<<0, rest::binary>>), do: {false, rest}
  def decode_bool(<<1, rest::binary>>), do: {true, rest}

  @doc "Decodes a length-prefixed UTF-8 string."
  @spec decode_string(binary()) :: {String.t(), binary()}
  def decode_string(binary) when is_binary(binary) do
    {length, rest} = decode_uleb128(binary)
    {string, remainder} = take_prefix(rest, length)
    unless String.valid?(string), do: raise(ArgumentError, "decoded bytes are not valid UTF-8")
    {string, remainder}
  end

  @doc "Decodes a vector using the provided element decoder."
  @spec decode_vector(binary(), decoder(value)) :: {list(value), binary()} when value: var
  def decode_vector(binary, decoder) when is_binary(binary) and is_function(decoder, 1) do
    {count, rest} = decode_uleb128(binary)
    decode_vector_items(rest, count, decoder, [])
  end

  @doc "Decodes a BCS option using the provided decoder."
  @spec decode_option(binary(), decoder(value)) :: {value | nil, binary()} when value: var
  def decode_option(<<0, rest::binary>>, _decoder), do: {nil, rest}

  def decode_option(<<1, rest::binary>>, decoder) when is_function(decoder, 1) do
    decoder.(rest)
  end

  @doc "Decodes a 32-byte Sui address."
  @spec decode_address(binary()) :: {binary(), binary()}
  def decode_address(<<address::binary-size(32), rest::binary>>), do: {address, rest}

  defp do_encode_uleb128(value, acc) when value < 0x80 do
    acc
    |> Enum.reverse([value])
    |> :erlang.list_to_binary()
  end

  defp do_encode_uleb128(value, acc) do
    byte = Bitwise.bor(Bitwise.band(value, 0x7F), 0x80)
    do_encode_uleb128(Bitwise.bsr(value, 7), [byte | acc])
  end

  defp do_decode_uleb128(<<byte, rest::binary>>, acc, shift) when byte < 0x80 do
    {acc + Bitwise.bsl(byte, shift), rest}
  end

  defp do_decode_uleb128(<<byte, rest::binary>>, acc, shift) do
    value = acc + Bitwise.bsl(Bitwise.band(byte, 0x7F), shift)
    do_decode_uleb128(rest, value, shift + 7)
  end

  defp take_prefix(binary, length) when byte_size(binary) >= length do
    <<prefix::binary-size(length), rest::binary>> = binary
    {prefix, rest}
  end

  defp decode_vector_items(binary, 0, _decoder, acc), do: {Enum.reverse(acc), binary}

  defp decode_vector_items(binary, count, decoder, acc) when count > 0 do
    {value, rest} = decoder.(binary)
    decode_vector_items(rest, count - 1, decoder, [value | acc])
  end
end
