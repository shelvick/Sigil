defmodule Sigil.Sui.Client do
  @moduledoc """
  Behaviour contract for Sui GraphQL access.
  """

  @typedoc "Client error reasons exposed to callers."
  @type error_reason ::
          :timeout
          | :rate_limited
          | {:graphql_errors, [map()]}
          | :not_found
          | :invalid_response

  @typedoc "Raw object payload returned from Sui."
  @type object_map :: %{String.t() => term()}

  @typedoc "Raw transaction effects payload returned from Sui."
  @type tx_effects :: %{String.t() => term()}

  @typedoc "Single objects query page returned from Sui."
  @type objects_page :: %{
          data: [object_map()],
          has_next_page: boolean(),
          end_cursor: String.t() | nil
        }

  @typedoc "Supported object query filter entries."
  @type object_filter_key ::
          {:type, String.t()}
          | {:owner, String.t()}
          | {:cursor, String.t()}
          | {:limit, pos_integer()}

  @typedoc "Supported object query filters."
  @type object_filter :: [object_filter_key()]

  @typedoc "Single client request option."
  @type request_opt ::
          {:url, String.t()}
          | {:req_options, keyword()}
          | {:cursor, String.t()}
          | {:limit, pos_integer()}
          | {:world, String.t()}

  @typedoc "Client request options."
  @type request_opts :: [request_opt()]

  @typedoc "Dynamic field name metadata returned from Sui."
  @type dynamic_field_name :: %{type: String.t(), json: term()}

  @typedoc "Normalized dynamic field value returned from Sui."
  @type dynamic_field_value :: %{type: String.t(), json: term()}

  @typedoc "Single dynamic field entry returned from Sui."
  @type dynamic_field_entry :: %{name: dynamic_field_name(), value: dynamic_field_value()}

  @typedoc "Single dynamic fields query page returned from Sui."
  @type dynamic_fields_page :: %{
          data: [dynamic_field_entry()],
          has_next_page: boolean(),
          end_cursor: String.t() | nil
        }

  @doc "Fetches a single object by id."
  @callback get_object(String.t(), request_opts()) ::
              {:ok, object_map()} | {:error, error_reason()}

  @typedoc "Object reference: {32-byte id, version, 32-byte digest}."
  @type object_ref :: {binary(), non_neg_integer(), binary()}

  @typedoc "Object with its on-chain reference."
  @type object_with_ref :: %{json: object_map(), ref: object_ref()}

  @doc "Fetches a single object with its on-chain reference (id, version, digest)."
  @callback get_object_with_ref(String.t(), request_opts()) ::
              {:ok, object_with_ref()} | {:error, error_reason()}

  @doc "Fetches objects matching the supplied filters."
  @callback get_objects(object_filter(), request_opts()) ::
              {:ok, objects_page()} | {:error, error_reason()}

  @doc "Fetches dynamic fields owned by a parent object."
  @callback get_dynamic_fields(String.t(), request_opts()) ::
              {:ok, dynamic_fields_page()} | {:error, error_reason()}

  @typedoc "Intent scope used for zkLogin signature verification."
  @type zklogin_intent_scope :: String.t()

  @typedoc "Raw zkLogin verification payload returned from Sui."
  @type zklogin_result :: %{String.t() => term()}

  @typedoc "SUI coin info used for gas selection."
  @type coin_info :: %{
          object_id: <<_::256>>,
          version: non_neg_integer(),
          digest: <<_::256>>,
          balance: non_neg_integer()
        }

  @doc "Submits a signed transaction to Sui."
  @callback execute_transaction(String.t(), [String.t()], request_opts()) ::
              {:ok, tx_effects()} | {:error, error_reason()}

  @doc "Verifies a zkLogin signature for the supplied author and intent scope."
  @callback verify_zklogin_signature(
              String.t(),
              String.t(),
              zklogin_intent_scope(),
              String.t(),
              request_opts()
            ) :: {:ok, zklogin_result()} | {:error, error_reason()}

  @doc "Fetches SUI coins owned by an address for gas selection."
  @callback get_coins(String.t(), request_opts()) ::
              {:ok, [coin_info()]} | {:error, error_reason()}
end
