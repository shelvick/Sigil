defmodule FrontierOSWeb.DashboardLiveTest do
  @moduledoc """
  Covers authenticated dashboard rendering and end-to-end wallet session flow.
  """

  use FrontierOS.ConnCase, async: true

  import Hammox

  alias FrontierOS.Cache
  alias FrontierOS.Accounts.Account
  alias FrontierOS.Sui.Types.{Character, Gate, NetworkNode, Turret}

  @world_package_id "0xtest_world"

  setup :verify_on_exit!

  setup do
    cache_pid = start_supervised!({Cache, tables: [:accounts, :characters, :assemblies]})
    pubsub = unique_pubsub_name()

    start_supervised!({Phoenix.PubSub, name: pubsub})

    {:ok,
     cache_tables: Cache.tables(cache_pid),
     pubsub: pubsub,
     wallet_address: unique_wallet_address()}
  end

  test "renders wallet entry form when not authenticated", %{conn: conn} do
    assert {:ok, _view, html} = live(conn, "/")

    assert html =~ "Connect Your Wallet"
    assert html =~ "Wallet Address"
    refute html =~ "Operational Assets"
  end

  test "wallet form action is POST /session", %{conn: conn} do
    assert {:ok, _view, html} = live(conn, "/")

    assert html =~ ~s(<form action="/session" method="post")
    assert html =~ ~s(name="_csrf_token")
  end

  test "renders assembly list when authenticated", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    gate = Gate.from_json(gate_json(%{"id" => uid("0xgate-dashboard")}))
    node = NetworkNode.from_json(network_node_json(%{"id" => uid("0xnode-dashboard")}))

    Cache.put(cache_tables.accounts, wallet_address, account)
    expect_dashboard_discovery(wallet_address, [gate, node])

    assert {:ok, _view, html} =
             live(authenticated_conn(conn, wallet_address, cache_tables, pubsub), "/")

    assert html =~ "Operational Assets"
    assert html =~ account.address
    assert html =~ "Captain Frontier"
    assert html =~ "Jump Gate Alpha"
    assert html =~ "Node One"
    assert html =~ "Gate"
    assert html =~ "NetworkNode"
    assert html =~ "online"
    assert html =~ "50 / 5000"
  end

  test "assembly list displays correct type for each assembly", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    gate = Gate.from_json(gate_json(%{"id" => uid("0xtype-gate")}))
    turret = Turret.from_json(turret_json(%{"id" => uid("0xtype-turret")}))

    Cache.put(cache_tables.accounts, wallet_address, account)
    expect_dashboard_discovery(wallet_address, [gate, turret])

    assert {:ok, _view, html} =
             live(authenticated_conn(conn, wallet_address, cache_tables, pubsub), "/")

    assert html =~ "Gate"
    assert html =~ "Turret"
    assert html =~ "Jump Gate Alpha"
    assert html =~ "Defense Turret"
  end

  test "assembly list shows status indicators", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    online_gate = Gate.from_json(gate_json(%{"id" => uid("0xonline-gate")}))

    offline_turret =
      Turret.from_json(
        turret_json(%{"id" => uid("0xoffline-turret"), "status" => %{"status" => "OFFLINE"}})
      )

    Cache.put(cache_tables.accounts, wallet_address, account)
    expect_dashboard_discovery(wallet_address, [online_gate, offline_turret])

    assert {:ok, _view, html} =
             live(authenticated_conn(conn, wallet_address, cache_tables, pubsub), "/")

    assert html =~ "online"
    assert html =~ "offline"
    assert html =~ "border-success/40"
    assert html =~ "border-warning/60"
  end

  test "assembly list shows default badge for null status", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)

    null_gate =
      Gate.from_json(gate_json(%{"id" => uid("0xnull-gate"), "status" => %{"status" => "NULL"}}))

    Cache.put(cache_tables.accounts, wallet_address, account)
    expect_dashboard_discovery(wallet_address, [null_gate])

    assert {:ok, _view, html} =
             live(authenticated_conn(conn, wallet_address, cache_tables, pubsub), "/")

    assert html =~ "null"
    assert html =~ "border-space-600/80"
  end

  test "assembly list shows fuel info for network nodes", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    node = NetworkNode.from_json(network_node_json(%{"id" => uid("0xfuel-node")}))

    Cache.put(cache_tables.accounts, wallet_address, account)
    expect_dashboard_discovery(wallet_address, [node])

    assert {:ok, _view, html} =
             live(authenticated_conn(conn, wallet_address, cache_tables, pubsub), "/")

    assert html =~ "50 / 5000"
    assert html =~ "1%"
    assert html =~ ~s(width: 1%)
  end

  test "clicking assembly row navigates to detail view", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    gate = Gate.from_json(gate_json(%{"id" => uid("0xrow-nav-gate")}))
    auth_conn = authenticated_conn(conn, wallet_address, cache_tables, pubsub)

    Cache.put(cache_tables.accounts, wallet_address, account)
    Cache.put(cache_tables.assemblies, gate.id, {wallet_address, gate})
    expect_dashboard_discovery(wallet_address, [gate])

    {:ok, view, html} = live(auth_conn, "/")

    assert html =~ ~s(phx-click="[[&quot;navigate&quot;)
    assert html =~ ~s(/assembly/#{gate.id})

    row_html = view |> element("tr[phx-click]") |> render()
    assert row_html =~ ~s(/assembly/#{gate.id})
    assert row_html =~ "cursor-pointer"

    assert {:ok, _detail_view, detail_html} =
             view
             |> element(~s(a[href="/assembly/#{gate.id}"]))
             |> render_click()
             |> follow_redirect(auth_conn, "/assembly/#{gate.id}")

    assert detail_html =~ "Jump Gate Alpha"
    assert detail_html =~ gate.linked_gate_id
  end

  test "assembly list updates on PubSub broadcast", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    gate = Gate.from_json(gate_json(%{"id" => uid("0xgate-broadcast")}))

    Cache.put(cache_tables.accounts, wallet_address, account)
    expect_dashboard_discovery(wallet_address, [gate])

    {:ok, view, html} = live(authenticated_conn(conn, wallet_address, cache_tables, pubsub), "/")
    assert html =~ "Jump Gate Alpha"

    updated_gate =
      Gate.from_json(
        gate_json(%{
          "id" => uid(gate.id),
          "metadata" => %{
            "assembly_id" => "0xgate-metadata",
            "name" => "Jump Gate Prime",
            "description" => "Updated gate description",
            "url" => "https://example.test/gates/prime"
          }
        })
      )

    Phoenix.PubSub.broadcast(pubsub, "assembly:#{gate.id}", {:assembly_updated, updated_gate})
    updated_html = render(view)

    assert updated_html =~ "Jump Gate Prime"
    refute updated_html =~ ">Jump Gate Alpha<"
  end

  test "assemblies_discovered replaces the full list", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    gate = Gate.from_json(gate_json(%{"id" => uid("0xreplace-gate")}))
    turret = Turret.from_json(turret_json(%{"id" => uid("0xreplace-turret")}))

    Cache.put(cache_tables.accounts, wallet_address, account)
    expect_dashboard_discovery(wallet_address, [gate])

    {:ok, view, html} = live(authenticated_conn(conn, wallet_address, cache_tables, pubsub), "/")
    assert html =~ "Jump Gate Alpha"
    refute html =~ "Defense Turret"

    Phoenix.PubSub.broadcast(
      pubsub,
      "assemblies:#{wallet_address}",
      {:assemblies_discovered, [turret]}
    )

    updated_html = render(view)

    assert updated_html =~ "Defense Turret"
    assert updated_html =~ "Turret"
    refute updated_html =~ "Jump Gate Alpha"
  end

  test "shows empty state when no assemblies found", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    Cache.put(cache_tables.accounts, wallet_address, account_fixture(wallet_address))
    expect_empty_dashboard_discovery(wallet_address)

    assert {:ok, _view, html} =
             live(authenticated_conn(conn, wallet_address, cache_tables, pubsub), "/")

    assert html =~ "No assemblies found"
    assert html =~ "Link another wallet or check again after more assets come online."
    refute html =~ "Assembly discovery is temporarily unavailable"
  end

  test "shows discovery failure state when assembly discovery fails", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    Cache.put(cache_tables.accounts, wallet_address, account_fixture(wallet_address))
    expect_dashboard_discovery_failure(wallet_address)

    assert {:ok, _view, html} =
             live(authenticated_conn(conn, wallet_address, cache_tables, pubsub), "/")

    assert html =~ "Unable to refresh assemblies right now."
    assert html =~ "Assembly discovery is temporarily unavailable"
    assert html =~ "Retry discovery by refreshing the command deck."
    refute html =~ "No assemblies found"
  end

  test "header shows truncated wallet address", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    Cache.put(cache_tables.accounts, wallet_address, account_fixture(wallet_address))
    expect_empty_dashboard_discovery(wallet_address)

    assert {:ok, _view, html} =
             live(authenticated_conn(conn, wallet_address, cache_tables, pubsub), "/")

    assert html =~ truncate_id(wallet_address)
    assert html =~ wallet_address
  end

  @tag :acceptance
  test "full flow: submit wallet address, see assemblies on dashboard", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    gate = Gate.from_json(gate_json(%{"id" => uid("0xacceptance-gate-dashboard")}))
    node = NetworkNode.from_json(network_node_json(%{"id" => uid("0xacceptance-node-dashboard")}))
    character_type = character_type()
    owner_cap_type = owner_cap_type()
    gate_id = gate.id
    node_id = node.id

    expect(FrontierOS.Sui.ClientMock, :get_objects, 2, fn filters, [] ->
      case filters do
        [type: type, owner: ^wallet_address] when type == character_type ->
          {:ok, %{data: [character_json()], has_next_page: false, end_cursor: nil}}

        [type: type, owner: ^wallet_address] when type == owner_cap_type ->
          {:ok,
           %{
             data: [owner_cap_json(gate_id), owner_cap_json(node_id)],
             has_next_page: false,
             end_cursor: nil
           }}
      end
    end)

    expect(FrontierOS.Sui.ClientMock, :get_object, 2, fn assembly_id, [] ->
      case assembly_id do
        ^gate_id -> {:ok, gate_json(%{"id" => uid(gate_id)})}
        ^node_id -> {:ok, network_node_json(%{"id" => uid(node_id)})}
      end
    end)

    conn =
      conn
      |> init_test_session(%{"cache_tables" => cache_tables, "pubsub" => pubsub})
      |> post("/session", %{"wallet_address" => wallet_address})

    assert redirected_to(conn) == "/"

    assert {:ok, _view, html} = live(recycle(conn), "/")

    assert html =~ wallet_address
    assert html =~ truncate_id(wallet_address)
    assert html =~ "Jump Gate Alpha"
    assert html =~ "Node One"
    assert html =~ "Gate"
    assert html =~ "NetworkNode"
    assert html =~ "online"
    assert html =~ "50 / 5000"
    assert html =~ "/assembly/#{gate.id}"
    refute html =~ "Connect Your Wallet"
    refute html =~ "No assemblies found"
  end

  defp expect_dashboard_discovery(wallet_address, assemblies) do
    owner_cap_type = owner_cap_type()

    expect(FrontierOS.Sui.ClientMock, :get_objects, fn [type: type, owner: ^wallet_address], []
                                                       when type == owner_cap_type ->
      {:ok,
       %{
         data: Enum.map(assemblies, &owner_cap_json(&1.id)),
         has_next_page: false,
         end_cursor: nil
       }}
    end)

    expect(FrontierOS.Sui.ClientMock, :get_object, length(assemblies), fn assembly_id, [] ->
      assembly = Enum.find(assemblies, &(&1.id == assembly_id))
      {:ok, assembly_json_for(assembly)}
    end)
  end

  defp expect_empty_dashboard_discovery(wallet_address) do
    owner_cap_type = owner_cap_type()

    expect(FrontierOS.Sui.ClientMock, :get_objects, fn [type: type, owner: ^wallet_address], []
                                                       when type == owner_cap_type ->
      {:ok, %{data: [], has_next_page: false, end_cursor: nil}}
    end)
  end

  defp expect_dashboard_discovery_failure(wallet_address) do
    owner_cap_type = owner_cap_type()

    expect(FrontierOS.Sui.ClientMock, :get_objects, fn [type: type, owner: ^wallet_address], []
                                                       when type == owner_cap_type ->
      {:error, :timeout}
    end)
  end

  defp authenticated_conn(conn, wallet_address, cache_tables, pubsub) do
    init_test_session(conn, %{
      "wallet_address" => wallet_address,
      "cache_tables" => cache_tables,
      "pubsub" => pubsub
    })
  end

  defp assembly_json_for(%Gate{id: id, status: %{status: status}}) do
    gate_json(%{"id" => uid(id), "status" => %{"status" => status_to_string(status)}})
  end

  defp assembly_json_for(%NetworkNode{id: id}), do: network_node_json(%{"id" => uid(id)})

  defp assembly_json_for(%Turret{id: id, status: %{status: status}}) do
    turret_json(%{"id" => uid(id), "status" => %{"status" => status_to_string(status)}})
  end

  defp account_fixture(wallet_address) do
    %Account{address: wallet_address, characters: [character_fixture()], tribe_id: 314}
  end

  defp character_fixture do
    Character.from_json(character_json())
  end

  defp unique_pubsub_name do
    :"dashboard_live_pubsub_#{System.unique_integer([:positive])}"
  end

  defp unique_wallet_address do
    suffix =
      System.unique_integer([:positive])
      |> Integer.to_string(16)
      |> String.downcase()
      |> String.pad_leading(64, "0")

    "0x" <> suffix
  end

  defp truncate_id("0x" <> _rest = id) when byte_size(id) > 14 do
    prefix = String.slice(id, 0, 8)
    suffix = String.slice(id, -4, 4)
    prefix <> "..." <> suffix
  end

  defp truncate_id(id), do: id

  defp character_type do
    "#{@world_package_id}::character::Character"
  end

  defp owner_cap_type do
    "#{@world_package_id}::access::OwnerCap"
  end

  defp character_json do
    %{
      "id" => uid("0xcharacter-dashboard"),
      "key" => %{"item_id" => "1", "tenant" => "0xcharacter-tenant"},
      "tribe_id" => "314",
      "character_address" => "0xcharacter-address",
      "metadata" => %{
        "assembly_id" => "0xcharacter-metadata",
        "name" => "Captain Frontier",
        "description" => "Primary command character",
        "url" => "https://example.test/characters/frontier"
      },
      "owner_cap_id" => uid("0xcharacter-owner")
    }
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

  defp location_hash do
    :binary.copy(<<7>>, 32)
  end

  defp status_to_string(:online), do: "ONLINE"
  defp status_to_string(:offline), do: "OFFLINE"
  defp status_to_string(:null), do: "NULL"

  defp uid(id), do: %{"id" => id}
end
