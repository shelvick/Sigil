defmodule FrontierOS.Sui.TypesTest do
  @moduledoc """
  Captures the packet 2 JSON parsing contract for Sui type structs.
  """

  use ExUnit.Case, async: true

  alias FrontierOS.Sui.Types

  test "parses TenantItemId with string-to-integer conversion" do
    tenant_item_id = Types.TenantItemId.from_json(%{"item_id" => "42", "tenant" => "0xtenant"})

    assert is_struct(tenant_item_id, FrontierOS.Sui.Types.TenantItemId)
    assert tenant_item_id.item_id == 42
    assert tenant_item_id.tenant == "0xtenant"
  end

  test "parses AssemblyStatus enum values to atoms" do
    null_status = Types.AssemblyStatus.from_json(%{"status" => "NULL"})
    assert is_struct(null_status, FrontierOS.Sui.Types.AssemblyStatus)
    assert null_status.status == :null

    offline_status = Types.AssemblyStatus.from_json(%{"status" => "OFFLINE"})
    assert is_struct(offline_status, FrontierOS.Sui.Types.AssemblyStatus)
    assert offline_status.status == :offline

    online_status = Types.AssemblyStatus.from_json(%{"status" => "ONLINE"})
    assert is_struct(online_status, FrontierOS.Sui.Types.AssemblyStatus)
    assert online_status.status == :online

    variant_online = Types.AssemblyStatus.from_json(%{"status" => %{"@variant" => "ONLINE"}})
    assert variant_online.status == :online

    variant_offline = Types.AssemblyStatus.from_json(%{"status" => %{"@variant" => "OFFLINE"}})
    assert variant_offline.status == :offline
  end

  test "parses Gate with nested structs and optional fields" do
    gate = Types.Gate.from_json(gate_json())

    assert is_struct(gate, FrontierOS.Sui.Types.Gate)
    assert gate.id == "0xgate"
    assert gate.key.item_id == 7
    assert gate.key.tenant == "0xtenant"
    assert gate.owner_cap_id == "0xownercap"
    assert gate.type_id == 9001
    assert gate.linked_gate_id == "0xlinked"
    assert gate.status.status == :online
    assert gate.location.location_hash == location_hash()
    assert gate.energy_source_id == "0xenergy"
    assert gate.metadata.assembly_id == "0xassembly"
    assert gate.metadata.name == "Jump Gate Alpha"
    assert gate.extension == "0x2::frontier::GateExtension"
  end

  test "parses Assembly from JSON" do
    assembly = Types.Assembly.from_json(assembly_json())

    assert is_struct(assembly, FrontierOS.Sui.Types.Assembly)
    assert assembly.id == "0xassembly"
    assert assembly.key.item_id == 8
    assert assembly.owner_cap_id == "0xassembly-owner"
    assert assembly.type_id == 77
    assert assembly.status.status == :offline
    assert assembly.location.location_hash == location_hash()
    assert assembly.energy_source_id == "0xassembly-energy"
    assert assembly.metadata.name == "Assembly One"
  end

  test "parses NetworkNode with nested Fuel and EnergySource" do
    network_node = Types.NetworkNode.from_json(network_node_json())

    assert is_struct(network_node, FrontierOS.Sui.Types.NetworkNode)
    assert network_node.id == "0xnode"
    assert network_node.key.item_id == 9
    assert network_node.status.status == :online
    assert network_node.fuel.max_capacity == 5_000
    assert network_node.fuel.burn_rate_in_ms == 100
    assert network_node.fuel.type_id == 42
    assert network_node.fuel.unit_volume == 2
    assert network_node.fuel.quantity == 50
    assert network_node.fuel.is_burning
    assert network_node.fuel.previous_cycle_elapsed_time == 7
    assert network_node.fuel.burn_start_time == 8
    assert network_node.fuel.last_updated == 9
    assert network_node.energy_source.max_energy_production == 10_000
    assert network_node.energy_source.current_energy_production == 2_500
    assert network_node.energy_source.total_reserved_energy == 1_250
    assert network_node.connected_assembly_ids == ["0xassembly-a", "0xassembly-b"]
  end

  test "parses Character with integer tribe_id" do
    character = Types.Character.from_json(character_json())

    assert is_struct(character, FrontierOS.Sui.Types.Character)
    assert character.id == "0xcharacter"
    assert character.key.item_id == 10
    assert character.tribe_id == 314
    assert character.character_address == "0xcharacter-address"
    assert character.owner_cap_id == "0xcharacter-owner"
    assert character.metadata.name == "Pilot One"
  end

  test "maps null JSON values to nil for optional fields" do
    gate =
      Types.Gate.from_json(
        gate_json(%{
          "linked_gate_id" => nil,
          "energy_source_id" => nil,
          "metadata" => nil,
          "extension" => nil
        })
      )

    assert gate.linked_gate_id == nil
    assert gate.energy_source_id == nil
    assert gate.metadata == nil
    assert gate.extension == nil
  end

  test "parses present optional Metadata as nested struct" do
    metadata =
      Types.Assembly.from_json(assembly_json())
      |> Map.fetch!(:metadata)

    assert is_struct(metadata, FrontierOS.Sui.Types.Metadata)
    assert metadata.assembly_id == "0xassembly-metadata"
    assert metadata.name == "Assembly One"
    assert metadata.description == "A test assembly"
    assert metadata.url == "https://example.test/assemblies/1"
  end

  test "parses Turret and StorageUnit from JSON" do
    turret = Types.Turret.from_json(turret_json())
    storage_unit = Types.StorageUnit.from_json(storage_unit_json())

    assert is_struct(turret, FrontierOS.Sui.Types.Turret)
    assert turret.id == "0xturret"
    assert turret.extension == "0x2::frontier::TurretExtension"
    assert turret.metadata.name == "Defense Turret"

    assert is_struct(storage_unit, FrontierOS.Sui.Types.StorageUnit)
    assert storage_unit.id == "0xstorage"
    assert storage_unit.inventory_keys == ["0xinv-1", "0xinv-2"]
    assert storage_unit.extension == "0x2::frontier::StorageExtension"
  end

  test "parses vector fields as lists" do
    network_node = Types.NetworkNode.from_json(network_node_json())
    storage_unit = Types.StorageUnit.from_json(storage_unit_json())

    assert network_node.connected_assembly_ids == ["0xassembly-a", "0xassembly-b"]
    assert storage_unit.inventory_keys == ["0xinv-1", "0xinv-2"]
  end

  test "parses GraphQL byte-vector and string scalar representations" do
    location =
      Types.Location.from_json(%{"location_hash" => :binary.bin_to_list(location_hash())})

    character = Types.Character.from_json(character_json())
    turret = Types.Turret.from_json(turret_json())

    assert is_struct(location, FrontierOS.Sui.Types.Location)
    binary_hash = location.location_hash
    assert binary_hash == location_hash()
    assert byte_size(binary_hash) == 32
    assert character.character_address == "0xcharacter-address"
    assert turret.extension == "0x2::frontier::TurretExtension"
  end

  test "Parser.integer!/1 rejects negative string values" do
    assert_raise ArgumentError, ~r/non-negative integer/, fn ->
      Types.TenantItemId.from_json(%{"item_id" => "-1", "tenant" => "0xtenant"})
    end
  end

  test "Location.from_json/1 accepts variable-length location hashes" do
    loc_32 = Types.Location.from_json(%{"location_hash" => :binary.copy(<<7>>, 32)})
    assert byte_size(loc_32.location_hash) == 32

    loc_44 = Types.Location.from_json(%{"location_hash" => :binary.copy(<<7>>, 44)})
    assert byte_size(loc_44.location_hash) == 44
  end

  defp gate_json(overrides \\ %{}) do
    Map.merge(
      %{
        "id" => uid("0xgate"),
        "key" => %{"item_id" => "7", "tenant" => "0xtenant"},
        "owner_cap_id" => uid("0xownercap"),
        "type_id" => "9001",
        "linked_gate_id" => "0xlinked",
        "status" => %{"status" => "ONLINE"},
        "location" => %{"location_hash" => :binary.bin_to_list(location_hash())},
        "energy_source_id" => "0xenergy",
        "metadata" => %{
          "assembly_id" => "0xassembly",
          "name" => "Jump Gate Alpha",
          "description" => "Gate description",
          "url" => "https://example.test/gates/alpha"
        },
        "extension" => "0x2::frontier::GateExtension"
      },
      overrides
    )
  end

  defp assembly_json(overrides \\ %{}) do
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

  defp network_node_json(overrides \\ %{}) do
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

  defp character_json(overrides \\ %{}) do
    Map.merge(
      %{
        "id" => uid("0xcharacter"),
        "key" => %{"item_id" => "10", "tenant" => "0xcharacter-tenant"},
        "tribe_id" => "314",
        "character_address" => "0xcharacter-address",
        "metadata" => %{
          "assembly_id" => "0xcharacter-metadata",
          "name" => "Pilot One",
          "description" => "Character metadata",
          "url" => "https://example.test/characters/1"
        },
        "owner_cap_id" => uid("0xcharacter-owner")
      },
      overrides
    )
  end

  defp turret_json(overrides \\ %{}) do
    Map.merge(
      %{
        "id" => uid("0xturret"),
        "key" => %{"item_id" => "11", "tenant" => "0xturret-tenant"},
        "owner_cap_id" => uid("0xturret-owner"),
        "type_id" => "777",
        "status" => %{"status" => "ONLINE"},
        "location" => %{"location_hash" => :binary.bin_to_list(location_hash())},
        "energy_source_id" => "0xturret-energy",
        "metadata" => %{
          "assembly_id" => "0xturret-metadata",
          "name" => "Defense Turret",
          "description" => "Turret metadata",
          "url" => "https://example.test/turrets/1"
        },
        "extension" => "0x2::frontier::TurretExtension"
      },
      overrides
    )
  end

  defp storage_unit_json(overrides \\ %{}) do
    Map.merge(
      %{
        "id" => uid("0xstorage"),
        "key" => %{"item_id" => "12", "tenant" => "0xstorage-tenant"},
        "owner_cap_id" => uid("0xstorage-owner"),
        "type_id" => "888",
        "status" => %{"status" => "NULL"},
        "location" => %{"location_hash" => :binary.bin_to_list(location_hash())},
        "inventory_keys" => ["0xinv-1", "0xinv-2"],
        "energy_source_id" => nil,
        "metadata" => %{
          "assembly_id" => "0xstorage-metadata",
          "name" => "Storage Unit",
          "description" => "Storage metadata",
          "url" => "https://example.test/storage/1"
        },
        "extension" => "0x2::frontier::StorageExtension"
      },
      overrides
    )
  end

  defp location_hash do
    <<0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24,
      25, 26, 27, 28, 29, 30, 31>>
  end

  defp uid(value), do: %{"id" => value}
end
