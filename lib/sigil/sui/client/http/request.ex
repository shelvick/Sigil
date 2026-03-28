defmodule Sigil.Sui.Client.HTTP.Request do
  @moduledoc """
  Shared GraphQL request and response helpers for the Sui HTTP client.
  """

  alias Sigil.Sui.Client

  @doc "Builds Req options for GraphQL request execution."
  @spec request_options(
          keyword(),
          String.t(),
          map(),
          String.t(),
          non_neg_integer(),
          non_neg_integer()
        ) ::
          keyword()
  def request_options(opts, query, variables, graphql_url, retry_delay, max_retries) do
    opts
    |> Keyword.get(:req_options, [])
    |> Keyword.merge(
      url: Keyword.get(opts, :url, graphql_url),
      json: %{"query" => query, "variables" => variables},
      receive_timeout: 30_000,
      retry: &retry?/2,
      retry_delay: retry_delay,
      max_retries: max_retries,
      retry_log_level: false
    )
  end

  @doc "Maps Req response tuples into client contract tuples."
  @spec map_graphql_response({:ok, Req.Response.t()} | {:error, Exception.t()}) ::
          {:ok, map()} | {:error, Client.error_reason()}
  def map_graphql_response({:ok, %Req.Response{status: 200, body: %{"errors" => errors}}})
      when is_list(errors) do
    {:error, {:graphql_errors, errors}}
  end

  def map_graphql_response({:ok, %Req.Response{status: 200, body: %{"data" => data}}})
      when is_map(data) do
    {:ok, data}
  end

  def map_graphql_response({:ok, %Req.Response{status: 429}}), do: {:error, :rate_limited}
  def map_graphql_response({:ok, %Req.Response{status: 200}}), do: {:error, :invalid_response}
  def map_graphql_response({:ok, %Req.Response{}}), do: {:error, :invalid_response}

  def map_graphql_response({:error, %Req.TransportError{reason: :timeout}}),
    do: {:error, :timeout}

  def map_graphql_response({:error, _exception}), do: {:error, :invalid_response}

  @doc "Returns true for retryable HTTP and transport failures."
  @spec retry?(Req.Request.t(), Req.Response.t() | Exception.t()) :: boolean()
  def retry?(_request, %Req.Response{status: status}) when status in [408, 500, 502, 503, 504],
    do: true

  def retry?(_request, %Req.TransportError{reason: reason})
      when reason in [:timeout, :econnrefused, :closed],
      do: true

  def retry?(_request, %Req.HTTPError{protocol: :http2, reason: :unprocessed}), do: true
  def retry?(_request, _response_or_exception), do: false
end
