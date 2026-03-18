defmodule Sigil.StaticData.WorldClient do
  @moduledoc """
  Behaviour contract for fetching World API reference data.
  """

  @typedoc "A raw World API record."
  @type record :: %{required(String.t()) => term()}

  @typedoc "Client error reasons exposed to callers."
  @type error_reason :: :timeout | {:http_error, integer()} | :invalid_response

  @typedoc "Request options for World API fetches."
  @type request_opts :: keyword()

  @doc "Fetches all item types from the World API."
  @callback fetch_types(request_opts()) :: {:ok, [record()]} | {:error, error_reason()}

  @doc "Fetches all solar systems from the World API."
  @callback fetch_solar_systems(request_opts()) :: {:ok, [record()]} | {:error, error_reason()}

  @doc "Fetches all constellations from the World API."
  @callback fetch_constellations(request_opts()) :: {:ok, [record()]} | {:error, error_reason()}

  @doc "Fetches all tribes from the World API."
  @callback fetch_tribes(request_opts()) :: {:ok, [record()]} | {:error, error_reason()}
end
