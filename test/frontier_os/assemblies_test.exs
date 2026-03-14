defmodule FrontierOS.AssembliesTest do
  @moduledoc """
  Covers the packet 2 assemblies context contract from the approved spec.
  """

  use ExUnit.Case, async: true

  import Hammox

  alias FrontierOS.{Assemblies, Cache}
  alias FrontierOS.Sui.Types

  @world_package_id "0xtest_world"

  setup :verify_on_exit!

  setup do
    cache_pid = start_supervised!({Cache, tables: [:assemblies]})
    pubsub = unique_pubsub_name()

    start_supervised!({Phoenix.PubSub, name: pubsub})

    {:ok, tables: Cache.tables(cache_pid), pubsub: pubsub, owner_cap_type: owner_cap_type()}
  end

  describe "discover_for_owner/2" do
    test "discover_for_owner/2 queries OwnerCaps from chain", %{
      tables: tables,
      pubsub: pubsub,
      owner_cap_type: owner_cap_type
    } do
      owner = owner_address()

      expect(FrontierOS.Sui.ClientMock, :get_objects, fn [type: ^owner_cap_type, owner: ^owner],
                                                         [] ->
        {:ok, owner_caps_page([])}
      end)

      assert {:ok, []} = Assemblies.discover_for_owner(owner, tables: tables, pubsub: pubsub)
      verify!()
    end

    test "discover_for_owner/2 resolves OwnerCap IDs to assemblies", %{
      tables: tables,
      pubsub: pubsub,
      owner_cap_type: owner_cap_type
    } do
      owner = owner_address()
      gate_id = "0xassembly-gate"
      turret_id = "0xassembly-turret"

      expect(FrontierOS.Sui.ClientMock, :get_objects, fn [type: ^owner_cap_type, owner: ^owner],
                                                         [] ->
        {:ok, owner_caps_page([owner_cap_json(gate_id), owner_cap_json(turret_id)])}
      end)

      expect(FrontierOS.Sui.ClientMock, :get_object, 2, fn assembly_id, [] ->
        send(self(), {:assembly_fetched, assembly_id})

        case assembly_id do
          ^gate_id -> {:ok, gate_json(%{"id" => uid(gate_id)})}
          ^turret_id -> {:ok, turret_json(%{"id" => uid(turret_id)})}
        end
      end)

      assert {:ok, assemblies} =
               Assemblies.discover_for_owner(owner, tables: tables, pubsub: pubsub)

      assert Enum.map(assemblies, & &1.id) |> Enum.sort() == [gate_id, turret_id]
      assert_receive {:assembly_fetched, ^gate_id}
      assert_receive {:assembly_fetched, ^turret_id}
      verify!()
    end

    test "discover_for_owner/2 parses Gate assemblies", %{
      tables: tables,
      pubsub: pubsub,
      owner_cap_type: owner_cap_type
    } do
      owner = owner_address()
      gate_id = "0xgate-assembly"

      expect(FrontierOS.Sui.ClientMock, :get_objects, fn [type: ^owner_cap_type, owner: ^owner],
                                                         [] ->
        {:ok, owner_caps_page([owner_cap_json(gate_id)])}
      end)

      expect(FrontierOS.Sui.ClientMock, :get_object, fn ^gate_id, [] ->
        {:ok, gate_json(%{"id" => uid(gate_id)})}
      end)

      assert {:ok, [%Types.Gate{id: ^gate_id} = gate]} =
               Assemblies.discover_for_owner(owner, tables: tables, pubsub: pubsub)

      assert gate.linked_gate_id == "0xlinked"
      verify!()
    end

    test "discover_for_owner/2 parses Turret assemblies", %{
      tables: tables,
      pubsub: pubsub,
      owner_cap_type: owner_cap_type
    } do
      owner = owner_address()
      turret_id = "0xturret-assembly"

      expect(FrontierOS.Sui.ClientMock, :get_objects, fn [type: ^owner_cap_type, owner: ^owner],
                                                         [] ->
        {:ok, owner_caps_page([owner_cap_json(turret_id)])}
      end)

      expect(FrontierOS.Sui.ClientMock, :get_object, fn ^turret_id, [] ->
        {:ok, turret_json(%{"id" => uid(turret_id)})}
      end)

      assert {:ok, [%Types.Turret{id: ^turret_id} = turret]} =
               Assemblies.discover_for_owner(owner, tables: tables, pubsub: pubsub)

      assert turret.extension == "0x2::frontier::TurretExtension"
      verify!()
    end

    test "discover_for_owner/2 caches assemblies in ETS", %{
      tables: tables,
      pubsub: pubsub,
      owner_cap_type: owner_cap_type
    } do
      owner = owner_address()
      assembly_id = "0xassembly-cache"

      expect(FrontierOS.Sui.ClientMock, :get_objects, fn [type: ^owner_cap_type, owner: ^owner],
                                                         [] ->
        {:ok, owner_caps_page([owner_cap_json(assembly_id)])}
      end)

      expect(FrontierOS.Sui.ClientMock, :get_object, fn ^assembly_id, [] ->
        {:ok, assembly_json(%{"id" => uid(assembly_id)})}
      end)

      assert {:ok, [%Types.Assembly{} = assembly]} =
               Assemblies.discover_for_owner(owner, tables: tables, pubsub: pubsub)

      assert Cache.get(tables.assemblies, assembly_id) == {owner, assembly}
      verify!()
    end

    test "discover_for_owner/2 broadcasts assemblies_discovered", %{
      tables: tables,
      pubsub: pubsub,
      owner_cap_type: owner_cap_type
    } do
      owner = owner_address()
      assembly_id = "0xassembly-broadcast"
      :ok = Phoenix.PubSub.subscribe(pubsub, "assemblies:#{owner}")

      expect(FrontierOS.Sui.ClientMock, :get_objects, fn [type: ^owner_cap_type, owner: ^owner],
                                                         [] ->
        {:ok, owner_caps_page([owner_cap_json(assembly_id)])}
      end)

      expect(FrontierOS.Sui.ClientMock, :get_object, fn ^assembly_id, [] ->
        {:ok, assembly_json(%{"id" => uid(assembly_id)})}
      end)

      assert {:ok, [assembly]} =
               Assemblies.discover_for_owner(owner, tables: tables, pubsub: pubsub)

      assert_receive {:assemblies_discovered, [^assembly]}
      verify!()
    end

    test "discover_for_owner/2 returns error on chain failure", %{
      tables: tables,
      pubsub: pubsub,
      owner_cap_type: owner_cap_type
    } do
      owner = owner_address()
      :ok = Phoenix.PubSub.subscribe(pubsub, "assemblies:#{owner}")

      expect(FrontierOS.Sui.ClientMock, :get_objects, fn [type: ^owner_cap_type, owner: ^owner],
                                                         [] ->
        {:error, :timeout}
      end)

      assert Assemblies.discover_for_owner(owner, tables: tables, pubsub: pubsub) ==
               {:error, :timeout}

      assert Cache.match(tables.assemblies, {:_, {owner, :_}}) == []
      refute_receive {:assemblies_discovered, _assemblies}
      verify!()
    end

    test "discover_for_owner/2 returns empty list when no OwnerCaps", %{
      tables: tables,
      pubsub: pubsub,
      owner_cap_type: owner_cap_type
    } do
      owner = owner_address()

      expect(FrontierOS.Sui.ClientMock, :get_objects, fn [type: ^owner_cap_type, owner: ^owner],
                                                         [] ->
        {:ok, owner_caps_page([])}
      end)

      assert {:ok, []} = Assemblies.discover_for_owner(owner, tables: tables, pubsub: pubsub)
      verify!()
    end

    test "discover_for_owner/2 parses NetworkNode assemblies", %{
      tables: tables,
      pubsub: pubsub,
      owner_cap_type: owner_cap_type
    } do
      owner = owner_address()
      assembly_id = "0xnetwork-node"

      expect(FrontierOS.Sui.ClientMock, :get_objects, fn [type: ^owner_cap_type, owner: ^owner],
                                                         [] ->
        {:ok, owner_caps_page([owner_cap_json(assembly_id)])}
      end)

      expect(FrontierOS.Sui.ClientMock, :get_object, fn ^assembly_id, [] ->
        {:ok, network_node_json(%{"id" => uid(assembly_id)})}
      end)

      assert {:ok, [%Types.NetworkNode{id: ^assembly_id} = network_node]} =
               Assemblies.discover_for_owner(owner, tables: tables, pubsub: pubsub)

      assert network_node.fuel.quantity == 50
      verify!()
    end

    test "discover_for_owner/2 parses StorageUnit assemblies", %{
      tables: tables,
      pubsub: pubsub,
      owner_cap_type: owner_cap_type
    } do
      owner = owner_address()
      assembly_id = "0xstorage-unit"

      expect(FrontierOS.Sui.ClientMock, :get_objects, fn [type: ^owner_cap_type, owner: ^owner],
                                                         [] ->
        {:ok, owner_caps_page([owner_cap_json(assembly_id)])}
      end)

      expect(FrontierOS.Sui.ClientMock, :get_object, fn ^assembly_id, [] ->
        {:ok, storage_unit_json(%{"id" => uid(assembly_id)})}
      end)

      assert {:ok, [%Types.StorageUnit{id: ^assembly_id} = storage_unit]} =
               Assemblies.discover_for_owner(owner, tables: tables, pubsub: pubsub)

      assert storage_unit.inventory_keys == ["0xinv-1", "0xinv-2"]
      verify!()
    end

    test "discover_for_owner/2 caches partial results on fetch failure", %{
      tables: tables,
      pubsub: pubsub,
      owner_cap_type: owner_cap_type
    } do
      owner = owner_address()
      good_id = "0xassembly-good"
      bad_id = "0xassembly-missing"

      expect(FrontierOS.Sui.ClientMock, :get_objects, fn [type: ^owner_cap_type, owner: ^owner],
                                                         [] ->
        {:ok, owner_caps_page([owner_cap_json(good_id), owner_cap_json(bad_id)])}
      end)

      expect(FrontierOS.Sui.ClientMock, :get_object, 2, fn assembly_id, [] ->
        case assembly_id do
          ^good_id -> {:ok, gate_json(%{"id" => uid(good_id)})}
          ^bad_id -> {:error, :not_found}
        end
      end)

      assert {:ok, [%Types.Gate{id: ^good_id} = gate]} =
               Assemblies.discover_for_owner(owner, tables: tables, pubsub: pubsub)

      assert Cache.get(tables.assemblies, good_id) == {owner, gate}
      assert Cache.get(tables.assemblies, bad_id) == nil
      verify!()
    end
  end

  describe "list_for_owner/2" do
    test "list_for_owner/2 returns cached assemblies", %{tables: tables} do
      owner = owner_address()
      gate = Types.Gate.from_json(gate_json(%{"id" => uid("0xlist-gate")}))
      turret = Types.Turret.from_json(turret_json(%{"id" => uid("0xlist-turret")}))

      Cache.put(tables.assemblies, gate.id, {owner, gate})
      Cache.put(tables.assemblies, turret.id, {owner, turret})
      Cache.put(tables.assemblies, "0xother-owner", {other_owner_address(), gate})

      assert Assemblies.list_for_owner(owner, tables: tables)
             |> Enum.map(& &1.id)
             |> Enum.sort() == [gate.id, turret.id]
    end

    test "list_for_owner/2 returns empty list for unknown owner", %{tables: tables} do
      owner = owner_address()

      Cache.put(
        tables.assemblies,
        "0xother-assembly",
        {other_owner_address(), Types.Assembly.from_json(assembly_json())}
      )

      assert Assemblies.list_for_owner(owner, tables: tables) == []
    end
  end

  describe "get_assembly/2" do
    test "get_assembly/2 returns cached assembly", %{tables: tables} do
      assembly = Types.Assembly.from_json(assembly_json())
      Cache.put(tables.assemblies, assembly.id, {owner_address(), assembly})

      assert Assemblies.get_assembly(assembly.id, tables: tables) == {:ok, assembly}
    end

    test "get_assembly/2 returns error for unknown ID", %{tables: tables} do
      assert Assemblies.get_assembly("0xmissing-assembly", tables: tables) == {:error, :not_found}
    end
  end

  describe "sync_assembly/2" do
    test "sync_assembly/2 refreshes assembly from chain", %{tables: tables, pubsub: pubsub} do
      owner = owner_address()
      assembly_id = "0xsync-assembly"

      cached =
        Types.Assembly.from_json(assembly_json(%{"id" => uid(assembly_id), "type_id" => "77"}))

      refreshed_json = assembly_json(%{"id" => uid(assembly_id), "type_id" => "99"})

      Cache.put(tables.assemblies, assembly_id, {owner, cached})

      expect(FrontierOS.Sui.ClientMock, :get_object, fn ^assembly_id, [] ->
        {:ok, refreshed_json}
      end)

      assert {:ok, %Types.Assembly{} = refreshed} =
               Assemblies.sync_assembly(assembly_id, tables: tables, pubsub: pubsub)

      assert refreshed.type_id == 99
      assert Cache.get(tables.assemblies, assembly_id) == {owner, refreshed}
      verify!()
    end

    test "sync_assembly/2 broadcasts assembly_updated", %{tables: tables, pubsub: pubsub} do
      owner = owner_address()
      assembly_id = "0xsync-broadcast"
      cached = Types.Assembly.from_json(assembly_json(%{"id" => uid(assembly_id)}))
      :ok = Phoenix.PubSub.subscribe(pubsub, "assembly:#{assembly_id}")

      Cache.put(tables.assemblies, assembly_id, {owner, cached})

      expect(FrontierOS.Sui.ClientMock, :get_object, fn ^assembly_id, [] ->
        {:ok, gate_json(%{"id" => uid(assembly_id)})}
      end)

      assert {:ok, updated} =
               Assemblies.sync_assembly(assembly_id, tables: tables, pubsub: pubsub)

      assert_receive {:assembly_updated, ^updated}
      verify!()
    end

    test "sync_assembly/2 returns error for uncached assembly", %{tables: tables, pubsub: pubsub} do
      expect(FrontierOS.Sui.ClientMock, :get_object, 0, fn _assembly_id, _opts ->
        {:ok, assembly_json()}
      end)

      assert Assemblies.sync_assembly("0xmissing-assembly", tables: tables, pubsub: pubsub) ==
               {:error, :not_found}

      verify!()
    end
  end

  @tag :acceptance
  test "full discovery flow: discover -> list -> get returns consistent data", %{
    tables: tables,
    pubsub: pubsub,
    owner_cap_type: owner_cap_type
  } do
    owner = owner_address()
    gate_id = "0xacceptance-gate"
    generic_id = "0xacceptance-assembly"
    node_id = "0xacceptance-node"

    expect(FrontierOS.Sui.ClientMock, :get_objects, fn [type: ^owner_cap_type, owner: ^owner],
                                                       [] ->
      {:ok,
       owner_caps_page([
         owner_cap_json(gate_id),
         owner_cap_json(generic_id),
         owner_cap_json(node_id)
       ])}
    end)

    expect(FrontierOS.Sui.ClientMock, :get_object, 3, fn assembly_id, [] ->
      case assembly_id do
        ^gate_id -> {:ok, gate_json(%{"id" => uid(gate_id)})}
        ^generic_id -> {:ok, assembly_json(%{"id" => uid(generic_id)})}
        ^node_id -> {:ok, network_node_json(%{"id" => uid(node_id)})}
      end
    end)

    assert {:ok, discovered} =
             Assemblies.discover_for_owner(owner, tables: tables, pubsub: pubsub)

    listed = Assemblies.list_for_owner(owner, tables: tables)
    expected_ids = Enum.sort([gate_id, generic_id, node_id])

    assert Enum.map(discovered, & &1.id) |> Enum.sort() == expected_ids
    assert Enum.map(listed, & &1.id) |> Enum.sort() == expected_ids

    assert {:ok, %Types.Gate{id: ^gate_id}} = Assemblies.get_assembly(gate_id, tables: tables)

    assert {:ok, %Types.Assembly{id: ^generic_id}} =
             Assemblies.get_assembly(generic_id, tables: tables)

    assert {:ok, %Types.NetworkNode{id: ^node_id}} =
             Assemblies.get_assembly(node_id, tables: tables)

    refute discovered == []
    refute listed == []
    verify!()
  end

  defp owner_cap_type do
    "#{@world_package_id}::access_control::OwnerCap"
  end

  defp unique_pubsub_name do
    :"assemblies_pubsub_#{System.unique_integer([:positive])}"
  end

  defp owner_address do
    "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  end

  defp other_owner_address do
    "0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
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

  defp gate_json(overrides) do
    Map.merge(
      %{
        "id" => uid("0xgate"),
        "key" => %{"item_id" => "7", "tenant" => "0xtenant"},
        "owner_cap_id" => uid("0xgate-owner"),
        "type_id" => "9001",
        "linked_gate_id" => "0xlinked",
        "status" => %{"status" => "ONLINE"},
        "location" => %{"location_hash" => :binary.bin_to_list(location_hash())},
        "energy_source_id" => "0xenergy",
        "metadata" => %{
          "assembly_id" => "0xgate-metadata",
          "name" => "Jump Gate Alpha",
          "description" => "Gate description",
          "url" => "https://example.test/gates/alpha"
        },
        "extension" => "0x2::frontier::GateExtension"
      },
      overrides
    )
  end

  defp assembly_json, do: assembly_json(%{})

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
        "fuel" => %{
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

  defp turret_json(overrides) do
    Map.merge(
      %{
        "id" => uid("0xturret"),
        "key" => %{"item_id" => "11", "tenant" => "0xturret-tenant"},
        "owner_cap_id" => uid("0xturret-owner"),
        "type_id" => "612",
        "status" => %{"status" => "ONLINE"},
        "location" => %{"location_hash" => :binary.bin_to_list(location_hash())},
        "energy_source_id" => "0xturret-energy",
        "metadata" => %{
          "assembly_id" => "0xturret-metadata",
          "name" => "Defense Turret",
          "description" => "Turret description",
          "url" => "https://example.test/turrets/1"
        },
        "extension" => "0x2::frontier::TurretExtension"
      },
      overrides
    )
  end

  defp storage_unit_json(overrides) do
    Map.merge(
      %{
        "id" => uid("0xstorage"),
        "key" => %{"item_id" => "12", "tenant" => "0xstorage-tenant"},
        "owner_cap_id" => uid("0xstorage-owner"),
        "type_id" => "700",
        "status" => %{"status" => "ONLINE"},
        "location" => %{"location_hash" => :binary.bin_to_list(location_hash())},
        "inventory_keys" => ["0xinv-1", "0xinv-2"],
        "energy_source_id" => "0xstorage-energy",
        "metadata" => %{
          "assembly_id" => "0xstorage-metadata",
          "name" => "Storage One",
          "description" => "Storage description",
          "url" => "https://example.test/storage/1"
        },
        "extension" => "0x2::frontier::StorageExtension"
      },
      overrides
    )
  end

  defp location_hash do
    :binary.copy(<<7>>, 32)
  end

  defp uid(id), do: %{"id" => id}
end
