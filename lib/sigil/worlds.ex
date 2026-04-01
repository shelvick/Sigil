defmodule Sigil.Worlds do
  @moduledoc """
  Resolves per-world configuration for EVE Frontier environments.

  This module centralizes lookups for world-scoped values such as package IDs,
  RPC URLs, and topic names.
  """

  @typedoc "Configured world name (for example: \"utopia\" or \"stillness\")."
  @type world_name() :: String.t()

  @typedoc "World configuration map from `:eve_worlds`."
  @type world_config() :: map()

  @doc "Returns the configured default world."
  @spec default_world() :: world_name()
  def default_world do
    Application.fetch_env!(:sigil, :eve_world)
  end

  @doc "Returns the list of active worlds, defaulting to the configured default world."
  @spec active_worlds() :: [world_name()]
  def active_worlds do
    case Application.get_env(:sigil, :active_worlds, [default_world()]) do
      worlds when is_list(worlds) ->
        worlds
        |> Enum.filter(&is_binary/1)
        |> Enum.uniq()
        |> case do
          [] -> [default_world()]
          filtered -> filtered
        end

      _other ->
        [default_world()]
    end
  end

  @doc "Fetches world config for the given world name or raises if missing."
  @spec get!(world_name()) :: world_config()
  def get!(world_name) when is_binary(world_name) do
    worlds = Application.fetch_env!(:sigil, :eve_worlds)
    Map.fetch!(worlds, world_name)
  end

  @doc "Returns the world package ID for the given world."
  @spec package_id(world_name()) :: String.t()
  def package_id(world_name) when is_binary(world_name) do
    %{package_id: package_id} = get!(world_name)
    package_id
  end

  @doc "Returns the Sigil package ID for the given world."
  @spec sigil_package_id(world_name()) :: String.t()
  def sigil_package_id(world_name) when is_binary(world_name) do
    %{sigil_package_id: package_id} = get!(world_name)
    package_id
  end

  @doc "Returns the GraphQL URL for the given world."
  @spec graphql_url(world_name()) :: String.t()
  def graphql_url(world_name) when is_binary(world_name) do
    %{graphql_url: graphql_url} = get!(world_name)
    graphql_url
  end

  @doc "Returns the RPC URL for the given world."
  @spec rpc_url(world_name()) :: String.t()
  def rpc_url(world_name) when is_binary(world_name) do
    %{rpc_url: rpc_url} = get!(world_name)
    rpc_url
  end

  @doc "Returns the World API URL for the given world, when configured."
  @spec world_api_url(world_name()) :: String.t() | nil
  def world_api_url(world_name) when is_binary(world_name) do
    get!(world_name)
    |> Map.get(:world_api_url)
  end

  @doc "Returns the reputation registry object ID for the given world, when configured."
  @spec reputation_registry_id(world_name()) :: String.t() | nil
  def reputation_registry_id(world_name) when is_binary(world_name) do
    get!(world_name)
    |> Map.get(:reputation_registry_id)
  end

  @doc "Builds a world-scoped PubSub topic name."
  @spec topic(world_name(), String.t()) :: String.t()
  def topic(world_name, base_topic) when is_binary(world_name) and is_binary(base_topic) do
    "#{world_name}:#{base_topic}"
  end
end
