defmodule FrontierOS.Sui.Client do
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

  @typedoc "Supported object query filter entries."
  @type object_filter_key ::
          {:type, String.t()}
          | {:owner, String.t()}
          | {:cursor, String.t()}
          | {:limit, pos_integer()}

  @typedoc "Supported object query filters."
  @type object_filter :: [object_filter_key()]

  @typedoc "Client request options."
  @type request_opts :: [{:url, String.t()}]

  @doc "Fetches a single object by id."
  @callback get_object(String.t(), request_opts()) ::
              {:ok, object_map()} | {:error, error_reason()}

  @doc "Fetches objects matching the supplied filters."
  @callback get_objects(object_filter(), request_opts()) ::
              {:ok, [object_map()]} | {:error, error_reason()}

  @doc "Submits a signed transaction to Sui."
  @callback execute_transaction(String.t(), [String.t()], request_opts()) ::
              {:ok, tx_effects()} | {:error, error_reason()}
end
