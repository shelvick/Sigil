defmodule FrontierOS.Assemblies do
  @moduledoc """
  Assembly discovery and cache access backed by ETS.
  """

  alias FrontierOS.Cache
  alias FrontierOS.Sui.Client
  alias FrontierOS.Sui.Types.{Assembly, Gate, NetworkNode, StorageUnit, Turret}

  @sui_client Application.compile_env!(:frontier_os, :sui_client)

  @typedoc "ETS tables required by the assemblies context."
  @type tables() :: %{assemblies: Cache.table_id()}

  @typedoc "Parsed assembly types cached by the context."
  @type assembly() :: Assembly.t() | Gate.t() | NetworkNode.t() | StorageUnit.t() | Turret.t()

  @typedoc "Options accepted by the assemblies context functions."
  @type option() ::
          {:tables, tables()}
          | {:pubsub, atom() | module()}
          | {:req_options, Client.request_opts()}

  @type options() :: [option()]

  @doc "Discovers assemblies owned by a wallet, caches them, and broadcasts the result."
  @spec discover_for_owner(String.t(), options()) ::
          {:ok, [assembly()]} | {:error, Client.error_reason()}
  def discover_for_owner(owner, opts) when is_binary(owner) and is_list(opts) do
    req_options = Keyword.get(opts, :req_options, [])

    with {:ok, %{data: owner_caps}} <-
           @sui_client.get_objects([type: owner_cap_type_string(), owner: owner], req_options) do
      assemblies =
        owner_caps
        |> Enum.map(&Map.fetch!(&1, "authorized_object_id"))
        |> Enum.reduce([], fn assembly_id, acc ->
          case fetch_assembly(assembly_id, req_options) do
            {:ok, assembly} ->
              cache_assembly(opts, owner, assembly)
              [assembly | acc]

            :skip ->
              acc

            {:error, _reason} ->
              acc
          end
        end)
        |> Enum.reverse()

      broadcast(
        Keyword.get(opts, :pubsub, FrontierOS.PubSub),
        owner_topic(owner),
        {:assemblies_discovered, assemblies}
      )

      {:ok, assemblies}
    end
  end

  @doc "Returns cached assemblies for a single owner."
  @spec list_for_owner(String.t(), options()) :: [assembly()]
  def list_for_owner(owner, opts) when is_binary(owner) and is_list(opts) do
    opts
    |> assembly_table()
    |> Cache.match({:_, {owner, :_}})
    |> Enum.map(fn {_assembly_id, {^owner, assembly}} -> assembly end)
  end

  @doc "Returns a cached assembly by id."
  @spec get_assembly(String.t(), options()) :: {:ok, assembly()} | {:error, :not_found}
  def get_assembly(assembly_id, opts) when is_binary(assembly_id) and is_list(opts) do
    table = assembly_table(opts)

    case Cache.get(table, assembly_id) do
      {_owner, assembly} -> {:ok, assembly}
      nil -> {:error, :not_found}
    end
  end

  @doc "Refreshes a cached assembly from chain and broadcasts the updated value."
  @spec sync_assembly(String.t(), options()) ::
          {:ok, assembly()} | {:error, :not_found | Client.error_reason()}
  def sync_assembly(assembly_id, opts) when is_binary(assembly_id) and is_list(opts) do
    req_options = Keyword.get(opts, :req_options, [])

    table = assembly_table(opts)

    case Cache.get(table, assembly_id) do
      {owner, _cached_assembly} ->
        case fetch_assembly(assembly_id, req_options) do
          {:ok, assembly} ->
            cache_assembly(opts, owner, assembly)

            broadcast(
              Keyword.get(opts, :pubsub, FrontierOS.PubSub),
              assembly_topic(assembly_id),
              {:assembly_updated, assembly}
            )

            {:ok, assembly}

          :skip ->
            Cache.delete(table, assembly_id)
            {:error, :not_found}

          {:error, _reason} = error ->
            error
        end

      nil ->
        {:error, :not_found}
    end
  end

  @spec fetch_assembly(String.t(), Client.request_opts()) ::
          {:ok, assembly()} | :skip | {:error, Client.error_reason()}
  defp fetch_assembly(assembly_id, req_options) do
    with {:ok, json} <- @sui_client.get_object(assembly_id, req_options) do
      parse_assembly(json)
    end
  end

  @spec parse_assembly(map()) :: {:ok, assembly()} | :skip
  defp parse_assembly(%{"character_address" => _} = _json), do: :skip

  defp parse_assembly(%{"linked_gate_id" => _value} = json), do: {:ok, Gate.from_json(json)}

  defp parse_assembly(%{"fuel" => _fuel, "energy_source" => _energy_source} = json),
    do: {:ok, NetworkNode.from_json(json)}

  defp parse_assembly(%{"inventory_keys" => _inventory_keys} = json),
    do: {:ok, StorageUnit.from_json(json)}

  defp parse_assembly(%{"extension" => _extension} = json), do: {:ok, Turret.from_json(json)}
  defp parse_assembly(%{"type_id" => _} = json), do: {:ok, Assembly.from_json(json)}
  defp parse_assembly(_json), do: :skip

  @spec cache_assembly(options(), String.t(), assembly()) :: :ok
  defp cache_assembly(opts, owner, assembly) do
    Cache.put(assembly_table(opts), assembly.id, {owner, assembly})
  end

  @spec assembly_table(options()) :: Cache.table_id()
  defp assembly_table(opts) do
    opts |> Keyword.fetch!(:tables) |> Map.fetch!(:assemblies)
  end

  @spec broadcast(atom() | module(), String.t(), term()) :: :ok | {:error, term()}
  defp broadcast(pubsub, topic, event) do
    Phoenix.PubSub.broadcast(pubsub, topic, event)
  end

  @spec owner_cap_type_string() :: String.t()
  defp owner_cap_type_string do
    "#{world_package_id()}::access::OwnerCap"
  end

  @spec world_package_id() :: String.t()
  defp world_package_id do
    world = Application.fetch_env!(:frontier_os, :eve_world)
    worlds = Application.fetch_env!(:frontier_os, :eve_worlds)
    Map.fetch!(worlds, world)
  end

  @spec owner_topic(String.t()) :: String.t()
  defp owner_topic(owner), do: "assemblies:#{owner}"

  @spec assembly_topic(String.t()) :: String.t()
  defp assembly_topic(assembly_id), do: "assembly:#{assembly_id}"
end
