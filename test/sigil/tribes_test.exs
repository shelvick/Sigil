defmodule Sigil.TribesTest do
  @moduledoc """
  Covers the tribes context contract from the approved CTX_Tribes spec.
  """

  use ExUnit.Case, async: true

  import Hammox

  alias Sigil.{Accounts, Assemblies, Cache, Tribes}
  alias Sigil.Sui.Types

  @world_package_id "0xtest_world"
  @tribe_id 314

  setup :verify_on_exit!

  setup do
    cache_pid = start_supervised!({Cache, tables: [:accounts, :characters, :assemblies, :tribes]})
    pubsub = unique_pubsub_name()

    start_supervised!({Phoenix.PubSub, name: pubsub})
    :ok = Phoenix.PubSub.subscribe(pubsub, "tribes")

    {:ok,
     tables: Cache.tables(cache_pid),
     pubsub: pubsub,
     character_type: character_type(),
     owner_cap_type: owner_cap_type()}
  end

  describe "discover_members/2" do
    test "discovers tribe members from chain by tribe_id", %{
      tables: tables,
      pubsub: pubsub,
      character_type: character_type
    } do
      expect(Sigil.Sui.ClientMock, :get_objects, fn filters, [] ->
        assert Keyword.get(filters, :type) == character_type
        assert Keyword.get(filters, :cursor) == nil

        {:ok,
         character_page([
           character_json(),
           character_json(%{"id" => uid("0xcharacter-2"), "tribe_id" => "999"}),
           character_json(%{"id" => uid("0xcharacter-3")})
         ])}
      end)

      assert {:ok, tribe} = Tribes.discover_members(@tribe_id, tables: tables, pubsub: pubsub)
      assert is_struct(tribe, Sigil.Tribes.Tribe)
      assert Enum.map(tribe.members, & &1.character_id) == ["0xcharacter", "0xcharacter-3"]
      verify!()
    end

    test "marks members as connected when registered on Sigil", %{
      tables: tables,
      pubsub: pubsub,
      character_type: character_type
    } do
      address = connected_wallet_address()
      connected_character = character_json()

      expect(Sigil.Sui.ClientMock, :get_objects, 2, fn filters, [] ->
        case {Keyword.get(filters, :type), Keyword.get(filters, :owner)} do
          {^character_type, ^address} ->
            {:ok, character_page([connected_character])}

          {^character_type, nil} ->
            {:ok,
             character_page([
               connected_character,
               character_json(%{"id" => uid("0xcharacter-2")})
             ])}
        end
      end)

      assert {:ok, _account} = Accounts.register_wallet(address, tables: tables, pubsub: pubsub)
      assert {:ok, tribe} = Tribes.discover_members(@tribe_id, tables: tables, pubsub: pubsub)

      connected_member = Enum.find(tribe.members, &(&1.character_id == "0xcharacter"))
      assert connected_member.connected == true
      assert connected_member.wallet_address == address
      verify!()
    end

    test "marks members as chain-only when not registered", %{
      tables: tables,
      pubsub: pubsub,
      character_type: character_type
    } do
      expect(Sigil.Sui.ClientMock, :get_objects, fn filters, [] ->
        assert Keyword.get(filters, :type) == character_type

        {:ok,
         character_page([
           character_json(%{"id" => uid("0xcharacter-chain-only")})
         ])}
      end)

      assert {:ok, tribe} = Tribes.discover_members(@tribe_id, tables: tables, pubsub: pubsub)

      chain_only_member = Enum.find(tribe.members, &(&1.character_id == "0xcharacter-chain-only"))
      assert chain_only_member.connected == false
      assert chain_only_member.wallet_address == nil
      verify!()
    end

    test "caches discovered tribe in ETS", %{
      tables: tables,
      pubsub: pubsub,
      character_type: character_type
    } do
      expect(Sigil.Sui.ClientMock, :get_objects, fn filters, [] ->
        assert Keyword.get(filters, :type) == character_type
        {:ok, character_page([character_json()])}
      end)

      assert {:ok, tribe} = Tribes.discover_members(@tribe_id, tables: tables, pubsub: pubsub)
      assert Cache.get(tables.tribes, @tribe_id) == tribe
      verify!()
    end

    test "broadcasts tribe_discovered event via PubSub", %{
      tables: tables,
      pubsub: pubsub,
      character_type: character_type
    } do
      expect(Sigil.Sui.ClientMock, :get_objects, fn filters, [] ->
        assert Keyword.get(filters, :type) == character_type
        {:ok, character_page([character_json()])}
      end)

      assert {:ok, tribe} = Tribes.discover_members(@tribe_id, tables: tables, pubsub: pubsub)
      assert_receive {:tribe_discovered, ^tribe}
      verify!()
    end

    test "paginates through multiple pages of characters", %{
      tables: tables,
      pubsub: pubsub,
      character_type: character_type
    } do
      expect(Sigil.Sui.ClientMock, :get_objects, 2, fn filters, [] ->
        case Keyword.get(filters, :cursor) do
          nil ->
            assert Keyword.get(filters, :type) == character_type

            {:ok,
             character_page(
               [character_json()],
               has_next_page: true,
               end_cursor: "cursor-1"
             )}

          "cursor-1" ->
            assert Keyword.get(filters, :type) == character_type

            {:ok,
             character_page([
               character_json(%{"id" => uid("0xcharacter-2")})
             ])}
        end
      end)

      assert {:ok, tribe} = Tribes.discover_members(@tribe_id, tables: tables, pubsub: pubsub)
      assert Enum.map(tribe.members, & &1.character_id) == ["0xcharacter", "0xcharacter-2"]
      verify!()
    end

    test "returns empty members list when no characters match tribe_id", %{
      tables: tables,
      pubsub: pubsub,
      character_type: character_type
    } do
      expect(Sigil.Sui.ClientMock, :get_objects, fn filters, [] ->
        assert Keyword.get(filters, :type) == character_type

        {:ok,
         character_page([
           character_json(%{"id" => uid("0xcharacter-other"), "tribe_id" => "999"})
         ])}
      end)

      assert {:ok, tribe} = Tribes.discover_members(@tribe_id, tables: tables, pubsub: pubsub)
      assert is_struct(tribe, Sigil.Tribes.Tribe)
      assert tribe.members == []
      verify!()
    end

    test "sets character_name to nil when character metadata is missing", %{
      tables: tables,
      pubsub: pubsub,
      character_type: character_type
    } do
      expect(Sigil.Sui.ClientMock, :get_objects, fn filters, [] ->
        assert Keyword.get(filters, :type) == character_type

        {:ok,
         character_page([
           character_json(%{"id" => uid("0xcharacter-nameless"), "metadata" => nil})
         ])}
      end)

      assert {:ok, tribe} = Tribes.discover_members(@tribe_id, tables: tables, pubsub: pubsub)

      assert [%{character_id: "0xcharacter-nameless", character_name: nil}] = tribe.members
      verify!()
    end

    test "propagates chain query errors", %{
      tables: tables,
      pubsub: pubsub,
      character_type: character_type
    } do
      expect(Sigil.Sui.ClientMock, :get_objects, fn filters, [] ->
        assert Keyword.get(filters, :type) == character_type
        {:error, :timeout}
      end)

      assert Tribes.discover_members(@tribe_id, tables: tables, pubsub: pubsub) ==
               {:error, :timeout}

      refute_receive {:tribe_discovered, _tribe}
      verify!()
    end
  end

  describe "list_members/2" do
    test "list_members returns cached tribe members", %{tables: tables} do
      member = tribe_member()
      Cache.put(tables.tribes, @tribe_id, tribe_struct(%{members: [member]}))

      assert Tribes.list_members(@tribe_id, tables: tables) == [member]
    end

    test "list_members returns empty list for undiscovered tribe", %{tables: tables} do
      assert Tribes.list_members(@tribe_id, tables: tables) == []
    end
  end

  describe "get_tribe/2" do
    test "get_tribe returns cached tribe struct", %{tables: tables} do
      tribe = tribe_struct(%{members: [tribe_member()]})
      Cache.put(tables.tribes, @tribe_id, tribe)

      assert Tribes.get_tribe(@tribe_id, tables: tables) == tribe
    end

    test "get_tribe returns nil for unknown tribe", %{tables: tables} do
      assert Tribes.get_tribe(@tribe_id, tables: tables) == nil
    end
  end

  describe "list_tribe_assemblies/2" do
    test "list_tribe_assemblies returns assemblies grouped by connected member", %{tables: tables} do
      connected_one =
        tribe_member(%{
          character_id: "0xcharacter-1",
          wallet_address: connected_wallet_address(),
          connected: true
        })

      connected_two =
        tribe_member(%{
          character_id: "0xcharacter-2",
          wallet_address: second_connected_wallet_address(),
          connected: true
        })

      tribe = tribe_struct(%{members: [connected_one, connected_two]})
      first_assembly = Types.Assembly.from_json(assembly_json(%{"id" => uid("0xassembly-1")}))
      second_assembly = Types.Assembly.from_json(assembly_json(%{"id" => uid("0xassembly-2")}))
      third_assembly = Types.Assembly.from_json(assembly_json(%{"id" => uid("0xassembly-3")}))

      Cache.put(tables.tribes, @tribe_id, tribe)

      Cache.put(
        tables.assemblies,
        first_assembly.id,
        {connected_one.wallet_address, first_assembly}
      )

      Cache.put(
        tables.assemblies,
        second_assembly.id,
        {connected_one.wallet_address, second_assembly}
      )

      Cache.put(
        tables.assemblies,
        third_assembly.id,
        {connected_two.wallet_address, third_assembly}
      )

      grouped = Tribes.list_tribe_assemblies(@tribe_id, tables: tables)

      grouped_ids =
        Enum.map(grouped, fn {member, assemblies} ->
          {member.character_id, Enum.map(assemblies, & &1.id)}
        end)

      assert grouped_ids == [
               {"0xcharacter-1", ["0xassembly-1", "0xassembly-2"]},
               {"0xcharacter-2", ["0xassembly-3"]}
             ]
    end

    test "list_tribe_assemblies includes connected members without cached assemblies", %{
      tables: tables
    } do
      connected_member =
        tribe_member(%{
          character_id: "0xcharacter-empty",
          wallet_address: connected_wallet_address(),
          connected: true
        })

      Cache.put(tables.tribes, @tribe_id, tribe_struct(%{members: [connected_member]}))

      assert Tribes.list_tribe_assemblies(@tribe_id, tables: tables) == [{connected_member, []}]
    end

    test "list_tribe_assemblies excludes chain-only members", %{tables: tables} do
      connected_member =
        tribe_member(%{wallet_address: connected_wallet_address(), connected: true})

      chain_only_member =
        tribe_member(%{
          character_id: "0xcharacter-chain-only",
          wallet_address: nil,
          connected: false
        })

      assembly = Types.Assembly.from_json(assembly_json(%{"id" => uid("0xassembly-connected")}))

      Cache.put(
        tables.tribes,
        @tribe_id,
        tribe_struct(%{members: [connected_member, chain_only_member]})
      )

      Cache.put(tables.assemblies, assembly.id, {connected_member.wallet_address, assembly})

      assert Tribes.list_tribe_assemblies(@tribe_id, tables: tables) == [
               {connected_member, [assembly]}
             ]
    end

    test "list_tribe_assemblies returns empty list for undiscovered tribe", %{tables: tables} do
      assert Tribes.list_tribe_assemblies(@tribe_id, tables: tables) == []
    end
  end

  @tag :acceptance
  test "full tribe flow - register, discover, list, assemblies", %{
    tables: tables,
    pubsub: pubsub,
    character_type: character_type,
    owner_cap_type: owner_cap_type
  } do
    address = connected_wallet_address()
    assembly_id = "0xtribe-assembly"
    connected_character = character_json()
    chain_only_character = character_json(%{"id" => uid("0xcharacter-chain-only")})

    outsider_character =
      character_json(%{"id" => uid("0xcharacter-outsider"), "tribe_id" => "999"})

    expect(Sigil.Sui.ClientMock, :get_objects, 3, fn filters, [] ->
      case {Keyword.get(filters, :type), Keyword.get(filters, :owner)} do
        {^character_type, ^address} ->
          {:ok, character_page([connected_character])}

        {^owner_cap_type, ^address} ->
          {:ok, owner_caps_page([owner_cap_json(assembly_id)])}

        {^character_type, nil} ->
          {:ok, character_page([connected_character, chain_only_character, outsider_character])}
      end
    end)

    expect(Sigil.Sui.ClientMock, :get_object, fn ^assembly_id, [] ->
      {:ok, assembly_json(%{"id" => uid(assembly_id)})}
    end)

    assert {:ok, _account} = Accounts.register_wallet(address, tables: tables, pubsub: pubsub)

    assert {:ok, [%Types.Assembly{id: ^assembly_id}]} =
             Assemblies.discover_for_owner(address, tables: tables, pubsub: pubsub)

    assert {:ok, tribe} = Tribes.discover_members(@tribe_id, tables: tables, pubsub: pubsub)

    listed_members = Tribes.list_members(@tribe_id, tables: tables)
    grouped_assemblies = Tribes.list_tribe_assemblies(@tribe_id, tables: tables)

    connected_member = Enum.find(listed_members, &(&1.character_id == "0xcharacter"))
    chain_only_member = Enum.find(listed_members, &(&1.character_id == "0xcharacter-chain-only"))

    assert is_struct(tribe, Sigil.Tribes.Tribe)

    assert Enum.map(listed_members, & &1.character_id) == [
             "0xcharacter",
             "0xcharacter-chain-only"
           ]

    assert connected_member.connected == true
    assert connected_member.wallet_address == address
    assert chain_only_member.connected == false
    assert chain_only_member.wallet_address == nil
    assert [{^connected_member, [%Types.Assembly{id: grouped_assembly_id}]}] = grouped_assemblies
    assert grouped_assembly_id == assembly_id
    refute listed_members == []
    refute Enum.any?(listed_members, &(&1.character_id == "0xcharacter-outsider"))
    verify!()
  end

  defp character_type do
    "#{@world_package_id}::character::Character"
  end

  defp owner_cap_type do
    "#{@world_package_id}::access::OwnerCap"
  end

  defp unique_pubsub_name do
    :"tribes_pubsub_#{System.unique_integer([:positive])}"
  end

  defp connected_wallet_address do
    "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  end

  defp second_connected_wallet_address do
    "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  end

  defp character_page(characters_json, opts \\ []) do
    %{
      data: characters_json,
      has_next_page: Keyword.get(opts, :has_next_page, false),
      end_cursor: Keyword.get(opts, :end_cursor)
    }
  end

  defp owner_caps_page(owner_caps_json) do
    %{data: owner_caps_json, has_next_page: false, end_cursor: nil}
  end

  defp character_json(overrides \\ %{}) do
    Map.merge(
      %{
        "id" => uid("0xcharacter"),
        "key" => %{"item_id" => "10", "tenant" => "0xcharacter-tenant"},
        "tribe_id" => Integer.to_string(@tribe_id),
        "character_address" => "0xcharacter-address",
        "metadata" => %{
          "assembly_id" => "0xassembly-metadata",
          "name" => "Pilot One",
          "description" => "Character metadata",
          "url" => "https://example.test/characters/1"
        },
        "owner_cap_id" => uid("0xcharacter-owner")
      },
      overrides
    )
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
        "status" => %{"status" => "ONLINE"},
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

  defp tribe_struct(overrides) do
    Map.merge(
      %{
        __struct__: Sigil.Tribes.Tribe,
        tribe_id: @tribe_id,
        members: [],
        discovered_at: ~U[2026-03-16 05:00:00Z]
      },
      overrides
    )
  end

  defp tribe_member(overrides \\ %{}) do
    Map.merge(
      %{
        __struct__: Sigil.Tribes.TribeMember,
        character_id: "0xcharacter",
        character_name: "Pilot One",
        character_address: "0xcharacter-address",
        tribe_id: @tribe_id,
        connected: true,
        wallet_address: connected_wallet_address()
      },
      overrides
    )
  end

  defp location_hash do
    :binary.copy(<<7>>, 32)
  end

  defp uid(id), do: %{"id" => id}
end
