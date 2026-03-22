defmodule Sigil.Application do
  @moduledoc """
  OTP Application for Sigil.

  Starts the supervision tree with Telemetry, Repo, PubSub, Cache, optional
  StaticData, optional GateIndexer, optional MonitorRegistry + MonitorSupervisor,
  optional AlertEngine, and Endpoint.
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
    :intel
  ]

  @doc false
  @impl true
  @spec start(Application.start_type(), term()) :: {:ok, pid()} | {:error, term()}
  def start(_type, _args) do
    children =
      [
        SigilWeb.Telemetry,
        Sigil.Repo,
        {Phoenix.PubSub, name: Sigil.PubSub},
        cache_child()
      ] ++
        maybe_static_data() ++
        maybe_gate_indexer() ++
        maybe_monitor_supervisor() ++ maybe_alert_engine() ++ [SigilWeb.Endpoint]

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

  @spec static_data_dir() :: String.t()
  defp static_data_dir do
    Application.get_env(
      :sigil,
      :static_data_dir,
      Application.app_dir(:sigil, "priv/static_data")
    )
  end
end
