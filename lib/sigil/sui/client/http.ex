defmodule Sigil.Sui.Client.HTTP do
  @moduledoc """
  Req-backed HTTP implementation for the Sui GraphQL client.
  """

  @behaviour Sigil.Sui.Client

  alias Sigil.Sui.{Base58, Client}

  @default_limit 50
  @default_retry_delay 1_000
  @default_max_retries 3

  @get_object_query """
  query GetObject($id: SuiAddress!) {
    object(address: $id) {
      address
      version
      digest
      owner {
        ... on Shared {
          initialSharedVersion
        }
      }
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
        owner {
          ... on Shared {
            initialSharedVersion
          }
        }
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
        bcs
        status
        transaction {
          digest
        }
        objectChanges {
          type
          objectId
          objectType
          version
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

  @verify_zklogin_query """
  query VerifyZkLoginSignature(
    $bytes: Base64!
    $signature: Base64!
    $intentScope: ZkLoginIntentScope!
    $author: SuiAddress!
  ) {
    verifyZkLoginSignature(
      bytes: $bytes
      signature: $signature
      intentScope: $intentScope
      author: $author
    ) {
      success
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

  @doc """
  Fetches a single Sui object with its on-chain reference (id, version, digest).

  Returns the Move JSON contents alongside the object ref tuple needed for
  transaction building (gas payment, object inputs).

  """
  @impl Client
  @spec get_object_with_ref(String.t(), Client.request_opts()) ::
          {:ok, Client.object_with_ref()} | {:error, Client.error_reason()}
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
            } = object
        }
        when is_binary(address) and is_binary(digest_b58) and is_map(object_json) ->
          with {:ok, id_bytes} <- decode_sui_address(address),
               {:ok, <<_::binary-size(32)>> = digest_bytes} <- base58_decode(digest_b58),
               {:ok, version_int} <- parse_version(version) do
            json = merge_owner_metadata(object_json, object)
            {:ok, %{json: json, ref: {id_bytes, version_int, digest_bytes}}}
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

  @doc "Verifies a zkLogin signature against the Sui GraphQL API."
  @impl Client
  @spec verify_zklogin_signature(
          String.t(),
          String.t(),
          Client.zklogin_intent_scope(),
          String.t(),
          Client.request_opts()
        ) :: {:ok, Client.zklogin_result()} | {:error, Client.error_reason()}
  def verify_zklogin_signature(bytes, signature, intent_scope, author, opts \\ [])
      when is_binary(bytes) and is_binary(signature) and is_binary(intent_scope) and
             is_binary(author) and is_list(opts) do
    graphql_request(
      @verify_zklogin_query,
      %{
        "bytes" => bytes,
        "signature" => signature,
        "intentScope" => intent_scope,
        "author" => author
      },
      opts
    )
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
      url: Keyword.get(opts, :url, graphql_url()),
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
  defp map_graphql_response({:ok, %Req.Response{status: 200, body: %{"errors" => errors}}})
       when is_list(errors) do
    {:error, {:graphql_errors, errors}}
  end

  defp map_graphql_response({:ok, %Req.Response{status: 200, body: %{"data" => data}}})
       when is_map(data) do
    {:ok, data}
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
        %{"asMoveObject" => %{"contents" => %{"json" => object_json}}} = node, {:ok, acc}
        when is_map(object_json) ->
          {:cont, {:ok, [merge_owner_metadata(object_json, node) | acc]}}

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

  # -- Owner metadata merging for shared objects --

  @spec merge_owner_metadata(map(), map()) :: map()
  defp merge_owner_metadata(json, %{"owner" => %{"initialSharedVersion" => version}})
       when is_binary(version) or is_integer(version) do
    Map.put(json, "shared", %{"initialSharedVersion" => to_string(version)})
  end

  defp merge_owner_metadata(json, _object), do: json

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
    case Base58.decode(string) do
      {:ok, _bytes} = ok -> ok
      {:error, :invalid_base58} -> {:error, :invalid_response}
    end
  end

  # -- World configuration --

  @spec graphql_url() :: String.t()
  defp graphql_url do
    world = Application.fetch_env!(:sigil, :eve_world)
    worlds = Application.fetch_env!(:sigil, :eve_worlds)
    %{graphql_url: url} = Map.fetch!(worlds, world)
    url
  end

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
    Application.get_env(:sigil, :sui_client_retry_delay, @default_retry_delay)
  end

  @spec max_retries() :: non_neg_integer()
  defp max_retries do
    Application.get_env(:sigil, :sui_client_max_retries, @default_max_retries)
  end
end
