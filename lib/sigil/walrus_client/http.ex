defmodule Sigil.WalrusClient.HTTP do
  @moduledoc """
  Req-backed HTTP client for Walrus blob storage.
  """

  @behaviour Sigil.WalrusClient

  @default_publisher_url "https://publisher.walrus-testnet.walrus.space"
  @default_aggregator_url "https://aggregator.walrus-testnet.walrus.space"
  @default_receive_timeout 30_000

  @doc "Uploads a blob to Walrus and returns the resulting blob id."
  @impl Sigil.WalrusClient
  @spec store_blob(binary(), pos_integer(), keyword()) :: Sigil.WalrusClient.store_result()
  def store_blob(blob, epochs, opts \\ [])
      when is_binary(blob) and is_integer(epochs) and epochs > 0 and is_list(opts) do
    opts
    |> publisher_request_options("/v1/blobs", params: [epochs: epochs], body: blob)
    |> Req.put()
    |> store_response()
  end

  @doc "Fetches a blob payload from the Walrus aggregator."
  @impl Sigil.WalrusClient
  @spec read_blob(String.t(), keyword()) :: Sigil.WalrusClient.read_result()
  def read_blob(blob_id, opts \\ []) when is_binary(blob_id) and is_list(opts) do
    opts
    |> aggregator_request_options("/v1/blobs/" <> blob_id)
    |> Req.get()
    |> read_response()
  end

  @doc "Checks whether a Walrus blob is available from the aggregator."
  @impl Sigil.WalrusClient
  @spec blob_exists?(String.t(), keyword()) :: boolean()
  def blob_exists?(blob_id, opts \\ []) when is_binary(blob_id) and is_list(opts) do
    opts
    |> aggregator_request_options("/v1/blobs/" <> blob_id)
    |> Keyword.put(:method, :head)
    |> Req.request()
    |> exists_response()
  end

  @spec publisher_request_options(keyword(), String.t(), keyword()) :: keyword()
  defp publisher_request_options(opts, path, request_opts) do
    Keyword.merge(Keyword.get(opts, :req_options, []),
      base_url: Keyword.get(opts, :publisher_url, @default_publisher_url),
      url: path,
      receive_timeout: @default_receive_timeout,
      retry: false
    )
    |> Keyword.merge(request_opts)
  end

  @spec aggregator_request_options(keyword(), String.t()) :: keyword()
  defp aggregator_request_options(opts, path) do
    Keyword.merge(Keyword.get(opts, :req_options, []),
      base_url: Keyword.get(opts, :aggregator_url, @default_aggregator_url),
      url: path,
      receive_timeout: @default_receive_timeout,
      retry: false
    )
  end

  @spec store_response({:ok, Req.Response.t()} | {:error, term()}) ::
          Sigil.WalrusClient.store_result()
  defp store_response({:ok, %Req.Response{status: status, body: body}}) when status in 200..299 do
    case extract_blob_id(body) do
      blob_id when is_binary(blob_id) and blob_id != "" -> {:ok, %{blob_id: blob_id}}
      _other -> {:error, :invalid_response}
    end
  end

  defp store_response({:ok, %Req.Response{status: 429}}), do: {:error, :rate_limited}
  defp store_response({:ok, %Req.Response{status: status}}), do: {:error, {:http_error, status}}
  defp store_response({:error, %Req.TransportError{reason: reason}}), do: {:error, reason}
  defp store_response({:error, reason}), do: {:error, reason}

  @spec read_response({:ok, Req.Response.t()} | {:error, term()}) ::
          Sigil.WalrusClient.read_result()
  defp read_response({:ok, %Req.Response{status: 200, body: body}}) when is_binary(body),
    do: {:ok, body}

  defp read_response({:ok, %Req.Response{status: 404}}), do: {:error, :not_found}
  defp read_response({:ok, %Req.Response{status: status}}), do: {:error, {:http_error, status}}
  defp read_response({:error, %Req.TransportError{reason: reason}}), do: {:error, reason}
  defp read_response({:error, reason}), do: {:error, reason}

  @spec exists_response({:ok, Req.Response.t()} | {:error, term()}) :: boolean()
  defp exists_response({:ok, %Req.Response{status: status}}) when status in 200..299, do: true
  defp exists_response({:ok, %Req.Response{status: _status}}), do: false
  defp exists_response({:error, _reason}), do: false

  @spec extract_blob_id(term()) :: String.t() | nil
  defp extract_blob_id(body) when is_map(body) do
    get_in(body, ["newlyCreated", "blobObject", "blobId"]) ||
      get_in(body, ["alreadyCertified", "blobId"])
  end

  defp extract_blob_id(_body), do: nil
end
