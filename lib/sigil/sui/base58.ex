defmodule Sigil.Sui.Base58 do
  @moduledoc """
  Pure-Elixir Base58 decoder for Sui transaction digests.

  Used by `Sigil.Diplomacy` (gas coin digest decoding) and
  `Sigil.Sui.Client.HTTP` (object reference digest decoding).
  No external dependencies.
  """

  @b58_alphabet ~c"123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"

  @doc "Decodes a Base58 string into raw bytes. Raises on invalid characters."
  @spec decode!(String.t()) :: binary()
  def decode!(string) when is_binary(string) do
    chars = String.to_charlist(string)
    leading_zeros = count_leading(chars, ?1, 0)
    integer = decode_chars!(chars, 0)
    value_bytes = if integer == 0, do: <<>>, else: :binary.encode_unsigned(integer)
    <<0::size(leading_zeros)-unit(8), value_bytes::binary>>
  end

  @doc "Decodes a Base58 string into raw bytes. Returns `{:ok, binary}` or `{:error, :invalid_base58}`."
  @spec decode(String.t()) :: {:ok, binary()} | {:error, :invalid_base58}
  def decode(string) when is_binary(string) do
    chars = String.to_charlist(string)
    leading_zeros = count_leading(chars, ?1, 0)

    case decode_chars(chars, 0) do
      {:ok, integer} ->
        value_bytes = if integer == 0, do: <<>>, else: :binary.encode_unsigned(integer)
        {:ok, <<0::size(leading_zeros)-unit(8), value_bytes::binary>>}

      :error ->
        {:error, :invalid_base58}
    end
  end

  # -- Raising variant helpers --

  @spec decode_chars!(charlist(), non_neg_integer()) :: non_neg_integer()
  defp decode_chars!([], acc), do: acc

  defp decode_chars!([char | rest], acc) do
    index = char_index!(char, @b58_alphabet, 0)
    decode_chars!(rest, acc * 58 + index)
  end

  @spec char_index!(char(), charlist(), non_neg_integer()) :: non_neg_integer()
  defp char_index!(char, [char | _rest], index), do: index
  defp char_index!(char, [_other | rest], index), do: char_index!(char, rest, index + 1)

  # -- Safe variant helpers --

  @spec decode_chars(charlist(), non_neg_integer()) :: {:ok, non_neg_integer()} | :error
  defp decode_chars([], acc), do: {:ok, acc}

  defp decode_chars([char | rest], acc) do
    case char_index(char, @b58_alphabet, 0) do
      {:ok, index} -> decode_chars(rest, acc * 58 + index)
      :error -> :error
    end
  end

  @spec char_index(char(), charlist(), non_neg_integer()) :: {:ok, non_neg_integer()} | :error
  defp char_index(_char, [], _index), do: :error
  defp char_index(char, [char | _rest], index), do: {:ok, index}
  defp char_index(char, [_other | rest], index), do: char_index(char, rest, index + 1)

  # -- Shared --

  @spec count_leading(charlist(), char(), non_neg_integer()) :: non_neg_integer()
  defp count_leading([char | rest], char, count), do: count_leading(rest, char, count + 1)
  defp count_leading(_other, _char, count), do: count
end
