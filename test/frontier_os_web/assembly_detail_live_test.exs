defmodule FrontierOSWeb.AssemblyDetailLiveTest do
  @moduledoc """
  Covers assembly detail rendering, updates, and authenticated navigation flow.
  """

  use FrontierOS.ConnCase, async: true

  import Hammox

  alias FrontierOS.{Cache, GameState.Poller}
  alias FrontierOS.Accounts.Account
  alias FrontierOS.Sui.Types.{Character, Gate, NetworkNode, StorageUnit, Turret}

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

  test "renders gate detail with linked_gate_id and extension", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    gate = Gate.from_json(gate_json())

    Cache.put(cache_tables.accounts, wallet_address, account)
    Cache.put(cache_tables.assemblies, gate.id, {wallet_address, gate})

    assert {:ok, _view, html} =
             live(
               authenticated_conn(conn, wallet_address, cache_tables, pubsub),
               "/assembly/#{gate.id}"
             )

    assert html =~ "Assembly uplink"
    assert html =~ "Gate"
    assert html =~ gate.linked_gate_id
    assert html =~ gate.extension
    assert html =~ gate.owner_cap_id
    assert html =~ "Location Hash"
    assert html =~ "Back to Dashboard"
  end

  test "renders turret detail with extension", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    turret = Turret.from_json(turret_json())

    Cache.put(cache_tables.accounts, wallet_address, account)
    Cache.put(cache_tables.assemblies, turret.id, {wallet_address, turret})

    assert {:ok, _view, html} =
             live(
               authenticated_conn(conn, wallet_address, cache_tables, pubsub),
               "/assembly/#{turret.id}"
             )

    assert html =~ "Turret"
    assert html =~ "Defense Turret"
    assert html =~ turret.extension
    assert html =~ turret.owner_cap_id
  end

  test "renders network node detail with fuel panel", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    node = NetworkNode.from_json(network_node_json())

    Cache.put(cache_tables.accounts, wallet_address, account)
    Cache.put(cache_tables.assemblies, node.id, {wallet_address, node})

    assert {:ok, _view, html} =
             live(
               authenticated_conn(conn, wallet_address, cache_tables, pubsub),
               "/assembly/#{node.id}"
             )

    assert html =~ "Fuel Panel"
    assert html =~ "50 / 5000"
    assert html =~ "1 per minute"
    assert html =~ "Yes"
    assert html =~ ~s(width: 1%)
    assert html =~ "Burn Start Time"
    assert html =~ "1970-01-01 00:00:08 UTC"
    assert html =~ "Last Updated"
    assert html =~ "1970-01-01 00:00:09 UTC"
  end

  test "renders network node detail with energy panel", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    node = NetworkNode.from_json(network_node_json())

    Cache.put(cache_tables.accounts, wallet_address, account)
    Cache.put(cache_tables.assemblies, node.id, {wallet_address, node})

    assert {:ok, _view, html} =
             live(
               authenticated_conn(conn, wallet_address, cache_tables, pubsub),
               "/assembly/#{node.id}"
             )

    assert html =~ "Energy Panel"
    assert html =~ "Max Energy Production"
    assert html =~ "10000"
    assert html =~ "Current Energy Production"
    assert html =~ "2500 (25%)"
    assert html =~ "Total Reserved Energy"
    assert html =~ "1250"
    assert html =~ "Available Energy"
  end

  test "renders network node detail with connected assembly list", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    node = NetworkNode.from_json(network_node_json())

    Cache.put(cache_tables.accounts, wallet_address, account)
    Cache.put(cache_tables.assemblies, node.id, {wallet_address, node})

    assert {:ok, _view, html} =
             live(
               authenticated_conn(conn, wallet_address, cache_tables, pubsub),
               "/assembly/#{node.id}"
             )

    assert html =~ "Connections"
    assert html =~ "Connection Count"
    assert html =~ "0xassembly-a"
    assert html =~ "0xassembly-b"
  end

  test "renders storage unit detail with inventory keys", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    storage = StorageUnit.from_json(storage_unit_json())

    Cache.put(cache_tables.accounts, wallet_address, account)
    Cache.put(cache_tables.assemblies, storage.id, {wallet_address, storage})

    assert {:ok, _view, html} =
             live(
               authenticated_conn(conn, wallet_address, cache_tables, pubsub),
               "/assembly/#{storage.id}"
             )

    assert html =~ "Inventory Keys"
    assert html =~ "Item Count"
    assert html =~ "0xinv-1"
    assert html =~ "0xinv-2"
    assert html =~ ~r/Item Count[\s\S]*?>\s*2\s*</
  end

  test "renders common fields for any assembly type", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    gate = Gate.from_json(gate_json())

    Cache.put(cache_tables.accounts, wallet_address, account)
    Cache.put(cache_tables.assemblies, gate.id, {wallet_address, gate})

    assert {:ok, _view, html} =
             live(
               authenticated_conn(conn, wallet_address, cache_tables, pubsub),
               "/assembly/#{gate.id}"
             )

    assert html =~ gate.id
    assert html =~ "online"
    assert html =~ "Gate"
    assert html =~ "Location Hash"
    refute html =~ "Unknown assembly type"
  end

  test "detail view updates on PubSub broadcast", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    turret = Turret.from_json(turret_json())

    Cache.put(cache_tables.accounts, wallet_address, account)
    Cache.put(cache_tables.assemblies, turret.id, {wallet_address, turret})

    {:ok, view, html} =
      live(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub),
        "/assembly/#{turret.id}"
      )

    assert html =~ "Defense Turret"

    updated_turret =
      Turret.from_json(
        turret_json(%{
          "id" => uid(turret.id),
          "metadata" => %{
            "assembly_id" => "0xturret-metadata",
            "name" => "Defense Turret Prime",
            "description" => "Upgraded turret",
            "url" => "https://example.test/turrets/prime"
          }
        })
      )

    Phoenix.PubSub.broadcast(pubsub, "assembly:#{turret.id}", {:assembly_updated, updated_turret})
    updated_html = render(view)

    assert updated_html =~ "Defense Turret Prime"
    refute updated_html =~ ">Defense Turret<"
  end

  test "redirects to dashboard when assembly not found", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)

    Cache.put(cache_tables.accounts, wallet_address, account)

    assert {:error, {:redirect, %{to: "/", flash: %{"error" => "Assembly not found"}}}} =
             live(
               authenticated_conn(conn, wallet_address, cache_tables, pubsub),
               "/assembly/0xmissing"
             )
  end

  test "back link navigates to dashboard", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    gate = Gate.from_json(gate_json())
    auth_conn = authenticated_conn(conn, wallet_address, cache_tables, pubsub)

    Cache.put(cache_tables.accounts, wallet_address, account)
    Cache.put(cache_tables.assemblies, gate.id, {wallet_address, gate})
    expect_empty_dashboard_discovery(wallet_address)

    {:ok, view, _html} = live(auth_conn, "/assembly/#{gate.id}")

    assert {:ok, _dashboard_view, dashboard_html} =
             view
             |> element("a", "Back to Dashboard")
             |> render_click()
             |> follow_redirect(auth_conn, "/")

    assert dashboard_html =~ "Command Deck"
    assert dashboard_html =~ "Operational Assets"
  end

  test "handles nil metadata gracefully", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)

    gate =
      Gate.from_json(
        gate_json(%{
          "id" => uid("0xnil-metadata-gate"),
          "metadata" => nil,
          "linked_gate_id" => nil,
          "energy_source_id" => nil,
          "extension" => nil
        })
      )

    Cache.put(cache_tables.accounts, wallet_address, account)
    Cache.put(cache_tables.assemblies, gate.id, {wallet_address, gate})

    assert {:ok, _view, html} =
             live(
               authenticated_conn(conn, wallet_address, cache_tables, pubsub),
               "/assembly/#{gate.id}"
             )

    assert html =~ "Unnamed"
    assert html =~ "No description provided"
    assert html =~ "Not linked"
    assert html =~ "None"
    assert html =~ "Not set"
    refute html =~ "Jump Gate Alpha"
  end

  test "handles zero fuel max_capacity without error", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)

    node =
      NetworkNode.from_json(
        network_node_json(%{
          "id" => uid("0xzero-fuel-node"),
          "fuel" => %{
            "max_capacity" => "0",
            "burn_rate_in_ms" => "60000",
            "type_id" => "42",
            "unit_volume" => "2",
            "quantity" => "0",
            "is_burning" => false,
            "previous_cycle_elapsed_time" => "7",
            "burn_start_time" => "8",
            "last_updated" => "9"
          }
        })
      )

    Cache.put(cache_tables.accounts, wallet_address, account)
    Cache.put(cache_tables.assemblies, node.id, {wallet_address, node})

    assert {:ok, _view, html} =
             live(
               authenticated_conn(conn, wallet_address, cache_tables, pubsub),
               "/assembly/#{node.id}"
             )

    assert html =~ "0 / 0"
    assert html =~ "N/A"
    assert html =~ "Not burning"
    assert html =~ ~s(width: 0%)
  end

  test "renders per-hour burn rate for large values", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)

    node =
      NetworkNode.from_json(
        network_node_json(%{
          "id" => uid("0xhourly-burn-node"),
          "fuel" => %{
            "max_capacity" => "5000",
            "burn_rate_in_ms" => "7200000",
            "type_id" => "42",
            "unit_volume" => "2",
            "quantity" => "50",
            "is_burning" => true,
            "previous_cycle_elapsed_time" => "7",
            "burn_start_time" => "8000",
            "last_updated" => "9000"
          }
        })
      )

    Cache.put(cache_tables.accounts, wallet_address, account)
    Cache.put(cache_tables.assemblies, node.id, {wallet_address, node})

    assert {:ok, _view, html} =
             live(
               authenticated_conn(conn, wallet_address, cache_tables, pubsub),
               "/assembly/#{node.id}"
             )

    assert html =~ "2 per hour"
  end

  test "poller syncs cached assembly updates sequentially", %{
    cache_tables: cache_tables,
    pubsub: pubsub
  } do
    gate_id = "0xpoller-gate"
    node_id = "0xpoller-node"

    Cache.put(
      cache_tables.assemblies,
      gate_id,
      {unique_wallet_address(), Gate.from_json(gate_json(%{"id" => uid(gate_id)}))}
    )

    Cache.put(
      cache_tables.assemblies,
      node_id,
      {unique_wallet_address(), NetworkNode.from_json(network_node_json(%{"id" => uid(node_id)}))}
    )

    parent = self()

    sync_fun = fn assembly_id, opts ->
      send(
        parent,
        {:sync_called, assembly_id, Keyword.fetch!(opts, :tables), Keyword.fetch!(opts, :pubsub)}
      )

      {:ok, :synced}
    end

    {:ok, poller} =
      Poller.start_link(
        assembly_ids: [gate_id, node_id],
        tables: cache_tables,
        pubsub: pubsub,
        interval_ms: 5,
        sync_fun: sync_fun
      )

    on_exit(fn ->
      if Process.alive?(poller) do
        try do
          GenServer.stop(poller, :normal, :infinity)
        catch
          :exit, _ -> :ok
        end
      end
    end)

    assert_receive {:sync_called, ^gate_id, ^cache_tables, ^pubsub}, 200
    assert_receive {:sync_called, ^node_id, ^cache_tables, ^pubsub}, 200
  end

  @tag :acceptance
  test "full flow: authenticated user views gate detail", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    gate = Gate.from_json(gate_json(%{"id" => uid("0xacceptance-gate-detail")}))
    character = character_json()
    character_type = character_type()

    Cache.put(cache_tables.assemblies, gate.id, {wallet_address, gate})

    expect(FrontierOS.Sui.ClientMock, :get_objects, fn filters, [] ->
      case filters do
        [type: type, owner: ^wallet_address] when type == character_type ->
          {:ok, %{data: [character], has_next_page: false, end_cursor: nil}}
      end
    end)

    conn =
      conn
      |> init_test_session(%{"cache_tables" => cache_tables, "pubsub" => pubsub})
      |> post("/session", %{"wallet_address" => wallet_address})

    assert redirected_to(conn) == "/"

    assert {:ok, _view, html} = live(recycle(conn), "/assembly/#{gate.id}")

    assert html =~ "Jump Gate Alpha"
    assert html =~ gate.linked_gate_id
    assert html =~ gate.extension
    assert html =~ gate.owner_cap_id
    refute html =~ "Assembly not found"
    refute html =~ "Connect Your Wallet"
  end

  defp expect_empty_dashboard_discovery(wallet_address) do
    owner_cap_type = owner_cap_type()

    expect(FrontierOS.Sui.ClientMock, :get_objects, fn [type: type, owner: ^wallet_address], []
                                                       when type == owner_cap_type ->
      {:ok, %{data: [], has_next_page: false, end_cursor: nil}}
    end)
  end

  defp authenticated_conn(conn, wallet_address, cache_tables, pubsub) do
    init_test_session(conn, %{
      "wallet_address" => wallet_address,
      "cache_tables" => cache_tables,
      "pubsub" => pubsub
    })
  end

  defp owner_cap_type do
    "0xtest_world::access::OwnerCap"
  end

  defp account_fixture(wallet_address) do
    %Account{
      address: wallet_address,
      characters: [Character.from_json(character_json())],
      tribe_id: 314
    }
  end

  defp unique_pubsub_name do
    :"assembly_detail_pubsub_#{System.unique_integer([:positive])}"
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
    "0xtest_world::character::Character"
  end

  defp character_json do
    %{
      "id" => uid("0xcharacter-detail"),
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

  defp gate_json(overrides \\ %{}) do
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

  defp storage_unit_json(overrides \\ %{}) do
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

  defp turret_json(overrides \\ %{}) do
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

  defp uid(id), do: %{"id" => id}
end
