defmodule Sigil.Sui.Client.HTTP do
  @moduledoc """
  Req-backed HTTP implementation for the Sui GraphQL client.
  """

  @behaviour Sigil.Sui.Client

  alias Sigil.Sui.Client
  alias Sigil.Sui.Client.HTTP.{Codec, Paging, Request}

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

  alias Sigil.Sui.Client.HTTP.{Coins, DynamicFields}

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
          with {:ok, id_bytes} <- Codec.decode_sui_address(address),
               {:ok, <<_::binary-size(32)>> = digest_bytes} <- Codec.base58_decode(digest_b58),
               {:ok, version_int} <- Codec.parse_version(version) do
            json = Codec.merge_owner_metadata(object_json, object)
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
    with {:ok, data} <-
           graphql_request(
             @get_objects_query,
             Paging.object_variables(filters, @default_limit),
             opts
           ) do
      Paging.build_objects_page(data)
    end
  end

  @doc "Submits a signed transaction via Sui JSON-RPC."
  @impl Client
  @spec execute_transaction(String.t(), [String.t()], Client.request_opts()) ::
          {:ok, Client.tx_effects()} | {:error, Client.error_reason()}
  def execute_transaction(tx_bytes, signatures, opts \\ [])
      when is_binary(tx_bytes) and is_list(signatures) and is_list(opts) do
    body = %{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => "sui_executeTransactionBlock",
      "params" => [
        tx_bytes,
        signatures,
        %{"showEffects" => true, "showRawEffects" => true},
        "WaitForEffectsCert"
      ]
    }

    req_opts =
      opts
      |> Keyword.get(:req_options, [])
      |> Keyword.merge(
        url: rpc_url(),
        json: body,
        receive_timeout: 30_000,
        retry: &Request.retry?/2,
        retry_delay: retry_delay(),
        max_retries: max_retries(),
        retry_log_level: false
      )

    case Req.post(req_opts) do
      {:ok,
       %{
         status: 200,
         body: %{
           "result" =>
             %{
               "digest" => digest,
               "effects" => %{"status" => %{"status" => "success"}}
             } = result
         }
       }} ->
        {:ok,
         %{
           "status" => "SUCCESS",
           "digest" => digest,
           "effectsBcs" => result["rawEffects"]
         }}

      {:ok,
       %{
         status: 200,
         body: %{
           "result" => %{
             "effects" => %{"status" => %{"status" => status} = status_detail}
           }
         }
       }} ->
        error_msg = Map.get(status_detail, "error", status)
        {:error, {:tx_failed, error_msg}}

      {:ok, %{status: 200, body: %{"error" => %{"message" => message}}}} ->
        {:error, {:rpc_error, message}}

      {:ok, %{status: 200, body: %{"error" => error}}} ->
        {:error, {:rpc_error, inspect(error)}}

      {:ok, %Req.Response{status: 429}} ->
        {:error, :rate_limited}

      {:ok, %Req.Response{}} ->
        {:error, :invalid_response}

      {:error, %Req.TransportError{reason: :timeout}} ->
        {:error, :timeout}

      {:error, _exception} ->
        {:error, :invalid_response}
    end
  end

  @doc "Fetches a single page of dynamic fields for a parent object."
  @impl Client
  @spec get_dynamic_fields(String.t(), Client.request_opts()) ::
          {:ok, Client.dynamic_fields_page()} | {:error, Client.error_reason()}
  def get_dynamic_fields(parent_id, opts \\ []) when is_binary(parent_id) and is_list(opts) do
    variables = %{
      "id" => parent_id,
      "first" => Keyword.get(opts, :limit, @default_limit),
      "after" => Keyword.get(opts, :cursor)
    }

    with {:ok, data} <- graphql_request(DynamicFields.query(), variables, opts) do
      DynamicFields.build_page(data)
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

  @doc "Fetches SUI coin refs and balances for the given owner address."
  @impl Client
  @spec get_coins(String.t(), Client.request_opts()) ::
          {:ok, [Client.coin_info()]} | {:error, Client.error_reason()}
  def get_coins(owner, opts \\ []) when is_binary(owner) and is_list(opts) do
    with {:ok, data} <-
           graphql_request(
             Coins.query(),
             %{"owner" => owner, "type" => "0x2::coin::Coin<0x2::sui::SUI>"},
             opts
           ) do
      Coins.build_list(data)
    end
  end

  @spec graphql_request(String.t(), map(), keyword()) ::
          {:ok, map()} | {:error, Client.error_reason()}
  defp graphql_request(query, variables, opts) do
    opts
    |> Request.request_options(query, variables, graphql_url(), retry_delay(), max_retries())
    |> Req.post()
    |> Request.map_graphql_response()
  end

  @spec graphql_url() :: String.t()
  defp graphql_url do
    world = Application.fetch_env!(:sigil, :eve_world)
    worlds = Application.fetch_env!(:sigil, :eve_worlds)
    %{graphql_url: url} = Map.fetch!(worlds, world)
    url
  end

  @spec rpc_url() :: String.t()
  defp rpc_url do
    world = Application.fetch_env!(:sigil, :eve_world)
    worlds = Application.fetch_env!(:sigil, :eve_worlds)
    %{rpc_url: url} = Map.fetch!(worlds, world)
    url
  end

  @spec retry_delay() :: non_neg_integer()
  defp retry_delay do
    Application.get_env(:sigil, :sui_client_retry_delay, @default_retry_delay)
  end

  @spec max_retries() :: non_neg_integer()
  defp max_retries do
    Application.get_env(:sigil, :sui_client_max_retries, @default_max_retries)
  end
end
