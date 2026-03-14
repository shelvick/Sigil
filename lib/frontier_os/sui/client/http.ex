defmodule FrontierOS.Sui.Client.HTTP do
  @moduledoc """
  Req-backed HTTP implementation for the Sui GraphQL client.
  """

  @behaviour FrontierOS.Sui.Client

  alias FrontierOS.Sui.Client

  @default_url "https://graphql.testnet.sui.io/graphql"
  @default_limit 50
  @default_retry_delay 1_000
  @default_max_retries 3

  @get_object_query """
  query GetObject($id: SuiAddress!) {
    object(address: $id) {
      address
      version
      digest
      asMoveObject {
        contents {
          json
          type {
            repr
          }
        }
      }
    }
  }
  """

  @get_objects_query """
  query GetObjects($filter: ObjectFilter, $first: Int, $after: String) {
    objects(filter: $filter, first: $first, after: $after) {
      pageInfo {
        hasNextPage
        endCursor
      }
      nodes {
        address
        asMoveObject {
          contents {
            json
            type {
              repr
            }
          }
        }
      }
    }
  }
  """

  @execute_transaction_mutation """
  mutation ExecuteTransaction($tx: Base64!, $sigs: [Base64!]!) {
    executeTransaction(transactionDataBcs: $tx, signatures: $sigs) {
      effects {
        status
        transaction {
          digest
        }
        gasEffects {
          gasSummary {
            computationCost
            storageCost
            storageRebate
          }
        }
      }
    }
  }
  """

  @doc "Fetches a single Sui object by address."
  @impl Client
  @spec get_object(String.t(), Client.request_opts()) ::
          {:ok, Client.object_map()} | {:error, Client.error_reason()}
  def get_object(id, opts \\ []) when is_binary(id) and is_list(opts) do
    with {:ok, data} <- graphql_request(@get_object_query, %{"id" => id}, opts) do
      case data do
        %{"object" => nil} ->
          {:error, :not_found}

        %{"object" => %{"asMoveObject" => %{"contents" => %{"json" => object_json}}}}
        when is_map(object_json) ->
          {:ok, object_json}

        _other ->
          {:error, :invalid_response}
      end
    end
  end

  @typedoc "Object reference tuple: {32-byte id, version, 32-byte digest}."
  @type object_ref :: {binary(), non_neg_integer(), binary()}

  @doc """
  Fetches a single Sui object with its on-chain reference (id, version, digest).

  Returns the Move JSON contents alongside the object ref tuple needed for
  transaction building (gas payment, object inputs).

  Not a behaviour callback — specific to the HTTP implementation.
  """
  @spec get_object_with_ref(String.t(), Client.request_opts()) ::
          {:ok, %{json: Client.object_map(), ref: object_ref()}} | {:error, Client.error_reason()}
  def get_object_with_ref(id, opts \\ []) when is_binary(id) and is_list(opts) do
    with {:ok, data} <- graphql_request(@get_object_query, %{"id" => id}, opts) do
      case data do
        %{"object" => nil} ->
          {:error, :not_found}

        %{
          "object" =>
            %{
              "address" => address,
              "version" => version,
              "digest" => digest_b58,
              "asMoveObject" => %{"contents" => %{"json" => object_json}}
            } = _object
        }
        when is_binary(address) and is_binary(digest_b58) and is_map(object_json) ->
          with {:ok, id_bytes} <- decode_sui_address(address),
               {:ok, <<_::binary-size(32)>> = digest_bytes} <- base58_decode(digest_b58),
               {:ok, version_int} <- parse_version(version) do
            {:ok, %{json: object_json, ref: {id_bytes, version_int, digest_bytes}}}
          else
            _ -> {:error, :invalid_response}
          end

        _other ->
          {:error, :invalid_response}
      end
    end
  end

  @doc "Fetches a single page of Sui objects matching the supplied filters."
  @impl Client
  @spec get_objects(Client.object_filter(), Client.request_opts()) ::
          {:ok, Client.objects_page()} | {:error, Client.error_reason()}
  def get_objects(filters, opts \\ []) when is_list(filters) and is_list(opts) do
    with {:ok, data} <- graphql_request(@get_objects_query, object_variables(filters), opts) do
      build_objects_page(data)
    end
  end

  @doc "Submits a signed transaction to the Sui GraphQL API."
  @impl Client
  @spec execute_transaction(String.t(), [String.t()], Client.request_opts()) ::
          {:ok, Client.tx_effects()} | {:error, Client.error_reason()}
  def execute_transaction(tx_bytes, signatures, opts \\ [])
      when is_binary(tx_bytes) and is_list(signatures) and is_list(opts) do
    with {:ok, data} <-
           graphql_request(
             @execute_transaction_mutation,
             %{"tx" => tx_bytes, "sigs" => signatures},
             opts
           ) do
      case data do
        %{"executeTransaction" => %{"effects" => effects}} when is_map(effects) ->
          {:ok, effects}

        _other ->
          {:error, :invalid_response}
      end
    end
  end

  @spec graphql_request(String.t(), map(), keyword()) ::
          {:ok, map()} | {:error, Client.error_reason()}
  defp graphql_request(query, variables, opts) do
    opts
    |> request_options(query, variables)
    |> Req.post()
    |> map_graphql_response()
  end

  @spec request_options(keyword(), String.t(), map()) :: keyword()
  defp request_options(opts, query, variables) do
    opts
    |> Keyword.get(:req_options, [])
    |> Keyword.merge(
      url: Keyword.get(opts, :url, @default_url),
      json: %{"query" => query, "variables" => variables},
      receive_timeout: 30_000,
      retry: &retry?/2,
      retry_delay: retry_delay(),
      max_retries: max_retries(),
      retry_log_level: false
    )
  end

  @spec map_graphql_response({:ok, Req.Response.t()} | {:error, Exception.t()}) ::
          {:ok, map()} | {:error, Client.error_reason()}
  defp map_graphql_response({:ok, %Req.Response{status: 200, body: %{"data" => data}}})
       when is_map(data) do
    {:ok, data}
  end

  defp map_graphql_response({:ok, %Req.Response{status: 200, body: %{"errors" => errors}}})
       when is_list(errors) do
    {:error, {:graphql_errors, errors}}
  end

  defp map_graphql_response({:ok, %Req.Response{status: 429}}), do: {:error, :rate_limited}

  defp map_graphql_response({:ok, %Req.Response{status: 200}}), do: {:error, :invalid_response}

  defp map_graphql_response({:ok, %Req.Response{}}), do: {:error, :invalid_response}

  defp map_graphql_response({:error, %Req.TransportError{reason: :timeout}}),
    do: {:error, :timeout}

  defp map_graphql_response({:error, _exception}), do: {:error, :invalid_response}

  @spec object_variables(Client.object_filter()) :: map()
  defp object_variables(filters) do
    {filter, after_cursor, limit} =
      Enum.reduce(filters, {%{}, nil, @default_limit}, fn
        {:type, type}, {filter, after_cursor, limit} ->
          {Map.put(filter, "type", type), after_cursor, limit}

        {:owner, owner}, {filter, after_cursor, limit} ->
          {Map.put(filter, "owner", owner), after_cursor, limit}

        {:cursor, cursor}, {filter, _after_cursor, limit} ->
          {filter, cursor, limit}

        {:limit, page_size}, {filter, after_cursor, _limit} ->
          {filter, after_cursor, page_size}
      end)

    %{"filter" => filter, "after" => after_cursor, "first" => limit}
  end

  @spec build_objects_page(map()) ::
          {:ok, Client.objects_page()} | {:error, Client.error_reason()}
  defp build_objects_page(%{"objects" => %{"pageInfo" => page_info, "nodes" => nodes}})
       when is_map(page_info) and is_list(nodes) do
    with {:ok, has_next_page} when is_boolean(has_next_page) <-
           Map.fetch(page_info, "hasNextPage"),
         {:ok, end_cursor} <- fetch_end_cursor(page_info),
         {:ok, object_data} <- extract_object_data(nodes) do
      {:ok, %{data: object_data, has_next_page: has_next_page, end_cursor: end_cursor}}
    else
      :error -> {:error, :invalid_response}
      {:error, :invalid_response} -> {:error, :invalid_response}
    end
  end

  defp build_objects_page(_other), do: {:error, :invalid_response}

  @spec fetch_end_cursor(map()) :: {:ok, String.t() | nil} | :error
  defp fetch_end_cursor(page_info) do
    case Map.fetch(page_info, "endCursor") do
      {:ok, end_cursor} when is_binary(end_cursor) or is_nil(end_cursor) -> {:ok, end_cursor}
      _other -> :error
    end
  end

  @spec extract_object_data([map()]) ::
          {:ok, [Client.object_map()]} | {:error, Client.error_reason()}
  defp extract_object_data(nodes) do
    reduced_nodes =
      Enum.reduce_while(nodes, {:ok, []}, fn
        %{"asMoveObject" => %{"contents" => %{"json" => object_json}}}, {:ok, acc}
        when is_map(object_json) ->
          {:cont, {:ok, [object_json | acc]}}

        %{"asMoveObject" => nil}, {:ok, acc} ->
          {:cont, {:ok, acc}}

        _node, _acc ->
          {:halt, {:error, :invalid_response}}
      end)

    case reduced_nodes do
      {:ok, object_data} -> {:ok, Enum.reverse(object_data)}
      {:error, :invalid_response} = error -> error
    end
  end

  # -- Address, version & digest decoding for object refs --

  @spec parse_version(term()) :: {:ok, non_neg_integer()} | :error
  defp parse_version(version) when is_integer(version) and version >= 0, do: {:ok, version}

  defp parse_version(version) when is_binary(version) do
    case Integer.parse(version) do
      {int, ""} when int >= 0 -> {:ok, int}
      _ -> :error
    end
  end

  defp parse_version(_other), do: :error

  @b58_alphabet ~c"123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"

  @spec decode_sui_address(String.t()) :: {:ok, binary()} | {:error, :invalid_response}
  defp decode_sui_address("0x" <> hex), do: decode_sui_address(hex)

  defp decode_sui_address(hex) when is_binary(hex) do
    padded = String.pad_leading(hex, 64, "0")

    case Base.decode16(padded, case: :mixed) do
      {:ok, <<_::binary-size(32)>> = bytes} -> {:ok, bytes}
      _ -> {:error, :invalid_response}
    end
  end

  @spec base58_decode(String.t()) :: {:ok, binary()} | {:error, :invalid_response}
  defp base58_decode(string) when is_binary(string) do
    chars = String.to_charlist(string)
    leading_zeros = count_leading(chars, ?1, 0)

    case decode_b58_chars(chars, 0) do
      {:ok, integer} ->
        value_bytes = if integer == 0, do: <<>>, else: :binary.encode_unsigned(integer)
        {:ok, <<0::size(leading_zeros)-unit(8), value_bytes::binary>>}

      :error ->
        {:error, :invalid_response}
    end
  end

  @spec decode_b58_chars(charlist(), non_neg_integer()) :: {:ok, non_neg_integer()} | :error
  defp decode_b58_chars([], acc), do: {:ok, acc}

  defp decode_b58_chars([char | rest], acc) do
    case b58_index(char, @b58_alphabet, 0) do
      {:ok, index} -> decode_b58_chars(rest, acc * 58 + index)
      :error -> :error
    end
  end

  @spec b58_index(char(), charlist(), non_neg_integer()) :: {:ok, non_neg_integer()} | :error
  defp b58_index(_char, [], _index), do: :error
  defp b58_index(char, [char | _rest], index), do: {:ok, index}
  defp b58_index(char, [_other | rest], index), do: b58_index(char, rest, index + 1)

  @spec count_leading(charlist(), char(), non_neg_integer()) :: non_neg_integer()
  defp count_leading([char | rest], char, count), do: count_leading(rest, char, count + 1)
  defp count_leading(_other, _char, count), do: count

  # -- Retry configuration --

  @spec retry?(Req.Request.t(), Req.Response.t() | Exception.t()) :: boolean()
  defp retry?(_request, %Req.Response{status: status}) when status in [408, 500, 502, 503, 504],
    do: true

  defp retry?(_request, %Req.TransportError{reason: reason})
       when reason in [:timeout, :econnrefused, :closed],
       do: true

  defp retry?(_request, %Req.HTTPError{protocol: :http2, reason: :unprocessed}), do: true

  defp retry?(_request, _response_or_exception), do: false

  @spec retry_delay() :: non_neg_integer()
  defp retry_delay do
    Application.get_env(:frontier_os, :sui_client_retry_delay, @default_retry_delay)
  end

  @spec max_retries() :: non_neg_integer()
  defp max_retries do
    Application.get_env(:frontier_os, :sui_client_max_retries, @default_max_retries)
  end
end
