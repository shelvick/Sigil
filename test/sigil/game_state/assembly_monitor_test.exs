defmodule Sigil.GameState.AssemblyMonitorTest do
  @moduledoc """
  Tests assembly monitor polling, change detection, and lifecycle behavior.
  """

  use ExUnit.Case, async: true

  import Hammox

  alias Sigil.{Assemblies, Cache}
  alias Sigil.GameState.AssemblyMonitor

  alias Sigil.Sui.Types.{
    Assembly,
    AssemblyStatus,
    EnergySource,
    Fuel,
    Gate,
    Location,
    Metadata,
    NetworkNode,
    StorageUnit,
    TenantItemId
  }

  @world_package_id "0x1111111111111111111111111111111111111111111111111111111111111111"

  setup :verify_on_exit!

  setup do
    cache_pid = start_supervised!({Cache, tables: [:assemblies]})
    pubsub = unique_pubsub_name()
    registry = unique_registry_name()

    start_supervised!({Phoenix.PubSub, name: pubsub})
    start_supervised!({Registry, keys: :unique, name: registry})

    {:ok, tables: Cache.tables(cache_pid), pubsub: pubsub, registry: registry}
  end

  test "polls assembly state on configured interval", %{
    tables: tables,
    pubsub: pubsub,
    registry: registry
  } do
    assembly_id = "0xassembly-interval"
    parent = self()

    sync_fun = fn ^assembly_id, _opts ->
      send(parent, {:sync_called, assembly_id})
      {:ok, assembly(id: assembly_id)}
    end

    _monitor =
      start_monitor!(
        assembly_id: assembly_id,
        tables: tables,
        pubsub: pubsub,
        registry: registry,
        interval_ms: 100,
        sync_fun: sync_fun
      )

    refute_receive {:sync_called, ^assembly_id}, 50
    assert_receive {:sync_called, ^assembly_id}, 1_000
    refute_receive {:sync_called, ^assembly_id}, 50
    assert_receive {:sync_called, ^assembly_id}, 1_000
  end

  @tag :acceptance
  test "discovery plus monitoring publishes depletion updates", %{
    tables: tables,
    pubsub: pubsub,
    registry: registry
  } do
    owner = owner_address()
    assembly_id = "0xassembly-acceptance"
    owner_cap_type = owner_cap_type()
    fetch_stage = start_supervised!({Agent, fn -> :discover end})
    monitor_supervisor = start_supervised!({DynamicSupervisor, strategy: :one_for_one})

    :ok = Phoenix.PubSub.subscribe(pubsub, "assembly:#{assembly_id}")

    expect(Sigil.Sui.ClientMock, :get_objects, fn [type: ^owner_cap_type, owner: ^owner], [] ->
      {:ok, owner_caps_page([owner_cap_json(assembly_id)])}
    end)

    stub(Sigil.Sui.ClientMock, :get_object, fn ^assembly_id, [] ->
      Agent.get_and_update(fetch_stage, fn
        :discover ->
          assembly = assembly_json(%{"id" => uid(assembly_id)})
          {{:ok, assembly}, :monitor}

        :monitor ->
          fuel_started_at = System.os_time(:millisecond)

          updated_json =
            network_node_json(%{
              "id" => uid(assembly_id),
              "fuel" =>
                fuel_json(%{
                  "quantity" => "10",
                  "burn_start_time" => Integer.to_string(fuel_started_at)
                })
            })

          {{:ok, updated_json}, {:done, updated_json}}

        {:done, updated_json} ->
          {{:ok, updated_json}, {:done, updated_json}}
      end)
    end)

    assert {:ok, [_assembly]} =
             Assemblies.discover_for_owner(owner,
               tables: tables,
               pubsub: pubsub,
               character_ids: [owner]
             )

    assert {:ok, monitor} =
             DynamicSupervisor.start_child(
               monitor_supervisor,
               AssemblyMonitor.child_spec(
                 assembly_id: assembly_id,
                 tables: tables,
                 pubsub: pubsub,
                 registry: registry,
                 interval_ms: 60_000
               )
             )

    Mox.allow(Sigil.Sui.ClientMock, self(), monitor)
    send(monitor, :poll)

    assert_receive {:assembly_updated, %NetworkNode{id: ^assembly_id}}, 1_000
    assert_receive {:assembly_monitor, ^assembly_id, payload}, 1_000
    assert %NetworkNode{id: ^assembly_id} = payload.assembly
    assert {:depletes_at, %DateTime{}} = payload.depletion
    assert payload.changes == []
    refute payload.assembly.status.status == :offline
  end

  test "detects and broadcasts status changes", %{
    tables: tables,
    pubsub: pubsub,
    registry: registry
  } do
    assembly_id = "0xassembly-status"
    :ok = Phoenix.PubSub.subscribe(pubsub, "assembly:#{assembly_id}")

    sync_fun =
      sequence_sync_fun(self(), [
        {:ok, assembly(id: assembly_id, status: assembly_status(:online))},
        {:ok, assembly(id: assembly_id, status: assembly_status(:offline))}
      ])

    monitor =
      start_monitor!(
        assembly_id: assembly_id,
        tables: tables,
        pubsub: pubsub,
        registry: registry,
        interval_ms: 60_000,
        sync_fun: sync_fun
      )

    send(monitor, :poll)
    assert_receive {:assembly_monitor, ^assembly_id, %{changes: []}}, 1_000

    send(monitor, :poll)

    assert_receive {:assembly_monitor, ^assembly_id, payload}, 1_000
    assert {:status_changed, :online, :offline} in payload.changes
    refute {:status_changed, :offline, :online} in payload.changes
  end

  test "detects fuel quantity changes for NetworkNode", %{
    tables: tables,
    pubsub: pubsub,
    registry: registry
  } do
    assembly_id = "0xnode-fuel"
    :ok = Phoenix.PubSub.subscribe(pubsub, "assembly:#{assembly_id}")

    sync_fun =
      sequence_sync_fun(self(), [
        {:ok, network_node(id: assembly_id, fuel: fuel(quantity: 50))},
        {:ok, network_node(id: assembly_id, fuel: fuel(quantity: 25))}
      ])

    monitor =
      start_monitor!(
        assembly_id: assembly_id,
        tables: tables,
        pubsub: pubsub,
        registry: registry,
        interval_ms: 60_000,
        sync_fun: sync_fun
      )

    send(monitor, :poll)
    assert_receive {:assembly_monitor, ^assembly_id, %{changes: []}}, 1_000

    send(monitor, :poll)

    assert_receive {:assembly_monitor, ^assembly_id, payload}, 1_000
    assert {:fuel_changed, 50, 25} in payload.changes
  end

  test "detects fuel burning state changes", %{tables: tables, pubsub: pubsub, registry: registry} do
    assembly_id = "0xnode-burning"
    :ok = Phoenix.PubSub.subscribe(pubsub, "assembly:#{assembly_id}")

    sync_fun =
      sequence_sync_fun(self(), [
        {:ok, network_node(id: assembly_id, fuel: fuel(is_burning: true))},
        {:ok, network_node(id: assembly_id, fuel: fuel(is_burning: false))}
      ])

    monitor =
      start_monitor!(
        assembly_id: assembly_id,
        tables: tables,
        pubsub: pubsub,
        registry: registry,
        interval_ms: 60_000,
        sync_fun: sync_fun
      )

    send(monitor, :poll)
    assert_receive {:assembly_monitor, ^assembly_id, %{changes: []}}, 1_000

    send(monitor, :poll)

    assert_receive {:assembly_monitor, ^assembly_id, payload}, 1_000
    assert {:fuel_burning_changed, true, false} in payload.changes
  end

  test "detects extension changes", %{tables: tables, pubsub: pubsub, registry: registry} do
    assembly_id = "0xgate-extension"
    :ok = Phoenix.PubSub.subscribe(pubsub, "assembly:#{assembly_id}")

    sync_fun =
      sequence_sync_fun(self(), [
        {:ok, gate(id: assembly_id, extension: nil)},
        {:ok, gate(id: assembly_id, extension: "0x2::frontier::GateExtension")}
      ])

    monitor =
      start_monitor!(
        assembly_id: assembly_id,
        tables: tables,
        pubsub: pubsub,
        registry: registry,
        interval_ms: 60_000,
        sync_fun: sync_fun
      )

    send(monitor, :poll)
    assert_receive {:assembly_monitor, ^assembly_id, %{changes: []}}, 1_000

    send(monitor, :poll)

    assert_receive {:assembly_monitor, ^assembly_id, payload}, 1_000
    assert {:extension_changed, nil, "0x2::frontier::GateExtension"} in payload.changes
  end

  test "computes fuel depletion for NetworkNode", %{
    tables: tables,
    pubsub: pubsub,
    registry: registry
  } do
    assembly_id = "0xnode-depletion"
    :ok = Phoenix.PubSub.subscribe(pubsub, "assembly:#{assembly_id}")

    sync_fun = fn ^assembly_id, _opts ->
      {:ok, network_node(id: assembly_id, fuel: fuel(quantity: 10, burn_rate_in_ms: 1_000))}
    end

    monitor =
      start_monitor!(
        assembly_id: assembly_id,
        tables: tables,
        pubsub: pubsub,
        registry: registry,
        interval_ms: 60_000,
        sync_fun: sync_fun
      )

    send(monitor, :poll)

    assert_receive {:assembly_monitor, ^assembly_id, payload}, 1_000
    assert {:depletes_at, %DateTime{}} = payload.depletion
  end

  test "returns nil depletion for non-NetworkNode assemblies", %{
    tables: tables,
    pubsub: pubsub,
    registry: registry
  } do
    assembly_id = "0xgate-no-depletion"
    :ok = Phoenix.PubSub.subscribe(pubsub, "assembly:#{assembly_id}")

    sync_fun = fn ^assembly_id, _opts ->
      {:ok, gate(id: assembly_id)}
    end

    monitor =
      start_monitor!(
        assembly_id: assembly_id,
        tables: tables,
        pubsub: pubsub,
        registry: registry,
        interval_ms: 60_000,
        sync_fun: sync_fun
      )

    send(monitor, :poll)

    assert_receive {:assembly_monitor, ^assembly_id, payload}, 1_000
    assert payload.depletion == nil
  end

  test "broadcasts composite event on assembly topic", %{
    tables: tables,
    pubsub: pubsub,
    registry: registry
  } do
    assembly_id = "0xassembly-broadcast"
    :ok = Phoenix.PubSub.subscribe(pubsub, "assembly:#{assembly_id}")

    sync_fun = fn ^assembly_id, _opts ->
      {:ok, assembly(id: assembly_id)}
    end

    monitor =
      start_monitor!(
        assembly_id: assembly_id,
        tables: tables,
        pubsub: pubsub,
        registry: registry,
        interval_ms: 60_000,
        sync_fun: sync_fun
      )

    send(monitor, :poll)

    assert_receive {:assembly_monitor, ^assembly_id,
                    %{
                      assembly: %Assembly{id: ^assembly_id} = assembly,
                      changes: [],
                      depletion: nil
                    }},
                   1_000

    assert assembly.status.status == :online
  end

  test "first poll broadcasts with empty changes list", %{
    tables: tables,
    pubsub: pubsub,
    registry: registry
  } do
    assembly_id = "0xassembly-first-poll"
    :ok = Phoenix.PubSub.subscribe(pubsub, "assembly:#{assembly_id}")

    sync_fun = fn ^assembly_id, _opts ->
      {:ok, assembly(id: assembly_id, status: assembly_status(:offline))}
    end

    monitor =
      start_monitor!(
        assembly_id: assembly_id,
        tables: tables,
        pubsub: pubsub,
        registry: registry,
        interval_ms: 60_000,
        sync_fun: sync_fun
      )

    send(monitor, :poll)

    assert_receive {:assembly_monitor, ^assembly_id, payload}, 1_000
    assert payload.changes == []
  end

  test "self-terminates after 5 consecutive not_found errors", %{
    tables: tables,
    pubsub: pubsub,
    registry: registry
  } do
    assembly_id = "0xassembly-missing"

    sync_fun = fn ^assembly_id, _opts ->
      {:error, :not_found}
    end

    monitor =
      start_monitor!(
        assembly_id: assembly_id,
        tables: tables,
        pubsub: pubsub,
        registry: registry,
        interval_ms: 60_000,
        sync_fun: sync_fun
      )

    ref = Process.monitor(monitor)

    Enum.each(1..4, fn _ -> send(monitor, :poll) end)
    assert Process.alive?(monitor)
    refute_receive {:DOWN, ^ref, :process, ^monitor, _reason}, 50

    send(monitor, :poll)

    assert_receive {:DOWN, ^ref, :process, ^monitor, reason}, 1_000
    assert reason in [:normal, :shutdown, {:shutdown, :normal}]
  end

  test "resets not_found counter on successful sync", %{
    tables: tables,
    pubsub: pubsub,
    registry: registry
  } do
    assembly_id = "0xassembly-reset"

    sync_fun =
      sequence_sync_fun(self(), [
        {:error, :not_found},
        {:error, :not_found},
        {:ok, assembly(id: assembly_id)}
      ])

    monitor =
      start_monitor!(
        assembly_id: assembly_id,
        tables: tables,
        pubsub: pubsub,
        registry: registry,
        interval_ms: 60_000,
        sync_fun: sync_fun
      )

    send(monitor, :poll)
    send(monitor, :poll)
    send(monitor, :poll)

    state = AssemblyMonitor.get_state(monitor)

    assert state.consecutive_not_found == 0
    assert %Assembly{id: ^assembly_id} = state.previous_assembly
  end

  test "handles transient sync errors without terminating", %{
    tables: tables,
    pubsub: pubsub,
    registry: registry
  } do
    assembly_id = "0xassembly-timeout"
    parent = self()

    sync_fun = fn ^assembly_id, _opts ->
      send(parent, {:transient_error_sync_called, assembly_id})
      {:error, :timeout}
    end

    monitor =
      start_monitor!(
        assembly_id: assembly_id,
        tables: tables,
        pubsub: pubsub,
        registry: registry,
        interval_ms: 60_000,
        sync_fun: sync_fun
      )

    state = AssemblyMonitor.get_state(monitor)

    assert {:noreply, next_state} = AssemblyMonitor.handle_info(:poll, state)
    assert_receive {:transient_error_sync_called, ^assembly_id}, 1_000
    assert next_state.consecutive_not_found == 0
    assert Process.alive?(monitor)
  end

  test "handles raised sync errors without terminating", %{
    tables: tables,
    pubsub: pubsub,
    registry: registry
  } do
    assembly_id = "0xassembly-crash"
    parent = self()

    sync_fun = fn ^assembly_id, _opts ->
      send(parent, {:raised_error_sync_called, assembly_id})
      raise "boom"
    end

    monitor =
      start_monitor!(
        assembly_id: assembly_id,
        tables: tables,
        pubsub: pubsub,
        registry: registry,
        interval_ms: 60_000,
        sync_fun: sync_fun
      )

    send(monitor, :poll)
    assert_receive {:raised_error_sync_called, ^assembly_id}, 1_000

    state = AssemblyMonitor.get_state(monitor)

    assert state.consecutive_not_found == 0
    assert Process.alive?(monitor)
  end

  test "maintains bounded fuel snapshot ring buffer", %{
    tables: tables,
    pubsub: pubsub,
    registry: registry
  } do
    assembly_id = "0xnode-snapshots"

    sync_fun =
      sequence_sync_fun(self(), [
        {:ok, network_node(id: assembly_id, fuel: fuel(quantity: 50))},
        {:ok, network_node(id: assembly_id, fuel: fuel(quantity: 25))},
        {:ok, network_node(id: assembly_id, fuel: fuel(quantity: 10))}
      ])

    monitor =
      start_monitor!(
        assembly_id: assembly_id,
        tables: tables,
        pubsub: pubsub,
        registry: registry,
        interval_ms: 60_000,
        max_snapshots: 2,
        sync_fun: sync_fun
      )

    send(monitor, :poll)
    send(monitor, :poll)
    send(monitor, :poll)

    state = AssemblyMonitor.get_state(monitor)

    assert length(state.fuel_snapshots) == 2
    assert Enum.map(state.fuel_snapshots, fn {_timestamp, quantity} -> quantity end) == [25, 10]
  end

  test "registers with Registry on init", %{tables: tables, pubsub: pubsub, registry: registry} do
    assembly_id = "0xassembly-registry"

    monitor =
      start_monitor!(
        assembly_id: assembly_id,
        tables: tables,
        pubsub: pubsub,
        registry: registry,
        interval_ms: 60_000,
        sync_fun: fn ^assembly_id, _opts -> {:ok, assembly(id: assembly_id)} end
      )

    assert Registry.lookup(registry, assembly_id) == [{monitor, nil}]
  end

  test "get_state returns current monitor state", %{
    tables: tables,
    pubsub: pubsub,
    registry: registry
  } do
    assembly_id = "0xassembly-state"

    sync_fun = fn ^assembly_id, _opts ->
      {:ok, network_node(id: assembly_id, fuel: fuel(quantity: 33))}
    end

    monitor =
      start_monitor!(
        assembly_id: assembly_id,
        tables: tables,
        pubsub: pubsub,
        registry: registry,
        interval_ms: 60_000,
        sync_fun: sync_fun
      )

    send(monitor, :poll)
    state = AssemblyMonitor.get_state(monitor)

    assert state.assembly_id == assembly_id
    assert %NetworkNode{id: ^assembly_id} = state.previous_assembly
    assert {:depletes_at, %DateTime{}} = state.depletion
    assert [{_timestamp, 33}] = state.fuel_snapshots
  end

  test "child_spec generates unique id" do
    spec_one = AssemblyMonitor.child_spec([])
    spec_two = AssemblyMonitor.child_spec([])

    assert spec_one.start == {AssemblyMonitor, :start_link, [[]]}
    assert spec_two.start == {AssemblyMonitor, :start_link, [[]]}
    refute spec_one.id == spec_two.id
  end

  test "uses injectable sync_fun", %{tables: tables, pubsub: pubsub, registry: registry} do
    assembly_id = "0xassembly-custom-sync"
    parent = self()

    sync_fun = fn ^assembly_id, opts ->
      send(
        parent,
        {:sync_called, assembly_id, Keyword.fetch!(opts, :tables), Keyword.fetch!(opts, :pubsub)}
      )

      {:ok, assembly(id: assembly_id)}
    end

    monitor =
      start_monitor!(
        assembly_id: assembly_id,
        tables: tables,
        pubsub: pubsub,
        registry: registry,
        interval_ms: 60_000,
        sync_fun: sync_fun
      )

    send(monitor, :poll)

    assert_receive {:sync_called, ^assembly_id, ^tables, ^pubsub}, 1_000
  end

  test "broadcasts empty changes when assembly unchanged", %{
    tables: tables,
    pubsub: pubsub,
    registry: registry
  } do
    assembly_id = "0xassembly-unchanged"
    :ok = Phoenix.PubSub.subscribe(pubsub, "assembly:#{assembly_id}")

    sync_fun =
      sequence_sync_fun(self(), [
        {:ok, storage_unit(id: assembly_id)},
        {:ok, storage_unit(id: assembly_id)}
      ])

    monitor =
      start_monitor!(
        assembly_id: assembly_id,
        tables: tables,
        pubsub: pubsub,
        registry: registry,
        interval_ms: 60_000,
        sync_fun: sync_fun
      )

    send(monitor, :poll)
    assert_receive {:assembly_monitor, ^assembly_id, %{changes: []}}, 1_000

    send(monitor, :poll)

    assert_receive {:assembly_monitor, ^assembly_id, payload}, 1_000
    assert payload.changes == []
  end

  defp start_monitor!(opts) do
    {:ok, monitor} = AssemblyMonitor.start_link(opts)
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

  defp sequence_sync_fun(parent, results) do
    agent = start_supervised!({Agent, fn -> results end})

    fn assembly_id, opts ->
      send(
        parent,
        {:sync_called, assembly_id, Keyword.fetch!(opts, :tables), Keyword.fetch!(opts, :pubsub)}
      )

      pop_next_result!(agent)
    end
  end

  defp pop_next_result!(agent) do
    Agent.get_and_update(agent, fn
      [next | rest] -> {next, rest}
      [] -> raise "sync sequence exhausted"
    end)
  end

  defp assembly(overrides) do
    struct!(
      Assembly,
      Keyword.merge(
        [
          id: "0xassembly",
          key: tenant_item_id(),
          owner_cap_id: "0xassembly-owner",
          type_id: 77,
          status: assembly_status(:online),
          location: location(),
          energy_source_id: "0xenergy",
          metadata: metadata("Assembly One")
        ],
        overrides
      )
    )
  end

  defp gate(overrides) do
    struct!(
      Gate,
      Keyword.merge(
        [
          id: "0xgate",
          key: tenant_item_id(),
          owner_cap_id: "0xgate-owner",
          type_id: 9_001,
          linked_gate_id: "0xlinked-gate",
          status: assembly_status(:online),
          location: location(),
          energy_source_id: "0xenergy",
          metadata: metadata("Gate One"),
          extension: "0x2::frontier::GateExtension"
        ],
        overrides
      )
    )
  end

  defp network_node(overrides) do
    struct!(
      NetworkNode,
      Keyword.merge(
        [
          id: "0xnode",
          key: tenant_item_id(),
          owner_cap_id: "0xnode-owner",
          type_id: 501,
          status: assembly_status(:online),
          location: location(),
          fuel: fuel([]),
          energy_source: energy_source(),
          metadata: metadata("Node One"),
          connected_assembly_ids: ["0xassembly-a", "0xassembly-b"]
        ],
        overrides
      )
    )
  end

  defp storage_unit(overrides) do
    struct!(
      StorageUnit,
      Keyword.merge(
        [
          id: "0xstorage",
          key: tenant_item_id(),
          owner_cap_id: "0xstorage-owner",
          type_id: 700,
          status: assembly_status(:online),
          location: location(),
          inventory_keys: ["0xinv-1", "0xinv-2"],
          energy_source_id: "0xenergy",
          metadata: metadata("Storage One"),
          extension: "0x2::frontier::StorageExtension"
        ],
        overrides
      )
    )
  end

  defp fuel(overrides) do
    now = System.os_time(:millisecond)

    struct!(
      Fuel,
      Keyword.merge(
        [
          max_capacity: 5_000,
          burn_rate_in_ms: 1_000,
          type_id: 42,
          unit_volume: 2,
          quantity: 50,
          is_burning: true,
          previous_cycle_elapsed_time: 0,
          burn_start_time: now,
          last_updated: now
        ],
        overrides
      )
    )
  end

  defp energy_source do
    %EnergySource{
      max_energy_production: 10_000,
      current_energy_production: 2_500,
      total_reserved_energy: 1_250
    }
  end

  defp metadata(name) do
    %Metadata{
      assembly_id: "0xmetadata",
      name: name,
      description: "Test metadata",
      url: "https://example.test/assemblies/#{String.downcase(String.replace(name, " ", "-"))}"
    }
  end

  defp owner_cap_type do
    "#{@world_package_id}::access::OwnerCap"
  end

  defp owner_address do
    "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  end

  defp owner_caps_page(owner_caps) do
    %{data: owner_caps, has_next_page: false, end_cursor: nil}
  end

  defp owner_cap_json(assembly_id) do
    %{
      "id" => uid("0xownercap-#{String.trim_leading(assembly_id, "0x")}"),
      "authorized_object_id" => assembly_id
    }
  end

  defp assembly_json(overrides) do
    Map.merge(
      %{
        "id" => uid("0xassembly"),
        "key" => %{"item_id" => "8", "tenant" => "0xassembly-tenant"},
        "owner_cap_id" => uid("0xassembly-owner"),
        "type_id" => "77",
        "status" => %{"status" => "OFFLINE"},
        "location" => %{"location_hash" => :binary.bin_to_list(location_hash())},
        "energy_source_id" => "0xassembly-energy",
        "metadata" => %{
          "assembly_id" => "0xassembly-metadata",
          "name" => "Assembly One",
          "description" => "A test assembly",
          "url" => "https://example.test/assemblies/1"
        }
      },
      overrides
    )
  end

  defp network_node_json(overrides) do
    Map.merge(
      %{
        "id" => uid("0xnode"),
        "key" => %{"item_id" => "9", "tenant" => "0xnode-tenant"},
        "owner_cap_id" => uid("0xnode-owner"),
        "type_id" => "501",
        "status" => %{"status" => "ONLINE"},
        "location" => %{"location_hash" => :binary.bin_to_list(location_hash())},
        "fuel" => fuel_json(%{}),
        "energy_source" => %{
          "max_energy_production" => "10000",
          "current_energy_production" => "2500",
          "total_reserved_energy" => "1250"
        },
        "metadata" => %{
          "assembly_id" => "0xnode-metadata",
          "name" => "Node One",
          "description" => "Network node",
          "url" => "https://example.test/nodes/1"
        },
        "connected_assembly_ids" => ["0xassembly-a", "0xassembly-b"]
      },
      overrides
    )
  end

  defp fuel_json(overrides) do
    Map.merge(
      %{
        "max_capacity" => "5000",
        "burn_rate_in_ms" => "100",
        "type_id" => "42",
        "unit_volume" => "2",
        "quantity" => "50",
        "is_burning" => true,
        "previous_cycle_elapsed_time" => "7",
        "burn_start_time" => "8",
        "last_updated" => "9"
      },
      overrides
    )
  end

  defp tenant_item_id do
    %TenantItemId{item_id: 7, tenant: "0xtenant"}
  end

  defp assembly_status(status) do
    %AssemblyStatus{status: status}
  end

  defp location do
    %Location{location_hash: location_hash()}
  end

  defp location_hash do
    :binary.copy(<<7>>, 32)
  end

  defp uid(id), do: %{"id" => id}

  defp unique_pubsub_name do
    :"assembly_monitor_pubsub_#{System.unique_integer([:positive])}"
  end

  defp unique_registry_name do
    :"assembly_monitor_registry_#{System.unique_integer([:positive])}"
  end
end
