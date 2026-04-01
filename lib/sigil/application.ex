defmodule Sigil.Application do
  @moduledoc """
  OTP Application for Sigil.

  Starts shared infrastructure (Telemetry, Repo, PubSub, StaticData, Endpoint)
  plus world-scoped workers for cache-backed chain state and event processing.
  """

  use Application

  alias Sigil.Cache
  alias Sigil.Sui.GrpcStream.Codec
  alias Sigil.Worlds

  @cache_tables [
    :assemblies,
    :characters,
    :standings,
    :accounts,
    :tribes,
    :nonces,
    :gate_network,
    :intel,
    :intel_market,
    :reputation
  ]

  @default_monitor_registries %{
    "stillness" => Sigil.GameState.MonitorRegistry.Stillness,
    "utopia" => Sigil.GameState.MonitorRegistry.Utopia,
    "internal" => Sigil.GameState.MonitorRegistry.Internal,
    "localnet" => Sigil.GameState.MonitorRegistry.Localnet,
    "test" => Sigil.GameState.MonitorRegistry.Test
  }

  @doc false
  @impl true
  @spec start(Application.start_type(), term()) :: {:ok, pid()} | {:error, term()}
  def start(_type, _args) do
    worlds = Worlds.active_worlds()
    multi_world? = length(worlds) > 1

    children =
      [
        SigilWeb.Telemetry
      ] ++
        maybe_repo() ++
        [
          {Phoenix.PubSub, name: Sigil.PubSub}
        ] ++
        cache_children(worlds, multi_world?) ++
        maybe_static_data() ++
        maybe_gate_indexer(worlds, multi_world?) ++
        maybe_monitor_supervisor(worlds, multi_world?) ++
        maybe_alert_engine(worlds, multi_world?) ++
        maybe_grpc_stream(worlds, multi_world?) ++
        maybe_assembly_event_router(worlds, multi_world?) ++
        maybe_reputation_engine(worlds, multi_world?) ++ [SigilWeb.Endpoint]

    maybe_migrate()

    opts = [strategy: :one_for_one, name: Sigil.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @doc """
  Callback invoked when the endpoint configuration changes at runtime.
  """
  @impl true
  @spec config_change(keyword(), keyword(), [atom()]) :: :ok
  def config_change(changed, _new, removed) do
    SigilWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  @spec maybe_migrate() :: :ok
  defp maybe_migrate do
    if Application.get_env(:sigil, :auto_migrate, false) do
      Sigil.Release.migrate()
    else
      :ok
    end
  end

  @spec maybe_repo() :: [module()]
  defp maybe_repo do
    if Application.get_env(:sigil, :start_repo, true) do
      [Sigil.Repo]
    else
      []
    end
  end

  @spec cache_children([Worlds.world_name()], boolean()) :: [Supervisor.child_spec()]
  defp cache_children(worlds, multi_world?) do
    Enum.map(worlds, fn world ->
      Supervisor.child_spec(
        {Sigil.Cache, tables: @cache_tables},
        id: world_child_id(Sigil.Cache, world, multi_world?)
      )
    end)
  end

  @spec maybe_static_data() :: [Supervisor.child_spec()]
  defp maybe_static_data do
    if Application.get_env(:sigil, :start_static_data, true) do
      [
        Supervisor.child_spec(
          {Sigil.StaticData, dets_dir: static_data_dir()},
          id: Sigil.StaticData
        )
      ]
    else
      []
    end
  end

  @spec maybe_gate_indexer([Worlds.world_name()], boolean()) :: [Supervisor.child_spec()]
  defp maybe_gate_indexer(worlds, multi_world?) do
    if Application.get_env(:sigil, :start_gate_indexer, true) do
      Enum.map(worlds, fn world ->
        Supervisor.child_spec(
          {Sigil.GateIndexer,
           [
             world: world,
             resolve_tables: world_cache_tables_resolver(world, multi_world?)
           ]},
          id: world_child_id(Sigil.GateIndexer, world, multi_world?)
        )
      end)
    else
      []
    end
  end

  @spec maybe_monitor_supervisor([Worlds.world_name()], boolean()) :: [Supervisor.child_spec()]
  defp maybe_monitor_supervisor(worlds, multi_world?) do
    if Application.get_env(:sigil, :start_monitor_supervisor, true) do
      Enum.flat_map(worlds, fn world ->
        monitor_registry = monitor_registry(world, multi_world?)

        [
          Supervisor.child_spec(
            {Registry, keys: :unique, name: monitor_registry},
            id: monitor_registry_child_id(world, monitor_registry, multi_world?)
          ),
          Supervisor.child_spec(
            {Sigil.GameState.MonitorSupervisor, registry: monitor_registry, world: world},
            id: world_child_id(Sigil.GameState.MonitorSupervisor, world, multi_world?)
          )
        ]
      end)
    else
      []
    end
  end

  @spec maybe_alert_engine([Worlds.world_name()], boolean()) :: [Supervisor.child_spec()]
  defp maybe_alert_engine(worlds, multi_world?) do
    if Application.get_env(:sigil, :start_alert_engine, true) do
      monitor_enabled? = Application.get_env(:sigil, :start_monitor_supervisor, true)

      Enum.map(worlds, fn world ->
        monitor_registry = monitor_registry(world, multi_world?)

        opts =
          [
            world: world,
            resolve_tables: world_alert_tables_resolver(world, multi_world?)
          ] ++
            if monitor_enabled? do
              [
                registry: monitor_registry,
                resolve_registry: fn -> monitor_registry end
              ]
            else
              []
            end

        Supervisor.child_spec(
          {Sigil.Alerts.Engine, opts},
          id: world_child_id(Sigil.Alerts.Engine, world, multi_world?)
        )
      end)
    else
      []
    end
  end

  @spec maybe_grpc_stream([Worlds.world_name()], boolean()) :: [Supervisor.child_spec()]
  defp maybe_grpc_stream(worlds, multi_world?) do
    if Application.get_env(:sigil, :start_grpc_stream, false) do
      streams =
        Enum.map(worlds, fn world ->
          opts =
            if multi_world? do
              [
                world: world,
                stream_id: "grpc_main:#{world}",
                event_filter_fun: world_event_filter(world)
              ]
            else
              []
            end

          Supervisor.child_spec(
            {Sigil.Sui.GrpcStream, opts},
            id: world_child_id(Sigil.Sui.GrpcStream, world, multi_world?)
          )
        end)

      [Supervisor.child_spec({GRPC.Client.Supervisor, []}, id: GRPC.Client.Supervisor) | streams]
    else
      []
    end
  end

  @spec maybe_assembly_event_router([Worlds.world_name()], boolean()) :: [Supervisor.child_spec()]
  defp maybe_assembly_event_router(worlds, multi_world?) do
    start_router = Application.get_env(:sigil, :start_assembly_event_router, false)
    start_monitor_supervisor = Application.get_env(:sigil, :start_monitor_supervisor, true)

    if start_router and start_monitor_supervisor do
      Enum.map(worlds, fn world ->
        monitor_registry = monitor_registry(world, multi_world?)

        Supervisor.child_spec(
          {Sigil.GameState.AssemblyEventRouter, registry: monitor_registry, world: world},
          id: world_child_id(Sigil.GameState.AssemblyEventRouter, world, multi_world?)
        )
      end)
    else
      []
    end
  end

  @spec maybe_reputation_engine([Worlds.world_name()], boolean()) :: [Supervisor.child_spec()]
  defp maybe_reputation_engine(worlds, multi_world?) do
    if Application.get_env(:sigil, :start_reputation_engine, false) do
      Enum.map(worlds, fn world ->
        Supervisor.child_spec(
          {Sigil.Reputation.Engine,
           [
             world: world,
             resolve_tables: world_cache_tables_resolver(world, multi_world?)
           ]},
          id: world_child_id(Sigil.Reputation.Engine, world, multi_world?)
        )
      end)
    else
      []
    end
  end

  @spec world_child_id(module(), Worlds.world_name(), boolean()) :: term()
  defp world_child_id(module, _world, false), do: module
  defp world_child_id(module, world, true), do: {module, world}

  @spec monitor_registry_child_id(Worlds.world_name(), atom(), boolean()) :: term()
  defp monitor_registry_child_id(_world, monitor_registry, false), do: monitor_registry

  defp monitor_registry_child_id(world, monitor_registry, true),
    do: {:monitor_registry, world, monitor_registry}

  @spec monitor_registry(Worlds.world_name(), boolean()) :: atom()
  defp monitor_registry(_world, false), do: monitor_registry_base()

  defp monitor_registry(world, true) do
    case monitor_registries() do
      %{^world => registry} when is_atom(registry) ->
        registry

      _other ->
        raise ArgumentError,
              "missing :monitor_registries atom entry for world #{inspect(world)}"
    end
  end

  @spec monitor_registry_base() :: atom()
  defp monitor_registry_base do
    case Application.get_env(:sigil, :monitor_registry) do
      registry when is_atom(registry) and not is_nil(registry) ->
        registry

      _other ->
        Sigil.GameState.MonitorRegistry
    end
  end

  @spec monitor_registries() :: %{optional(Worlds.world_name()) => atom()}
  defp monitor_registries do
    configured =
      case Application.get_env(:sigil, :monitor_registries, %{}) do
        registries when is_map(registries) -> registries
        _other -> %{}
      end

    Map.merge(@default_monitor_registries, configured)
  end

  @spec world_cache_tables_resolver(Worlds.world_name(), boolean()) :: (-> map() | nil)
  defp world_cache_tables_resolver(world, multi_world?) do
    fn -> resolve_cache_tables(world, multi_world?) end
  end

  @spec world_alert_tables_resolver(Worlds.world_name(), boolean()) ::
          (-> %{assemblies: Cache.table_id(), accounts: Cache.table_id()} | nil)
  defp world_alert_tables_resolver(world, multi_world?) do
    fn ->
      case resolve_cache_tables(world, multi_world?) do
        %{assemblies: _assemblies, accounts: _accounts} = tables -> tables
        _other -> nil
      end
    end
  end

  @spec resolve_cache_tables(Worlds.world_name(), boolean()) :: map() | nil
  defp resolve_cache_tables(world, multi_world?) do
    case Process.whereis(Sigil.Supervisor) do
      pid when is_pid(pid) ->
        children = Supervisor.which_children(pid)

        find_world_cache_tables(children, world) ||
          if(multi_world?, do: nil, else: find_single_world_cache_tables(children))

      _other ->
        nil
    end
  end

  @spec find_world_cache_tables([Supervisor.child_spec()], Worlds.world_name()) :: map() | nil
  defp find_world_cache_tables(children, world) do
    Enum.find_value(children, fn
      {{Sigil.Cache, ^world}, cache_pid, _kind, _modules} when is_pid(cache_pid) ->
        Cache.tables(cache_pid)

      _other ->
        nil
    end)
  end

  @spec find_single_world_cache_tables([Supervisor.child_spec()]) :: map() | nil
  defp find_single_world_cache_tables(children) do
    Enum.find_value(children, fn
      {Sigil.Cache, cache_pid, _kind, _modules} when is_pid(cache_pid) ->
        Cache.tables(cache_pid)

      _other ->
        nil
    end)
  end

  @spec world_event_filter(Worlds.world_name()) :: (map() -> boolean())
  defp world_event_filter(world) do
    world_prefix = Worlds.package_id(world) <> "::"

    fn
      %{"type" => %{"repr" => type}} = event when is_binary(type) ->
        String.starts_with?(type, world_prefix) and Codec.default_event_filter(event)

      _other ->
        false
    end
  end

  @spec static_data_dir() :: String.t()
  defp static_data_dir do
    Application.get_env(
      :sigil,
      :static_data_dir,
      Application.app_dir(:sigil, "priv/static_data")
    )
  end
end
