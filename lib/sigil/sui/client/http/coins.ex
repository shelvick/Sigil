defmodule Sigil.Sui.Client.HTTP.Coins do
  @moduledoc """
  GraphQL query and response parsing helpers for Sui coin operations.

  Extracted from `Sigil.Sui.Client.HTTP` to keep the main client module under
  the 500-line limit.
  """

  alias Sigil.Sui.Client

  @get_coins_query """
  query GetCoins($owner: SuiAddress!, $type: String) {
    address(address: $owner) {
      coins(type: $type) {
        nodes {
          address
          version
          digest
          contents {
            json
          }
        }
      }
    }
  }
  """

  @doc "Returns the GetCoins GraphQL query string."
  @spec query() :: String.t()
  def query, do: @get_coins_query

  @doc "Parses GraphQL coin response data into a list of coin_info maps."
  @spec build_list(map()) :: {:ok, [Client.coin_info()]} | {:error, Client.error_reason()}
  def build_list(%{"address" => %{"coins" => %{"nodes" => nodes}}}) when is_list(nodes) do
    nodes
    |> Enum.reduce_while({:ok, []}, fn node, {:ok, acc} ->
      case build_coin_info(node) do
        {:ok, coin_info} -> {:cont, {:ok, [coin_info | acc]}}
        {:error, :invalid_response} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, coin_infos} -> {:ok, Enum.reverse(coin_infos)}
      {:error, :invalid_response} = error -> error
    end
  end

  def build_list(_other), do: {:error, :invalid_response}

  @spec build_coin_info(map()) :: {:ok, Client.coin_info()} | {:error, Client.error_reason()}
  defp build_coin_info(%{
         "address" => address,
         "version" => version,
         "digest" => digest_b58,
         "contents" => %{"json" => %{"balance" => balance}}
       })
       when is_binary(address) and is_binary(digest_b58) do
    with {:ok, object_id} <- decode_sui_address(address),
         {:ok, <<_::binary-size(32)>> = digest} <- base58_decode(digest_b58),
         {:ok, version_int} <- parse_non_neg_integer(version),
         {:ok, balance_int} <- parse_non_neg_integer(balance) do
      {:ok, %{object_id: object_id, version: version_int, digest: digest, balance: balance_int}}
    else
      _other -> {:error, :invalid_response}
    end
  end

  defp build_coin_info(_other), do: {:error, :invalid_response}

  @spec decode_sui_address(String.t()) :: {:ok, <<_::256>>} | :error
  defp decode_sui_address("0x" <> hex), do: decode_sui_address(hex)

  defp decode_sui_address(hex) when is_binary(hex) do
    padded = String.pad_leading(hex, 64, "0")

    case Base.decode16(padded, case: :mixed) do
      {:ok, <<_::binary-size(32)>> = bytes} -> {:ok, bytes}
      _ -> :error
    end
  end

  @spec base58_decode(String.t()) :: {:ok, binary()} | :error
  defp base58_decode(encoded) when is_binary(encoded) do
    case Sigil.Sui.Base58.decode(encoded) do
      {:ok, _bytes} = ok -> ok
      {:error, :invalid_base58} -> :error
    end
  end

  @spec parse_non_neg_integer(term()) :: {:ok, non_neg_integer()} | :error
  defp parse_non_neg_integer(value) when is_integer(value) and value >= 0, do: {:ok, value}

  defp parse_non_neg_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} when int >= 0 -> {:ok, int}
      _other -> :error
    end
  end

  defp parse_non_neg_integer(_other), do: :error
end
