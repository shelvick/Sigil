defmodule SigilWeb.AssemblyDetailLiveIsolatedTestLive do
  @moduledoc """
  Test-only wrapper that mounts `SigilWeb.AssemblyDetailLive` through `live_isolated/3`.
  """

  use SigilWeb, :live_view

  on_mount SigilWeb.WalletSession

  @doc false
  @impl true
  def mount(_params, %{"assembly_id" => assembly_id} = session, socket) do
    socket =
      socket
      |> maybe_assign_dependency(:monitor_supervisor, session)
      |> maybe_assign_dependency(:monitor_registry, session)
      |> maybe_assign_dependency(:static_data, session)

    SigilWeb.AssemblyDetailLive.mount(%{"id" => assembly_id}, session, socket)
  end

  @doc false
  @impl true
  def render(assigns), do: SigilWeb.AssemblyDetailLive.render(assigns)

  @doc false
  @impl true
  def handle_info(message, socket) do
    SigilWeb.AssemblyDetailLive.handle_info(message, socket)
  end

  @doc false
  @impl true
  def handle_event(event, params, socket) do
    apply(SigilWeb.AssemblyDetailLive, :handle_event, [event, params, socket])
  end

  defp maybe_assign_dependency(socket, key, session) do
    case Map.fetch(session, Atom.to_string(key)) do
      {:ok, value} -> Phoenix.Component.assign(socket, key, value)
      :error -> socket
    end
  end
end

defmodule SigilWeb.AssemblyDetailLiveTest do
  @moduledoc """
  Covers assembly detail rendering, updates, and authenticated navigation flow.
  """

  use Sigil.ConnCase, async: true

  import Ecto.Query
  import Hammox

  alias Sigil.Cache
  alias Sigil.Repo
  alias Sigil.Accounts.Account
  alias Sigil.GameState.MonitorSupervisor
  alias Sigil.Intel.IntelReport
  alias Sigil.StaticData
  alias Sigil.StaticDataTestFixtures, as: StaticDataFixtures
  alias Sigil.Sui.Types.{Character, Gate, NetworkNode, StorageUnit, Turret}

  @zklogin_sig Base.encode64(<<0x05, 0::size(320)>>)

  setup :verify_on_exit!

  setup %{sandbox_owner: sandbox_owner} do
    cache_pid =
      start_supervised!({Cache, tables: [:accounts, :characters, :assemblies, :nonces, :intel]})

    pubsub = unique_pubsub_name()
    static_data = start_static_data!(sandbox_owner)

    start_supervised!({Phoenix.PubSub, name: pubsub})

    {:ok,
     cache_tables: Cache.tables(cache_pid),
     pubsub: pubsub,
     static_data: static_data,
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
             isolated_detail_live(conn, gate.id, wallet_address, cache_tables, pubsub)

    assert html =~ "Assembly uplink"
    assert html =~ "Gate"
    assert html =~ gate.linked_gate_id
    assert html =~ gate.extension
    assert html =~ "Type"
    assert html =~ "Location Hash"
    assert html =~ "Dashboard"
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
    assert html =~ "Type"
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

    assert html =~ "Inventory Slots"
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
             isolated_detail_live(conn, gate.id, wallet_address, cache_tables, pubsub)

    assert html =~ gate.id
    assert html =~ "online"
    assert html =~ "Gate"
    assert html =~ "Location Hash"
    refute html =~ "Unknown assembly type"
  end

  test "detail view updates on monitor PubSub broadcast", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    turret = Turret.from_json(turret_json(%{"id" => uid("0xmonitor-turret")}))
    registry = unique_registry_name()

    Cache.put(cache_tables.accounts, wallet_address, account)
    Cache.put(cache_tables.assemblies, turret.id, {wallet_address, turret})
    start_supervised!({Registry, keys: :unique, name: registry})
    supervisor = start_supervised!({MonitorSupervisor, registry: registry})

    {:ok, view, html} =
      isolated_detail_live(
        conn,
        turret.id,
        wallet_address,
        cache_tables,
        pubsub,
        monitor_supervisor: supervisor,
        monitor_registry: registry
      )

    assert html =~ "Defense Turret"

    updated_turret =
      Turret.from_json(
        turret_json(%{
          "id" => uid(turret.id),
          "metadata" => %{
            "assembly_id" => "0xturret-metadata",
            "name" => "Defense Turret Monitor Prime",
            "description" => "Upgraded by monitor",
            "url" => "https://example.test/turrets/monitor-prime"
          }
        })
      )

    Phoenix.PubSub.broadcast(
      pubsub,
      "assembly:#{turret.id}",
      {:assembly_monitor, turret.id, %{changes: [], assembly: updated_turret, depletion: nil}}
    )

    updated_html = render(view)

    assert updated_html =~ "Defense Turret Monitor Prime"
    refute updated_html =~ ">Defense Turret<"
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

    Sigil.Sui.ClientMock
    |> Hammox.expect(:get_object, fn "0xmissing", _opts -> {:error, :not_found} end)

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
             |> element("a[data-phx-link][href='/']", "Dashboard")
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
             isolated_detail_live(conn, gate.id, wallet_address, cache_tables, pubsub)

    assert html =~ "Gate 0x"
    refute html =~ "No description provided"
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

  test "NetworkNode detail shows fuel depletion prediction", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    node = NetworkNode.from_json(network_node_json(%{"id" => uid("0xdepletion-node")}))
    registry = unique_registry_name()

    Cache.put(cache_tables.accounts, wallet_address, account)
    Cache.put(cache_tables.assemblies, node.id, {wallet_address, node})
    start_supervised!({Registry, keys: :unique, name: registry})
    supervisor = start_supervised!({MonitorSupervisor, registry: registry})

    {:ok, view, html} =
      isolated_detail_live(
        conn,
        node.id,
        wallet_address,
        cache_tables,
        pubsub,
        monitor_supervisor: supervisor,
        monitor_registry: registry
      )

    assert html =~ "Fuel Panel"
    assert html =~ "Depletes at"
    refute html =~ "2042-01-01 01:00:00 UTC"

    {:ok, depletes_at, 0} = DateTime.from_iso8601("2042-01-01T01:00:00Z")
    depletion = {:depletes_at, depletes_at}

    Phoenix.PubSub.broadcast(
      pubsub,
      "assembly:#{node.id}",
      {:assembly_monitor, node.id, %{changes: [], assembly: node, depletion: depletion}}
    )

    updated_html = render(view)

    assert updated_html =~ "Depletes at"
    assert updated_html =~ "in "
    refute updated_html =~ "Not burning"
    refute updated_html =~ "No fuel"
  end

  test "NetworkNode detail shows not burning when fuel idle", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)

    node =
      NetworkNode.from_json(
        network_node_json(%{
          "id" => uid("0xidle-fuel-node"),
          "fuel" => %{
            "max_capacity" => "5000",
            "burn_rate_in_ms" => "60000",
            "type_id" => "42",
            "unit_volume" => "2",
            "quantity" => "50",
            "is_burning" => false,
            "previous_cycle_elapsed_time" => "7",
            "burn_start_time" => "8",
            "last_updated" => "9"
          }
        })
      )

    registry = unique_registry_name()

    Cache.put(cache_tables.accounts, wallet_address, account)
    Cache.put(cache_tables.assemblies, node.id, {wallet_address, node})
    start_supervised!({Registry, keys: :unique, name: registry})
    supervisor = start_supervised!({MonitorSupervisor, registry: registry})

    {:ok, view, _html} =
      isolated_detail_live(
        conn,
        node.id,
        wallet_address,
        cache_tables,
        pubsub,
        monitor_supervisor: supervisor,
        monitor_registry: registry
      )

    Phoenix.PubSub.broadcast(
      pubsub,
      "assembly:#{node.id}",
      {:assembly_monitor, node.id, %{changes: [], assembly: node, depletion: :not_burning}}
    )

    html = render(view)
    assert html =~ "Not burning"
    refute html =~ "Depletes at"
    refute html =~ ~s(phx-hook="FuelCountdown")
  end

  test "non-NetworkNode assemblies do not show depletion", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    gate = Gate.from_json(gate_json(%{"id" => uid("0xno-depletion-gate")}))
    registry = unique_registry_name()

    Cache.put(cache_tables.accounts, wallet_address, account)
    Cache.put(cache_tables.assemblies, gate.id, {wallet_address, gate})
    start_supervised!({Registry, keys: :unique, name: registry})
    supervisor = start_supervised!({MonitorSupervisor, registry: registry})

    {:ok, _view, html} =
      isolated_detail_live(
        conn,
        gate.id,
        wallet_address,
        cache_tables,
        pubsub,
        monitor_supervisor: supervisor,
        monitor_registry: registry
      )

    assert html =~ "Jump Gate Alpha"
    refute html =~ "Depletes at"
    refute html =~ "Not burning"
    refute html =~ "No fuel"
  end

  test "mount ensures monitor is running for assembly", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    gate = Gate.from_json(gate_json(%{"id" => uid("0xmount-monitor-gate")}))
    registry = unique_registry_name()

    Cache.put(cache_tables.accounts, wallet_address, account)
    Cache.put(cache_tables.assemblies, gate.id, {wallet_address, gate})
    start_supervised!({Registry, keys: :unique, name: registry})
    supervisor = start_supervised!({MonitorSupervisor, registry: registry})

    {:ok, _view, _html} =
      isolated_detail_live(
        conn,
        gate.id,
        wallet_address,
        cache_tables,
        pubsub,
        monitor_supervisor: supervisor,
        monitor_registry: registry
      )

    assert {:ok, _monitor} = MonitorSupervisor.get_monitor(registry, gate.id)
  end

  @tag :acceptance
  test "assembly detail UI updates through full event-driven monitor path", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    assembly_id = hex_id(144)

    node =
      NetworkNode.from_json(
        network_node_json(%{
          "id" => uid(assembly_id),
          "metadata" => %{
            "assembly_id" => "0xnode-event-driven",
            "name" => "Node One",
            "description" => "Network node",
            "url" => "https://example.test/nodes/1"
          }
        })
      )

    event_node =
      NetworkNode.from_json(
        network_node_json(%{
          "id" => uid(assembly_id),
          "metadata" => %{
            "assembly_id" => "0xnode-event-driven",
            "name" => "Node Event Prime",
            "description" => "Updated by event-driven monitor",
            "url" => "https://example.test/nodes/event-prime"
          }
        })
      )

    registry = unique_registry_name()
    topic = "chain_events:assembly-detail:#{System.unique_integer([:positive])}"
    parent = self()

    Cache.put(cache_tables.accounts, wallet_address, account)
    Cache.put(cache_tables.assemblies, node.id, {wallet_address, node})
    start_supervised!({Registry, keys: :unique, name: registry})

    monitor_supervisor = start_supervised!({MonitorSupervisor, registry: registry})

    sync_fun = fn ^assembly_id, _opts ->
      send(parent, {:event_driven_sync_called, assembly_id})
      {:ok, event_node}
    end

    assert {:ok, _monitor} =
             MonitorSupervisor.start_monitor(
               monitor_supervisor,
               assembly_id: assembly_id,
               tables: cache_tables,
               pubsub: pubsub,
               registry: registry,
               interval_ms: 60_000,
               sync_fun: sync_fun
             )

    router =
      start_supervised!({
        Sigil.GameState.AssemblyEventRouter,
        pubsub: pubsub, topic: topic, registry: registry
      })

    _router_state = :sys.get_state(router)
    :ok = Phoenix.PubSub.subscribe(pubsub, "assembly:#{assembly_id}")

    {:ok, view, html} =
      isolated_detail_live(
        conn,
        node.id,
        wallet_address,
        cache_tables,
        pubsub,
        monitor_supervisor: monitor_supervisor,
        monitor_registry: registry
      )

    assert html =~ "Node One"

    Phoenix.PubSub.broadcast(pubsub, topic, {
      :chain_event,
      :assembly_status_changed,
      %{"assembly_id" => assembly_id, "status" => "ONLINE"},
      7701
    })

    assert_receive {:event_driven_sync_called, ^assembly_id}, 1_000
    assert_receive {:assembly_monitor, ^assembly_id, _payload}, 1_000

    updated_html = render(view)

    assert updated_html =~ "Node Event Prime"
    refute updated_html =~ "Assembly not found"
    refute updated_html =~ "Connect Your Wallet"

    Phoenix.PubSub.broadcast(pubsub, topic, {
      :chain_event,
      :assembly_status_changed,
      %{"assembly_id" => assembly_id, "status" => "ONLINE"},
      7702
    })

    refute_receive {:event_driven_sync_called, ^assembly_id}, 200
  end

  @tag :acceptance
  test "wallet verification → navigate to gate detail", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    gate = Gate.from_json(gate_json(%{"id" => uid("0xacceptance-gate-detail")}))
    character_type = character_type()

    Cache.put(cache_tables.assemblies, gate.id, {wallet_address, gate})

    expect(Sigil.Sui.ClientMock, :verify_zklogin_signature, fn _bytes,
                                                               @zklogin_sig,
                                                               "PERSONAL_MESSAGE",
                                                               ^wallet_address,
                                                               [] ->
      {:ok, %{"verifyZkLoginSignature" => %{"success" => true}}}
    end)

    expect(Sigil.Sui.ClientMock, :get_objects, fn [type: ^character_type], [] ->
      {:ok,
       %{
         data: [character_json(%{"character_address" => wallet_address})],
         has_next_page: false,
         end_cursor: nil
       }}
    end)

    # Generate nonce through the real LiveView flow
    {:ok, view, _html} =
      live(
        init_test_session(conn, %{"cache_tables" => cache_tables, "pubsub" => pubsub}),
        "/"
      )

    view
    |> element("#wallet-connect")
    |> render_hook("wallet_connected", %{"address" => wallet_address, "name" => "Eve Vault"})

    assert_push_event(view, "request_sign", %{"nonce" => nonce})

    message = "Sign in to Sigil: #{nonce}"
    bytes = Base.encode64(message)

    # POST to /session with real nonce from server
    conn =
      conn
      |> init_test_session(%{"cache_tables" => cache_tables, "pubsub" => pubsub})
      |> post("/session", %{
        "wallet_address" => wallet_address,
        "bytes" => bytes,
        "signature" => zklogin_signature(),
        "nonce" => nonce
      })

    assert redirected_to(conn) == "/"

    assert {:ok, _view, html} = live(recycle(conn), "/assembly/#{gate.id}")

    assert html =~ "Jump Gate Alpha"
    assert html =~ gate.linked_gate_id
    assert html =~ gate.extension
    assert html =~ "Type"
    refute html =~ "Assembly not found"
    refute html =~ "Connect Your Wallet"
  end

  test "gate detail shows authorize button when no extension and user is owner", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)

    gate =
      Gate.from_json(gate_json(%{"id" => uid("0xowned-gate-no-extension"), "extension" => nil}))

    Cache.put(cache_tables.accounts, wallet_address, account)
    Cache.put(cache_tables.assemblies, gate.id, {wallet_address, gate})

    assert {:ok, _view, html} =
             isolated_gate_extension_live(conn, gate.id, wallet_address, cache_tables, pubsub)

    assert html =~ "No extension configured"
    assert html =~ "Authorize Sigil Extension"
    refute html =~ "Extension Active"
    refute html =~ "Reconnect your wallet"
  end

  test "gate detail hides authorize button for non-owner", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)

    gate =
      Gate.from_json(gate_json(%{"id" => uid("0xforeign-gate-no-extension"), "extension" => nil}))

    other_owner = unique_wallet_address()

    Cache.put(cache_tables.accounts, wallet_address, account)
    Cache.put(cache_tables.assemblies, gate.id, {other_owner, gate})

    assert {:ok, _view, html} =
             isolated_gate_extension_live(conn, gate.id, wallet_address, cache_tables, pubsub)

    assert html =~ gate.linked_gate_id
    assert html =~ "None"
    refute html =~ "Authorize Sigil Extension"
    refute html =~ "No extension configured"
    refute html =~ "Reconnect your wallet"
  end

  test "missing active character hides authorize action", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_without_characters_fixture(wallet_address)

    gate =
      Gate.from_json(gate_json(%{"id" => uid("0xowned-gate-no-character"), "extension" => nil}))

    Cache.put(cache_tables.accounts, wallet_address, account)
    Cache.put(cache_tables.assemblies, gate.id, {wallet_address, gate})

    assert {:ok, _view, html} =
             isolated_gate_extension_live(conn, gate.id, wallet_address, cache_tables, pubsub)

    assert html =~ "Reconnect your wallet"
    refute html =~ "Authorize Sigil Extension"
    refute html =~ "Extension Active"
    refute html =~ "Approve in your wallet"
  end

  test "authorize extension prompts wallet approval", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    {account, character_id} = signing_account_fixture(wallet_address)

    gate =
      signing_gate_fixture(32, 33, %{
        "extension" => nil,
        "metadata" => %{
          "assembly_id" => "0xgate-metadata",
          "name" => "Jump Gate Alpha",
          "description" => "Gate description",
          "url" => "https://example.test/gates/alpha"
        }
      })

    Cache.put(cache_tables.accounts, wallet_address, account)
    Cache.put(cache_tables.assemblies, gate.id, {wallet_address, gate})
    expect_gate_extension_build(gate, character_id)

    {:ok, view, _html} =
      isolated_gate_extension_live(conn, gate.id, wallet_address, cache_tables, pubsub)

    assert render(view) =~ "Authorize Sigil Extension"

    assert has_element?(view, "button", "Authorize Sigil Extension")

    view
    |> element("button", "Authorize Sigil Extension")
    |> render_click()

    assert_push_event(view, "request_sign_transaction", %{"tx_bytes" => tx_bytes})
    assert is_binary(tx_bytes)

    html = render(view)
    assert html =~ "Approve in your wallet"
    refute html =~ "Extension authorized successfully"
    refute html =~ "Transaction failed"
  end

  test "signed transaction shows success flash", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    {account, character_id} = signing_account_fixture(wallet_address)
    gate = signing_gate_fixture(34, 35, %{"extension" => nil})
    gate_id = gate.id
    owner_cap_id = gate.owner_cap_id
    updated_extension = unique_wallet_address()

    Cache.put(cache_tables.accounts, wallet_address, account)
    Cache.put(cache_tables.assemblies, gate.id, {wallet_address, gate})
    expect_gate_extension_build(gate, character_id)
    test_pid = self()

    expect(Sigil.Sui.ClientMock, :execute_transaction, fn submitted_tx_bytes,
                                                          ["wallet-signature"],
                                                          [] ->
      send(test_pid, {:extension_submit_attempted, submitted_tx_bytes})

      {:ok,
       %{
         "status" => "SUCCESS",
         "digest" => "gate-extension-success",
         "effectsBcs" => "effects-bcs-success"
       }}
    end)

    expect(Sigil.Sui.ClientMock, :get_object, fn ^gate_id, [] ->
      {:ok,
       gate_json(%{
         "id" => uid(gate_id),
         "owner_cap_id" => uid(owner_cap_id),
         "extension" => updated_extension
       })}
    end)

    {:ok, view, _html} =
      isolated_gate_extension_live(conn, gate.id, wallet_address, cache_tables, pubsub)

    assert render(view) =~ "Authorize Sigil Extension"

    assert has_element?(view, "button", "Authorize Sigil Extension")

    view
    |> element("button", "Authorize Sigil Extension")
    |> render_click()

    assert_push_event(view, "request_sign_transaction", %{"tx_bytes" => tx_bytes})

    render_hook(view, "transaction_signed", %{
      "bytes" => tx_bytes,
      "signature" => "wallet-signature"
    })

    assert_receive {:extension_submit_attempted, ^tx_bytes}

    html = render(view)
    assert html =~ "Extension authorized successfully"
    assert html =~ updated_extension
    refute html =~ "Approve in your wallet"
    refute html =~ "No extension configured"
  end

  test "wallet signing error shows flash", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    {account, character_id} = signing_account_fixture(wallet_address)
    gate = signing_gate_fixture(36, 37, %{"extension" => nil})

    Cache.put(cache_tables.accounts, wallet_address, account)
    Cache.put(cache_tables.assemblies, gate.id, {wallet_address, gate})
    expect_gate_extension_build(gate, character_id)

    {:ok, view, _html} =
      isolated_gate_extension_live(conn, gate.id, wallet_address, cache_tables, pubsub)

    assert render(view) =~ "Authorize Sigil Extension"

    assert has_element?(view, "button", "Authorize Sigil Extension")

    view
    |> element("button", "Authorize Sigil Extension")
    |> render_click()

    assert_push_event(view, "request_sign_transaction", %{"tx_bytes" => _tx_bytes})

    render_hook(view, "transaction_error", %{"reason" => "User rejected the request"})

    html = render(view)
    assert has_element?(view, "[role=alert]")
    assert html =~ "User rejected the request"
    refute html =~ "Approve in your wallet"
    refute html =~ "Extension authorized successfully"
  end

  test "signing overlay is visible during approval", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    {account, character_id} = signing_account_fixture(wallet_address)
    gate = signing_gate_fixture(38, 39, %{"extension" => nil})

    Cache.put(cache_tables.accounts, wallet_address, account)
    Cache.put(cache_tables.assemblies, gate.id, {wallet_address, gate})
    expect_gate_extension_build(gate, character_id)

    {:ok, view, _html} =
      isolated_gate_extension_live(conn, gate.id, wallet_address, cache_tables, pubsub)

    assert render(view) =~ "Authorize Sigil Extension"

    assert has_element?(view, "button", "Authorize Sigil Extension")

    view
    |> element("button", "Authorize Sigil Extension")
    |> render_click()

    assert_push_event(view, "request_sign_transaction", %{"tx_bytes" => _tx_bytes})

    html = render(view)
    assert html =~ "Approve in your wallet"
    refute html =~ "Extension authorized successfully"
    refute html =~ "Reconnect your wallet"
  end

  test "extension status shown with authorize button", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    gate = Gate.from_json(gate_json(%{"id" => uid("0xowned-gate-with-extension")}))

    Cache.put(cache_tables.accounts, wallet_address, account)
    Cache.put(cache_tables.assemblies, gate.id, {wallet_address, gate})

    assert {:ok, _view, html} =
             isolated_gate_extension_live(conn, gate.id, wallet_address, cache_tables, pubsub)

    assert html =~ gate.extension
    assert html =~ "Extension Active"
    assert html =~ "Re-authorize Extension"
    refute html =~ "No extension configured"
    refute html =~ "Reconnect your wallet"
  end

  @tag :acceptance
  test "authenticated owner authorizes gate extension and sees updated status", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    {account, character_id} = signing_account_fixture(wallet_address)
    gate = signing_gate_fixture(40, 41, %{"extension" => nil})
    gate_id = gate.id
    owner_cap_id = gate.owner_cap_id
    updated_extension = unique_wallet_address()

    Cache.put(cache_tables.accounts, wallet_address, account)
    Cache.put(cache_tables.assemblies, gate.id, {wallet_address, gate})
    expect_gate_extension_build(gate, character_id)
    test_pid = self()

    expect(Sigil.Sui.ClientMock, :execute_transaction, fn submitted_tx_bytes,
                                                          ["wallet-signature"],
                                                          [] ->
      send(test_pid, {:extension_submit_attempted, submitted_tx_bytes})

      {:ok,
       %{
         "status" => "SUCCESS",
         "digest" => "gate-extension-acceptance",
         "effectsBcs" => "effects-bcs-acceptance"
       }}
    end)

    expect(Sigil.Sui.ClientMock, :get_object, fn ^gate_id, [] ->
      {:ok,
       gate_json(%{
         "id" => uid(gate_id),
         "owner_cap_id" => uid(owner_cap_id),
         "extension" => updated_extension
       })}
    end)

    {:ok, view, _html} =
      live(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub),
        "/assembly/#{gate.id}"
      )

    assert render(view) =~ "Authorize Sigil Extension"

    assert has_element?(view, "button", "Authorize Sigil Extension")

    view
    |> element("button", "Authorize Sigil Extension")
    |> render_click()

    assert_push_event(view, "request_sign_transaction", %{"tx_bytes" => tx_bytes})

    render_hook(view, "transaction_signed", %{
      "bytes" => tx_bytes,
      "signature" => "wallet-signature"
    })

    assert_receive {:extension_submit_attempted, ^tx_bytes}

    html = render(view)
    assert html =~ "Extension Active"
    assert html =~ updated_extension
    refute html =~ "No extension configured"
    refute html =~ "Transaction failed"
  end

  test "authorize failure shows error flash", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    {account, _character_id} = signing_account_fixture(wallet_address)
    gate = signing_gate_fixture(44, 45, %{"extension" => nil})
    owner_cap_id = gate.owner_cap_id

    Cache.put(cache_tables.accounts, wallet_address, account)
    Cache.put(cache_tables.assemblies, gate.id, {wallet_address, gate})

    expect(Sigil.Sui.ClientMock, :get_object_with_ref, fn ^owner_cap_id, [] ->
      {:error, :timeout}
    end)

    {:ok, view, _html} =
      isolated_gate_extension_live(conn, gate.id, wallet_address, cache_tables, pubsub)

    assert render(view) =~ "Authorize Sigil Extension"

    assert has_element?(view, "button", "Authorize Sigil Extension")

    html =
      view
      |> element("button", "Authorize Sigil Extension")
      |> render_click()

    assert has_element?(view, "[role=alert]")
    assert html =~ "timeout"
    refute html =~ "Approve in your wallet"
    refute html =~ "Extension authorized successfully"
  end

  test "submit failure shows error flash", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    {account, character_id} = signing_account_fixture(wallet_address)
    gate = signing_gate_fixture(42, 43, %{"extension" => nil})

    Cache.put(cache_tables.accounts, wallet_address, account)
    Cache.put(cache_tables.assemblies, gate.id, {wallet_address, gate})
    expect_gate_extension_build(gate, character_id)
    test_pid = self()

    expect(Sigil.Sui.ClientMock, :execute_transaction, fn submitted_tx_bytes,
                                                          ["wallet-signature"],
                                                          [] ->
      send(test_pid, {:extension_submit_attempted, submitted_tx_bytes})
      {:error, :timeout}
    end)

    {:ok, view, _html} =
      isolated_gate_extension_live(conn, gate.id, wallet_address, cache_tables, pubsub)

    assert render(view) =~ "Authorize Sigil Extension"

    assert has_element?(view, "button", "Authorize Sigil Extension")

    view
    |> element("button", "Authorize Sigil Extension")
    |> render_click()

    assert_push_event(view, "request_sign_transaction", %{"tx_bytes" => tx_bytes})

    render_hook(view, "transaction_signed", %{
      "bytes" => tx_bytes,
      "signature" => "wallet-signature"
    })

    assert_receive {:extension_submit_attempted, ^tx_bytes}

    html = render(view)
    assert has_element?(view, "[role=alert]")
    assert html =~ "timeout"
    refute html =~ "Approve in your wallet"
    refute html =~ "Extension authorized successfully"
  end

  test "wallet_detected event is handled without crashing", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    gate = Gate.from_json(gate_json(%{"id" => uid("0xwallet-detected-gate")}))

    Cache.put(cache_tables.accounts, wallet_address, account)
    Cache.put(cache_tables.assemblies, gate.id, {wallet_address, gate})

    {:ok, view, _html} =
      isolated_gate_extension_live(conn, gate.id, wallet_address, cache_tables, pubsub)

    # The WalletConnect hook fires wallet_detected on mount — must not crash
    render_hook(view, "wallet_detected", %{"wallets" => ["Eve Vault"]})

    html = render(view)
    assert html =~ "Jump Gate Alpha"
    assert html =~ "Assembly uplink"
  end

  test "wallet_error event is handled without crashing", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    gate = Gate.from_json(gate_json(%{"id" => uid("0xwallet-error-gate")}))

    Cache.put(cache_tables.accounts, wallet_address, account)
    Cache.put(cache_tables.assemblies, gate.id, {wallet_address, gate})

    {:ok, view, _html} =
      isolated_gate_extension_live(conn, gate.id, wallet_address, cache_tables, pubsub)

    # The WalletConnect hook may fire wallet_error — must not crash
    render_hook(view, "wallet_error", %{"reason" => "No wallets found"})

    html = render(view)
    assert html =~ "Jump Gate Alpha"
  end

  test "transaction_signed pushes report_transaction_effects to wallet hook", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    {account, character_id} = signing_account_fixture(wallet_address)
    gate = signing_gate_fixture(46, 47, %{"extension" => nil})
    gate_id = gate.id
    owner_cap_id = gate.owner_cap_id
    updated_extension = unique_wallet_address()

    Cache.put(cache_tables.accounts, wallet_address, account)
    Cache.put(cache_tables.assemblies, gate.id, {wallet_address, gate})
    expect_gate_extension_build(gate, character_id)
    test_pid = self()

    expect(Sigil.Sui.ClientMock, :execute_transaction, fn submitted_tx_bytes,
                                                          ["wallet-signature"],
                                                          [] ->
      send(test_pid, {:extension_submit_attempted, submitted_tx_bytes})

      {:ok,
       %{
         "status" => "SUCCESS",
         "digest" => "gate-extension-effects",
         "effectsBcs" => "effects-bcs-data"
       }}
    end)

    expect(Sigil.Sui.ClientMock, :get_object, fn ^gate_id, [] ->
      {:ok,
       gate_json(%{
         "id" => uid(gate_id),
         "owner_cap_id" => uid(owner_cap_id),
         "extension" => updated_extension
       })}
    end)

    {:ok, view, _html} =
      isolated_gate_extension_live(conn, gate.id, wallet_address, cache_tables, pubsub)

    view
    |> element("button", "Authorize Sigil Extension")
    |> render_click()

    assert_push_event(view, "request_sign_transaction", %{"tx_bytes" => tx_bytes})

    render_hook(view, "transaction_signed", %{
      "bytes" => tx_bytes,
      "signature" => "wallet-signature"
    })

    assert_receive {:extension_submit_attempted, ^tx_bytes}

    # Verify report_transaction_effects was pushed to the wallet hook
    assert_push_event(view, "report_transaction_effects", %{effects: "effects-bcs-data"})

    html = render(view)
    assert html =~ "Extension authorized successfully"
  end

  describe "intel location integration" do
    test "assembly detail shows reported location from tribe intel", %{
      conn: conn,
      cache_tables: cache_tables,
      pubsub: pubsub,
      wallet_address: wallet_address,
      static_data: static_data
    } do
      account = account_fixture(wallet_address)
      gate = Gate.from_json(gate_json(%{"id" => uid("0xintel-location-gate")}))

      report =
        insert_location_report!(%{
          tribe_id: account.tribe_id,
          assembly_id: gate.id,
          solar_system_id: 30_000_001,
          reported_by: wallet_address,
          reported_by_character_id: hd(account.characters).id,
          reported_by_name: "Captain Frontier"
        })

      Cache.put(cache_tables.accounts, wallet_address, account)
      Cache.put(cache_tables.assemblies, gate.id, {wallet_address, gate})
      Cache.put(cache_tables.intel, {:location, account.tribe_id, gate.id}, report)

      assert {:ok, _view, html} =
               isolated_detail_live(
                 conn,
                 gate.id,
                 wallet_address,
                 cache_tables,
                 pubsub,
                 static_data: static_data
               )

      assert html =~ "Location"
      assert html =~ "A 2560"
      refute html =~ "Location unknown"
    end

    test "location form visible for tribe members", %{
      conn: conn,
      cache_tables: cache_tables,
      pubsub: pubsub,
      wallet_address: wallet_address,
      static_data: static_data
    } do
      account = account_fixture(wallet_address)
      gate = Gate.from_json(gate_json(%{"id" => uid("0xintel-form-gate"), "extension" => nil}))

      Cache.put(cache_tables.accounts, wallet_address, account)
      Cache.put(cache_tables.assemblies, gate.id, {wallet_address, gate})

      assert {:ok, _view, html} =
               isolated_detail_live(
                 conn,
                 gate.id,
                 wallet_address,
                 cache_tables,
                 pubsub,
                 static_data: static_data
               )

      assert html =~ "Set Location"
      assert html =~ "Solar system name"
      assert html =~ "Type to search"
      refute html =~ "Solar system data not available"
    end

    test "Set Location creates intel report and updates display", %{
      conn: conn,
      cache_tables: cache_tables,
      pubsub: pubsub,
      wallet_address: wallet_address,
      static_data: static_data
    } do
      account = account_fixture(wallet_address)
      gate = Gate.from_json(gate_json(%{"id" => uid("0xintel-submit-gate"), "extension" => nil}))

      Cache.put(cache_tables.accounts, wallet_address, account)
      Cache.put(cache_tables.assemblies, gate.id, {wallet_address, gate})

      {:ok, view, _html} =
        isolated_detail_live(
          conn,
          gate.id,
          wallet_address,
          cache_tables,
          pubsub,
          static_data: static_data
        )

      html =
        view
        |> form("#set-location-form", %{"location" => %{"solar_system_name" => "A 2560"}})
        |> render_submit()

      assert html =~ "A 2560"
      assert html =~ "Location saved"
      refute html =~ "Location unknown"

      persisted_report =
        Repo.one(
          from report in IntelReport,
            where: report.assembly_id == ^gate.id and report.report_type == :location
        )

      assert %IntelReport{tribe_id: 314, solar_system_id: 30_000_001} = persisted_report
      assert persisted_report.assembly_id == gate.id
    end

    test "Set Location hidden for users without tribe", %{
      conn: conn,
      cache_tables: cache_tables,
      pubsub: pubsub,
      wallet_address: wallet_address,
      static_data: static_data
    } do
      account =
        %Account{
          address: wallet_address,
          characters: [Character.from_json(character_json(%{"tribe_id" => "0"}))],
          tribe_id: nil
        }

      gate =
        Gate.from_json(gate_json(%{"id" => uid("0xintel-no-tribe-gate"), "extension" => nil}))

      Cache.put(cache_tables.accounts, wallet_address, account)
      Cache.put(cache_tables.assemblies, gate.id, {wallet_address, gate})

      assert {:ok, _view, html} =
               isolated_detail_live(
                 conn,
                 gate.id,
                 wallet_address,
                 cache_tables,
                 pubsub,
                 static_data: static_data
               )

      refute html =~ "Set Location"
      refute html =~ "Update Location"
      refute html =~ "Location unknown"
    end

    test "location card updates only for location intel broadcast", %{
      conn: conn,
      cache_tables: cache_tables,
      pubsub: pubsub,
      wallet_address: wallet_address,
      static_data: static_data
    } do
      account = account_fixture(wallet_address)
      gate = Gate.from_json(gate_json(%{"id" => uid("0xintel-broadcast-gate")}))

      Cache.put(cache_tables.accounts, wallet_address, account)
      Cache.put(cache_tables.assemblies, gate.id, {wallet_address, gate})

      {:ok, view, _html} =
        isolated_detail_live(
          conn,
          gate.id,
          wallet_address,
          cache_tables,
          pubsub,
          static_data: static_data
        )

      scouting = %IntelReport{
        id: Ecto.UUID.generate(),
        tribe_id: account.tribe_id,
        assembly_id: gate.id,
        solar_system_id: 30_000_001,
        report_type: :scouting,
        notes: "Scouts spotted",
        reported_by: wallet_address,
        reported_by_character_id: hd(account.characters).id,
        inserted_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now()
      }

      Phoenix.PubSub.broadcast(
        pubsub,
        Sigil.Intel.topic(account.tribe_id, world: "test"),
        {:intel_updated, scouting}
      )

      # Scouting broadcast should not populate the location card
      assert render(view) =~ "Location unknown"

      location = %IntelReport{
        scouting
        | report_type: :location,
          solar_system_id: 30_000_002,
          notes: "Updated location"
      }

      Phoenix.PubSub.broadcast(
        pubsub,
        Sigil.Intel.topic(account.tribe_id, world: "test"),
        {:intel_updated, location}
      )

      html = render(view)
      assert html =~ "B 31337"
      refute html =~ "Location unknown"
    end

    test "location card clears only on location intel deletion", %{
      conn: conn,
      cache_tables: cache_tables,
      pubsub: pubsub,
      wallet_address: wallet_address,
      static_data: static_data
    } do
      account = account_fixture(wallet_address)
      gate = Gate.from_json(gate_json(%{"id" => uid("0xintel-delete-gate")}))

      report =
        insert_location_report!(%{
          tribe_id: account.tribe_id,
          assembly_id: gate.id,
          solar_system_id: 30_000_001,
          reported_by: wallet_address,
          reported_by_character_id: hd(account.characters).id,
          reported_by_name: "Captain Frontier"
        })

      Cache.put(cache_tables.accounts, wallet_address, account)
      Cache.put(cache_tables.assemblies, gate.id, {wallet_address, gate})
      Cache.put(cache_tables.intel, {:location, account.tribe_id, gate.id}, report)

      {:ok, view, _html} =
        isolated_detail_live(
          conn,
          gate.id,
          wallet_address,
          cache_tables,
          pubsub,
          static_data: static_data
        )

      assert render(view) =~ "A 2560"

      scouting = %{report | id: Ecto.UUID.generate(), report_type: :scouting}

      Phoenix.PubSub.broadcast(
        pubsub,
        Sigil.Intel.topic(account.tribe_id, world: "test"),
        {:intel_deleted, scouting}
      )

      assert render(view) =~ "A 2560"

      Phoenix.PubSub.broadcast(
        pubsub,
        Sigil.Intel.topic(account.tribe_id, world: "test"),
        {:intel_deleted, report}
      )

      html = render(view)
      assert html =~ "Location unknown"
      refute html =~ "Forward staging"
    end

    @tag :acceptance
    test "tribe member sets location from detail page", %{
      conn: conn,
      cache_tables: cache_tables,
      pubsub: pubsub,
      wallet_address: wallet_address,
      static_data: static_data
    } do
      gate =
        Gate.from_json(gate_json(%{"id" => uid("0xacceptance-intel-gate"), "extension" => nil}))

      account = account_fixture(wallet_address)

      Cache.put(cache_tables.accounts, wallet_address, account)
      Cache.put(cache_tables.assemblies, gate.id, {wallet_address, gate})

      {:ok, view, _html} =
        live(
          authenticated_conn(conn, wallet_address, cache_tables, pubsub, static_data: static_data),
          "/assembly/#{gate.id}"
        )

      html =
        view
        |> form("#set-location-form", %{"location" => %{"solar_system_name" => "A 2560"}})
        |> render_submit()

      assert html =~ "A 2560"
      refute html =~ "Location unknown"
      refute html =~ "Unknown or ambiguous solar system"
    end

    test "detail Set Location rejects invalid system name", %{
      conn: conn,
      cache_tables: cache_tables,
      pubsub: pubsub,
      wallet_address: wallet_address,
      static_data: static_data
    } do
      account = account_fixture(wallet_address)
      gate = Gate.from_json(gate_json(%{"id" => uid("0xintel-invalid-gate"), "extension" => nil}))

      Cache.put(cache_tables.accounts, wallet_address, account)
      Cache.put(cache_tables.assemblies, gate.id, {wallet_address, gate})

      {:ok, view, _html} =
        isolated_detail_live(
          conn,
          gate.id,
          wallet_address,
          cache_tables,
          pubsub,
          static_data: static_data
        )

      html =
        view
        |> form("#set-location-form", %{"location" => %{"solar_system_name" => "Z 9999"}})
        |> render_submit()

      assert html =~ "Unknown or ambiguous solar system"
      assert html =~ "Z 9999"
      # "A 2560" appears in the datalist but location card should still say unknown
      assert html =~ "Location unknown"
    end

    test "detail hides location editor without active character", %{
      conn: conn,
      cache_tables: cache_tables,
      pubsub: pubsub,
      wallet_address: wallet_address,
      static_data: static_data
    } do
      account = account_without_characters_fixture(wallet_address)

      gate =
        Gate.from_json(gate_json(%{"id" => uid("0xintel-no-character-gate"), "extension" => nil}))

      Cache.put(cache_tables.accounts, wallet_address, account)
      Cache.put(cache_tables.assemblies, gate.id, {wallet_address, gate})

      assert {:ok, _view, html} =
               isolated_detail_live(
                 conn,
                 gate.id,
                 wallet_address,
                 cache_tables,
                 pubsub,
                 static_data: static_data
               )

      refute html =~ "Set Location"
      refute html =~ "Update Location"
      assert html =~ "Location unknown"
      assert html =~ "Jump Gate Alpha"
    end

    test "detail hides location editor without StaticData", %{
      conn: conn,
      cache_tables: cache_tables,
      pubsub: pubsub,
      wallet_address: wallet_address
    } do
      account = account_fixture(wallet_address)

      gate =
        Gate.from_json(
          gate_json(%{"id" => uid("0xintel-no-static-data-gate"), "extension" => nil})
        )

      Cache.put(cache_tables.accounts, wallet_address, account)
      Cache.put(cache_tables.assemblies, gate.id, {wallet_address, gate})

      assert {:ok, _view, html} =
               isolated_detail_live(conn, gate.id, wallet_address, cache_tables, pubsub)

      refute html =~ "Set Location"
      refute html =~ "Update Location"
      assert html =~ "Jump Gate Alpha"
    end

    test "assembly detail shows View on Map link when location reported", %{
      conn: conn,
      cache_tables: cache_tables,
      pubsub: pubsub,
      wallet_address: wallet_address,
      static_data: static_data
    } do
      account = account_fixture(wallet_address)
      gate = Gate.from_json(gate_json(%{"id" => uid("0xintel-map-link-gate")}))

      report =
        insert_location_report!(%{
          tribe_id: account.tribe_id,
          assembly_id: gate.id,
          solar_system_id: 30_000_001,
          reported_by: wallet_address,
          reported_by_character_id: hd(account.characters).id,
          reported_by_name: "Captain Frontier"
        })

      Cache.put(cache_tables.accounts, wallet_address, account)
      Cache.put(cache_tables.assemblies, gate.id, {wallet_address, gate})
      Cache.put(cache_tables.intel, {:location, account.tribe_id, gate.id}, report)

      assert {:ok, _view, html} =
               isolated_detail_live(
                 conn,
                 gate.id,
                 wallet_address,
                 cache_tables,
                 pubsub,
                 static_data: static_data
               )

      assert html =~ "View on Map"
      assert html =~ ~s(href="/map?system_id=#{report.solar_system_id}")
    end

    test "assembly detail hides View on Map link without location report", %{
      conn: conn,
      cache_tables: cache_tables,
      pubsub: pubsub,
      wallet_address: wallet_address,
      static_data: static_data
    } do
      account = account_fixture(wallet_address)

      gate_with_location =
        Gate.from_json(gate_json(%{"id" => uid("0xintel-map-link-control-gate")}))

      gate_with_undisclosed_location =
        Gate.from_json(gate_json(%{"id" => uid("0xintel-map-link-undisclosed-gate")}))

      gate_without_location =
        Gate.from_json(gate_json(%{"id" => uid("0xintel-map-link-none-gate")}))

      report =
        insert_location_report!(%{
          tribe_id: account.tribe_id,
          assembly_id: gate_with_location.id,
          solar_system_id: 30_000_001,
          reported_by: wallet_address,
          reported_by_character_id: hd(account.characters).id,
          reported_by_name: "Captain Frontier"
        })

      undisclosed_report =
        insert_location_report!(%{
          tribe_id: account.tribe_id,
          assembly_id: gate_with_undisclosed_location.id,
          solar_system_id: 0,
          reported_by: wallet_address,
          reported_by_character_id: hd(account.characters).id,
          reported_by_name: "Captain Frontier"
        })

      Cache.put(cache_tables.accounts, wallet_address, account)

      Cache.put(
        cache_tables.assemblies,
        gate_with_location.id,
        {wallet_address, gate_with_location}
      )

      Cache.put(
        cache_tables.assemblies,
        gate_with_undisclosed_location.id,
        {wallet_address, gate_with_undisclosed_location}
      )

      Cache.put(
        cache_tables.assemblies,
        gate_without_location.id,
        {wallet_address, gate_without_location}
      )

      Cache.put(cache_tables.intel, {:location, account.tribe_id, gate_with_location.id}, report)

      Cache.put(
        cache_tables.intel,
        {:location, account.tribe_id, gate_with_undisclosed_location.id},
        undisclosed_report
      )

      assert {:ok, _view, html_with_location} =
               isolated_detail_live(
                 conn,
                 gate_with_location.id,
                 wallet_address,
                 cache_tables,
                 pubsub,
                 static_data: static_data
               )

      assert html_with_location =~ "View on Map"
      assert html_with_location =~ ~s(href="/map?system_id=#{report.solar_system_id}")

      assert {:ok, _view, html_with_undisclosed_location} =
               isolated_detail_live(
                 conn,
                 gate_with_undisclosed_location.id,
                 wallet_address,
                 cache_tables,
                 pubsub,
                 static_data: static_data
               )

      assert html_with_undisclosed_location =~ "Location unknown"
      refute html_with_undisclosed_location =~ "View on Map"
      refute html_with_undisclosed_location =~ ~s(/map?system_id=0)

      assert {:ok, _view, html_without_location} =
               isolated_detail_live(
                 conn,
                 gate_without_location.id,
                 wallet_address,
                 cache_tables,
                 pubsub,
                 static_data: static_data
               )

      assert html_without_location =~ "Location unknown"
      refute html_without_location =~ "View on Map"
      refute html_without_location =~ ~s(/map?system_id=)
    end
  end

  defp expect_empty_dashboard_discovery(_wallet_address) do
    owner_cap_type = owner_cap_type()
    character_id = "0xcharacter-detail"

    expect(Sigil.Sui.ClientMock, :get_objects, fn [type: type, owner: ^character_id], []
                                                  when type == owner_cap_type ->
      {:ok, %{data: [], has_next_page: false, end_cursor: nil}}
    end)
  end

  defp authenticated_conn(conn, wallet_address, cache_tables, pubsub, extra_session \\ %{}) do
    init_test_session(
      conn,
      authenticated_session(wallet_address, cache_tables, pubsub, extra_session)
    )
  end

  defp authenticated_session(wallet_address, cache_tables, pubsub, extra_session) do
    %{
      "wallet_address" => wallet_address,
      "cache_tables" => cache_tables,
      "pubsub" => pubsub
    }
    |> Map.merge(normalize_session(extra_session))
  end

  defp isolated_detail_live(
         conn,
         assembly_id,
         wallet_address,
         cache_tables,
         pubsub,
         extra_session \\ []
       ) do
    extra_session = normalize_session(extra_session)

    live_isolated(conn, SigilWeb.AssemblyDetailLiveIsolatedTestLive,
      session:
        authenticated_session(wallet_address, cache_tables, pubsub, %{
          "assembly_id" => assembly_id
        })
        |> Map.merge(extra_session)
    )
  end

  defp isolated_gate_extension_live(conn, assembly_id, wallet_address, cache_tables, pubsub) do
    isolated_detail_live(conn, assembly_id, wallet_address, cache_tables, pubsub)
  end

  defp character_type do
    "0x1111111111111111111111111111111111111111111111111111111111111111::character::Character"
  end

  defp owner_cap_type do
    "0x1111111111111111111111111111111111111111111111111111111111111111::access::OwnerCap"
  end

  defp account_fixture(wallet_address) do
    %Account{
      address: wallet_address,
      characters: [Character.from_json(character_json())],
      tribe_id: 314
    }
  end

  defp account_without_characters_fixture(wallet_address) do
    %Account{address: wallet_address, characters: [], tribe_id: 314}
  end

  defp signing_account_fixture(wallet_address) do
    character_id = hex_id(31)

    account =
      %Account{
        address: wallet_address,
        characters: [Character.from_json(character_json(%{"id" => uid(character_id)}))],
        tribe_id: 314
      }

    {account, character_id}
  end

  defp signing_gate_fixture(id_byte, owner_cap_byte, overrides) do
    gate_json =
      gate_json(%{
        "id" => uid(hex_id(id_byte)),
        "owner_cap_id" => uid(hex_id(owner_cap_byte)),
        "extension" => "0x2::frontier::GateExtension"
      })
      |> Map.merge(overrides)

    Gate.from_json(gate_json)
  end

  defp expect_gate_extension_build(gate, character_id) do
    expected_tx_bytes =
      expected_gate_extension_tx_bytes(
        gate.id,
        14,
        gate.owner_cap_id,
        19,
        digest_bytes(99),
        character_id,
        10
      )

    expect(Sigil.Sui.ClientMock, :get_object_with_ref, 3, fn
      owner_cap_id, [] when owner_cap_id == gate.owner_cap_id ->
        {:ok, owner_cap_with_ref(owner_cap_id, 19, 99)}

      ^character_id, [] ->
        {:ok, object_with_ref(character_id, 10, 51, 100)}

      gate_id, [] when gate_id == gate.id ->
        {:ok, object_with_ref(gate_id, 14, 52, 101)}
    end)

    expected_tx_bytes
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
    |> Sigil.Sui.TxGateExtension.build_authorize_extension(
      {hex_to_bytes(owner_cap_id), owner_cap_version, owner_cap_digest},
      %{
        object_id: hex_to_bytes(character_id),
        initial_shared_version: character_shared_version
      }
    )
    |> Sigil.Sui.TransactionBuilder.build_kind!()
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

  defp normalize_session(extra_session) when is_map(extra_session), do: extra_session

  defp normalize_session(extra_session) do
    extra_session
    |> Enum.map(fn {key, value} -> {to_string(key), value} end)
    |> Map.new()
  end

  defp unique_pubsub_name do
    :"assembly_detail_pubsub_#{System.unique_integer([:positive])}"
  end

  defp unique_registry_name do
    :"assembly_detail_registry_#{System.unique_integer([:positive])}"
  end

  defp unique_wallet_address do
    suffix =
      System.unique_integer([:positive])
      |> Integer.to_string(16)
      |> String.downcase()
      |> String.pad_leading(64, "0")

    "0x" <> suffix
  end

  defp character_json(overrides \\ %{}) do
    Map.merge(
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
      },
      overrides
    )
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

  defp start_static_data!(sandbox_owner) do
    start_supervised!(
      {StaticData, test_data: StaticDataFixtures.sample_test_data(), mox_owner: sandbox_owner}
    )
  end

  defp insert_location_report!(attrs) do
    %IntelReport{}
    |> IntelReport.location_changeset(
      Map.merge(
        %{
          tribe_id: 314,
          assembly_id: "0xassembly-location",
          solar_system_id: 30_000_001,
          label: "Forward position",
          notes: "Scout-confirmed location",
          reported_by: "0xabc123",
          reported_by_name: "Scout Prime",
          reported_by_character_id: "0xcharacter-detail"
        },
        attrs
      )
    )
    |> Repo.insert!()
  end

  # Base64-encoded bytes starting with zkLogin scheme byte (0x05)
  defp zklogin_signature, do: Base.encode64(<<0x05, 0::size(320)>>)

  defp uid(id), do: %{"id" => id}
end
