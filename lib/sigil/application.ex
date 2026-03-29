defmodule Sigil.Application do
  @moduledoc """
  OTP Application for Sigil.

  Starts the supervision tree with Telemetry, Repo, PubSub, Cache, optional
  StaticData, optional GateIndexer, optional MonitorRegistry + MonitorSupervisor,
  optional AlertEngine, optional GrpcStream, optional AssemblyEventRouter,
  and Endpoint.
  """

  use Application

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

  @doc false
  @impl true
  @spec start(Application.start_type(), term()) :: {:ok, pid()} | {:error, term()}
  def start(_type, _args) do
    children =
      [
        SigilWeb.Telemetry
      ] ++
        maybe_repo() ++
        [
          {Phoenix.PubSub, name: Sigil.PubSub},
          cache_child()
        ] ++
        maybe_static_data() ++
        maybe_gate_indexer() ++
        maybe_monitor_supervisor() ++
        maybe_alert_engine() ++
        maybe_grpc_stream() ++
        maybe_assembly_event_router() ++
        maybe_reputation_engine() ++ [SigilWeb.Endpoint]

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

  @spec cache_child() :: Supervisor.child_spec()
  defp cache_child do
    Supervisor.child_spec({Sigil.Cache, tables: @cache_tables}, id: Sigil.Cache)
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

  @spec maybe_gate_indexer() :: [Supervisor.child_spec()]
  defp maybe_gate_indexer do
    if Application.get_env(:sigil, :start_gate_indexer, true) do
      [Supervisor.child_spec({Sigil.GateIndexer, []}, id: Sigil.GateIndexer)]
    else
      []
    end
  end

  @spec maybe_monitor_supervisor() :: [Supervisor.child_spec()]
  defp maybe_monitor_supervisor do
    if Application.get_env(:sigil, :start_monitor_supervisor, true) do
      registry = Application.fetch_env!(:sigil, :monitor_registry)

      [
        Supervisor.child_spec({Registry, keys: :unique, name: registry}, id: registry),
        Supervisor.child_spec(
          {Sigil.GameState.MonitorSupervisor, registry: registry},
          id: Sigil.GameState.MonitorSupervisor
        )
      ]
    else
      []
    end
  end

  @spec maybe_alert_engine() :: [Supervisor.child_spec()]
  defp maybe_alert_engine do
    if Application.get_env(:sigil, :start_alert_engine, true) do
      [Supervisor.child_spec({Sigil.Alerts.Engine, []}, id: Sigil.Alerts.Engine)]
    else
      []
    end
  end

  @spec maybe_grpc_stream() :: [Supervisor.child_spec()]
  defp maybe_grpc_stream do
    if Application.get_env(:sigil, :start_grpc_stream, false) do
      [
        Supervisor.child_spec({GRPC.Client.Supervisor, []}, id: GRPC.Client.Supervisor),
        Supervisor.child_spec({Sigil.Sui.GrpcStream, []}, id: Sigil.Sui.GrpcStream)
      ]
    else
      []
    end
  end

  @spec maybe_assembly_event_router() :: [Supervisor.child_spec()]
  defp maybe_assembly_event_router do
    start_router = Application.get_env(:sigil, :start_assembly_event_router, false)
    start_monitor_supervisor = Application.get_env(:sigil, :start_monitor_supervisor, true)

    if start_router and start_monitor_supervisor do
      registry = Application.fetch_env!(:sigil, :monitor_registry)

      [
        Supervisor.child_spec(
          {Sigil.GameState.AssemblyEventRouter, registry: registry},
          id: Sigil.GameState.AssemblyEventRouter
        )
      ]
    else
      []
    end
  end

  @spec maybe_reputation_engine() :: [Supervisor.child_spec()]
  defp maybe_reputation_engine do
    if Application.get_env(:sigil, :start_reputation_engine, false) do
      [Supervisor.child_spec({Sigil.Reputation.Engine, []}, id: Sigil.Reputation.Engine)]
    else
      []
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
