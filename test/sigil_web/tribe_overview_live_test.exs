defmodule SigilWeb.TribeOverviewLiveTest do
  @moduledoc """
  Covers the UI_TribeOverviewLive specification (R1-R14) from Packet 4.
  Tests tribe overview page: member list, assembly aggregation, standings summary,
  PubSub updates, authorization, and navigation.
  """

  use Sigil.ConnCase, async: true

  import Hammox

  alias Sigil.Cache
  alias Sigil.Accounts.Account
  alias Sigil.Sui.Types.{Character, Gate, NetworkNode, Turret}
  alias Sigil.Tribes.{Tribe, TribeMember}

  @tribe_id 314

  setup :verify_on_exit!

  setup do
    cache_pid =
      start_supervised!(
        {Cache, tables: [:accounts, :characters, :assemblies, :nonces, :tribes, :standings]}
      )

    pubsub = unique_pubsub_name()

    start_supervised!({Phoenix.PubSub, name: pubsub})

    {:ok,
     cache_tables: Cache.tables(cache_pid),
     pubsub: pubsub,
     wallet_address: unique_wallet_address()}
  end

  # ---------------------------------------------------------------------------
  # R1: Page renders for authenticated tribe member [SYSTEM]
  # ---------------------------------------------------------------------------

  @tag :acceptance
  test "authenticated tribe member sees tribe overview page", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    tribe =
      tribe_fixture(@tribe_id, [member_fixture("0xchar-1", "Captain", true, wallet_address)])

    Cache.put(cache_tables.tribes, @tribe_id, tribe)

    # Seed standings data
    Cache.put(cache_tables.standings, {:tribe_standing, 42}, 0)
    Cache.put(cache_tables.standings, :default_standing, 2)

    # Seed tribe name
    Cache.put(cache_tables.standings, {:world_tribe, @tribe_id}, %{
      id: @tribe_id,
      name: "Progenitor Collective",
      short_name: "PGCL"
    })

    assert {:ok, _view, html} =
             live(
               authenticated_conn(conn, wallet_address, cache_tables, pubsub),
               "/tribe/#{@tribe_id}"
             )

    # Page renders with tribe name and member
    assert html =~ "Progenitor Collective"
    assert html =~ "Captain"

    # No error states
    refute html =~ "Not your tribe"
    refute html =~ "Connect Your Wallet"
  end

  # ---------------------------------------------------------------------------
  # R2: Unauthorized tribe access redirects [INTEGRATION]
  # ---------------------------------------------------------------------------

  test "user cannot view other tribe's overview", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    # User belongs to tribe 314 but tries to visit tribe 999
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    assert {:error, {:redirect, %{to: "/", flash: %{"error" => error_msg}}}} =
             live(
               authenticated_conn(conn, wallet_address, cache_tables, pubsub),
               "/tribe/999"
             )

    assert error_msg =~ "Not your tribe"
  end

  # ---------------------------------------------------------------------------
  # R3: Unauthenticated access redirects [INTEGRATION]
  # ---------------------------------------------------------------------------

  test "unauthenticated user redirected from tribe overview", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub
  } do
    assert {:error, {:redirect, %{to: "/"}}} =
             live(
               init_test_session(conn, %{
                 "cache_tables" => cache_tables,
                 "pubsub" => pubsub
               }),
               "/tribe/#{@tribe_id}"
             )
  end

  # ---------------------------------------------------------------------------
  # R4: Member list shows connected vs chain-only [INTEGRATION]
  # ---------------------------------------------------------------------------

  test "member list distinguishes connected and chain-only members", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    connected = member_fixture("0xchar-connected", "Captain Online", true, wallet_address)
    chain_only = member_fixture("0xchar-chain", "Ghost Pilot", false, nil)

    tribe = tribe_fixture(@tribe_id, [connected, chain_only])
    Cache.put(cache_tables.tribes, @tribe_id, tribe)

    seed_default_standings(cache_tables)

    assert {:ok, _view, html} =
             live(
               authenticated_conn(conn, wallet_address, cache_tables, pubsub),
               "/tribe/#{@tribe_id}"
             )

    assert html =~ "Captain Online"
    assert html =~ "Ghost Pilot"

    # Connected member should have distinct visual indicator from chain-only
    # (green vs grey — we assert both names appear; detailed styling checked at implementation)
    refute html =~ "No members found"
  end

  # ---------------------------------------------------------------------------
  # R5: Member assemblies grouped by member [INTEGRATION]
  # ---------------------------------------------------------------------------

  test "assemblies panel groups assemblies by member", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    connected = member_fixture("0xchar-assemblies", "Fleet Commander", true, wallet_address)
    tribe = tribe_fixture(@tribe_id, [connected])
    Cache.put(cache_tables.tribes, @tribe_id, tribe)

    # Cache assemblies for the connected member
    gate = Gate.from_json(gate_json(%{"id" => uid("0xmember-gate")}))
    node = NetworkNode.from_json(network_node_json(%{"id" => uid("0xmember-node")}))

    Cache.put(cache_tables.assemblies, gate.id, {wallet_address, gate})
    Cache.put(cache_tables.assemblies, node.id, {wallet_address, node})

    seed_default_standings(cache_tables)

    assert {:ok, _view, html} =
             live(
               authenticated_conn(conn, wallet_address, cache_tables, pubsub),
               "/tribe/#{@tribe_id}"
             )

    assert html =~ "Fleet Commander"
    assert html =~ "Jump Gate Alpha"
    assert html =~ "Node One"
    refute html =~ "No assemblies found"
  end

  # ---------------------------------------------------------------------------
  # R6: Standings summary shows tier counts [INTEGRATION]
  # ---------------------------------------------------------------------------

  test "standings summary shows count per standing tier", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    tribe =
      tribe_fixture(@tribe_id, [
        member_fixture("0xchar-standings", "Leader", true, wallet_address)
      ])

    Cache.put(cache_tables.tribes, @tribe_id, tribe)

    # Seed standings data: 2 hostile, 1 friendly
    Cache.put(cache_tables.standings, {:tribe_standing, 42}, 0)
    Cache.put(cache_tables.standings, {:tribe_standing, 43}, 0)
    Cache.put(cache_tables.standings, {:tribe_standing, 44}, 3)
    Cache.put(cache_tables.standings, :default_standing, 2)

    # Mark that standings table exists
    Cache.put(cache_tables.standings, {:active_table, wallet_address}, %{
      object_id: "0x" <> String.duplicate("ab", 32),
      object_id_bytes: :binary.copy(<<0xAB>>, 32),
      initial_shared_version: 1,
      owner: wallet_address
    })

    assert {:ok, _view, html} =
             live(
               authenticated_conn(conn, wallet_address, cache_tables, pubsub),
               "/tribe/#{@tribe_id}"
             )

    # Should display counts per tier
    assert html =~ "Hostile"
    assert html =~ "Friendly"
    refute html =~ "No standings table"
  end

  # ---------------------------------------------------------------------------
  # R7: Default standing displayed [INTEGRATION]
  # ---------------------------------------------------------------------------

  test "default standing shows with NBSI or NRDS label", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    tribe =
      tribe_fixture(@tribe_id, [member_fixture("0xchar-default", "Leader", true, wallet_address)])

    Cache.put(cache_tables.tribes, @tribe_id, tribe)

    # Set default standing to neutral (NRDS)
    Cache.put(cache_tables.standings, :default_standing, 2)

    # Mark that standings table exists
    Cache.put(cache_tables.standings, {:active_table, wallet_address}, %{
      object_id: "0x" <> String.duplicate("cd", 32),
      object_id_bytes: :binary.copy(<<0xCD>>, 32),
      initial_shared_version: 1,
      owner: wallet_address
    })

    assert {:ok, _view, html} =
             live(
               authenticated_conn(conn, wallet_address, cache_tables, pubsub),
               "/tribe/#{@tribe_id}"
             )

    assert html =~ "NRDS"
    refute html =~ "No standings table"
  end

  # ---------------------------------------------------------------------------
  # R8: No standings table message [INTEGRATION]
  # ---------------------------------------------------------------------------

  test "shows no standings table message when none exists", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    tribe =
      tribe_fixture(@tribe_id, [member_fixture("0xchar-notable", "Leader", true, wallet_address)])

    Cache.put(cache_tables.tribes, @tribe_id, tribe)

    # No active table or standings data seeded

    assert {:ok, _view, html} =
             live(
               authenticated_conn(conn, wallet_address, cache_tables, pubsub),
               "/tribe/#{@tribe_id}"
             )

    assert html =~ "No standings table"
    refute html =~ "Manage Standings"
  end

  # ---------------------------------------------------------------------------
  # R9: Manage standings link [INTEGRATION]
  # ---------------------------------------------------------------------------

  test "manage standings link points to diplomacy page", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    tribe =
      tribe_fixture(@tribe_id, [member_fixture("0xchar-link", "Leader", true, wallet_address)])

    Cache.put(cache_tables.tribes, @tribe_id, tribe)

    # Mark standings table as existing
    Cache.put(cache_tables.standings, {:active_table, wallet_address}, %{
      object_id: "0x" <> String.duplicate("de", 32),
      object_id_bytes: :binary.copy(<<0xDE>>, 32),
      initial_shared_version: 1,
      owner: wallet_address
    })

    Cache.put(cache_tables.standings, :default_standing, 2)

    assert {:ok, _view, html} =
             live(
               authenticated_conn(conn, wallet_address, cache_tables, pubsub),
               "/tribe/#{@tribe_id}"
             )

    assert html =~ "Manage Standings"
    assert html =~ "/tribe/#{@tribe_id}/diplomacy"
    refute html =~ "No standings table"
  end

  # ---------------------------------------------------------------------------
  # R10: Tribe discovery on mount [INTEGRATION]
  # ---------------------------------------------------------------------------

  test "mount triggers tribe discovery when not cached", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    # Don't cache tribe data — mount should trigger discovery and show loading state
    seed_default_standings(cache_tables)

    # Expect chain query for characters (tribe discovery)
    character_type = character_type()

    expect(Sigil.Sui.ClientMock, :get_objects, fn [type: ^character_type], [] ->
      {:ok,
       %{
         data: [character_json(%{"character_address" => wallet_address})],
         has_next_page: false,
         end_cursor: nil
       }}
    end)

    assert {:ok, _view, html} =
             live(
               authenticated_conn(conn, wallet_address, cache_tables, pubsub),
               "/tribe/#{@tribe_id}"
             )

    # Should show loading state while discovery runs
    assert html =~ "Discovering tribe members"
    refute html =~ "Discovery failed"
  end

  # ---------------------------------------------------------------------------
  # R11: PubSub updates member list [INTEGRATION]
  # ---------------------------------------------------------------------------

  test "tribe discovery broadcast updates member list", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    # Start with one member
    initial_member = member_fixture("0xchar-initial", "First Pilot", true, wallet_address)
    tribe = tribe_fixture(@tribe_id, [initial_member])
    Cache.put(cache_tables.tribes, @tribe_id, tribe)

    seed_default_standings(cache_tables)

    {:ok, view, html} =
      live(authenticated_conn(conn, wallet_address, cache_tables, pubsub), "/tribe/#{@tribe_id}")

    assert html =~ "First Pilot"

    # Broadcast tribe discovery with new member
    new_member = member_fixture("0xchar-new", "Second Pilot", false, nil)
    updated_tribe = tribe_fixture(@tribe_id, [initial_member, new_member])
    Cache.put(cache_tables.tribes, @tribe_id, updated_tribe)

    Phoenix.PubSub.broadcast(pubsub, "tribes", {:tribe_discovered, updated_tribe})
    updated_html = render(view)

    assert updated_html =~ "Second Pilot"
    assert updated_html =~ "First Pilot"
  end

  # ---------------------------------------------------------------------------
  # R12: PubSub updates standings summary [INTEGRATION]
  # ---------------------------------------------------------------------------

  test "standing update broadcast refreshes standings summary", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    tribe =
      tribe_fixture(@tribe_id, [member_fixture("0xchar-update", "Leader", true, wallet_address)])

    Cache.put(cache_tables.tribes, @tribe_id, tribe)

    # Start with one hostile standing
    Cache.put(cache_tables.standings, {:tribe_standing, 42}, 0)
    Cache.put(cache_tables.standings, :default_standing, 2)

    Cache.put(cache_tables.standings, {:active_table, wallet_address}, %{
      object_id: "0x" <> String.duplicate("ef", 32),
      object_id_bytes: :binary.copy(<<0xEF>>, 32),
      initial_shared_version: 1,
      owner: wallet_address
    })

    {:ok, view, _html} =
      live(authenticated_conn(conn, wallet_address, cache_tables, pubsub), "/tribe/#{@tribe_id}")

    # Add a new standing via cache and broadcast
    Cache.put(cache_tables.standings, {:tribe_standing, 43}, 4)

    Phoenix.PubSub.broadcast(
      pubsub,
      "diplomacy",
      {:standing_updated, %{tribe_id: 43, standing: :allied}}
    )

    updated_html = render(view)

    assert updated_html =~ "Allied"
    refute updated_html =~ "Standing update failed"
  end

  # ---------------------------------------------------------------------------
  # R13: Tribe name from World API [INTEGRATION]
  # ---------------------------------------------------------------------------

  test "page header shows tribe name from World API", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    tribe =
      tribe_fixture(@tribe_id, [member_fixture("0xchar-name", "Leader", true, wallet_address)])

    Cache.put(cache_tables.tribes, @tribe_id, tribe)

    # Seed World API tribe name
    Cache.put(cache_tables.standings, {:world_tribe, @tribe_id}, %{
      id: @tribe_id,
      name: "Progenitor Collective",
      short_name: "PGCL"
    })

    seed_default_standings(cache_tables)

    assert {:ok, _view, html} =
             live(
               authenticated_conn(conn, wallet_address, cache_tables, pubsub),
               "/tribe/#{@tribe_id}"
             )

    assert html =~ "Progenitor Collective"
    assert html =~ "PGCL"
    refute html =~ "Tribe ##{@tribe_id}"
  end

  # ---------------------------------------------------------------------------
  # R14: Aggregate assembly stats [INTEGRATION]
  # ---------------------------------------------------------------------------

  test "assemblies panel shows aggregate stats by type", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    connected = member_fixture("0xchar-aggregate", "Commander", true, wallet_address)
    tribe = tribe_fixture(@tribe_id, [connected])
    Cache.put(cache_tables.tribes, @tribe_id, tribe)

    # Add multiple assemblies of different types
    gate1 = Gate.from_json(gate_json(%{"id" => uid("0xagg-gate-1")}))
    gate2 = Gate.from_json(gate_json(%{"id" => uid("0xagg-gate-2")}))
    turret = Turret.from_json(turret_json(%{"id" => uid("0xagg-turret")}))
    node = NetworkNode.from_json(network_node_json(%{"id" => uid("0xagg-node")}))

    Cache.put(cache_tables.assemblies, gate1.id, {wallet_address, gate1})
    Cache.put(cache_tables.assemblies, gate2.id, {wallet_address, gate2})
    Cache.put(cache_tables.assemblies, turret.id, {wallet_address, turret})
    Cache.put(cache_tables.assemblies, node.id, {wallet_address, node})

    seed_default_standings(cache_tables)

    assert {:ok, _view, html} =
             live(
               authenticated_conn(conn, wallet_address, cache_tables, pubsub),
               "/tribe/#{@tribe_id}"
             )

    # Should show type counts in aggregate
    assert html =~ "Gate"
    assert html =~ "Turret"
    assert html =~ "NetworkNode"
    refute html =~ "No assemblies found"
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp authenticated_conn(conn, wallet_address, cache_tables, pubsub) do
    init_test_session(conn, %{
      "wallet_address" => wallet_address,
      "cache_tables" => cache_tables,
      "pubsub" => pubsub
    })
  end

  defp account_fixture(wallet_address, tribe_id) do
    %Account{
      address: wallet_address,
      characters: [Character.from_json(character_json())],
      tribe_id: tribe_id
    }
  end

  defp tribe_fixture(tribe_id, members) do
    %Tribe{
      tribe_id: tribe_id,
      members: members,
      discovered_at: DateTime.utc_now()
    }
  end

  defp member_fixture(character_id, name, connected, wallet_address) do
    %TribeMember{
      character_id: character_id,
      character_name: name,
      character_address: "0x" <> String.duplicate("aa", 32),
      tribe_id: @tribe_id,
      connected: connected,
      wallet_address: wallet_address
    }
  end

  defp seed_default_standings(cache_tables) do
    Cache.put(cache_tables.standings, :default_standing, 2)
  end

  defp unique_pubsub_name do
    :"tribe_overview_pubsub_#{System.unique_integer([:positive])}"
  end

  defp unique_wallet_address do
    suffix =
      System.unique_integer([:positive])
      |> Integer.to_string(16)
      |> String.downcase()
      |> String.pad_leading(64, "0")

    "0x" <> suffix
  end

  defp character_type do
    "0x1111111111111111111111111111111111111111111111111111111111111111::character::Character"
  end

  defp character_json(overrides \\ %{}) do
    Map.merge(
      %{
        "id" => uid("0xcharacter"),
        "key" => %{"item_id" => "1", "tenant" => "0xcharacter-tenant"},
        "tribe_id" => "#{@tribe_id}",
        "character_address" => "0xcharacter-address",
        "metadata" => %{
          "assembly_id" => "0xcharacter-metadata",
          "name" => "Captain Frontier",
          "description" => "Primary command character",
          "url" => "https://example.test/characters/frontier"
        },
        "owner_cap_id" => uid("0xcharacter-owner")
      },
      overrides
    )
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
          "burn_rate_in_ms" => "60000",
          "type_id" => "42",
          "unit_volume" => "2",
          "quantity" => "50",
          "is_burning" => true,
          "previous_cycle_elapsed_time" => "7",
          "burn_start_time" => "8000",
          "last_updated" => "9000"
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

  defp location_hash, do: :binary.copy(<<7>>, 32)

  defp uid(id), do: %{"id" => id}
end
