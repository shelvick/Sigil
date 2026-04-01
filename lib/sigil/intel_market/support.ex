defmodule Sigil.IntelMarket.Support do
  @moduledoc """
  Shared cache, pagination, and parsing helpers for intel marketplace modules.
  """

  alias Sigil.Cache
  alias Sigil.IntelMarket
  alias Sigil.Intel.IntelListing
  alias Sigil.Sui.Client
  alias Sigil.Worlds

  @doc "Returns the intel marketplace ETS table from context options."
  @spec market_table(IntelMarket.options()) :: Cache.table_id()
  def market_table(opts) do
    opts |> Keyword.fetch!(:tables) |> Map.fetch!(:intel_market)
  end

  @doc "Broadcasts a marketplace event on the configured PubSub instance."
  @spec broadcast(IntelMarket.options(), term()) :: :ok | {:error, term()}
  def broadcast(opts, event) do
    pubsub = Keyword.get(opts, :pubsub, Sigil.PubSub)
    Phoenix.PubSub.broadcast(pubsub, IntelMarket.topic(opts), event)
  end

  @doc "Lists all matching chain objects across paginated Sui responses."
  @spec list_objects(module(), Client.object_filter(), Client.request_opts()) ::
          {:ok, [Client.object_map()]} | {:error, Client.error_reason()}
  def list_objects(client, filters, req_options) do
    list_objects(client, filters, req_options, [])
  end

  @doc "Parses a required integer field with a default fallback for nil values."
  @spec parse_integer(String.t() | integer() | nil, integer()) :: integer()
  def parse_integer(nil, default), do: default
  def parse_integer(value, _default) when is_integer(value), do: value
  def parse_integer(value, _default) when is_binary(value), do: String.to_integer(value)

  @doc "Parses a required integer field with zero as the default."
  @spec parse_integer(String.t() | integer()) :: integer()
  def parse_integer(value), do: parse_integer(value, 0)

  @doc "Parses an optional integer field while preserving nil values."
  @spec parse_optional_integer(String.t() | integer() | nil) :: integer() | nil
  def parse_optional_integer(nil), do: nil
  def parse_optional_integer(value), do: parse_integer(value)

  @doc "Normalizes the on-chain listing status enum into the local Ecto enum."
  @spec parse_listing_status(String.t() | integer() | nil) :: IntelListing.listing_status()
  def parse_listing_status(nil), do: :active
  def parse_listing_status("0"), do: :active
  def parse_listing_status(0), do: :active
  def parse_listing_status("1"), do: :sold
  def parse_listing_status(1), do: :sold
  def parse_listing_status("2"), do: :cancelled
  def parse_listing_status(2), do: :cancelled

  @doc "Returns the fully qualified Sui type for the marketplace singleton."
  @spec marketplace_type(IntelMarket.options()) :: String.t()
  def marketplace_type(opts \\ []) when is_list(opts) do
    "#{sigil_package_id(opts)}::intel_market::IntelMarketplace"
  end

  @doc "Returns the fully qualified Sui type for marketplace listings."
  @spec listing_type(IntelMarket.options()) :: String.t()
  def listing_type(opts \\ []) when is_list(opts) do
    "#{sigil_package_id(opts)}::intel_market::IntelListing"
  end

  defp list_objects(client, filters, req_options, acc) do
    with {:ok, %{data: data, has_next_page: has_next_page, end_cursor: end_cursor}} <-
           client.get_objects(filters, req_options) do
      all_objects = acc ++ data
      next_object_page(client, filters, req_options, all_objects, has_next_page, end_cursor)
    end
  end

  defp next_object_page(client, filters, req_options, all_objects, true, end_cursor)
       when is_binary(end_cursor) do
    list_objects(client, Keyword.put(filters, :cursor, end_cursor), req_options, all_objects)
  end

  defp next_object_page(_client, _filters, _req_options, _all_objects, true, _end_cursor) do
    {:error, :invalid_response}
  end

  defp next_object_page(_client, _filters, _req_options, all_objects, false, _end_cursor) do
    {:ok, all_objects}
  end

  @spec sigil_package_id(IntelMarket.options()) :: String.t()
  defp sigil_package_id(opts) when is_list(opts) do
    Keyword.get_lazy(opts, :sigil_package_id, fn ->
      opts
      |> Keyword.get(:world, Worlds.default_world())
      |> Worlds.sigil_package_id()
    end)
  end
end
