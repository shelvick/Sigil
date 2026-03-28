defmodule Sigil.Diplomacy.Discovery do
  @moduledoc """
  Discovery and lookup helpers for diplomacy cached state.
  """

  alias Sigil.Cache
  alias Sigil.Diplomacy.ObjectCodec
  alias Sigil.Sui.Client

  @sui_client Application.compile_env!(:sigil, :sui_client)

  @doc "Discovers the custodian for a tribe and updates cache and PubSub."
  @spec discover_custodian(non_neg_integer(), Sigil.Diplomacy.options()) ::
          {:ok, Sigil.Diplomacy.custodian_info() | nil} | {:error, Client.error_reason()}
  def discover_custodian(tribe_id, opts)
      when is_integer(tribe_id) and tribe_id >= 0 and is_list(opts) do
    client = Keyword.get(opts, :client, @sui_client)
    req_options = Keyword.get(opts, :req_options, [])

    with {:ok, %{data: objects}} <- client.get_objects([type: custodian_type()], req_options) do
      custodian =
        objects
        |> Enum.find(&(ObjectCodec.parse_tribe_id(&1) == tribe_id))
        |> ObjectCodec.to_custodian_info()

      if custodian do
        Sigil.Diplomacy.set_active_custodian(custodian, Keyword.put(opts, :tribe_id, tribe_id))
      end

      Phoenix.PubSub.broadcast(
        Keyword.get(opts, :pubsub, Sigil.PubSub),
        "diplomacy",
        {:custodian_discovered, custodian}
      )

      {:ok, custodian}
    end
  end

  @doc "Resolves a character shared-object reference from opts, cache, or chain."
  @spec resolve_character_ref(String.t(), Sigil.Diplomacy.options()) ::
          {:ok, Sigil.Diplomacy.character_ref()} | {:error, term()}
  def resolve_character_ref(character_id, opts) when is_binary(character_id) and is_list(opts) do
    table = standings_table(opts)

    cond do
      character_ref = Keyword.get(opts, :character_ref) ->
        {:ok, character_ref}

      cached_ref = Cache.get(table, {:character_ref, character_id}) ->
        {:ok, cached_ref}

      true ->
        client = Keyword.get(opts, :client, @sui_client)
        req_options = Keyword.get(opts, :req_options, [])

        with {:ok, %{json: object}} <- client.get_object_with_ref(character_id, req_options),
             version when is_integer(version) <- ObjectCodec.parse_shared_version(object) do
          character_ref = %{
            object_id: ObjectCodec.hex_to_bytes(character_id),
            initial_shared_version: version
          }

          Cache.put(table, {:character_ref, character_id}, character_ref)
          {:ok, character_ref}
        else
          nil -> {:error, :no_character_ref}
          {:error, _reason} = error -> error
        end
    end
  end

  @doc "Resolves the shared registry reference from opts, cache, or chain."
  @spec resolve_registry_ref(Sigil.Diplomacy.options()) ::
          {:ok, Sigil.Diplomacy.registry_ref()} | {:error, term()}
  def resolve_registry_ref(opts) when is_list(opts) do
    table = standings_table(opts)

    cond do
      registry_ref = Keyword.get(opts, :registry_ref) ->
        {:ok, registry_ref}

      cached_ref = Cache.get(table, {:registry_ref}) ->
        {:ok, cached_ref}

      true ->
        client = Keyword.get(opts, :client, @sui_client)
        req_options = Keyword.get(opts, :req_options, [])

        with {:ok, %{data: objects}} <- client.get_objects([type: registry_type()], req_options),
             {:ok, registry_ref} <- ObjectCodec.build_registry_ref(objects) do
          Cache.put(table, {:registry_ref}, registry_ref)
          {:ok, registry_ref}
        end
    end
  end

  @doc "Fetches tribe names from World API and stores them in cache."
  @spec resolve_tribe_names(Sigil.Diplomacy.options()) ::
          {:ok, [Sigil.Diplomacy.world_tribe()]} | {:error, term()}
  def resolve_tribe_names(opts) when is_list(opts) do
    req_options = Keyword.get(opts, :req_options, [])
    world_client = Application.fetch_env!(:sigil, :world_client)

    with {:ok, tribe_records} <- world_client.fetch_tribes(req_options) do
      tribes =
        Enum.map(tribe_records, fn record ->
          tribe = %{id: record["id"], name: record["name"], short_name: record["short_name"]}
          Cache.put(standings_table(opts), {:world_tribe, tribe.id}, tribe)
          tribe
        end)

      {:ok, tribes}
    end
  end

  @doc "Returns a cached tribe name entry or nil."
  @spec get_tribe_name(non_neg_integer(), Sigil.Diplomacy.options()) ::
          Sigil.Diplomacy.world_tribe() | nil
  def get_tribe_name(tribe_id, opts) when is_integer(tribe_id) and is_list(opts) do
    Cache.get(standings_table(opts), {:world_tribe, tribe_id})
  end

  @spec standings_table(Sigil.Diplomacy.options()) :: Cache.table_id()
  defp standings_table(opts), do: opts |> Keyword.fetch!(:tables) |> Map.fetch!(:standings)

  @spec custodian_type() :: String.t()
  defp custodian_type do
    "#{sigil_package_id()}::tribe_custodian::Custodian"
  end

  @spec registry_type() :: String.t()
  defp registry_type do
    "#{sigil_package_id()}::tribe_custodian::TribeCustodianRegistry"
  end

  @spec sigil_package_id() :: String.t()
  defp sigil_package_id do
    world = Application.fetch_env!(:sigil, :eve_world)
    worlds = Application.fetch_env!(:sigil, :eve_worlds)
    %{sigil_package_id: id} = Map.fetch!(worlds, world)
    id
  end
end
