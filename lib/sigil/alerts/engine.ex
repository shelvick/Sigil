defmodule Sigil.Alerts.Engine do
  @moduledoc """
  Singleton alert engine that subscribes to assembly monitor topics, persists
  alerts, and dispatches webhook notifications.
  """

  use GenServer

  require Logger

  alias Sigil.Alerts
  alias Sigil.Alerts.{Alert, WebhookConfig}
  alias Sigil.Alerts.Engine.{Dispatcher, RuleEvaluator, Runtime}
  alias Sigil.Cache
  alias Sigil.Worlds

  @default_discovery_interval_ms 60_000
  @default_purge_interval_ms 86_400_000
  @default_purge_after_days 7
  @default_cooldown_ms 14_400_000
  @default_pubsub Sigil.PubSub
  @monitor_lifecycle_topic "monitors:lifecycle"
  @reputation_topic "reputation"
  @resolve_retry_ms 500
  @default_notifier Application.compile_env(
                      :sigil,
                      :webhook_notifier,
                      Sigil.Alerts.WebhookNotifier.Discord
                    )
  @type dispatch_fun() :: (Alert.t(), WebhookConfig.t(), module(), keyword() -> term())
  @type subscription_fun() :: (String.t() -> term())
  @typedoc "Runtime state for the alert engine."
  @type state() :: %{
          pubsub: atom() | module(),
          world: Worlds.world_name(),
          registry: atom() | nil,
          resolve_registry: (-> atom() | nil),
          tables: %{assemblies: Cache.table_id(), accounts: Cache.table_id()} | nil,
          resolve_tables: (-> %{assemblies: Cache.table_id(), accounts: Cache.table_id()} | nil),
          watched_ids: MapSet.t(String.t()),
          discovery_interval_ms: pos_integer(),
          purge_interval_ms: pos_integer(),
          purge_after_days: pos_integer(),
          cooldown_ms: non_neg_integer(),
          now_fun: (-> DateTime.t()),
          create_alert_fun: (map(), keyword() -> term()),
          get_webhook_config_fun: (integer(), keyword() -> term()),
          notifier: module(),
          notifier_opts: keyword(),
          dispatch_fun: dispatch_fun(),
          subscribe_fun: subscription_fun(),
          owner_pid: pid(),
          sandbox_owner: pid() | nil,
          mox_owner: pid() | nil
        }

  @typedoc "Start option accepted by the alert engine."
  @type option() ::
          {:pubsub, atom() | module()}
          | {:world, Worlds.world_name()}
          | {:registry, atom()}
          | {:resolve_registry, (-> atom() | nil)}
          | {:tables, %{assemblies: Cache.table_id(), accounts: Cache.table_id()}}
          | {:resolve_tables,
             (-> %{assemblies: Cache.table_id(), accounts: Cache.table_id()} | nil)}
          | {:discovery_interval_ms, pos_integer()}
          | {:purge_interval_ms, pos_integer()}
          | {:purge_after_days, pos_integer()}
          | {:cooldown_ms, non_neg_integer()}
          | {:now_fun, (-> DateTime.t())}
          | {:create_alert_fun, (map(), keyword() -> term())}
          | {:get_webhook_config_fun, (integer(), keyword() -> term())}
          | {:notifier, module()}
          | {:notifier_opts, keyword()}
          | {:dispatch_fun, dispatch_fun()}
          | {:subscribe_fun, subscription_fun()}
          | {:sandbox_owner, pid()}
          | {:mox_owner, pid()}
          | {:owner_pid, pid()}

  @type options() :: [option()]

  @doc "Returns the singleton child spec used by the application supervisor."
  @spec child_spec(options()) :: Supervisor.child_spec()
  def child_spec(opts), do: %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}}

  @doc "Starts the alert engine."
  @spec start_link(options()) :: GenServer.on_start()
  def start_link(opts),
    do: GenServer.start_link(__MODULE__, Keyword.put_new(opts, :owner_pid, self()))

  @doc "Returns the current engine state."
  @spec get_state(GenServer.server()) :: state()
  def get_state(server), do: GenServer.call(server, :get_state)

  @impl true
  @spec init(options()) :: {:ok, state(), {:continue, :post_init}}
  def init(opts) do
    defaults = %{
      default_resolve_registry: &Runtime.default_resolve_registry/0,
      default_resolve_tables: &Runtime.default_resolve_tables/0,
      default_discovery_interval_ms: @default_discovery_interval_ms,
      default_purge_interval_ms: @default_purge_interval_ms,
      default_purge_after_days: @default_purge_after_days,
      default_cooldown_ms: @default_cooldown_ms,
      default_get_webhook_config_fun: &Alerts.get_webhook_config/2
    }

    base_state =
      Runtime.build_base_state(
        opts,
        defaults,
        @default_pubsub,
        @default_notifier,
        &create_alert/2
      )

    dispatch_fun =
      Keyword.get_lazy(opts, :dispatch_fun, fn ->
        fn alert, config, notifier, notifier_opts ->
          Dispatcher.default_dispatch(
            alert,
            config,
            notifier,
            notifier_opts,
            base_state.owner_pid,
            base_state.mox_owner || base_state.owner_pid
          )
        end
      end)

    {:ok, %{base_state | dispatch_fun: dispatch_fun}, {:continue, :post_init}}
  end

  @impl true
  @spec handle_continue(:post_init, state()) :: {:noreply, state()}
  def handle_continue(:post_init, state) do
    :ok = Runtime.maybe_allow_sandbox_owner(state.sandbox_owner)
    :ok = Dispatcher.maybe_allow_mock_owner(state.mox_owner || state.owner_pid, state.notifier)
    :ok = Dispatcher.maybe_allow_req_test_owner(state.owner_pid, state.notifier_opts)

    :ok =
      Phoenix.PubSub.subscribe(state.pubsub, Worlds.topic(state.world, @monitor_lifecycle_topic))

    :ok = Phoenix.PubSub.subscribe(state.pubsub, Worlds.topic(state.world, @reputation_topic))
    send(self(), :discover_monitors)
    Runtime.schedule_purge(state.purge_interval_ms)
    {:noreply, state}
  end

  @impl true
  @spec handle_call(:get_state, GenServer.from(), state()) :: {:reply, state(), state()}
  def handle_call(:get_state, _from, state), do: {:reply, state, state}

  @impl true
  @spec handle_info(
          :discover_monitors
          | :purge_old_dismissed
          | {:assembly_monitor, String.t(), map()}
          | {:monitor_started, String.t()}
          | {:reputation_updated, map()}
          | {:assembly_updated, term()},
          state()
        ) ::
          {:noreply, state()}
  def handle_info(:discover_monitors, state) do
    next_state =
      state
      |> Runtime.maybe_resolve_registry()
      |> Runtime.maybe_resolve_tables()
      |> Runtime.discover_monitors(state.pubsub, state.world)

    interval =
      case {next_state.registry, next_state.tables} do
        {registry, tables} when is_atom(registry) and not is_nil(registry) and is_map(tables) ->
          next_state.discovery_interval_ms

        _unresolved ->
          @resolve_retry_ms
      end

    Runtime.schedule_discovery(interval)
    {:noreply, next_state}
  end

  def handle_info(:purge_old_dismissed, state) do
    _result = Alerts.purge_old_dismissed(state.purge_after_days, [])
    Runtime.schedule_purge(state.purge_interval_ms)
    {:noreply, state}
  end

  def handle_info({:assembly_monitor, assembly_id, payload}, state) when is_binary(assembly_id) do
    next_state = state |> Runtime.maybe_resolve_tables() |> Runtime.maybe_resolve_registry()
    updated_state = process_monitor_event(assembly_id, payload, next_state)
    {:noreply, updated_state}
  end

  def handle_info({:monitor_started, assembly_id}, state) when is_binary(assembly_id) do
    next_state =
      state
      |> Runtime.maybe_resolve_registry()
      |> Runtime.maybe_resolve_tables()
      |> Runtime.maybe_subscribe_for_event(assembly_id)

    {:noreply, next_state}
  end

  def handle_info({:reputation_updated, payload}, state) when is_map(payload) do
    :ok = process_reputation_event(payload, state)
    {:noreply, state}
  end

  # Ignore {:assembly_updated, _} broadcasts from Assemblies.sync_assembly/2.
  # The engine acts on {:assembly_monitor, id, payload} events instead.
  def handle_info({:assembly_updated, _assembly}, state) do
    {:noreply, state}
  end

  @spec process_monitor_event(String.t(), map(), state()) :: state()
  defp process_monitor_event(assembly_id, payload, state) do
    state = Runtime.maybe_subscribe_for_event(state, assembly_id)

    case owner_context(assembly_id, payload, state.tables) do
      {:ok, context} ->
        payload
        |> triggered_alerts(context, state)
        |> Enum.each(&persist_and_dispatch(&1, state))

      :error ->
        Logger.warning("alert engine skipped event for #{assembly_id}: missing owner context")
    end

    state
  end

  @spec process_reputation_event(map(), state()) :: :ok
  defp process_reputation_event(payload, state) do
    case RuleEvaluator.evaluate_reputation_change(payload) do
      {:fire, attrs} -> persist_and_dispatch(attrs, state)
      :skip -> :ok
    end
  end

  @spec owner_context(
          String.t(),
          map(),
          %{assemblies: Cache.table_id(), accounts: Cache.table_id()} | nil
        ) ::
          {:ok,
           %{account_address: String.t(), assembly_name: String.t(), tribe_id: integer() | nil}}
          | :error
  defp owner_context(_assembly_id, _payload, nil), do: :error

  defp owner_context(assembly_id, payload, tables) do
    case Cache.get(tables.assemblies, assembly_id) do
      {account_address, _assembly} when is_binary(account_address) ->
        tribe_id =
          case Cache.get(tables.accounts, account_address) do
            %{tribe_id: value} -> value
            _other -> nil
          end

        {:ok,
         %{
           account_address: account_address,
           assembly_name: assembly_name(payload, assembly_id),
           tribe_id: tribe_id
         }}

      _other ->
        :error
    end
  end

  @spec assembly_name(map(), String.t()) :: String.t()
  defp assembly_name(%{assembly: %{metadata: %{name: name}}}, _assembly_id)
       when is_binary(name) and name != "",
       do: name

  defp assembly_name(_payload, assembly_id), do: assembly_id

  @spec triggered_alerts(map(), RuleEvaluator.context(), state()) :: [map()]
  defp triggered_alerts(payload, context, state) do
    RuleEvaluator.triggered_alerts(payload, context, state.now_fun.())
  end

  @spec persist_and_dispatch(map(), state()) :: :ok
  defp persist_and_dispatch(attrs, state) do
    case state.create_alert_fun.(attrs, cooldown_ms: state.cooldown_ms) do
      {:ok, %Alert{} = alert} ->
        maybe_dispatch_webhook(alert, state)

      {:ok, :duplicate} ->
        :ok

      {:ok, :cooldown} ->
        :ok

      {:error, reason} ->
        Logger.warning("alert engine failed to persist alert #{attrs.type}: #{inspect(reason)}")
        :ok

      other ->
        Logger.warning("alert engine received unexpected alert result: #{inspect(other)}")
        :ok
    end
  rescue
    error ->
      Logger.warning(
        "alert engine crashed while persisting #{attrs.type}: #{Exception.message(error)}"
      )

      :ok
  end

  @spec maybe_dispatch_webhook(Alert.t(), state()) :: :ok
  defp maybe_dispatch_webhook(%Alert{tribe_id: tribe_id}, _state) when not is_integer(tribe_id),
    do: :ok

  defp maybe_dispatch_webhook(%Alert{} = alert, state) do
    case state.get_webhook_config_fun.(alert.tribe_id, []) do
      %WebhookConfig{enabled: true} = config ->
        safe_dispatch(alert, config, state)

      %{enabled: true} = config when is_map(config) ->
        safe_dispatch(alert, struct!(WebhookConfig, config), state)

      _other ->
        :ok
    end
  rescue
    error ->
      Logger.warning("alert engine failed to load webhook config: #{Exception.message(error)}")
      :ok
  end

  @spec safe_dispatch(Alert.t(), WebhookConfig.t(), state()) :: :ok
  defp safe_dispatch(alert, config, state) do
    _result = state.dispatch_fun.(alert, config, state.notifier, state.notifier_opts)
    :ok
  rescue
    error ->
      Logger.warning("alert engine webhook dispatch failed: #{Exception.message(error)}")
      :ok
  catch
    kind, reason ->
      Logger.warning("alert engine webhook dispatch failed: #{inspect({kind, reason})}")
      :ok
  end

  @spec create_alert(map(), keyword()) ::
          {:ok, Alert.t()} | {:ok, :duplicate} | {:ok, :cooldown} | {:error, Ecto.Changeset.t()}
  defp create_alert(attrs, opts) do
    Alerts.create_alert(stringify_alert_attrs(attrs), opts)
  end

  @spec stringify_alert_attrs(map()) :: map()
  defp stringify_alert_attrs(attrs) do
    Enum.into(attrs, %{}, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      {key, value} -> {key, value}
    end)
  end
end
