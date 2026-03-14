defmodule FrontierOS.StaticData.WorldClient.HTTP do
  @moduledoc """
  Req-backed World API client with pagination support.
  """

  @behaviour FrontierOS.StaticData.WorldClient

  alias FrontierOS.StaticData.WorldClient

  @default_base_url "https://world-api-stillness.live.tech.evefrontier.com"
  @page_size 1_000
  @default_retry_delay 1_000
  @default_max_retries 3

  @doc "Fetches every item type record across all pages."
  @impl WorldClient
  @spec fetch_types(WorldClient.request_opts()) ::
          {:ok, [WorldClient.record()]} | {:error, WorldClient.error_reason()}
  def fetch_types(opts \\ []), do: fetch_paginated("/v2/types", opts)

  @doc "Fetches every solar system record across all pages."
  @impl WorldClient
  @spec fetch_solar_systems(WorldClient.request_opts()) ::
          {:ok, [WorldClient.record()]} | {:error, WorldClient.error_reason()}
  def fetch_solar_systems(opts \\ []), do: fetch_paginated("/v2/solarsystems", opts)

  @doc "Fetches every constellation record across all pages."
  @impl WorldClient
  @spec fetch_constellations(WorldClient.request_opts()) ::
          {:ok, [WorldClient.record()]} | {:error, WorldClient.error_reason()}
  def fetch_constellations(opts \\ []), do: fetch_paginated("/v2/constellations", opts)

  @spec fetch_paginated(String.t(), WorldClient.request_opts()) ::
          {:ok, [WorldClient.record()]} | {:error, WorldClient.error_reason()}
  defp fetch_paginated(path, opts) do
    with {:ok, first_page, total} <- fetch_page(path, 0, opts) do
      total
      |> page_offsets()
      |> Enum.reduce_while({:ok, first_page}, fn offset, {:ok, records} ->
        case fetch_page(path, offset, opts) do
          {:ok, page_records, _page_total} -> {:cont, {:ok, records ++ page_records}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
    end
  end

  @spec fetch_page(String.t(), non_neg_integer(), WorldClient.request_opts()) ::
          {:ok, [WorldClient.record()], non_neg_integer()} | {:error, WorldClient.error_reason()}
  defp fetch_page(path, offset, opts) do
    request_options = request_options(path, offset, opts)

    case Req.get(request_options) do
      {:ok,
       %Req.Response{status: 200, body: %{"data" => data, "metadata" => %{"total" => total}}}}
      when is_list(data) and is_integer(total) and total >= 0 ->
        {:ok, data, total}

      {:ok, %Req.Response{status: 200}} ->
        {:error, :invalid_response}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:http_error, status}}

      {:error, %Req.TransportError{reason: :timeout}} ->
        {:error, :timeout}

      {:error, _exception} ->
        {:error, :invalid_response}
    end
  end

  @spec request_options(String.t(), non_neg_integer(), WorldClient.request_opts()) :: keyword()
  defp request_options(path, offset, opts) do
    opts
    |> Keyword.get(:req_options, [])
    |> Keyword.merge(
      base_url: Keyword.get(opts, :base_url, @default_base_url),
      url: path,
      params: [limit: @page_size, offset: offset],
      receive_timeout: 30_000,
      retry: :transient,
      retry_delay: Keyword.get(opts, :retry_delay, retry_delay()),
      max_retries: Keyword.get(opts, :max_retries, max_retries()),
      retry_log_level: false
    )
  end

  @spec retry_delay() :: non_neg_integer()
  defp retry_delay do
    Application.get_env(:frontier_os, :world_client_retry_delay, @default_retry_delay)
  end

  @spec max_retries() :: non_neg_integer()
  defp max_retries do
    Application.get_env(:frontier_os, :world_client_max_retries, @default_max_retries)
  end

  @spec page_offsets(non_neg_integer()) :: [non_neg_integer()]
  defp page_offsets(total) when total <= @page_size, do: []

  defp page_offsets(total) do
    for page_index <- 1..div(total - 1, @page_size), do: page_index * @page_size
  end
end
