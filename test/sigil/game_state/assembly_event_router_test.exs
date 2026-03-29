defmodule Sigil.GameState.AssemblyEventRouterParserStub do
  @moduledoc """
  Parser stub used to verify AssemblyEventRouter parser-module injection.
  """

  @doc """
  Returns true only for a custom test event type.
  """
  @spec assembly_event?(atom()) :: boolean()
  def assembly_event?(:custom_router_event), do: true
  def assembly_event?(_event_type), do: false

  @doc """
  Extracts assembly IDs from the custom parser test payload shape.
  """
  @spec extract_assembly_id(atom(), map()) :: {:ok, String.t()} | {:error, atom()}
  def extract_assembly_id(:custom_router_event, %{"target" => assembly_id})
      when is_binary(assembly_id) and assembly_id != "" do
    {:ok, assembly_id}
  end

  def extract_assembly_id(:custom_router_event, _raw_data), do: {:error, :missing_target}
  def extract_assembly_id(_event_type, _raw_data), do: {:error, :not_assembly_event}
end

defmodule Sigil.GameState.AssemblyEventRouterProbeMonitor do
  @moduledoc """
  Minimal monitor process that registers under a test Registry and forwards
  received messages back to the test process.
  """

  use GenServer

  @doc """
  Returns a unique child spec so multiple probe monitors can run in one test.
  """
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: {__MODULE__, System.unique_integer([:positive])},
      start: {__MODULE__, :start_link, [opts]},
      restart: :temporary,
      type: :worker
    }
  end

  @doc """
  Starts a probe monitor process for router fan-out assertions.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  @spec init(keyword()) :: {:ok, %{listener: pid()}}
  def init(opts) do
    registry = Keyword.fetch!(opts, :registry)
    assembly_id = Keyword.fetch!(opts, :assembly_id)
    listener = Keyword.fetch!(opts, :listener)

    {:ok, _} = Registry.register(registry, assembly_id, nil)

    {:ok, %{listener: listener}}
  end

  @impl true
  @spec handle_info(term(), %{listener: pid()}) :: {:noreply, %{listener: pid()}}
  def handle_info(message, %{listener: listener} = state) do
    send(listener, {:probe_monitor_event, self(), message})
    {:noreply, state}
  end
end

defmodule Sigil.GameState.AssemblyEventRouterTest do
  @moduledoc """
  Covers assembly event router fan-out behavior from chain_events PubSub messages.
  """

  use ExUnit.Case, async: true

  @compile {:no_warn_undefined, Sigil.GameState.AssemblyEventRouter}

  alias Sigil.{Cache, GameState.AssemblyMonitor}
  alias Sigil.GameState.AssemblyEventRouterProbeMonitor
  alias Sigil.Sui.Types.{Assembly, AssemblyStatus, Location, Metadata, TenantItemId}

  setup do
    pubsub = unique_pubsub_name()
    topic = unique_topic()
    registry = unique_registry_name()
    cache = start_supervised!({Cache, tables: [:assemblies]})

    start_supervised!({Phoenix.PubSub, name: pubsub})
    start_supervised!({Registry, keys: :unique, name: registry})

    {:ok, pubsub: pubsub, topic: topic, registry: registry, tables: Cache.tables(cache)}
  end

  @tag :acceptance
  test "chain event dispatches monitor notification through router pipeline", context do
    assembly_id = "0xrouter-acceptance"
    monitor = start_probe_monitor!(context.registry, assembly_id)
    _router = start_router!(context)

    Phoenix.PubSub.broadcast(context.pubsub, context.topic, {
      :chain_event,
      :assembly_status_changed,
      %{"assembly_id" => assembly_id, "status" => "ONLINE"},
      701
    })

    assert_receive {:probe_monitor_event, ^monitor,
                    {:assembly_event, :assembly_status_changed, ^assembly_id, 701}},
                   1_000

    refute_receive {:probe_monitor_event, ^monitor,
                    {:assembly_event, :killmail_created, _assembly_id, _checkpoint}},
                   200
  end

  test "routes event to real assembly monitor without crashing it", context do
    assembly_id = "0xrouter-real-monitor"
    :ok = Phoenix.PubSub.subscribe(context.pubsub, "assembly:#{assembly_id}")

    parent = self()

    sync_fun = fn ^assembly_id, _opts ->
      send(parent, {:router_monitor_sync_called, assembly_id})
      {:ok, assembly_fixture(assembly_id)}
    end

    monitor = start_real_monitor!(context, assembly_id, sync_fun)

    ref = Process.monitor(monitor)
    _router = start_router!(context)

    Phoenix.PubSub.broadcast(context.pubsub, context.topic, {
      :chain_event,
      :assembly_status_changed,
      %{"assembly_id" => assembly_id},
      110
    })

    assert_receive {:router_monitor_sync_called, ^assembly_id}, 1_000
    assert_receive {:assembly_monitor, ^assembly_id, payload}, 1_000
    assert %Assembly{id: ^assembly_id} = payload.assembly
    refute_receive {:DOWN, ^ref, :process, ^monitor, _reason}, 200
  end

  test "routes assembly status changed event to correct monitor", context do
    assembly_id = "0xrouter-status"
    monitor = start_probe_monitor!(context.registry, assembly_id)
    _router = start_router!(context)

    Phoenix.PubSub.broadcast(context.pubsub, context.topic, {
      :chain_event,
      :assembly_status_changed,
      %{"assembly_id" => assembly_id},
      101
    })

    assert_receive {:probe_monitor_event, ^monitor,
                    {:assembly_event, :assembly_status_changed, ^assembly_id, 101}},
                   1_000
  end

  test "routes assembly fuel event to correct monitor", context do
    assembly_id = "0xrouter-fuel"
    monitor = start_probe_monitor!(context.registry, assembly_id)
    _router = start_router!(context)

    Phoenix.PubSub.broadcast(context.pubsub, context.topic, {
      :chain_event,
      :assembly_fuel_changed,
      %{"assembly_id" => assembly_id, "new_quantity" => "8"},
      102
    })

    assert_receive {:probe_monitor_event, ^monitor,
                    {:assembly_event, :assembly_fuel_changed, ^assembly_id, 102}},
                   1_000
  end

  test "routes assembly extension authorized event to correct monitor", context do
    assembly_id = "0xrouter-extension"
    monitor = start_probe_monitor!(context.registry, assembly_id)
    _router = start_router!(context)

    Phoenix.PubSub.broadcast(context.pubsub, context.topic, {
      :chain_event,
      :assembly_extension_authorized,
      %{"assembly_id" => assembly_id, "extension_type" => "gate"},
      103
    })

    assert_receive {:probe_monitor_event, ^monitor,
                    {:assembly_event, :assembly_extension_authorized, ^assembly_id, 103}},
                   1_000
  end

  test "ignores non-assembly chain events", context do
    assembly_id = "0xrouter-ignore"
    monitor = start_probe_monitor!(context.registry, assembly_id)
    _router = start_router!(context)

    Phoenix.PubSub.broadcast(context.pubsub, context.topic, {
      :chain_event,
      :killmail_created,
      %{"assembly_id" => assembly_id},
      104
    })

    refute_receive {:probe_monitor_event, ^monitor, _message}, 200
  end

  test "silently drops events for assemblies with no active monitor", context do
    _router = start_router!(context)

    Phoenix.PubSub.broadcast(context.pubsub, context.topic, {
      :chain_event,
      :assembly_status_changed,
      %{"assembly_id" => "0xunmonitored"},
      105
    })

    refute_receive {:probe_monitor_event, _monitor, _message}, 200
  end

  test "handles malformed events with missing assembly_id gracefully", context do
    assembly_id = "0xrouter-malformed"
    monitor = start_probe_monitor!(context.registry, assembly_id)
    _router = start_router!(context)

    Phoenix.PubSub.broadcast(context.pubsub, context.topic, {
      :chain_event,
      :assembly_status_changed,
      %{"status" => "ONLINE"},
      106
    })

    refute_receive {:probe_monitor_event, ^monitor, _message}, 200
  end

  test "subscribes to chain_events topic and receives broadcasts", context do
    assembly_id = "0xrouter-subscribe"
    monitor = start_probe_monitor!(context.registry, assembly_id)
    _router = start_router!(context)

    Phoenix.PubSub.broadcast(context.pubsub, context.topic, {
      :chain_event,
      :assembly_status_changed,
      %{"assembly_id" => assembly_id},
      107
    })

    assert_receive {:probe_monitor_event, ^monitor,
                    {:assembly_event, :assembly_status_changed, ^assembly_id, 107}},
                   1_000
  end

  test "router is not a named process", context do
    router = start_router!(context)

    assert Process.info(router, :registered_name) == {:registered_name, []}
  end

  test "uses injectable parser module", context do
    assembly_id = "0xrouter-custom-parser"
    monitor = start_probe_monitor!(context.registry, assembly_id)

    _router =
      start_router!(context,
        parser_module: Sigil.GameState.AssemblyEventRouterParserStub
      )

    Phoenix.PubSub.broadcast(context.pubsub, context.topic, {
      :chain_event,
      :custom_router_event,
      %{"target" => assembly_id},
      108
    })

    assert_receive {:probe_monitor_event, ^monitor,
                    {:assembly_event, :custom_router_event, ^assembly_id, 108}},
                   1_000
  end

  test "dispatches to correct monitor when multiple monitors are registered", context do
    assembly_a = "0xrouter-multi-a"
    assembly_b = "0xrouter-multi-b"

    monitor_a = start_probe_monitor!(context.registry, assembly_a)
    monitor_b = start_probe_monitor!(context.registry, assembly_b)

    _router = start_router!(context)

    Phoenix.PubSub.broadcast(context.pubsub, context.topic, {
      :chain_event,
      :assembly_status_changed,
      %{"assembly_id" => assembly_b},
      109
    })

    assert_receive {:probe_monitor_event, ^monitor_b,
                    {:assembly_event, :assembly_status_changed, ^assembly_b, 109}},
                   1_000

    refute_receive {:probe_monitor_event, ^monitor_a, _message}, 200
  end

  defp start_router!(context, overrides \\ []) do
    router =
      start_supervised!({
        Sigil.GameState.AssemblyEventRouter,
        Keyword.merge(
          [
            pubsub: context.pubsub,
            topic: context.topic,
            registry: context.registry
          ],
          overrides
        )
      })

    _state = :sys.get_state(router)
    router
  end

  @spec start_probe_monitor!(atom(), String.t()) :: pid()
  defp start_probe_monitor!(registry, assembly_id) do
    start_supervised!(
      {AssemblyEventRouterProbeMonitor,
       registry: registry, assembly_id: assembly_id, listener: self()}
    )
  end

  @spec start_real_monitor!(map(), String.t(), function()) :: pid()
  defp start_real_monitor!(context, assembly_id, sync_fun) do
    {:ok, monitor} =
      AssemblyMonitor.start_link(
        assembly_id: assembly_id,
        tables: context.tables,
        pubsub: context.pubsub,
        registry: context.registry,
        interval_ms: 60_000,
        sync_fun: sync_fun
      )

    _state = AssemblyMonitor.get_state(monitor)

    on_exit(fn ->
      if Process.alive?(monitor) do
        try do
          GenServer.stop(monitor, :normal, :infinity)
        catch
          :exit, _ -> :ok
        end
      end
    end)

    monitor
  end

  defp unique_pubsub_name do
    :"assembly_event_router_pubsub_#{System.unique_integer([:positive])}"
  end

  defp unique_registry_name do
    :"assembly_event_router_registry_#{System.unique_integer([:positive])}"
  end

  defp unique_topic do
    "chain_events:#{System.unique_integer([:positive])}"
  end

  @spec assembly_fixture(String.t()) :: Assembly.t()
  defp assembly_fixture(assembly_id) do
    %Assembly{
      id: assembly_id,
      key: %TenantItemId{item_id: 1, tenant: "0xtenant"},
      owner_cap_id: "0xowner-cap",
      type_id: 77,
      status: %AssemblyStatus{status: :online},
      location: %Location{location_hash: :binary.copy(<<7>>, 32)},
      energy_source_id: "0xenergy-source",
      metadata: %Metadata{
        assembly_id: assembly_id,
        name: "Router Integration Assembly",
        description: "assembly fixture for router integration",
        url: "https://example.test/assemblies/router"
      }
    }
  end
end
