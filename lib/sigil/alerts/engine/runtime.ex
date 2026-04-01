defmodule Sigil.Alerts.Engine.Runtime do
  @moduledoc """
  Runtime wiring helpers for alert-engine state and monitor subscriptions.
  """

  require Logger

  alias Ecto.Adapters.SQL.Sandbox
  alias Sigil.Cache
  alias Sigil.GameState.MonitorSupervisor
  alias Sigil.Worlds

  @doc "Builds initial runtime state from start options and defaults."
  @spec build_base_state(keyword(), map(), atom() | module(), module(), (map(), keyword() ->
                                                                           term())) ::
          map()
  def build_base_state(opts, defaults, default_pubsub, default_notifier, create_alert_fun) do
    %{
      pubsub: Keyword.get(opts, :pubsub, default_pubsub),
      world: Keyword.get(opts, :world, Worlds.default_world()),
      registry: Keyword.get(opts, :registry),
      resolve_registry: Keyword.get(opts, :resolve_registry, defaults.default_resolve_registry),
      tables: Keyword.get(opts, :tables),
      resolve_tables: Keyword.get(opts, :resolve_tables, defaults.default_resolve_tables),
      watched_ids: MapSet.new(),
      discovery_interval_ms:
        Keyword.get(opts, :discovery_interval_ms, defaults.default_discovery_interval_ms),
      purge_interval_ms:
        Keyword.get(opts, :purge_interval_ms, defaults.default_purge_interval_ms),
      purge_after_days: Keyword.get(opts, :purge_after_days, defaults.default_purge_after_days),
      cooldown_ms: Keyword.get(opts, :cooldown_ms, defaults.default_cooldown_ms),
      now_fun: Keyword.get(opts, :now_fun, &DateTime.utc_now/0),
      create_alert_fun: Keyword.get(opts, :create_alert_fun, create_alert_fun),
      get_webhook_config_fun:
        Keyword.get(opts, :get_webhook_config_fun, defaults.default_get_webhook_config_fun),
      notifier: Keyword.get(opts, :notifier, default_notifier),
      notifier_opts: Keyword.get(opts, :notifier_opts, []),
      dispatch_fun: nil,
      subscribe_fun:
        Keyword.get(opts, :subscribe_fun, fn assembly_id ->
          Phoenix.PubSub.subscribe(
            Keyword.get(opts, :pubsub, default_pubsub),
            assembly_topic(assembly_id)
          )
        end),
      owner_pid: Keyword.fetch!(opts, :owner_pid),
      sandbox_owner: Keyword.get(opts, :sandbox_owner),
      mox_owner: Keyword.get(opts, :mox_owner)
    }
  end

  @doc "Resolves the configured monitor registry name from runtime application env."
  @spec default_resolve_registry() :: atom() | nil
  def default_resolve_registry do
    case Application.get_env(:sigil, :monitor_registry) do
      registry when is_atom(registry) -> registry
      _other -> nil
    end
  end

  @doc "Resolves cache table ids from the application supervisor."
  @spec default_resolve_tables() ::
          %{assemblies: Cache.table_id(), accounts: Cache.table_id()} | nil
  def default_resolve_tables do
    case Process.whereis(Sigil.Supervisor) do
      pid when is_pid(pid) ->
        pid
        |> Supervisor.which_children()
        |> Enum.find_value(fn
          {Sigil.Cache, cache_pid, _kind, _modules} when is_pid(cache_pid) ->
            case Cache.tables(cache_pid) do
              %{assemblies: _assemblies, accounts: _accounts} = tables -> tables
              _other -> nil
            end

          _other ->
            nil
        end)

      _other ->
        nil
    end
  end

  @doc "Ensures registry in state is live or attempts to resolve it again."
  @spec maybe_resolve_registry(map()) :: map()
  def maybe_resolve_registry(%{registry: registry} = state)
      when is_atom(registry) and not is_nil(registry) do
    if Process.whereis(registry) do
      state
    else
      %{state | registry: nil}
    end
  end

  @doc false
  def maybe_resolve_registry(state) do
    case state.resolve_registry.() do
      registry when is_atom(registry) and not is_nil(registry) ->
        if Process.whereis(registry) do
          %{state | registry: registry}
        else
          %{state | registry: nil}
        end

      _other ->
        %{state | registry: nil}
    end
  end

  @doc "Ensures ETS tables in state are live or attempts to resolve them again."
  @spec maybe_resolve_tables(map()) :: map()
  def maybe_resolve_tables(%{tables: %{assemblies: assemblies, accounts: accounts}} = state) do
    if tables_exist?(assemblies, accounts), do: state, else: %{state | tables: nil}
  end

  @doc false
  def maybe_resolve_tables(state) do
    case state.resolve_tables.() do
      %{assemblies: assemblies, accounts: accounts} = tables ->
        if tables_exist?(assemblies, accounts) do
          %{state | tables: tables}
        else
          %{state | tables: nil}
        end

      _other ->
        %{state | tables: nil}
    end
  end

  @doc "Subscribes to an assembly topic only once per watched monitor id set."
  @spec maybe_subscribe_for_event(map(), String.t()) :: map()
  def maybe_subscribe_for_event(%{watched_ids: watched_ids} = state, assembly_id) do
    if MapSet.member?(watched_ids, assembly_id) do
      state
    else
      :ok = state.subscribe_fun.(assembly_id)
      %{state | watched_ids: MapSet.put(watched_ids, assembly_id)}
    end
  rescue
    error ->
      Logger.warning(
        "alert engine failed to subscribe for #{assembly_id}: #{Exception.message(error)}"
      )

      state
  end

  @doc "Discovers active monitor ids and syncs PubSub subscriptions accordingly."
  @spec discover_monitors(map(), atom() | module(), Worlds.world_name()) :: map()
  def discover_monitors(%{registry: nil} = state, _pubsub, _world), do: state
  @doc false
  def discover_monitors(%{tables: nil} = state, _pubsub, _world), do: state

  @doc false
  def discover_monitors(state, pubsub, _world) do
    current_ids =
      state.registry
      |> MonitorSupervisor.list_monitors()
      |> Enum.map(fn {assembly_id, _pid} -> assembly_id end)
      |> MapSet.new()

    new_ids = MapSet.difference(current_ids, state.watched_ids)
    removed_ids = MapSet.difference(state.watched_ids, current_ids)

    Enum.each(new_ids, &state.subscribe_fun.(&1))
    Enum.each(removed_ids, &Phoenix.PubSub.unsubscribe(pubsub, assembly_topic(&1)))

    %{state | watched_ids: current_ids}
  rescue
    error ->
      Logger.warning("alert engine discovery failed: #{Exception.message(error)}")
      state
  end

  @doc "Returns true when both required ETS tables exist."
  @spec tables_exist?(Cache.table_id(), Cache.table_id()) :: boolean()
  def tables_exist?(assemblies, accounts),
    do: :ets.info(assemblies) != :undefined and :ets.info(accounts) != :undefined

  @doc "Allows engine process to use sandbox owner database connection when present."
  @spec maybe_allow_sandbox_owner(pid() | nil) :: :ok
  def maybe_allow_sandbox_owner(nil), do: :ok

  @doc false
  def maybe_allow_sandbox_owner(owner) when is_pid(owner) do
    if Code.ensure_loaded?(Sandbox) and function_exported?(Sandbox, :allow, 3) do
      Sandbox.allow(Sigil.Repo, owner, self())
    end

    :ok
  rescue
    _error -> :ok
  end

  @doc "Schedules the next monitor discovery tick."
  @spec schedule_discovery(pos_integer()) :: reference()
  def schedule_discovery(interval_ms),
    do: Process.send_after(self(), :discover_monitors, interval_ms)

  @doc "Schedules the next dismissed-alert purge tick."
  @spec schedule_purge(pos_integer()) :: reference()
  def schedule_purge(interval_ms),
    do: Process.send_after(self(), :purge_old_dismissed, interval_ms)

  @doc "Builds monitor topic names from assembly identifiers."
  @spec assembly_topic(String.t()) :: String.t()
  def assembly_topic(assembly_id), do: "assembly:#{assembly_id}"
end
