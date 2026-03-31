defmodule Sigil.DiplomacyTest do
  @moduledoc """
  Covers the packet 2 diplomacy context rewrite and TxDiplomacy deletion contract.
  """

  use ExUnit.Case, async: true

  import Hammox

  alias Sigil.{Cache, Diplomacy, Repo}
  alias Sigil.Reputation.ReputationScore
  alias Sigil.Sui.{TransactionBuilder, TxCustodian}

  @sigil_package_id "0x06ce9d6bed77615383575cc7eba4883d32769b30cd5df00561e38434a59611a1"
  @custodian_type "#{@sigil_package_id}::tribe_custodian::Custodian"
  @registry_type "#{@sigil_package_id}::tribe_custodian::TribeCustodianRegistry"
  @source_tribe_id 314
  @other_source_tribe_id 271

  setup :verify_on_exit!

  setup do
    cache_pid = start_supervised!({Cache, tables: [:standings, :reputation]})
    pubsub = unique_pubsub_name()

    start_supervised!({Phoenix.PubSub, name: pubsub})
    :ok = Phoenix.PubSub.subscribe(pubsub, "diplomacy")

    {:ok,
     tables: Cache.tables(cache_pid),
     pubsub: pubsub,
     sender: sender_address(),
     source_tribe_id: @source_tribe_id,
     other_source_tribe_id: @other_source_tribe_id,
     character_id: address(0x44)}
  end

  describe "SVC_TxDiplomacy deletion checks" do
    test "tx_diplomacy module file has been removed" do
      refute File.exists?(tx_diplomacy_source_path())
    end

    test "tx_diplomacy dedicated test file has been removed" do
      refute File.exists?(tx_diplomacy_test_path())
    end

    test "CTX_Diplomacy source no longer references TxDiplomacy" do
      refute File.read!(diplomacy_source_path()) =~ "TxDiplomacy"
    end
  end

  describe "discover_custodian/2" do
    test "discover_custodian returns custodian for tribe", %{
      tables: tables,
      source_tribe_id: tribe_id
    } do
      matching = custodian_object_json(tribe_id: tribe_id, object_id: address(0x51))
      other = custodian_object_json(tribe_id: tribe_id + 1, object_id: address(0x52))

      expect(Sigil.Sui.ClientMock, :get_objects, fn [type: @custodian_type], [] ->
        {:ok, page([other, matching])}
      end)

      assert {:ok, custodian} = Diplomacy.discover_custodian(tribe_id, tables: tables)
      assert custodian.object_id == address(0x51)
      assert custodian.tribe_id == tribe_id
      assert custodian.initial_shared_version == 17
      assert byte_size(custodian.object_id_bytes) == 32
    end

    test "discover_custodian returns nil when no custodian exists", %{
      tables: tables,
      pubsub: pubsub,
      source_tribe_id: tribe_id
    } do
      expect(Sigil.Sui.ClientMock, :get_objects, fn [type: @custodian_type], [] ->
        {:ok, page([custodian_object_json(tribe_id: tribe_id + 1)])}
      end)

      assert Diplomacy.discover_custodian(tribe_id, tables: tables, pubsub: pubsub) == {:ok, nil}
      assert_receive {:custodian_discovered, nil}
    end

    test "discover_custodian auto-sets active custodian and broadcasts", %{
      tables: tables,
      pubsub: pubsub,
      source_tribe_id: tribe_id
    } do
      object = custodian_object_json(tribe_id: tribe_id, object_id: address(0x53))

      expect(Sigil.Sui.ClientMock, :get_objects, fn [type: @custodian_type], [] ->
        {:ok, page([object])}
      end)

      assert {:ok, custodian} =
               Diplomacy.discover_custodian(tribe_id,
                 tables: tables,
                 pubsub: pubsub,
                 tribe_id: tribe_id
               )

      assert Diplomacy.get_active_custodian(tables: tables, tribe_id: tribe_id) == custodian
      assert_receive {:custodian_discovered, ^custodian}
    end

    test "custodian_info includes current_leader from chain data", %{
      tables: tables,
      sender: sender
    } do
      expect(Sigil.Sui.ClientMock, :get_objects, fn [type: @custodian_type], [] ->
        {:ok, page([custodian_object_json(current_leader: sender, object_id: address(0x54))])}
      end)

      assert {:ok, custodian} = Diplomacy.discover_custodian(@source_tribe_id, tables: tables)
      assert custodian.current_leader == sender
    end
  end

  describe "reference resolution" do
    test "resolve_character_ref returns character ref from opts cache or chain", %{
      tables: tables,
      character_id: character_id
    } do
      opts_ref = character_ref(object_id: object_id(0x61), initial_shared_version: 8)
      cached_ref = character_ref(object_id: object_id(0x62), initial_shared_version: 9)
      chain_ref = character_ref(object_id: hex_to_bytes(character_id), initial_shared_version: 10)

      assert Diplomacy.resolve_character_ref(character_id,
               tables: tables,
               character_ref: opts_ref
             ) == {:ok, opts_ref}

      Cache.put(tables.standings, {:character_ref, character_id}, cached_ref)

      assert Diplomacy.resolve_character_ref(character_id, tables: tables) == {:ok, cached_ref}

      Cache.delete(tables.standings, {:character_ref, character_id})

      expect(Sigil.Sui.ClientMock, :get_object_with_ref, fn ^character_id, [] ->
        {:ok, %{json: shared_object_json(character_id, 10), ref: {<<0::256>>, 10, <<0::256>>}}}
      end)

      assert Diplomacy.resolve_character_ref(character_id, tables: tables) == {:ok, chain_ref}
      assert Cache.get(tables.standings, {:character_ref, character_id}) == chain_ref
    end

    test "resolve_registry_ref returns registry ref from opts cache or chain", %{tables: tables} do
      opts_ref = registry_ref(object_id: object_id(0x71), initial_shared_version: 13)
      cached_ref = registry_ref(object_id: object_id(0x72), initial_shared_version: 14)
      chain_ref = registry_ref(object_id: object_id(0x73), initial_shared_version: 15)

      assert Diplomacy.resolve_registry_ref(tables: tables, registry_ref: opts_ref) ==
               {:ok, opts_ref}

      Cache.put(tables.standings, {:registry_ref}, cached_ref)
      assert Diplomacy.resolve_registry_ref(tables: tables) == {:ok, cached_ref}

      Cache.delete(tables.standings, {:registry_ref})

      expect(Sigil.Sui.ClientMock, :get_objects, fn [type: @registry_type], [] ->
        {:ok, page([shared_object_json(address(0x73), 15)])}
      end)

      assert Diplomacy.resolve_registry_ref(tables: tables) == {:ok, chain_ref}
      assert Cache.get(tables.standings, {:registry_ref}) == chain_ref
    end
  end

  describe "standings reads" do
    test "get_standing returns cached standing for known tribe", %{
      tables: tables,
      source_tribe_id: tribe_id
    } do
      Cache.put(tables.standings, {:tribe_standing, tribe_id, 42}, 0)

      assert Diplomacy.get_standing(42, tables: tables, tribe_id: tribe_id) == :hostile
    end

    test "get_standing returns neutral for unknown tribe", %{
      tables: tables,
      source_tribe_id: tribe_id
    } do
      assert Diplomacy.get_standing(999, tables: tables, tribe_id: tribe_id) == :neutral
    end

    test "list_standings returns all cached tribe standings for the active source tribe", %{
      tables: tables,
      source_tribe_id: tribe_id,
      other_source_tribe_id: other_tribe_id
    } do
      Cache.put(tables.standings, {:tribe_standing, tribe_id, 10}, 4)
      Cache.put(tables.standings, {:tribe_standing, tribe_id, 20}, 1)
      Cache.put(tables.standings, {:tribe_standing, other_tribe_id, 30}, 0)

      standings =
        Diplomacy.list_standings(tables: tables, tribe_id: tribe_id)
        |> Enum.sort_by(& &1.tribe_id)

      assert standings == [
               %{tribe_id: 10, standing: :allied},
               %{tribe_id: 20, standing: :unfriendly}
             ]
    end

    test "list_pilot_standings returns all cached pilot overrides for the active source tribe", %{
      tables: tables,
      source_tribe_id: tribe_id,
      other_source_tribe_id: other_tribe_id
    } do
      pilot_one = address(0x81)
      pilot_two = address(0x82)
      other_pilot = address(0x83)

      Cache.put(tables.standings, {:pilot_standing, tribe_id, pilot_two}, 4)
      Cache.put(tables.standings, {:pilot_standing, tribe_id, pilot_one}, 0)
      Cache.put(tables.standings, {:pilot_standing, other_tribe_id, other_pilot}, 1)

      standings =
        Diplomacy.list_pilot_standings(tables: tables, tribe_id: tribe_id)
        |> Enum.sort_by(& &1.pilot)

      assert standings == [
               %{pilot: pilot_one, standing: :hostile},
               %{pilot: pilot_two, standing: :allied}
             ]
    end

    test "get_pilot_standing returns neutral for unknown pilot", %{
      tables: tables,
      source_tribe_id: tribe_id
    } do
      assert Diplomacy.get_pilot_standing(address(0x84), tables: tables, tribe_id: tribe_id) ==
               :neutral
    end

    test "get_default_standing returns cached or neutral default for the active source tribe", %{
      tables: tables,
      source_tribe_id: tribe_id,
      other_source_tribe_id: other_tribe_id
    } do
      assert Diplomacy.get_default_standing(tables: tables, tribe_id: tribe_id) == :neutral

      Cache.put(tables.standings, {:default_standing, other_tribe_id}, 4)
      Cache.put(tables.standings, {:default_standing, tribe_id}, 1)

      assert Diplomacy.get_default_standing(tables: tables, tribe_id: tribe_id) == :unfriendly
    end

    test "standing values map to correct atoms", %{tables: tables, source_tribe_id: tribe_id} do
      Cache.put(tables.standings, {:tribe_standing, tribe_id, 0}, 0)
      Cache.put(tables.standings, {:tribe_standing, tribe_id, 1}, 1)
      Cache.put(tables.standings, {:tribe_standing, tribe_id, 2}, 2)
      Cache.put(tables.standings, {:tribe_standing, tribe_id, 3}, 3)
      Cache.put(tables.standings, {:tribe_standing, tribe_id, 4}, 4)

      mapped =
        Diplomacy.list_standings(tables: tables, tribe_id: tribe_id)
        |> Enum.sort_by(& &1.tribe_id)
        |> Enum.map(& &1.standing)

      assert mapped == [:hostile, :unfriendly, :neutral, :friendly, :allied]
    end
  end

  describe "leader checks" do
    test "leader? returns true when sender matches custodian leader", %{
      tables: tables,
      sender: sender,
      source_tribe_id: tribe_id
    } do
      Cache.put(
        tables.standings,
        {:active_custodian, tribe_id},
        custodian_info(current_leader: sender)
      )

      assert Diplomacy.leader?(tables: tables, tribe_id: tribe_id, sender: sender)
    end

    test "leader? returns false for non-leader", %{tables: tables, source_tribe_id: tribe_id} do
      Cache.put(
        tables.standings,
        {:active_custodian, tribe_id},
        custodian_info(current_leader: address(0x91))
      )

      refute Diplomacy.leader?(tables: tables, tribe_id: tribe_id, sender: address(0x92))
    end

    test "leader? returns false when no active custodian", %{
      tables: tables,
      source_tribe_id: tribe_id
    } do
      refute Diplomacy.leader?(tables: tables, tribe_id: tribe_id, sender: address(0x93))
    end
  end

  describe "active custodian cache" do
    test "active custodian round-trips through cache", %{
      tables: tables,
      source_tribe_id: tribe_id
    } do
      custodian = custodian_info(tribe_id: tribe_id, object_id: address(0x94))

      assert :ok = Diplomacy.set_active_custodian(custodian, tables: tables, tribe_id: tribe_id)
      assert Diplomacy.get_active_custodian(tables: tables, tribe_id: tribe_id) == custodian
    end
  end

  describe "transaction building" do
    test "build_set_standing_tx builds kind bytes via TxCustodian", %{
      tables: tables,
      sender: sender,
      source_tribe_id: tribe_id
    } do
      custodian =
        custodian_info(tribe_id: tribe_id, current_leader: sender, object_id: address(0xA1))

      character = character_ref(object_id: object_id(0xA2), initial_shared_version: 29)

      Cache.put(tables.standings, {:active_custodian, tribe_id}, custodian)

      assert {:ok, %{tx_bytes: tx_bytes}} =
               Diplomacy.build_set_standing_tx(42, 0,
                 tables: tables,
                 tribe_id: tribe_id,
                 sender: sender,
                 character_ref: character
               )

      assert tx_bytes == expected_set_standing_kind_bytes(custodian, character, 42, 0)
      refute File.read!(diplomacy_source_path()) =~ "TxDiplomacy"
    end

    test "build_set_standing_tx errors without active custodian", %{
      tables: tables,
      sender: sender,
      source_tribe_id: tribe_id
    } do
      assert Diplomacy.build_set_standing_tx(42, 0,
               tables: tables,
               tribe_id: tribe_id,
               sender: sender,
               character_ref: character_ref()
             ) == {:error, :no_active_custodian}
    end

    test "build_set_standing_tx errors without character_ref", %{
      tables: tables,
      sender: sender,
      source_tribe_id: tribe_id
    } do
      Cache.put(
        tables.standings,
        {:active_custodian, tribe_id},
        custodian_info(tribe_id: tribe_id)
      )

      assert Diplomacy.build_set_standing_tx(42, 0,
               tables: tables,
               tribe_id: tribe_id,
               sender: sender
             ) == {:error, :no_character_ref}
    end

    test "build_create_custodian_tx produces valid transaction bytes", %{tables: tables} do
      registry = registry_ref(object_id: object_id(0xA3), initial_shared_version: 31)
      character = character_ref(object_id: object_id(0xA4), initial_shared_version: 32)

      assert {:ok, %{tx_bytes: tx_bytes}} =
               Diplomacy.build_create_custodian_tx(
                 tables: tables,
                 tribe_id: 1,
                 registry_ref: registry,
                 character_ref: character
               )

      assert tx_bytes == expected_create_custodian_kind_bytes(registry, character)
    end

    test "build_create_custodian_tx errors without registry_ref", %{tables: tables} do
      character = character_ref(object_id: object_id(0xA5), initial_shared_version: 33)

      expect(Sigil.Sui.ClientMock, :get_objects, fn [type: @registry_type], [] ->
        {:ok, page([])}
      end)

      assert Diplomacy.build_create_custodian_tx(tables: tables, character_ref: character) ==
               {:error, :no_registry_ref}
    end

    test "build_batch_set_standings_tx builds kind bytes", %{
      tables: tables,
      sender: sender,
      source_tribe_id: tribe_id
    } do
      custodian =
        custodian_info(tribe_id: tribe_id, current_leader: sender, object_id: address(0xA6))

      character = character_ref(object_id: object_id(0xA7), initial_shared_version: 34)
      updates = [{1, 0}, {2, 3}, {3, 4}]

      Cache.put(tables.standings, {:active_custodian, tribe_id}, custodian)

      assert {:ok, %{tx_bytes: tx_bytes}} =
               Diplomacy.build_batch_set_standings_tx(updates,
                 tables: tables,
                 tribe_id: tribe_id,
                 sender: sender,
                 character_ref: character
               )

      assert tx_bytes == expected_batch_set_standings_kind_bytes(custodian, character, updates)
    end

    test "build_set_pilot_standing_tx builds kind bytes", %{
      tables: tables,
      sender: sender,
      source_tribe_id: tribe_id
    } do
      custodian =
        custodian_info(tribe_id: tribe_id, current_leader: sender, object_id: address(0xA8))

      character = character_ref(object_id: object_id(0xA9), initial_shared_version: 35)
      pilot = address(0xAA)

      Cache.put(tables.standings, {:active_custodian, tribe_id}, custodian)

      assert {:ok, %{tx_bytes: tx_bytes}} =
               Diplomacy.build_set_pilot_standing_tx(pilot, 1,
                 tables: tables,
                 tribe_id: tribe_id,
                 sender: sender,
                 character_ref: character
               )

      assert tx_bytes == expected_set_pilot_standing_kind_bytes(custodian, character, pilot, 1)
    end

    test "build_set_default_standing_tx builds kind bytes", %{
      tables: tables,
      sender: sender,
      source_tribe_id: tribe_id
    } do
      custodian =
        custodian_info(tribe_id: tribe_id, current_leader: sender, object_id: address(0xAB))

      character = character_ref(object_id: object_id(0xAC), initial_shared_version: 36)

      Cache.put(tables.standings, {:active_custodian, tribe_id}, custodian)

      assert {:ok, %{tx_bytes: tx_bytes}} =
               Diplomacy.build_set_default_standing_tx(4,
                 tables: tables,
                 tribe_id: tribe_id,
                 sender: sender,
                 character_ref: character
               )

      assert tx_bytes == expected_set_default_standing_kind_bytes(custodian, character, 4)
    end

    test "build_batch_set_pilot_standings_tx builds kind bytes", %{
      tables: tables,
      sender: sender,
      source_tribe_id: tribe_id
    } do
      custodian =
        custodian_info(tribe_id: tribe_id, current_leader: sender, object_id: address(0xAD))

      character = character_ref(object_id: object_id(0xAE), initial_shared_version: 37)
      updates = [{address(0xAF), 0}, {address(0xB0), 4}]

      Cache.put(tables.standings, {:active_custodian, tribe_id}, custodian)

      assert {:ok, %{tx_bytes: tx_bytes}} =
               Diplomacy.build_batch_set_pilot_standings_tx(updates,
                 tables: tables,
                 tribe_id: tribe_id,
                 sender: sender,
                 character_ref: character
               )

      assert tx_bytes ==
               expected_batch_set_pilot_standings_kind_bytes(custodian, character, updates)
    end

    test "building tx stores pending operation in cache", %{
      tables: tables,
      sender: sender,
      source_tribe_id: tribe_id
    } do
      custodian =
        custodian_info(tribe_id: tribe_id, current_leader: sender, object_id: address(0xB1))

      character = character_ref(object_id: object_id(0xB2), initial_shared_version: 38)

      Cache.put(tables.standings, {:active_custodian, tribe_id}, custodian)

      assert {:ok, %{tx_bytes: tx_bytes}} =
               Diplomacy.build_set_standing_tx(77, 3,
                 tables: tables,
                 tribe_id: tribe_id,
                 sender: sender,
                 character_ref: character
               )

      assert Cache.get(tables.standings, {:pending_tx, tx_bytes}) ==
               {:set_standing, tribe_id, 77, 3}
    end
  end

  describe "transaction submission" do
    test "submit_signed_transaction updates cache and broadcasts on success", %{
      tables: tables,
      pubsub: pubsub,
      sender: sender,
      source_tribe_id: tribe_id
    } do
      custodian =
        custodian_info(tribe_id: tribe_id, current_leader: sender, object_id: address(0xB3))

      character = character_ref(object_id: object_id(0xB4), initial_shared_version: 39)

      Cache.put(tables.standings, {:active_custodian, tribe_id}, custodian)

      assert {:ok, %{tx_bytes: tx_bytes}} =
               Diplomacy.build_set_standing_tx(42, 0,
                 tables: tables,
                 pubsub: pubsub,
                 tribe_id: tribe_id,
                 sender: sender,
                 character_ref: character
               )

      expect(Sigil.Sui.ClientMock, :execute_transaction, fn ^tx_bytes, ["wallet-signature"], [] ->
        {:ok, success_effects("set-standing-success")}
      end)

      assert {:ok, %{digest: "set-standing-success", effects_bcs: "dGVzdC1lZmZlY3Rz"}} =
               Diplomacy.submit_signed_transaction(tx_bytes, "wallet-signature",
                 tables: tables,
                 pubsub: pubsub,
                 tribe_id: tribe_id,
                 sender: sender
               )

      assert Diplomacy.get_standing(42, tables: tables, tribe_id: tribe_id) == :hostile
      assert_receive {:standing_updated, %{tribe_id: 42, standing: :hostile}}
    end

    test "submit_signed_transaction leaves cache unchanged on error", %{
      tables: tables,
      pubsub: pubsub,
      sender: sender,
      source_tribe_id: tribe_id
    } do
      custodian =
        custodian_info(tribe_id: tribe_id, current_leader: sender, object_id: address(0xB5))

      character = character_ref(object_id: object_id(0xB6), initial_shared_version: 40)

      Cache.put(tables.standings, {:active_custodian, tribe_id}, custodian)
      Cache.put(tables.standings, {:tribe_standing, tribe_id, 42}, 3)

      assert {:ok, %{tx_bytes: tx_bytes}} =
               Diplomacy.build_set_standing_tx(42, 0,
                 tables: tables,
                 pubsub: pubsub,
                 tribe_id: tribe_id,
                 sender: sender,
                 character_ref: character
               )

      expect(Sigil.Sui.ClientMock, :execute_transaction, fn ^tx_bytes, ["wallet-signature"], [] ->
        {:error, {:graphql_errors, [%{"message" => "signature rejected"}]}}
      end)

      assert Diplomacy.submit_signed_transaction(tx_bytes, "wallet-signature",
               tables: tables,
               pubsub: pubsub,
               tribe_id: tribe_id,
               sender: sender
             ) == {:error, {:graphql_errors, [%{"message" => "signature rejected"}]}}

      assert Diplomacy.get_standing(42, tables: tables, tribe_id: tribe_id) == :friendly
      refute_receive {:standing_updated, _}
    end

    test "submit_signed_transaction applies pending operation and broadcasts", %{
      tables: tables,
      pubsub: pubsub,
      sender: sender,
      source_tribe_id: tribe_id
    } do
      custodian =
        custodian_info(tribe_id: tribe_id, current_leader: sender, object_id: address(0xB7))

      character = character_ref(object_id: object_id(0xB8), initial_shared_version: 41)

      Cache.put(tables.standings, {:active_custodian, tribe_id}, custodian)

      assert {:ok, %{tx_bytes: tx_bytes}} =
               Diplomacy.build_set_default_standing_tx(1,
                 tables: tables,
                 pubsub: pubsub,
                 tribe_id: tribe_id,
                 sender: sender,
                 character_ref: character
               )

      expect(Sigil.Sui.ClientMock, :execute_transaction, fn ^tx_bytes, ["wallet-signature"], [] ->
        {:ok, success_effects("default-standing-success")}
      end)

      assert {:ok, %{digest: "default-standing-success", effects_bcs: "dGVzdC1lZmZlY3Rz"}} =
               Diplomacy.submit_signed_transaction(tx_bytes, "wallet-signature",
                 tables: tables,
                 pubsub: pubsub,
                 tribe_id: tribe_id,
                 sender: sender
               )

      assert Cache.get(tables.standings, {:pending_tx, tx_bytes}) == nil
      assert Diplomacy.get_default_standing(tables: tables, tribe_id: tribe_id) == :unfriendly
      assert_receive {:default_standing_updated, :unfriendly}
    end
  end

  describe "governance transaction building" do
    test "build_vote_leader_tx returns tx_bytes for valid candidate", %{
      tables: tables,
      sender: sender,
      source_tribe_id: tribe_id
    } do
      candidate = address(0xB9)

      custodian =
        custodian_info(
          tribe_id: tribe_id,
          current_leader: sender,
          current_leader_votes: 1,
          members: [sender, candidate],
          votes_table_id: address(0xBA),
          vote_tallies_table_id: address(0xBB),
          object_id: address(0xBC)
        )

      character = character_ref(object_id: object_id(0xBD), initial_shared_version: 42)

      Cache.put(tables.standings, {:active_custodian, tribe_id}, custodian)

      assert {:ok, %{tx_bytes: tx_bytes}} =
               Diplomacy.build_vote_leader_tx(candidate,
                 tables: tables,
                 tribe_id: tribe_id,
                 sender: sender,
                 character_ref: character
               )

      assert tx_bytes == expected_vote_leader_kind_bytes(custodian, character, candidate)
      assert Cache.get(tables.standings, {:pending_tx, tx_bytes}) == {:vote_leader, candidate}
      assert Cache.get(tables.standings, {:governance_refresh, tx_bytes}) == tribe_id
    end

    test "build_vote_leader_tx fails without active custodian", %{
      tables: tables,
      sender: sender,
      source_tribe_id: tribe_id
    } do
      assert Diplomacy.build_vote_leader_tx(address(0xBE),
               tables: tables,
               tribe_id: tribe_id,
               sender: sender,
               character_ref: character_ref()
             ) == {:error, :no_active_custodian}
    end

    test "build_claim_leadership_tx returns tx_bytes", %{
      tables: tables,
      sender: sender,
      source_tribe_id: tribe_id
    } do
      custodian =
        custodian_info(
          tribe_id: tribe_id,
          current_leader: address(0xBF),
          current_leader_votes: 1,
          members: [sender, address(0xC0)],
          votes_table_id: address(0xC1),
          vote_tallies_table_id: address(0xC2),
          object_id: address(0xC3)
        )

      character = character_ref(object_id: object_id(0xC4), initial_shared_version: 43)

      Cache.put(tables.standings, {:active_custodian, tribe_id}, custodian)

      assert {:ok, %{tx_bytes: tx_bytes}} =
               Diplomacy.build_claim_leadership_tx(
                 tables: tables,
                 tribe_id: tribe_id,
                 sender: sender,
                 character_ref: character
               )

      assert tx_bytes == expected_claim_leadership_kind_bytes(custodian, character)
      assert Cache.get(tables.standings, {:pending_tx, tx_bytes}) == :claim_leadership
      assert Cache.get(tables.standings, {:governance_refresh, tx_bytes}) == tribe_id
    end

    test "build_claim_leadership_tx fails without custodian", %{
      tables: tables,
      sender: sender,
      source_tribe_id: tribe_id
    } do
      assert Diplomacy.build_claim_leadership_tx(
               tables: tables,
               tribe_id: tribe_id,
               sender: sender,
               character_ref: character_ref()
             ) == {:error, :no_active_custodian}
    end

    test "build_claim_leadership_tx fails without character ref", %{
      tables: tables,
      sender: sender,
      source_tribe_id: tribe_id
    } do
      Cache.put(
        tables.standings,
        {:active_custodian, tribe_id},
        custodian_info(
          tribe_id: tribe_id,
          current_leader: sender,
          current_leader_votes: 2,
          members: [sender],
          votes_table_id: address(0xC5),
          vote_tallies_table_id: address(0xC6),
          object_id: address(0xC7)
        )
      )

      assert Diplomacy.build_claim_leadership_tx(
               tables: tables,
               tribe_id: tribe_id,
               sender: sender
             ) == {:error, :no_character_ref}

      assert Cache.match(tables.standings, {{:pending_tx, :_}, :_}) == []
    end
  end

  describe "governance data loading" do
    test "load_governance_data reads all governance pages", %{
      tables: tables,
      source_tribe_id: tribe_id
    } do
      votes_table_id = address(0xC8)
      tallies_table_id = address(0xC9)
      voter_one = address(0xCA)
      voter_two = address(0xCB)
      candidate_one = address(0xCC)
      candidate_two = address(0xCD)

      Cache.put(
        tables.standings,
        {:active_custodian, tribe_id},
        custodian_info(
          tribe_id: tribe_id,
          current_leader: candidate_one,
          current_leader_votes: 2,
          members: [voter_one, voter_two],
          votes_table_id: votes_table_id,
          vote_tallies_table_id: tallies_table_id,
          object_id: address(0xCE)
        )
      )

      expect(Sigil.Sui.ClientMock, :get_dynamic_fields, 4, fn table_id, opts ->
        case {table_id, opts} do
          {^votes_table_id, []} ->
            {:ok,
             page([dynamic_field_entry(voter_one, candidate_one)],
               has_next_page: true,
               end_cursor: "votes-1"
             )}

          {^votes_table_id, [cursor: "votes-1"]} ->
            {:ok, page([dynamic_field_entry(voter_two, candidate_two)])}

          {^tallies_table_id, []} ->
            {:ok,
             page([dynamic_field_entry(candidate_one, 2, value_type: "u64")],
               has_next_page: true,
               end_cursor: "tallies-1"
             )}

          {^tallies_table_id, [cursor: "tallies-1"]} ->
            {:ok, page([dynamic_field_entry(candidate_two, 1, value_type: "u64")])}
        end
      end)

      assert {:ok, governance_data} =
               Diplomacy.load_governance_data(tables: tables, tribe_id: tribe_id)

      assert governance_data == %{
               votes: %{
                 voter_one => candidate_one,
                 voter_two => candidate_two
               },
               tallies: %{
                 candidate_one => 2,
                 candidate_two => 1
               }
             }
    end

    test "load_governance_data caches governance data in ETS", %{
      tables: tables,
      source_tribe_id: tribe_id
    } do
      votes_table_id = address(0xCF)
      tallies_table_id = address(0xD0)
      candidate = address(0xD1)
      voter = address(0xD2)

      Cache.put(
        tables.standings,
        {:active_custodian, tribe_id},
        custodian_info(
          tribe_id: tribe_id,
          current_leader: candidate,
          current_leader_votes: 1,
          members: [voter],
          votes_table_id: votes_table_id,
          vote_tallies_table_id: tallies_table_id,
          object_id: address(0xD3)
        )
      )

      expect(Sigil.Sui.ClientMock, :get_dynamic_fields, 2, fn table_id, opts ->
        case {table_id, opts} do
          {^votes_table_id, []} ->
            {:ok, page([dynamic_field_entry(voter, candidate)])}

          {^tallies_table_id, []} ->
            {:ok, page([dynamic_field_entry(candidate, 1, value_type: "u64")])}
        end
      end)

      assert {:ok, governance_data} =
               Diplomacy.load_governance_data(tables: tables, tribe_id: tribe_id)

      assert Cache.get(tables.standings, {:governance_data, tribe_id}) == governance_data
    end

    test "load_governance_data fails without partial cache", %{
      tables: tables,
      source_tribe_id: tribe_id
    } do
      votes_table_id = address(0xD4)

      Cache.put(
        tables.standings,
        {:active_custodian, tribe_id},
        custodian_info(
          tribe_id: tribe_id,
          current_leader: address(0xD5),
          current_leader_votes: 1,
          members: [address(0xD6)],
          votes_table_id: votes_table_id,
          vote_tallies_table_id: address(0xD7),
          object_id: address(0xD8)
        )
      )

      expect(Sigil.Sui.ClientMock, :get_dynamic_fields, fn ^votes_table_id, [] ->
        {:error, :timeout}
      end)

      assert Diplomacy.load_governance_data(tables: tables, tribe_id: tribe_id) ==
               {:error, :timeout}

      assert Cache.get(tables.standings, {:governance_data, tribe_id}) == nil
    end

    test "load_governance_data fails without custodian", %{
      tables: tables,
      source_tribe_id: tribe_id
    } do
      assert Diplomacy.load_governance_data(tables: tables, tribe_id: tribe_id) ==
               {:error, :no_active_custodian}
    end

    test "to_custodian_info parses governance ids and leader data" do
      leader = address(0xD9)
      member = address(0xDA)
      votes_table_id = address(0xDB)
      tallies_table_id = address(0xDC)
      object_id = address(0xDD)

      object =
        custodian_object_json(
          object_id: object_id,
          tribe_id: @source_tribe_id,
          current_leader: leader,
          current_leader_votes: 3,
          members: [leader, member],
          votes_table_id: votes_table_id,
          vote_tallies_table_id: tallies_table_id
        )

      assert Sigil.Diplomacy.ObjectCodec.to_custodian_info(object) == %{
               object_id: object_id,
               object_id_bytes: hex_to_bytes(object_id),
               initial_shared_version: 17,
               tribe_id: @source_tribe_id,
               current_leader: leader,
               current_leader_votes: 3,
               members: [leader, member],
               votes_table_id: votes_table_id,
               vote_tallies_table_id: tallies_table_id,
               oracle_address: nil
             }
    end
  end

  describe "governance membership and refresh" do
    test "member? returns true for custodian member and false for non-member", %{
      tables: tables,
      sender: sender,
      source_tribe_id: tribe_id
    } do
      Cache.put(
        tables.standings,
        {:active_custodian, tribe_id},
        custodian_info(
          tribe_id: tribe_id,
          current_leader: address(0xDE),
          current_leader_votes: 1,
          members: [sender, address(0xDF)],
          votes_table_id: address(0xE0),
          vote_tallies_table_id: address(0xE1),
          object_id: address(0xE2)
        )
      )

      assert Diplomacy.member?(tables: tables, tribe_id: tribe_id, sender: sender)
      refute Diplomacy.member?(tables: tables, tribe_id: tribe_id, sender: address(0xE3))
    end

    test "member? returns false without custodian", %{
      tables: tables,
      source_tribe_id: tribe_id
    } do
      refute Diplomacy.member?(tables: tables, tribe_id: tribe_id, sender: address(0xE4))
    end

    test "governance ops broadcast on tribe topic", %{
      tables: tables,
      pubsub: pubsub,
      sender: sender,
      source_tribe_id: tribe_id
    } do
      topic = "diplomacy:#{tribe_id}"
      Phoenix.PubSub.subscribe(pubsub, topic)

      Cache.put(
        tables.standings,
        {:active_custodian, tribe_id},
        custodian_info(
          tribe_id: tribe_id,
          current_leader: sender,
          current_leader_votes: 1,
          members: [sender, address(0xE5)],
          votes_table_id: address(0xE6),
          vote_tallies_table_id: address(0xE7),
          object_id: address(0xE8)
        )
      )

      for {tx_bytes, pending_op, digest} <- [
            {"vote-governance-tx", {:vote_leader, address(0xE5)}, "vote-governance-success"},
            {"claim-governance-tx", :claim_leadership, "claim-governance-success"}
          ] do
        Cache.put(tables.standings, {:pending_tx, tx_bytes}, pending_op)
        Cache.put(tables.standings, {:governance_refresh, tx_bytes}, tribe_id)

        expect(Sigil.Sui.ClientMock, :execute_transaction, fn ^tx_bytes,
                                                              ["wallet-signature"],
                                                              [] ->
          {:ok, success_effects(digest)}
        end)

        expect(Sigil.Sui.ClientMock, :get_objects, fn [type: @custodian_type], [] ->
          {:ok,
           page([
             custodian_object_json(
               object_id: address(0xE8),
               tribe_id: tribe_id,
               current_leader: sender,
               current_leader_votes: 1,
               members: [sender, address(0xE5)],
               votes_table_id: address(0xE6),
               vote_tallies_table_id: address(0xE7),
               initial_shared_version: 17
             )
           ])}
        end)

        votes_table_id = address(0xE6)
        tallies_table_id = address(0xE7)

        expect(Sigil.Sui.ClientMock, :get_dynamic_fields, 2, fn table_id, opts ->
          case {table_id, opts} do
            {^votes_table_id, []} -> {:ok, page([])}
            {^tallies_table_id, []} -> {:ok, page([])}
          end
        end)

        assert {:ok, %{digest: ^digest, effects_bcs: "dGVzdC1lZmZlY3Rz"}} =
                 Diplomacy.submit_signed_transaction(tx_bytes, "wallet-signature",
                   tables: tables,
                   pubsub: pubsub,
                   tribe_id: tribe_id,
                   sender: sender
                 )

        assert_receive {:governance_updated, %{tribe_id: ^tribe_id}}
        refute_receive {:governance_updated, %{tribe_id: ^tribe_id}}
      end

      refute_receive {:standing_updated, _}
    end

    test "vote submission refreshes governance state", %{
      tables: tables,
      pubsub: pubsub,
      sender: sender,
      source_tribe_id: tribe_id
    } do
      topic = "diplomacy:#{tribe_id}"
      Phoenix.PubSub.subscribe(pubsub, topic)

      candidate = address(0xE9)
      votes_table_id = address(0xEA)
      tallies_table_id = address(0xEB)

      Cache.put(
        tables.standings,
        {:active_custodian, tribe_id},
        custodian_info(
          tribe_id: tribe_id,
          current_leader: sender,
          current_leader_votes: 1,
          members: [sender, candidate],
          votes_table_id: votes_table_id,
          vote_tallies_table_id: tallies_table_id,
          object_id: address(0xEC)
        )
      )

      character = character_ref(object_id: object_id(0xED), initial_shared_version: 44)

      assert {:ok, %{tx_bytes: tx_bytes}} =
               Diplomacy.build_vote_leader_tx(candidate,
                 tables: tables,
                 pubsub: pubsub,
                 tribe_id: tribe_id,
                 sender: sender,
                 character_ref: character
               )

      expect(Sigil.Sui.ClientMock, :execute_transaction, fn ^tx_bytes, ["wallet-signature"], [] ->
        {:ok, success_effects("vote-refresh-success")}
      end)

      expect(Sigil.Sui.ClientMock, :get_objects, fn [type: @custodian_type], [] ->
        {:ok,
         page([
           custodian_object_json(
             object_id: address(0xEC),
             tribe_id: tribe_id,
             current_leader: sender,
             current_leader_votes: 2,
             members: [sender, candidate],
             votes_table_id: votes_table_id,
             vote_tallies_table_id: tallies_table_id
           )
         ])}
      end)

      expect(Sigil.Sui.ClientMock, :get_dynamic_fields, 2, fn table_id, opts ->
        case {table_id, opts} do
          {^votes_table_id, []} ->
            {:ok, page([dynamic_field_entry(sender, candidate)])}

          {^tallies_table_id, []} ->
            {:ok, page([dynamic_field_entry(candidate, 2, value_type: "u64")])}
        end
      end)

      assert {:ok, %{digest: "vote-refresh-success", effects_bcs: "dGVzdC1lZmZlY3Rz"}} =
               Diplomacy.submit_signed_transaction(tx_bytes, "wallet-signature",
                 tables: tables,
                 pubsub: pubsub,
                 tribe_id: tribe_id,
                 sender: sender
               )

      assert Cache.get(tables.standings, {:governance_data, tribe_id}) == %{
               votes: %{sender => candidate},
               tallies: %{candidate => 2}
             }

      assert_receive {:governance_updated, %{tribe_id: ^tribe_id}}
    end

    test "failed governance refresh retains marker for retry", %{
      tables: tables,
      pubsub: pubsub,
      sender: sender,
      source_tribe_id: tribe_id
    } do
      votes_table_id = address(0xEE)
      tallies_table_id = address(0xEF)
      candidate = address(0xF0)

      Cache.put(
        tables.standings,
        {:active_custodian, tribe_id},
        custodian_info(
          tribe_id: tribe_id,
          current_leader: sender,
          current_leader_votes: 1,
          members: [sender, candidate],
          votes_table_id: votes_table_id,
          vote_tallies_table_id: tallies_table_id,
          object_id: address(0xF1)
        )
      )

      character = character_ref(object_id: object_id(0xF2), initial_shared_version: 45)

      assert {:ok, %{tx_bytes: tx_bytes}} =
               Diplomacy.build_vote_leader_tx(candidate,
                 tables: tables,
                 pubsub: pubsub,
                 tribe_id: tribe_id,
                 sender: sender,
                 character_ref: character
               )

      expect(Sigil.Sui.ClientMock, :execute_transaction, fn ^tx_bytes, ["wallet-signature"], [] ->
        {:ok, success_effects("vote-refresh-transient-failure")}
      end)

      expect(Sigil.Sui.ClientMock, :get_objects, fn [type: @custodian_type], [] ->
        {:error, :timeout}
      end)

      assert {:ok, %{digest: "vote-refresh-transient-failure", effects_bcs: "dGVzdC1lZmZlY3Rz"}} =
               Diplomacy.submit_signed_transaction(tx_bytes, "wallet-signature",
                 tables: tables,
                 pubsub: pubsub,
                 tribe_id: tribe_id,
                 sender: sender
               )

      assert Cache.get(tables.standings, {:governance_refresh, tx_bytes}) == tribe_id
      assert Cache.get(tables.standings, {:pending_tx, tx_bytes}) == {:vote_leader, candidate}
      assert Cache.get(tables.standings, {:pending_tx_inflight, tx_bytes}) == nil
      assert Cache.get(tables.standings, {:governance_data, tribe_id}) == nil
      refute_receive {:governance_updated, %{tribe_id: ^tribe_id}}
    end

    test "markerless governance fallback clears inflight state", %{
      tables: tables,
      pubsub: pubsub,
      sender: sender,
      source_tribe_id: tribe_id
    } do
      topic = "diplomacy:#{tribe_id}"
      Phoenix.PubSub.subscribe(pubsub, topic)

      tx_bytes = "markerless-claim-tx"
      Cache.put(tables.standings, {:pending_tx, tx_bytes}, :claim_leadership)
      Cache.put(tables.standings, {:pending_tx_inflight, tx_bytes}, :claim_leadership)

      assert :ok =
               Sigil.Diplomacy.PendingOps.apply(
                 tables.standings,
                 [pubsub: pubsub, tribe_id: tribe_id, sender: sender],
                 tx_bytes
               )

      assert Cache.get(tables.standings, {:pending_tx_inflight, tx_bytes}) == nil
      assert_receive {:governance_updated, %{tribe_id: ^tribe_id}}
    end
  end

  describe "tribe name resolution" do
    test "resolve_tribe_names fetches and caches tribe data", %{tables: tables} do
      tribe_id = @source_tribe_id
      custodian = custodian_info()

      expect(Sigil.StaticData.WorldClientMock, :fetch_tribes, fn [] ->
        {:ok, world_tribe_records()}
      end)

      # Set active custodian first — tribe name resolution requires custodian context
      Diplomacy.set_active_custodian(custodian, tables: tables, tribe_id: tribe_id)

      assert {:ok, tribes} = Diplomacy.resolve_tribe_names(tables: tables, tribe_id: tribe_id)

      assert Enum.sort_by(tribes, & &1.id) == [
               %{id: 271, name: "Frontier Defense Union", short_name: "FDU"},
               %{id: 314, name: "Progenitor Collective", short_name: "PGCL"}
             ]

      assert Diplomacy.get_tribe_name(314, tables: tables, tribe_id: tribe_id) == %{
               id: 314,
               name: "Progenitor Collective",
               short_name: "PGCL"
             }
    end

    test "get_tribe_name returns cached tribe or nil", %{tables: tables} do
      Cache.put(tables.standings, {:world_tribe, 314}, %{
        id: 314,
        name: "Progenitor Collective",
        short_name: "PGCL"
      })

      assert Diplomacy.get_tribe_name(314, tables: tables) == %{
               id: 314,
               name: "Progenitor Collective",
               short_name: "PGCL"
             }

      assert Diplomacy.get_tribe_name(999, tables: tables) == nil
    end
  end

  describe "reputation integration" do
    test "pin_standing/3 updates both DB and ETS", %{
      tables: tables,
      source_tribe_id: tribe_id,
      sender: sender
    } do
      owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: false)
      on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)

      target_tribe_id = 808

      Cache.put(
        tables.standings,
        {:active_custodian, tribe_id},
        custodian_info(tribe_id: tribe_id, current_leader: sender)
      )

      assert {:ok, _row} =
               %ReputationScore{}
               |> ReputationScore.changeset(%{
                 source_tribe_id: tribe_id,
                 target_tribe_id: target_tribe_id,
                 score: 120,
                 pinned: false,
                 pinned_standing: nil
               })
               |> Repo.insert()

      assert :ok =
               Diplomacy.pin_standing(target_tribe_id, :friendly,
                 tables: tables,
                 tribe_id: tribe_id,
                 sender: sender
               )

      persisted =
        Repo.get_by!(ReputationScore,
          source_tribe_id: tribe_id,
          target_tribe_id: target_tribe_id
        )

      assert persisted.pinned == true
      assert persisted.pinned_standing == 3

      assert %{
               tribe_id: ^tribe_id,
               target_tribe_id: ^target_tribe_id,
               score: 120,
               pinned: true,
               pinned_standing: :friendly
             } = Cache.get(tables.reputation, {:reputation_score, tribe_id, target_tribe_id})
    end

    test "unpin_standing/2 clears pin in both DB and ETS", %{
      tables: tables,
      source_tribe_id: tribe_id,
      sender: sender
    } do
      owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: false)
      on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)

      target_tribe_id = 809

      Cache.put(
        tables.standings,
        {:active_custodian, tribe_id},
        custodian_info(tribe_id: tribe_id, current_leader: sender)
      )

      assert {:ok, _row} =
               %ReputationScore{}
               |> ReputationScore.changeset(%{
                 source_tribe_id: tribe_id,
                 target_tribe_id: target_tribe_id,
                 score: 240,
                 pinned: true,
                 pinned_standing: 4
               })
               |> Repo.insert()

      Cache.put(tables.reputation, {:reputation_score, tribe_id, target_tribe_id}, %{
        tribe_id: tribe_id,
        target_tribe_id: target_tribe_id,
        score: 240,
        pinned: true,
        pinned_standing: :allied,
        updated_at: DateTime.utc_now()
      })

      assert :ok =
               Diplomacy.unpin_standing(target_tribe_id,
                 tables: tables,
                 tribe_id: tribe_id,
                 sender: sender
               )

      persisted =
        Repo.get_by!(ReputationScore,
          source_tribe_id: tribe_id,
          target_tribe_id: target_tribe_id
        )

      assert persisted.pinned == false
      assert persisted.pinned_standing == nil

      assert %{pinned: false, pinned_standing: nil} =
               Cache.get(tables.reputation, {:reputation_score, tribe_id, target_tribe_id})
    end

    test "pinned?/2 reflects current ETS pin state", %{tables: tables, source_tribe_id: tribe_id} do
      target_tribe_id = 810

      Cache.put(tables.reputation, {:reputation_score, tribe_id, target_tribe_id}, %{
        tribe_id: tribe_id,
        target_tribe_id: target_tribe_id,
        score: 0,
        pinned: true,
        pinned_standing: :neutral,
        updated_at: DateTime.utc_now()
      })

      assert Diplomacy.pinned?(target_tribe_id, tables: tables, tribe_id: tribe_id)

      Cache.put(tables.reputation, {:reputation_score, tribe_id, target_tribe_id}, %{
        tribe_id: tribe_id,
        target_tribe_id: target_tribe_id,
        score: 0,
        pinned: false,
        pinned_standing: nil,
        updated_at: DateTime.utc_now()
      })

      refute Diplomacy.pinned?(target_tribe_id, tables: tables, tribe_id: tribe_id)
    end

    test "get_reputation_score/2 returns score from ETS", %{
      tables: tables,
      source_tribe_id: tribe_id
    } do
      target_tribe_id = 811

      expected = %{
        tribe_id: tribe_id,
        target_tribe_id: target_tribe_id,
        score: -375,
        pinned: true,
        pinned_standing: :hostile,
        updated_at: DateTime.utc_now()
      }

      Cache.put(tables.reputation, {:reputation_score, tribe_id, target_tribe_id}, expected)

      assert Diplomacy.get_reputation_score(target_tribe_id, tables: tables, tribe_id: tribe_id) ==
               expected
    end

    test "list_reputation_scores/1 returns all tribe scores", %{
      tables: tables,
      source_tribe_id: tribe_id,
      other_source_tribe_id: other_tribe_id
    } do
      Cache.put(tables.reputation, {:reputation_score, tribe_id, 1}, %{
        tribe_id: tribe_id,
        target_tribe_id: 1,
        score: 100,
        pinned: false,
        pinned_standing: nil,
        updated_at: DateTime.utc_now()
      })

      Cache.put(tables.reputation, {:reputation_score, tribe_id, 2}, %{
        tribe_id: tribe_id,
        target_tribe_id: 2,
        score: -50,
        pinned: true,
        pinned_standing: :hostile,
        updated_at: DateTime.utc_now()
      })

      Cache.put(tables.reputation, {:reputation_score, other_tribe_id, 3}, %{
        tribe_id: other_tribe_id,
        target_tribe_id: 3,
        score: 999,
        pinned: false,
        pinned_standing: nil,
        updated_at: DateTime.utc_now()
      })

      scores =
        Diplomacy.list_reputation_scores(tables: tables, tribe_id: tribe_id)
        |> Enum.sort_by(& &1.target_tribe_id)

      assert Enum.map(scores, &{&1.target_tribe_id, &1.score, &1.pinned}) == [
               {1, 100, false},
               {2, -50, true}
             ]
    end

    test "set_oracle_address/3 builds set_oracle transaction", %{
      tables: tables,
      sender: sender,
      source_tribe_id: tribe_id
    } do
      custodian =
        custodian_info(
          tribe_id: tribe_id,
          current_leader: sender,
          object_id: address(0xC3),
          oracle_address: nil
        )

      character = character_ref(object_id: object_id(0xC4), initial_shared_version: 43)
      oracle_address = address(0xC5)

      Cache.put(tables.standings, {:active_custodian, tribe_id}, custodian)

      assert {:ok, %{tx_bytes: tx_bytes}} =
               Diplomacy.set_oracle_address(tribe_id, oracle_address,
                 tables: tables,
                 tribe_id: tribe_id,
                 sender: sender,
                 character_ref: character
               )

      assert tx_bytes == expected_set_oracle_kind_bytes(custodian, character, oracle_address)
    end

    test "remove_oracle_address/2 builds remove_oracle transaction", %{
      tables: tables,
      sender: sender,
      source_tribe_id: tribe_id
    } do
      custodian =
        custodian_info(
          tribe_id: tribe_id,
          current_leader: sender,
          object_id: address(0xC6),
          oracle_address: address(0xC7)
        )

      character = character_ref(object_id: object_id(0xC8), initial_shared_version: 44)

      Cache.put(tables.standings, {:active_custodian, tribe_id}, custodian)

      assert {:ok, %{tx_bytes: tx_bytes}} =
               Diplomacy.remove_oracle_address(tribe_id,
                 tables: tables,
                 tribe_id: tribe_id,
                 sender: sender,
                 character_ref: character
               )

      assert tx_bytes == expected_remove_oracle_kind_bytes(custodian, character)
    end

    test "submit_signed_transaction applies oracle pending ops on success", %{
      tables: tables,
      sender: sender,
      source_tribe_id: tribe_id
    } do
      custodian =
        custodian_info(
          tribe_id: tribe_id,
          current_leader: sender,
          object_id: address(0xCD),
          oracle_address: nil
        )

      character = character_ref(object_id: object_id(0xCE), initial_shared_version: 45)
      oracle_address = address(0xCF)

      Cache.put(tables.standings, {:active_custodian, tribe_id}, custodian)

      assert {:ok, %{tx_bytes: set_tx_bytes}} =
               Diplomacy.set_oracle_address(tribe_id, oracle_address,
                 tables: tables,
                 tribe_id: tribe_id,
                 sender: sender,
                 character_ref: character
               )

      expect(Sigil.Sui.ClientMock, :execute_transaction, fn ^set_tx_bytes,
                                                            ["wallet-signature"],
                                                            [] ->
        {:ok, success_effects("set-oracle-success")}
      end)

      assert {:ok, %{digest: "set-oracle-success", effects_bcs: "dGVzdC1lZmZlY3Rz"}} =
               Diplomacy.submit_signed_transaction(set_tx_bytes, "wallet-signature",
                 tables: tables,
                 tribe_id: tribe_id,
                 sender: sender
               )

      assert Cache.get(tables.standings, {:pending_tx, set_tx_bytes}) == nil

      assert %{oracle_address: ^oracle_address} =
               Cache.get(tables.standings, {:active_custodian, tribe_id})

      assert {:ok, %{tx_bytes: remove_tx_bytes}} =
               Diplomacy.remove_oracle_address(tribe_id,
                 tables: tables,
                 tribe_id: tribe_id,
                 sender: sender,
                 character_ref: character
               )

      expect(Sigil.Sui.ClientMock, :execute_transaction, fn ^remove_tx_bytes,
                                                            ["wallet-signature"],
                                                            [] ->
        {:ok, success_effects("remove-oracle-success")}
      end)

      assert {:ok, %{digest: "remove-oracle-success", effects_bcs: "dGVzdC1lZmZlY3Rz"}} =
               Diplomacy.submit_signed_transaction(remove_tx_bytes, "wallet-signature",
                 tables: tables,
                 tribe_id: tribe_id,
                 sender: sender
               )

      assert Cache.get(tables.standings, {:pending_tx, remove_tx_bytes}) == nil

      assert %{oracle_address: nil} =
               Cache.get(tables.standings, {:active_custodian, tribe_id})
    end

    test "oracle_enabled?/1 reflects cached custodian oracle state", %{
      tables: tables,
      source_tribe_id: tribe_id
    } do
      Cache.put(tables.standings, {:active_custodian, tribe_id}, %{
        object_id: address(0xC9),
        object_id_bytes: object_id(0xC9),
        initial_shared_version: 12,
        tribe_id: tribe_id,
        current_leader: sender_address(),
        oracle_address: address(0xCA)
      })

      assert Diplomacy.oracle_enabled?(tables: tables, tribe_id: tribe_id)

      Cache.put(tables.standings, {:active_custodian, tribe_id}, %{
        object_id: address(0xCB),
        object_id_bytes: object_id(0xCB),
        initial_shared_version: 12,
        tribe_id: tribe_id,
        current_leader: sender_address(),
        oracle_address: nil
      })

      refute Diplomacy.oracle_enabled?(tables: tables, tribe_id: tribe_id)
    end

    test "pin_standing broadcasts reputation_pinned event", %{
      tables: tables,
      pubsub: pubsub,
      source_tribe_id: tribe_id,
      sender: sender
    } do
      owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: false)
      on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)

      target_tribe_id = 812

      Cache.put(
        tables.standings,
        {:active_custodian, tribe_id},
        custodian_info(tribe_id: tribe_id, current_leader: sender)
      )

      :ok = Phoenix.PubSub.subscribe(pubsub, "reputation")

      assert {:ok, _row} =
               %ReputationScore{}
               |> ReputationScore.changeset(%{
                 source_tribe_id: tribe_id,
                 target_tribe_id: target_tribe_id,
                 score: 15,
                 pinned: false,
                 pinned_standing: nil
               })
               |> Repo.insert()

      assert :ok =
               Diplomacy.pin_standing(target_tribe_id, :friendly,
                 tables: tables,
                 pubsub: pubsub,
                 tribe_id: tribe_id,
                 sender: sender
               )

      assert_receive {:reputation_pinned,
                      %{tribe_id: ^tribe_id, target_tribe_id: ^target_tribe_id}}
    end

    test "unpin_standing broadcasts reputation_unpinned event", %{
      tables: tables,
      pubsub: pubsub,
      source_tribe_id: tribe_id,
      sender: sender
    } do
      owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: false)
      on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)

      target_tribe_id = 813

      Cache.put(
        tables.standings,
        {:active_custodian, tribe_id},
        custodian_info(tribe_id: tribe_id, current_leader: sender)
      )

      :ok = Phoenix.PubSub.subscribe(pubsub, "reputation")

      assert {:ok, _row} =
               %ReputationScore{}
               |> ReputationScore.changeset(%{
                 source_tribe_id: tribe_id,
                 target_tribe_id: target_tribe_id,
                 score: 25,
                 pinned: true,
                 pinned_standing: 3
               })
               |> Repo.insert()

      Cache.put(tables.reputation, {:reputation_score, tribe_id, target_tribe_id}, %{
        tribe_id: tribe_id,
        target_tribe_id: target_tribe_id,
        score: 25,
        pinned: true,
        pinned_standing: :friendly,
        updated_at: DateTime.utc_now()
      })

      assert :ok =
               Diplomacy.unpin_standing(target_tribe_id,
                 tables: tables,
                 pubsub: pubsub,
                 tribe_id: tribe_id,
                 sender: sender
               )

      assert_receive {:reputation_unpinned,
                      %{tribe_id: ^tribe_id, target_tribe_id: ^target_tribe_id}}
    end
  end

  @tag :acceptance
  test "leader submits hostile standing update and sees source tribe cache change", %{
    tables: tables,
    pubsub: pubsub,
    sender: sender,
    source_tribe_id: tribe_id
  } do
    custodian =
      custodian_info(tribe_id: tribe_id, current_leader: sender, object_id: address(0xC1))

    character = character_ref(object_id: object_id(0xC2), initial_shared_version: 42)

    Cache.put(tables.standings, {:active_custodian, tribe_id}, custodian)

    assert {:ok, %{tx_bytes: tx_bytes}} =
             Diplomacy.build_set_standing_tx(808, 0,
               tables: tables,
               pubsub: pubsub,
               tribe_id: tribe_id,
               sender: sender,
               character_ref: character
             )

    expect(Sigil.Sui.ClientMock, :execute_transaction, fn ^tx_bytes, ["wallet-sig"], [] ->
      {:ok, success_effects("acceptance-digest")}
    end)

    assert {:ok, %{digest: "acceptance-digest", effects_bcs: "dGVzdC1lZmZlY3Rz"}} =
             Diplomacy.submit_signed_transaction(tx_bytes, "wallet-sig",
               tables: tables,
               pubsub: pubsub,
               tribe_id: tribe_id,
               sender: sender
             )

    assert Diplomacy.get_standing(808, tables: tables, tribe_id: tribe_id) == :hostile
    refute Diplomacy.get_standing(808, tables: tables, tribe_id: tribe_id) == :neutral
    assert_receive {:standing_updated, %{tribe_id: 808, standing: :hostile}}
    refute_receive {:default_standing_updated, _}
  end

  defp unique_pubsub_name do
    :"diplomacy_pubsub_#{System.unique_integer([:positive])}"
  end

  defp sender_address do
    address(0xD1)
  end

  defp address(byte) do
    "0x" <> Base.encode16(:binary.copy(<<byte>>, 32), case: :lower)
  end

  defp object_id(byte), do: :binary.copy(<<byte>>, 32)

  defp custodian_info(overrides \\ %{}) do
    overrides = Enum.into(overrides, %{})
    object_id_hex = Map.get(overrides, :object_id, address(0xE1))

    Map.merge(
      %{
        object_id: object_id_hex,
        object_id_bytes: hex_to_bytes(object_id_hex),
        initial_shared_version: 17,
        tribe_id: @source_tribe_id,
        current_leader: sender_address(),
        current_leader_votes: 1,
        members: [sender_address()],
        votes_table_id: address(0xE4),
        vote_tallies_table_id: address(0xE5)
      },
      overrides
    )
  end

  defp character_ref(overrides \\ %{}) do
    overrides = Enum.into(overrides, %{})

    Map.merge(
      %{
        object_id: object_id(0xE2),
        initial_shared_version: 18
      },
      overrides
    )
  end

  defp registry_ref(overrides) do
    overrides = Enum.into(overrides, %{})

    Map.merge(
      %{
        object_id: object_id(0xE3),
        initial_shared_version: 19
      },
      overrides
    )
  end

  defp custodian_object_json(overrides) do
    object_id_hex = Keyword.get(overrides, :object_id, address(0xF1))
    initial_shared_version = Keyword.get(overrides, :initial_shared_version, 17)

    %{
      "id" => object_id_hex,
      "tribe_id" => Keyword.get(overrides, :tribe_id, @source_tribe_id),
      "current_leader" => Keyword.get(overrides, :current_leader, sender_address()),
      "current_leader_votes" => Keyword.get(overrides, :current_leader_votes, 1),
      "members" => Keyword.get(overrides, :members, [sender_address()]),
      "votes" => %{"id" => Keyword.get(overrides, :votes_table_id, address(0xF2))},
      "vote_tallies" => %{"id" => Keyword.get(overrides, :vote_tallies_table_id, address(0xF3))},
      "shared" => %{"initialSharedVersion" => Integer.to_string(initial_shared_version)},
      "initialSharedVersion" => Integer.to_string(initial_shared_version)
    }
  end

  defp shared_object_json(object_id_hex, initial_shared_version) do
    %{
      "id" => object_id_hex,
      "shared" => %{"initialSharedVersion" => Integer.to_string(initial_shared_version)},
      "initialSharedVersion" => Integer.to_string(initial_shared_version)
    }
  end

  defp page(entries, overrides \\ []) do
    %{
      data: entries,
      has_next_page: Keyword.get(overrides, :has_next_page, false),
      end_cursor: Keyword.get(overrides, :end_cursor)
    }
  end

  defp expected_set_standing_kind_bytes(custodian, character, tribe_id, standing) do
    custodian
    |> custodian_ref_from_info()
    |> TxCustodian.build_set_standing(character, tribe_id, standing, [])
    |> TransactionBuilder.build_kind!()
    |> Base.encode64()
  end

  defp expected_create_custodian_kind_bytes(registry, character) do
    registry
    |> TxCustodian.build_create_custodian(character, [])
    |> TransactionBuilder.build_kind!()
    |> Base.encode64()
  end

  defp expected_batch_set_standings_kind_bytes(custodian, character, updates) do
    custodian
    |> custodian_ref_from_info()
    |> TxCustodian.build_batch_set_standings(character, updates, [])
    |> TransactionBuilder.build_kind!()
    |> Base.encode64()
  end

  defp expected_set_pilot_standing_kind_bytes(custodian, character, pilot, standing) do
    custodian
    |> custodian_ref_from_info()
    |> TxCustodian.build_set_pilot_standing(character, hex_to_bytes(pilot), standing, [])
    |> TransactionBuilder.build_kind!()
    |> Base.encode64()
  end

  defp expected_set_default_standing_kind_bytes(custodian, character, standing) do
    custodian
    |> custodian_ref_from_info()
    |> TxCustodian.build_set_default_standing(character, standing, [])
    |> TransactionBuilder.build_kind!()
    |> Base.encode64()
  end

  defp expected_batch_set_pilot_standings_kind_bytes(custodian, character, updates) do
    encoded_updates =
      Enum.map(updates, fn {pilot, standing} -> {hex_to_bytes(pilot), standing} end)

    custodian
    |> custodian_ref_from_info()
    |> TxCustodian.build_batch_set_pilot_standings(character, encoded_updates, [])
    |> TransactionBuilder.build_kind!()
    |> Base.encode64()
  end

  defp expected_vote_leader_kind_bytes(custodian, character, candidate) do
    custodian
    |> custodian_ref_from_info()
    |> TxCustodian.build_vote_leader(character, hex_to_bytes(candidate), [])
    |> TransactionBuilder.build_kind!()
    |> Base.encode64()
  end

  defp expected_claim_leadership_kind_bytes(custodian, character) do
    custodian
    |> custodian_ref_from_info()
    |> TxCustodian.build_claim_leadership(character, [])
    |> TransactionBuilder.build_kind!()
    |> Base.encode64()
  end

  defp dynamic_field_entry(name_json, value_json, opts \\ []) do
    %{
      name: %{type: Keyword.get(opts, :name_type, "address"), json: name_json},
      value: %{type: Keyword.get(opts, :value_type, "address"), json: value_json}
    }
  end

  defp expected_set_oracle_kind_bytes(custodian, character, oracle_address) do
    custodian
    |> custodian_ref_from_info()
    |> TxCustodian.build_set_oracle(character, hex_to_bytes(oracle_address), [])
    |> TransactionBuilder.build_kind!()
    |> Base.encode64()
  end

  defp expected_remove_oracle_kind_bytes(custodian, character) do
    custodian
    |> custodian_ref_from_info()
    |> TxCustodian.build_remove_oracle(character, [])
    |> TransactionBuilder.build_kind!()
    |> Base.encode64()
  end

  defp custodian_ref_from_info(custodian) do
    %{
      object_id: custodian.object_id_bytes,
      initial_shared_version: custodian.initial_shared_version
    }
  end

  defp hex_to_bytes("0x" <> hex), do: Base.decode16!(hex, case: :mixed)

  defp success_effects(digest) do
    %{
      "effectsBcs" => "dGVzdC1lZmZlY3Rz",
      "status" => "SUCCESS",
      "digest" => digest,
      "gasEffects" => %{"gasSummary" => %{"computationCost" => "1"}}
    }
  end

  defp world_tribe_records do
    [
      %{"id" => 314, "name" => "Progenitor Collective", "short_name" => "PGCL"},
      %{"id" => 271, "name" => "Frontier Defense Union", "short_name" => "FDU"}
    ]
  end

  defp tx_diplomacy_source_path do
    Path.join(project_root(), "lib/sigil/sui/tx_diplomacy.ex")
  end

  defp tx_diplomacy_test_path do
    Path.join(project_root(), "test/sigil/sui/tx_diplomacy_test.exs")
  end

  defp diplomacy_source_path do
    Path.join(project_root(), "lib/sigil/diplomacy.ex")
  end

  defp project_root do
    Path.expand("../..", __DIR__)
  end
end
