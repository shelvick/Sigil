defmodule Sigil.GameState.MonitorSupervisorTest do
  @moduledoc """
  Covers monitor supervisor lifecycle, lookup, and restart behavior.
  """

  use ExUnit.Case, async: true

  alias Sigil.Cache
  alias Sigil.GameState.{AssemblyMonitor, MonitorSupervisor}

  setup do
    cache_pid = start_supervised!({Cache, tables: [:assemblies]})
    pubsub = unique_pubsub_name()
    registry = unique_registry_name()

    start_supervised!({Phoenix.PubSub, name: pubsub})
    start_supervised!({Registry, keys: :unique, name: registry})

    {:ok, tables: Cache.tables(cache_pid), pubsub: pubsub, registry: registry}
  end

  test "start_monitor starts a child AssemblyMonitor", context do
    supervisor = start_monitor_supervisor!(context.registry)
    assembly_id = "0xassembly-start"

    assert {:ok, monitor} =
             MonitorSupervisor.start_monitor(supervisor, monitor_opts(context, assembly_id))

    state = AssemblyMonitor.get_state(monitor)

    assert state.assembly_id == assembly_id
    assert {:ok, ^monitor} = MonitorSupervisor.get_monitor(context.registry, assembly_id)
  end

  test "start_monitor broadcasts lifecycle event", context do
    supervisor = start_monitor_supervisor!(context.registry)
    assembly_id = "0xassembly-lifecycle"
    :ok = Phoenix.PubSub.subscribe(context.pubsub, "monitors:lifecycle")

    assert {:ok, _monitor} =
             MonitorSupervisor.start_monitor(supervisor, monitor_opts(context, assembly_id))

    assert_receive {:monitor_started, ^assembly_id}, 1_000
  end

  test "start_monitor uses explicit pubsub for lifecycle event", context do
    supervisor = start_monitor_supervisor!(context.registry)
    assembly_id = "0xassembly-default-pubsub"
    :ok = Phoenix.PubSub.subscribe(context.pubsub, "monitors:lifecycle")

    opts = context |> monitor_opts(assembly_id) |> Keyword.put(:pubsub, context.pubsub)

    assert {:ok, _monitor} = MonitorSupervisor.start_monitor(supervisor, opts)
    assert_receive {:monitor_started, ^assembly_id}, 1_000
  end

  test "stop_monitor terminates a specific monitor", context do
    supervisor = start_monitor_supervisor!(context.registry)
    assembly_id = "0xassembly-stop"

    {:ok, monitor} =
      MonitorSupervisor.start_monitor(supervisor, monitor_opts(context, assembly_id))

    _state = AssemblyMonitor.get_state(monitor)
    ref = Process.monitor(monitor)

    assert :ok = MonitorSupervisor.stop_monitor(supervisor, assembly_id, context.registry)
    assert_receive {:DOWN, ^ref, :process, ^monitor, reason}, 1_000
    assert reason in [:normal, :noproc, :shutdown, {:shutdown, :normal}, {:shutdown, :noproc}]
  end

  test "stop_monitor returns error for unknown assembly", context do
    supervisor = start_monitor_supervisor!(context.registry)

    assert {:error, :not_found} =
             MonitorSupervisor.stop_monitor(supervisor, "0xassembly-missing", context.registry)
  end

  test "ensure_monitors starts monitors for new assemblies", context do
    supervisor = start_monitor_supervisor!(context.registry)
    assembly_ids = ["0xassembly-a", "0xassembly-b"]

    assert :ok =
             MonitorSupervisor.ensure_monitors(
               supervisor,
               assembly_ids,
               shared_monitor_opts(context)
             )

    assert {:ok, monitor_a} = MonitorSupervisor.get_monitor(context.registry, "0xassembly-a")
    assert {:ok, monitor_b} = MonitorSupervisor.get_monitor(context.registry, "0xassembly-b")
    refute monitor_a == monitor_b
  end

  test "ensure_monitors skips already-monitored assemblies", context do
    supervisor = start_monitor_supervisor!(context.registry)
    assembly_id = "0xassembly-existing"

    {:ok, existing_monitor} =
      MonitorSupervisor.start_monitor(supervisor, monitor_opts(context, assembly_id))

    _state = AssemblyMonitor.get_state(existing_monitor)

    assert :ok =
             MonitorSupervisor.ensure_monitors(
               supervisor,
               [assembly_id, "0xassembly-new"],
               shared_monitor_opts(context)
             )

    assert {:ok, ^existing_monitor} = MonitorSupervisor.get_monitor(context.registry, assembly_id)
    assert {:ok, _new_monitor} = MonitorSupervisor.get_monitor(context.registry, "0xassembly-new")
    assert 2 == length(MonitorSupervisor.list_monitors(context.registry))
  end

  test "get_monitor returns pid for monitored assembly", context do
    supervisor = start_monitor_supervisor!(context.registry)
    assembly_id = "0xassembly-lookup"

    {:ok, monitor} =
      MonitorSupervisor.start_monitor(supervisor, monitor_opts(context, assembly_id))

    _state = AssemblyMonitor.get_state(monitor)

    assert {:ok, ^monitor} = MonitorSupervisor.get_monitor(context.registry, assembly_id)
  end

  test "get_monitor returns error for unmonitored assembly", context do
    assert {:error, :not_found} =
             MonitorSupervisor.get_monitor(context.registry, "0xassembly-missing")
  end

  test "crashed monitor is restarted and re-registers", context do
    supervisor = start_monitor_supervisor!(context.registry)
    assembly_id = "0xassembly-restart"
    parent = self()

    {:ok, original_monitor} =
      MonitorSupervisor.start_monitor(
        supervisor,
        monitor_opts(context, assembly_id,
          interval_ms: 10,
          sync_fun: fn ^assembly_id, _opts ->
            send(parent, {:sync_called, self(), assembly_id})
            {:error, :timeout}
          end
        )
      )

    _state = AssemblyMonitor.get_state(original_monitor)
    ref = Process.monitor(original_monitor)

    Process.exit(original_monitor, :kill)

    assert_receive {:DOWN, ^ref, :process, ^original_monitor, reason}, 1_000
    assert reason in [:killed, :shutdown, {:shutdown, :killed}, {:shutdown, :normal}, :normal]

    assert {:ok, restarted_monitor} =
             wait_for_restarted_sync(original_monitor, assembly_id)

    refute restarted_monitor == original_monitor

    assert {:ok, ^restarted_monitor} =
             MonitorSupervisor.get_monitor(context.registry, assembly_id)
  end

  test "start_link returns unnamed supervisor PID", context do
    {:ok, supervisor} = MonitorSupervisor.start_link(registry: context.registry)

    on_exit(fn ->
      if Process.alive?(supervisor) do
        try do
          GenServer.stop(supervisor, :normal, :infinity)
        catch
          :exit, _reason -> :ok
        end
      end
    end)

    assert Process.info(supervisor, :registered_name) == {:registered_name, []}
  end

  test "ensure_monitors then get_monitor returns PIDs", context do
    supervisor = start_monitor_supervisor!(context.registry)
    assembly_ids = ["0xassembly-1", "0xassembly-2", "0xassembly-3"]

    assert :ok =
             MonitorSupervisor.ensure_monitors(
               supervisor,
               assembly_ids,
               shared_monitor_opts(context)
             )

    returned_monitors =
      Enum.map(assembly_ids, fn assembly_id ->
        assert {:ok, monitor} = MonitorSupervisor.get_monitor(context.registry, assembly_id)
        {assembly_id, monitor}
      end)

    assert length(returned_monitors) == 3
    assert returned_monitors |> Enum.map(&elem(&1, 1)) |> Enum.uniq() |> length() == 3
  end

  test "list_monitors returns registered monitors", context do
    supervisor = start_monitor_supervisor!(context.registry)

    {:ok, monitor_a} =
      MonitorSupervisor.start_monitor(supervisor, monitor_opts(context, "0xassembly-a"))

    {:ok, monitor_b} =
      MonitorSupervisor.start_monitor(supervisor, monitor_opts(context, "0xassembly-b"))

    _state = AssemblyMonitor.get_state(monitor_a)
    _state = AssemblyMonitor.get_state(monitor_b)

    registered_monitors =
      context.registry
      |> MonitorSupervisor.list_monitors()
      |> Enum.sort()

    expected_monitors =
      [{"0xassembly-a", monitor_a}, {"0xassembly-b", monitor_b}]
      |> Enum.sort()

    assert registered_monitors == expected_monitors
  end

  defp start_monitor_supervisor!(registry) do
    start_supervised!({MonitorSupervisor, registry: registry})
  end

  defp monitor_opts(context, assembly_id, overrides \\ []) do
    Keyword.merge(
      [
        assembly_id: assembly_id,
        tables: context.tables,
        pubsub: context.pubsub,
        registry: context.registry,
        interval_ms: 60_000,
        sync_fun: fn ^assembly_id, _opts -> {:error, :not_found} end
      ],
      overrides
    )
  end

  defp shared_monitor_opts(context) do
    [
      tables: context.tables,
      pubsub: context.pubsub,
      registry: context.registry,
      interval_ms: 60_000,
      sync_fun: fn _assembly_id, _opts -> {:error, :not_found} end
    ]
  end

  defp wait_for_restarted_sync(original_monitor, assembly_id) do
    receive do
      {:sync_called, ^original_monitor, ^assembly_id} ->
        wait_for_restarted_sync(original_monitor, assembly_id)

      {:sync_called, restarted_monitor, ^assembly_id} ->
        {:ok, restarted_monitor}
    after
      1_000 ->
        {:error, :not_restarted}
    end
  end

  defp unique_pubsub_name do
    :"monitor_supervisor_pubsub_#{System.unique_integer([:positive])}"
  end

  defp unique_registry_name do
    :"monitor_supervisor_registry_#{System.unique_integer([:positive])}"
  end
end
