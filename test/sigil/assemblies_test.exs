defmodule Sigil.AssembliesTest do
  @moduledoc """
  Covers the packet 2 assemblies context contract from the approved spec.
  """

  use ExUnit.Case, async: true

  import Hammox

  alias Sigil.{Assemblies, Cache}
  alias Sigil.Sui.{TransactionBuilder, TxGateExtension, Types}

  @world_package_id "0x1111111111111111111111111111111111111111111111111111111111111111"

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

      expect(Sigil.Sui.ClientMock, :get_objects, fn [type: ^owner_cap_type, owner: ^owner], [] ->
        {:ok, owner_caps_page([])}
      end)

      assert {:ok, []} =
               Assemblies.discover_for_owner(owner,
                 tables: tables,
                 pubsub: pubsub,
                 character_ids: [owner]
               )

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

      expect(Sigil.Sui.ClientMock, :get_objects, fn [type: ^owner_cap_type, owner: ^owner], [] ->
        {:ok, owner_caps_page([owner_cap_json(gate_id), owner_cap_json(turret_id)])}
      end)

      expect(Sigil.Sui.ClientMock, :get_object, 2, fn assembly_id, [] ->
        send(self(), {:assembly_fetched, assembly_id})

        case assembly_id do
          ^gate_id -> {:ok, gate_json(%{"id" => uid(gate_id)})}
          ^turret_id -> {:ok, turret_json(%{"id" => uid(turret_id)})}
        end
      end)

      assert {:ok, assemblies} =
               Assemblies.discover_for_owner(owner,
                 tables: tables,
                 pubsub: pubsub,
                 character_ids: [owner]
               )

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

      expect(Sigil.Sui.ClientMock, :get_objects, fn [type: ^owner_cap_type, owner: ^owner], [] ->
        {:ok, owner_caps_page([owner_cap_json(gate_id)])}
      end)

      expect(Sigil.Sui.ClientMock, :get_object, fn ^gate_id, [] ->
        {:ok, gate_json(%{"id" => uid(gate_id)})}
      end)

      assert {:ok, [%Types.Gate{id: ^gate_id} = gate]} =
               Assemblies.discover_for_owner(owner,
                 tables: tables,
                 pubsub: pubsub,
                 character_ids: [owner]
               )

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

      expect(Sigil.Sui.ClientMock, :get_objects, fn [type: ^owner_cap_type, owner: ^owner], [] ->
        {:ok, owner_caps_page([owner_cap_json(turret_id)])}
      end)

      expect(Sigil.Sui.ClientMock, :get_object, fn ^turret_id, [] ->
        {:ok, turret_json(%{"id" => uid(turret_id)})}
      end)

      assert {:ok, [%Types.Turret{id: ^turret_id} = turret]} =
               Assemblies.discover_for_owner(owner,
                 tables: tables,
                 pubsub: pubsub,
                 character_ids: [owner]
               )

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

      expect(Sigil.Sui.ClientMock, :get_objects, fn [type: ^owner_cap_type, owner: ^owner], [] ->
        {:ok, owner_caps_page([owner_cap_json(assembly_id)])}
      end)

      expect(Sigil.Sui.ClientMock, :get_object, fn ^assembly_id, [] ->
        {:ok, assembly_json(%{"id" => uid(assembly_id)})}
      end)

      assert {:ok, [%Types.Assembly{} = assembly]} =
               Assemblies.discover_for_owner(owner,
                 tables: tables,
                 pubsub: pubsub,
                 character_ids: [owner]
               )

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

      expect(Sigil.Sui.ClientMock, :get_objects, fn [type: ^owner_cap_type, owner: ^owner], [] ->
        {:ok, owner_caps_page([owner_cap_json(assembly_id)])}
      end)

      expect(Sigil.Sui.ClientMock, :get_object, fn ^assembly_id, [] ->
        {:ok, assembly_json(%{"id" => uid(assembly_id)})}
      end)

      assert {:ok, [assembly]} =
               Assemblies.discover_for_owner(owner,
                 tables: tables,
                 pubsub: pubsub,
                 character_ids: [owner]
               )

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

      expect(Sigil.Sui.ClientMock, :get_objects, fn [type: ^owner_cap_type, owner: ^owner], [] ->
        {:error, :timeout}
      end)

      assert Assemblies.discover_for_owner(owner,
               tables: tables,
               pubsub: pubsub,
               character_ids: [owner]
             ) ==
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

      expect(Sigil.Sui.ClientMock, :get_objects, fn [type: ^owner_cap_type, owner: ^owner], [] ->
        {:ok, owner_caps_page([])}
      end)

      assert {:ok, []} =
               Assemblies.discover_for_owner(owner,
                 tables: tables,
                 pubsub: pubsub,
                 character_ids: [owner]
               )

      verify!()
    end

    test "discover_for_owner/2 parses NetworkNode assemblies", %{
      tables: tables,
      pubsub: pubsub,
      owner_cap_type: owner_cap_type
    } do
      owner = owner_address()
      assembly_id = "0xnetwork-node"

      expect(Sigil.Sui.ClientMock, :get_objects, fn [type: ^owner_cap_type, owner: ^owner], [] ->
        {:ok, owner_caps_page([owner_cap_json(assembly_id)])}
      end)

      expect(Sigil.Sui.ClientMock, :get_object, fn ^assembly_id, [] ->
        {:ok, network_node_json(%{"id" => uid(assembly_id)})}
      end)

      assert {:ok, [%Types.NetworkNode{id: ^assembly_id} = network_node]} =
               Assemblies.discover_for_owner(owner,
                 tables: tables,
                 pubsub: pubsub,
                 character_ids: [owner]
               )

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

      expect(Sigil.Sui.ClientMock, :get_objects, fn [type: ^owner_cap_type, owner: ^owner], [] ->
        {:ok, owner_caps_page([owner_cap_json(assembly_id)])}
      end)

      expect(Sigil.Sui.ClientMock, :get_object, fn ^assembly_id, [] ->
        {:ok, storage_unit_json(%{"id" => uid(assembly_id)})}
      end)

      assert {:ok, [%Types.StorageUnit{id: ^assembly_id} = storage_unit]} =
               Assemblies.discover_for_owner(owner,
                 tables: tables,
                 pubsub: pubsub,
                 character_ids: [owner]
               )

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

      expect(Sigil.Sui.ClientMock, :get_objects, fn [type: ^owner_cap_type, owner: ^owner], [] ->
        {:ok, owner_caps_page([owner_cap_json(good_id), owner_cap_json(bad_id)])}
      end)

      expect(Sigil.Sui.ClientMock, :get_object, 2, fn assembly_id, [] ->
        case assembly_id do
          ^good_id -> {:ok, gate_json(%{"id" => uid(good_id)})}
          ^bad_id -> {:error, :not_found}
        end
      end)

      assert {:ok, [%Types.Gate{id: ^good_id} = gate]} =
               Assemblies.discover_for_owner(owner,
                 tables: tables,
                 pubsub: pubsub,
                 character_ids: [owner]
               )

      assert Cache.get(tables.assemblies, good_id) == {owner, gate}
      assert Cache.get(tables.assemblies, bad_id) == nil
      verify!()
    end

    test "discover_for_owner/2 aggregates OwnerCaps across multiple characters", %{
      tables: tables,
      pubsub: pubsub,
      owner_cap_type: owner_cap_type
    } do
      owner = owner_address()
      char_a = "0xcharacter-a"
      char_b = "0xcharacter-b"
      gate_id = "0xgate-multi"
      node_id = "0xnode-multi"

      expect(Sigil.Sui.ClientMock, :get_objects, 2, fn
        [type: ^owner_cap_type, owner: ^char_a], [] ->
          {:ok, owner_caps_page([owner_cap_json(gate_id)])}

        [type: ^owner_cap_type, owner: ^char_b], [] ->
          {:ok, owner_caps_page([owner_cap_json(node_id)])}
      end)

      expect(Sigil.Sui.ClientMock, :get_object, 2, fn
        ^gate_id, [] -> {:ok, gate_json(%{"id" => uid(gate_id)})}
        ^node_id, [] -> {:ok, network_node_json(%{"id" => uid(node_id)})}
      end)

      assert {:ok, assemblies} =
               Assemblies.discover_for_owner(owner,
                 tables: tables,
                 pubsub: pubsub,
                 character_ids: [char_a, char_b]
               )

      assert length(assemblies) == 2
      ids = Enum.map(assemblies, & &1.id) |> Enum.sort()
      assert ids == Enum.sort([gate_id, node_id])
      assert Cache.get(tables.assemblies, gate_id) != nil
      assert Cache.get(tables.assemblies, node_id) != nil
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

  describe "assembly_owned_by?/3" do
    test "assembly_owned_by?/3 returns true for matching owner", %{tables: tables} do
      owner = owner_address()
      gate_id = hex_id(16)
      gate = Types.Gate.from_json(gate_json(%{"id" => uid(gate_id)}))

      Cache.put(tables.assemblies, gate_id, {owner, gate})

      assert Assemblies.assembly_owned_by?(gate_id, owner, tables: tables)
    end

    test "assembly_owned_by?/3 returns false for mismatched or unknown owner", %{tables: tables} do
      gate_id = hex_id(17)
      gate = Types.Gate.from_json(gate_json(%{"id" => uid(gate_id)}))

      Cache.put(tables.assemblies, gate_id, {owner_address(), gate})

      refute Assemblies.assembly_owned_by?(gate_id, other_owner_address(), tables: tables)
      refute Assemblies.assembly_owned_by?(hex_id(18), owner_address(), tables: tables)
    end
  end

  describe "build_authorize_gate_extension_tx/3" do
    test "build_authorize_gate_extension_tx/3 queries OwnerCap reference from chain", %{
      tables: tables
    } do
      owner = owner_address()
      gate_id = hex_id(33)
      character_id = hex_id(34)
      owner_cap_id = hex_id(35)

      gate =
        Types.Gate.from_json(
          gate_json(%{
            "id" => uid(gate_id),
            "owner_cap_id" => uid(owner_cap_id),
            "extension" => nil
          })
        )

      Cache.put(tables.assemblies, gate_id, {owner, gate})

      expect(Sigil.Sui.ClientMock, :get_object_with_ref, 3, fn object_id, [] ->
        send(self(), {:object_with_ref_requested, object_id})
        {:ok, object_with_ref(object_id, 7, 41, 81)}
      end)

      assert {:ok, %{tx_bytes: tx_bytes}} =
               Assemblies.build_authorize_gate_extension_tx(gate_id, character_id, tables: tables)

      assert is_binary(tx_bytes)
      assert_receive {:object_with_ref_requested, ^owner_cap_id}
      assert_receive {:object_with_ref_requested, ^character_id}
      assert_receive {:object_with_ref_requested, ^gate_id}
      verify!()
    end

    test "build_authorize_gate_extension_tx/3 queries shared metadata", %{tables: tables} do
      owner = owner_address()
      gate_id = hex_id(36)
      character_id = hex_id(37)
      owner_cap_id = hex_id(38)

      gate =
        Types.Gate.from_json(
          gate_json(%{
            "id" => uid(gate_id),
            "owner_cap_id" => uid(owner_cap_id),
            "extension" => nil
          })
        )

      Cache.put(tables.assemblies, gate_id, {owner, gate})

      expect(Sigil.Sui.ClientMock, :get_object_with_ref, 3, fn
        ^owner_cap_id, [] -> {:ok, owner_cap_with_ref(owner_cap_id, 12, 82)}
        ^character_id, [] -> {:ok, object_with_ref(character_id, 5, 42, 83)}
        ^gate_id, [] -> {:ok, object_with_ref(gate_id, 9, 43, 84)}
      end)

      assert {:ok, %{tx_bytes: tx_bytes}} =
               Assemblies.build_authorize_gate_extension_tx(gate_id, character_id, tables: tables)

      assert tx_bytes ==
               expected_gate_extension_tx_bytes(
                 gate_id,
                 9,
                 owner_cap_id,
                 12,
                 digest_bytes(82),
                 character_id,
                 5
               )

      verify!()
    end

    test "build_authorize_gate_extension_tx/3 returns Base64-encoded tx bytes", %{tables: tables} do
      owner = owner_address()
      gate_id = hex_id(39)
      character_id = hex_id(40)
      owner_cap_id = hex_id(41)

      gate =
        Types.Gate.from_json(
          gate_json(%{
            "id" => uid(gate_id),
            "owner_cap_id" => uid(owner_cap_id),
            "extension" => nil
          })
        )

      Cache.put(tables.assemblies, gate_id, {owner, gate})

      expect(Sigil.Sui.ClientMock, :get_object_with_ref, 3, fn
        ^owner_cap_id, [] -> {:ok, owner_cap_with_ref(owner_cap_id, 14, 85)}
        ^character_id, [] -> {:ok, object_with_ref(character_id, 6, 44, 86)}
        ^gate_id, [] -> {:ok, object_with_ref(gate_id, 10, 45, 87)}
      end)

      assert {:ok, %{tx_bytes: tx_bytes}} =
               Assemblies.build_authorize_gate_extension_tx(gate_id, character_id, tables: tables)

      assert tx_bytes ==
               expected_gate_extension_tx_bytes(
                 gate_id,
                 10,
                 owner_cap_id,
                 14,
                 digest_bytes(85),
                 character_id,
                 6
               )

      assert is_binary(Base.decode64!(tx_bytes))
      verify!()
    end

    test "build_authorize_gate_extension_tx/3 stores pending tx metadata in ETS", %{
      tables: tables
    } do
      owner = owner_address()
      gate_id = hex_id(42)
      character_id = hex_id(43)
      owner_cap_id = hex_id(44)

      gate =
        Types.Gate.from_json(
          gate_json(%{
            "id" => uid(gate_id),
            "owner_cap_id" => uid(owner_cap_id),
            "extension" => nil
          })
        )

      Cache.put(tables.assemblies, gate_id, {owner, gate})

      expect(Sigil.Sui.ClientMock, :get_object_with_ref, 3, fn
        ^owner_cap_id, [] -> {:ok, owner_cap_with_ref(owner_cap_id, 15, 88)}
        ^character_id, [] -> {:ok, object_with_ref(character_id, 7, 46, 89)}
        ^gate_id, [] -> {:ok, object_with_ref(gate_id, 11, 47, 90)}
      end)

      assert {:ok, %{tx_bytes: tx_bytes}} =
               Assemblies.build_authorize_gate_extension_tx(gate_id, character_id, tables: tables)

      assert Cache.get(tables.assemblies, {:pending_ext_tx, tx_bytes}) ==
               {:authorize_gate_extension, gate_id}

      verify!()
    end

    test "build_authorize_gate_extension_tx/3 returns error for non-gate assembly", %{
      tables: tables
    } do
      turret_id = hex_id(45)
      turret = Types.Turret.from_json(turret_json(%{"id" => uid(turret_id)}))

      Cache.put(tables.assemblies, turret_id, {owner_address(), turret})

      expect(Sigil.Sui.ClientMock, :get_object_with_ref, 0, fn _object_id, _opts ->
        {:ok, owner_cap_with_ref(hex_id(46), 1, 1)}
      end)

      assert Assemblies.build_authorize_gate_extension_tx(turret_id, hex_id(47), tables: tables) ==
               {:error, :not_a_gate}

      verify!()
    end

    test "build_authorize_gate_extension_tx/3 returns error for unknown assembly", %{
      tables: tables
    } do
      expect(Sigil.Sui.ClientMock, :get_object_with_ref, 0, fn _object_id, _opts ->
        {:ok, owner_cap_with_ref(hex_id(48), 1, 1)}
      end)

      assert Assemblies.build_authorize_gate_extension_tx(hex_id(49), hex_id(50), tables: tables) ==
               {:error, :not_found}

      verify!()
    end

    test "build_authorize_gate_extension_tx/3 returns error on OwnerCap failure", %{
      tables: tables
    } do
      owner = owner_address()
      gate_id = hex_id(51)
      character_id = hex_id(52)
      owner_cap_id = hex_id(53)

      gate =
        Types.Gate.from_json(
          gate_json(%{
            "id" => uid(gate_id),
            "owner_cap_id" => uid(owner_cap_id),
            "extension" => nil
          })
        )

      Cache.put(tables.assemblies, gate_id, {owner, gate})

      expect(Sigil.Sui.ClientMock, :get_object_with_ref, fn ^owner_cap_id, [] ->
        {:error, :timeout}
      end)

      assert Assemblies.build_authorize_gate_extension_tx(gate_id, character_id, tables: tables) ==
               {:error, :timeout}

      verify!()
    end

    test "build_authorize_gate_extension_tx/3 returns error on Character failure", %{
      tables: tables
    } do
      owner = owner_address()
      gate_id = hex_id(54)
      character_id = hex_id(55)
      owner_cap_id = hex_id(56)

      gate =
        Types.Gate.from_json(
          gate_json(%{
            "id" => uid(gate_id),
            "owner_cap_id" => uid(owner_cap_id),
            "extension" => nil
          })
        )

      Cache.put(tables.assemblies, gate_id, {owner, gate})

      expect(Sigil.Sui.ClientMock, :get_object_with_ref, 2, fn
        ^owner_cap_id, [] -> {:ok, owner_cap_with_ref(owner_cap_id, 16, 91)}
        ^character_id, [] -> {:error, :not_found}
      end)

      assert Assemblies.build_authorize_gate_extension_tx(gate_id, character_id, tables: tables) ==
               {:error, :not_found}

      verify!()
    end

    test "build_authorize_gate_extension_tx/3 returns error on Gate failure", %{tables: tables} do
      owner = owner_address()
      gate_id = hex_id(57)
      character_id = hex_id(58)
      owner_cap_id = hex_id(59)

      gate =
        Types.Gate.from_json(
          gate_json(%{
            "id" => uid(gate_id),
            "owner_cap_id" => uid(owner_cap_id),
            "extension" => nil
          })
        )

      Cache.put(tables.assemblies, gate_id, {owner, gate})

      expect(Sigil.Sui.ClientMock, :get_object_with_ref, 3, fn
        ^owner_cap_id, [] -> {:ok, owner_cap_with_ref(owner_cap_id, 17, 92)}
        ^character_id, [] -> {:ok, object_with_ref(character_id, 8, 48, 93)}
        ^gate_id, [] -> {:error, :invalid_response}
      end)

      assert Assemblies.build_authorize_gate_extension_tx(gate_id, character_id, tables: tables) ==
               {:error, :invalid_response}

      verify!()
    end

    test "build_authorize_gate_extension_tx/3 passes fetched refs to tx builder", %{
      tables: tables
    } do
      owner = owner_address()
      gate_id = hex_id(60)
      character_id = hex_id(61)
      owner_cap_id = hex_id(62)

      gate =
        Types.Gate.from_json(
          gate_json(%{
            "id" => uid(gate_id),
            "owner_cap_id" => uid(owner_cap_id),
            "extension" => nil
          })
        )

      Cache.put(tables.assemblies, gate_id, {owner, gate})

      expect(Sigil.Sui.ClientMock, :get_object_with_ref, 3, fn
        ^owner_cap_id, [] -> {:ok, owner_cap_with_ref(owner_cap_id, 18, 94)}
        ^character_id, [] -> {:ok, object_with_ref(character_id, 9, 49, 95)}
        ^gate_id, [] -> {:ok, object_with_ref(gate_id, 13, 50, 96)}
      end)

      assert {:ok, %{tx_bytes: tx_bytes}} =
               Assemblies.build_authorize_gate_extension_tx(gate_id, character_id, tables: tables)

      assert tx_bytes ==
               expected_gate_extension_tx_bytes(
                 gate_id,
                 13,
                 owner_cap_id,
                 18,
                 digest_bytes(94),
                 character_id,
                 9
               )

      verify!()
    end
  end

  describe "submit_signed_extension_tx/3" do
    test "submit_signed_extension_tx/3 executes transaction on chain", %{tables: tables} do
      tx_bytes = Base.encode64("gate-extension-kind")
      signature = "wallet-signature"

      expect(Sigil.Sui.ClientMock, :execute_transaction, fn ^tx_bytes, [^signature], [] ->
        send(self(), {:transaction_executed, tx_bytes, signature})

        {:ok,
         %{
           "status" => "SUCCESS",
           "transaction" => %{"digest" => "digest-1"},
           "bcs" => "effects-bcs-1"
         }}
      end)

      assert {:ok, %{digest: "digest-1", effects_bcs: "effects-bcs-1"}} =
               Assemblies.submit_signed_extension_tx(tx_bytes, signature, tables: tables)

      assert_receive {:transaction_executed, ^tx_bytes, ^signature}
      verify!()
    end

    test "submit_signed_extension_tx/3 syncs gate from chain on success", %{tables: tables} do
      owner = owner_address()
      gate_id = hex_id(63)
      tx_bytes = Base.encode64("pending-gate-extension-kind")
      signature = "wallet-signature"
      cached_gate = Types.Gate.from_json(gate_json(%{"id" => uid(gate_id), "extension" => nil}))

      refreshed_gate =
        Types.Gate.from_json(gate_json(%{"id" => uid(gate_id), "extension" => hex_id(97)}))

      Cache.put(tables.assemblies, gate_id, {owner, cached_gate})

      Cache.put(
        tables.assemblies,
        {:pending_ext_tx, tx_bytes},
        {:authorize_gate_extension, gate_id}
      )

      expect(Sigil.Sui.ClientMock, :execute_transaction, fn ^tx_bytes, [^signature], [] ->
        {:ok,
         %{
           "status" => "SUCCESS",
           "transaction" => %{"digest" => "digest-2"},
           "bcs" => "effects-bcs-2"
         }}
      end)

      expect(Sigil.Sui.ClientMock, :get_object, fn ^gate_id, [] ->
        {:ok, gate_json(%{"id" => uid(gate_id), "extension" => refreshed_gate.extension})}
      end)

      assert {:ok, %{digest: "digest-2", effects_bcs: "effects-bcs-2"}} =
               Assemblies.submit_signed_extension_tx(tx_bytes, signature, tables: tables)

      assert Cache.get(tables.assemblies, gate_id) == {owner, refreshed_gate}
      assert Cache.get(tables.assemblies, {:pending_ext_tx, tx_bytes}) == nil
      verify!()
    end

    test "submit_signed_extension_tx/3 returns error on chain failure", %{tables: tables} do
      gate_id = hex_id(64)
      tx_bytes = Base.encode64("failing-gate-extension-kind")
      signature = "wallet-signature"

      Cache.put(
        tables.assemblies,
        {:pending_ext_tx, tx_bytes},
        {:authorize_gate_extension, gate_id}
      )

      expect(Sigil.Sui.ClientMock, :execute_transaction, fn ^tx_bytes, [^signature], [] ->
        {:error, :timeout}
      end)

      expect(Sigil.Sui.ClientMock, :get_object, 0, fn _gate_id, _opts ->
        {:ok, gate_json(%{})}
      end)

      assert Assemblies.submit_signed_extension_tx(tx_bytes, signature, tables: tables) ==
               {:error, :timeout}

      assert Cache.get(tables.assemblies, {:pending_ext_tx, tx_bytes}) ==
               {:authorize_gate_extension, gate_id}

      verify!()
    end

    test "submit_signed_extension_tx/3 ignores missing pending metadata", %{tables: tables} do
      tx_bytes = Base.encode64("orphaned-gate-extension-kind")
      signature = "wallet-signature"

      expect(Sigil.Sui.ClientMock, :execute_transaction, fn ^tx_bytes, [^signature], [] ->
        {:ok,
         %{
           "status" => "SUCCESS",
           "transaction" => %{"digest" => "digest-3"},
           "bcs" => "effects-bcs-3"
         }}
      end)

      expect(Sigil.Sui.ClientMock, :get_object, 0, fn _gate_id, _opts ->
        {:ok, gate_json(%{})}
      end)

      assert {:ok, %{digest: "digest-3", effects_bcs: "effects-bcs-3"}} =
               Assemblies.submit_signed_extension_tx(tx_bytes, signature, tables: tables)

      assert Cache.get(tables.assemblies, {:pending_ext_tx, tx_bytes}) == nil
      verify!()
    end
  end

  @tag :acceptance
  test "full flow: build gate extension tx -> submit -> gate extension updated in cache", %{
    tables: tables,
    pubsub: pubsub,
    owner_cap_type: owner_cap_type
  } do
    owner = owner_address()
    gate_id = hex_id(65)
    character_id = hex_id(66)
    owner_cap_id = hex_id(67)
    signature = "wallet-sig"

    discovered_gate =
      Types.Gate.from_json(
        gate_json(%{
          "id" => uid(gate_id),
          "owner_cap_id" => uid(owner_cap_id),
          "extension" => nil
        })
      )

    updated_gate =
      Types.Gate.from_json(
        gate_json(%{
          "id" => uid(gate_id),
          "owner_cap_id" => uid(owner_cap_id),
          "extension" => hex_id(98)
        })
      )

    expect(Sigil.Sui.ClientMock, :get_objects, fn [type: ^owner_cap_type, owner: ^character_id],
                                                  [] ->
      {:ok, owner_caps_page([owner_cap_json(gate_id)])}
    end)

    get_object_call_count = :counters.new(1, [])

    expect(Sigil.Sui.ClientMock, :get_object, 2, fn
      ^gate_id, [] ->
        :ok = :counters.add(get_object_call_count, 1, 1)

        case :counters.get(get_object_call_count, 1) do
          1 ->
            send(self(), :gate_loaded_from_discovery)

            {:ok,
             gate_json(%{
               "id" => uid(gate_id),
               "owner_cap_id" => uid(owner_cap_id),
               "extension" => nil
             })}

          2 ->
            send(self(), :gate_loaded_after_submit)

            {:ok,
             gate_json(%{
               "id" => uid(gate_id),
               "owner_cap_id" => uid(owner_cap_id),
               "extension" => updated_gate.extension
             })}
        end
    end)

    expect(Sigil.Sui.ClientMock, :get_object_with_ref, 3, fn
      ^owner_cap_id, [] -> {:ok, owner_cap_with_ref(owner_cap_id, 19, 99)}
      ^character_id, [] -> {:ok, object_with_ref(character_id, 10, 51, 100)}
      ^gate_id, [] -> {:ok, object_with_ref(gate_id, 14, 52, 101)}
    end)

    expected_tx_bytes =
      expected_gate_extension_tx_bytes(
        gate_id,
        14,
        owner_cap_id,
        19,
        digest_bytes(99),
        character_id,
        10
      )

    expect(Sigil.Sui.ClientMock, :execute_transaction, fn ^expected_tx_bytes, [^signature], [] ->
      {:ok,
       %{
         "status" => "SUCCESS",
         "transaction" => %{"digest" => "digest-4"},
         "bcs" => "effects-bcs-4"
       }}
    end)

    assert {:ok, [%Types.Gate{id: ^gate_id}]} =
             Assemblies.discover_for_owner(owner,
               tables: tables,
               pubsub: pubsub,
               character_ids: [character_id]
             )

    assert_receive :gate_loaded_from_discovery
    assert {:ok, ^discovered_gate} = Assemblies.get_assembly(gate_id, tables: tables)

    assert {:ok, %{tx_bytes: tx_bytes}} =
             Assemblies.build_authorize_gate_extension_tx(gate_id, character_id, tables: tables)

    assert tx_bytes == expected_tx_bytes

    assert {:ok, %{digest: "digest-4", effects_bcs: "effects-bcs-4"}} =
             Assemblies.submit_signed_extension_tx(tx_bytes, signature, tables: tables)

    assert_receive :gate_loaded_after_submit

    assert {:ok, %Types.Gate{id: ^gate_id} = refreshed_gate} =
             Assemblies.get_assembly(gate_id, tables: tables)

    assert refreshed_gate.extension == updated_gate.extension
    refute refreshed_gate.extension == discovered_gate.extension
    refute refreshed_gate.extension == nil
    verify!()
  end

  describe "sync_assembly/2" do
    test "sync_assembly/2 refreshes assembly from chain", %{tables: tables, pubsub: pubsub} do
      owner = owner_address()
      assembly_id = "0xsync-assembly"

      cached =
        Types.Assembly.from_json(assembly_json(%{"id" => uid(assembly_id), "type_id" => "77"}))

      refreshed_json = assembly_json(%{"id" => uid(assembly_id), "type_id" => "99"})

      Cache.put(tables.assemblies, assembly_id, {owner, cached})

      expect(Sigil.Sui.ClientMock, :get_object, fn ^assembly_id, [] ->
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

      expect(Sigil.Sui.ClientMock, :get_object, fn ^assembly_id, [] ->
        {:ok, gate_json(%{"id" => uid(assembly_id)})}
      end)

      assert {:ok, updated} =
               Assemblies.sync_assembly(assembly_id, tables: tables, pubsub: pubsub)

      assert_receive {:assembly_updated, ^updated}
      verify!()
    end

    test "sync_assembly/2 returns error for uncached assembly", %{tables: tables, pubsub: pubsub} do
      expect(Sigil.Sui.ClientMock, :get_object, 0, fn _assembly_id, _opts ->
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

    expect(Sigil.Sui.ClientMock, :get_objects, fn [type: ^owner_cap_type, owner: ^owner], [] ->
      {:ok,
       owner_caps_page([
         owner_cap_json(gate_id),
         owner_cap_json(generic_id),
         owner_cap_json(node_id)
       ])}
    end)

    expect(Sigil.Sui.ClientMock, :get_object, 3, fn assembly_id, [] ->
      case assembly_id do
        ^gate_id -> {:ok, gate_json(%{"id" => uid(gate_id)})}
        ^generic_id -> {:ok, assembly_json(%{"id" => uid(generic_id)})}
        ^node_id -> {:ok, network_node_json(%{"id" => uid(node_id)})}
      end
    end)

    assert {:ok, discovered} =
             Assemblies.discover_for_owner(owner,
               tables: tables,
               pubsub: pubsub,
               character_ids: [owner]
             )

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

  test "discover_for_owner skips Character objects from OwnerCap query", %{
    tables: tables,
    pubsub: pubsub
  } do
    owner = "0xskip_test_owner"
    owner_cap_type = owner_cap_type()
    character_id = "0xcharacter_obj"
    gate_id = "0xgate_obj"

    expect(Sigil.Sui.ClientMock, :get_objects, fn [type: type, owner: ^owner], []
                                                  when type == owner_cap_type ->
      {:ok,
       %{
         data: [
           %{"authorized_object_id" => character_id},
           %{"authorized_object_id" => gate_id}
         ],
         has_next_page: false,
         end_cursor: nil
       }}
    end)

    expect(Sigil.Sui.ClientMock, :get_object, 2, fn
      ^character_id, [] ->
        {:ok,
         %{
           "id" => character_id,
           "key" => %{"item_id" => "1", "tenant" => "test"},
           "character_address" => "0xcharaddr",
           "tribe_id" => 100,
           "metadata" => %{
             "assembly_id" => character_id,
             "name" => "TestChar",
             "description" => "",
             "url" => ""
           },
           "owner_cap_id" => "0xcap"
         }}

      ^gate_id, [] ->
        {:ok, gate_json(%{"id" => uid(gate_id)})}
    end)

    assert {:ok, assemblies} =
             Assemblies.discover_for_owner(owner,
               tables: tables,
               pubsub: pubsub,
               character_ids: [owner]
             )

    assert length(assemblies) == 1
    assert [%Types.Gate{id: ^gate_id}] = assemblies
  end

  test "discover_for_owner skips unknown non-assembly objects", %{
    tables: tables,
    pubsub: pubsub
  } do
    owner = "0xunknown_skip_owner"
    owner_cap_type = owner_cap_type()
    unknown_id = "0xunknown_obj"

    expect(Sigil.Sui.ClientMock, :get_objects, fn [type: type, owner: ^owner], []
                                                  when type == owner_cap_type ->
      {:ok,
       %{
         data: [%{"authorized_object_id" => unknown_id}],
         has_next_page: false,
         end_cursor: nil
       }}
    end)

    expect(Sigil.Sui.ClientMock, :get_object, fn ^unknown_id, [] ->
      {:ok, %{"id" => unknown_id, "some_field" => "unrecognized"}}
    end)

    assert {:ok, []} =
             Assemblies.discover_for_owner(owner,
               tables: tables,
               pubsub: pubsub,
               character_ids: [owner]
             )
  end

  test "sync_assembly deletes stale cache when object is no longer an assembly", %{
    tables: tables,
    pubsub: pubsub
  } do
    assembly_id = "0xstale_assembly"
    owner = "0xstale_owner"

    Cache.put(
      tables.assemblies,
      assembly_id,
      {owner,
       %Types.Assembly{
         id: assembly_id,
         key: %Types.TenantItemId{item_id: 1, tenant: "test"},
         owner_cap_id: "0xcap",
         type_id: 100,
         status: %Types.AssemblyStatus{status: :online},
         location: %Types.Location{location_hash: <<0::256>>},
         energy_source_id: nil,
         metadata: nil
       }}
    )

    assert {:ok, _} = Assemblies.get_assembly(assembly_id, tables: tables)

    expect(Sigil.Sui.ClientMock, :get_object, fn ^assembly_id, [] ->
      {:ok, %{"id" => assembly_id, "character_address" => "0xchar"}}
    end)

    assert {:error, :not_found} =
             Assemblies.sync_assembly(assembly_id, tables: tables, pubsub: pubsub)

    assert {:error, :not_found} =
             Assemblies.get_assembly(assembly_id, tables: tables)
  end

  defp owner_cap_type do
    "#{@world_package_id}::access::OwnerCap"
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

  defp expected_gate_extension_tx_bytes(
         gate_id,
         gate_shared_version,
         owner_cap_id,
         owner_cap_version,
         owner_cap_digest,
         character_id,
         character_shared_version
       ) do
    %{
      object_id: hex_to_bytes(gate_id),
      initial_shared_version: gate_shared_version
    }
    |> TxGateExtension.build_authorize_extension(
      {hex_to_bytes(owner_cap_id), owner_cap_version, owner_cap_digest},
      %{
        object_id: hex_to_bytes(character_id),
        initial_shared_version: character_shared_version
      }
    )
    |> TransactionBuilder.build_kind!()
    |> Base.encode64()
  end

  defp object_with_ref(object_id, shared_version, ref_version, digest_byte) do
    %{
      json: %{
        "id" => object_id,
        "shared" => %{"initialSharedVersion" => Integer.to_string(shared_version)}
      },
      ref: {hex_to_bytes(object_id), ref_version, digest_bytes(digest_byte)}
    }
  end

  defp owner_cap_with_ref(object_id, ref_version, digest_byte) do
    %{
      json: %{"id" => object_id},
      ref: {hex_to_bytes(object_id), ref_version, digest_bytes(digest_byte)}
    }
  end

  defp digest_bytes(byte), do: :binary.copy(<<byte>>, 32)

  defp hex_id(byte) when is_integer(byte) and byte >= 0 and byte <= 255 do
    "0x" <> String.duplicate(Base.encode16(<<byte>>, case: :lower), 32)
  end

  defp hex_to_bytes("0x" <> hex), do: Base.decode16!(hex, case: :mixed)

  defp location_hash do
    :binary.copy(<<7>>, 32)
  end

  defp uid(id), do: %{"id" => id}
end
