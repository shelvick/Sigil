defmodule SigilWeb.DashboardLiveIsolatedTestLive do
  @moduledoc """
  Test-only wrapper that mounts `SigilWeb.DashboardLive` with injectable monitor dependencies.
  """

  use SigilWeb, :live_view

  on_mount SigilWeb.WalletSession

  @doc false
  @impl true
  def mount(params, session, socket) do
    socket =
      socket
      |> maybe_assign_monitor_dependency(:monitor_supervisor, session)
      |> maybe_assign_monitor_dependency(:monitor_registry, session)

    SigilWeb.DashboardLive.mount(params, session, socket)
  end

  @doc false
  @impl true
  def render(assigns), do: SigilWeb.DashboardLive.render(assigns)

  @doc false
  @impl true
  def handle_info(message, socket) do
    SigilWeb.DashboardLive.handle_info(message, socket)
  end

  @doc false
  @impl true
  def handle_event(event, params, socket) do
    SigilWeb.DashboardLive.handle_event(event, params, socket)
  end

  defp maybe_assign_monitor_dependency(socket, key, session) do
    case Map.fetch(session, Atom.to_string(key)) do
      {:ok, value} -> Phoenix.Component.assign(socket, key, value)
      :error -> socket
    end
  end
end

defmodule SigilWeb.DashboardLiveTest do
  @moduledoc """
  Covers authenticated dashboard rendering and end-to-end wallet session flow.
  """

  use Sigil.ConnCase, async: true

  import Hammox

  alias Sigil.Alerts
  alias Sigil.Alerts.Alert
  alias Sigil.Cache
  alias Sigil.Accounts.Account
  alias Sigil.GameState.MonitorSupervisor
  alias Sigil.Repo
  alias Sigil.Sui.Types.{Character, Gate, NetworkNode, Turret}

  @world_package_id "0x1111111111111111111111111111111111111111111111111111111111111111"
  @zklogin_sig Base.encode64(<<0x05, 0::size(320)>>)

  setup :verify_on_exit!

  setup do
    cache_pid = start_supervised!({Cache, tables: [:accounts, :characters, :assemblies, :nonces]})
    pubsub = unique_pubsub_name()

    start_supervised!({Phoenix.PubSub, name: pubsub})

    {:ok,
     cache_tables: Cache.tables(cache_pid),
     pubsub: pubsub,
     wallet_address: unique_wallet_address()}
  end

  test "renders wallet connect button when not authenticated", %{conn: conn} do
    assert {:ok, _view, html} = live(conn, "/")

    assert html =~ "Connect Your Wallet"
    assert html =~ "Connect Wallet"
    assert html =~ ~s(id="wallet-connect")
    assert html =~ ~s(phx-hook="WalletConnect")
    refute html =~ "Wallet Address"
    refute html =~ ~s(<form action="/session" method="post")
    refute html =~ "Operational Assets"
  end

  test "shows install wallet message when no wallets detected", %{conn: conn} do
    assert {:ok, _view, html} = live(conn, "/")

    assert html =~ "No Sui wallet detected. Install EVE Vault to continue."
    refute html =~ "Disconnect Wallet"
    refute html =~ "Operational Assets"
  end

  test "wallet hook mount triggers wallet_detected event", %{conn: conn} do
    {:ok, view, initial_html} = live(conn, "/")

    assert initial_html =~ "Connect Your Wallet"

    html = render_hook(view, "wallet_detected", %{"wallets" => []})

    assert html =~ "No Sui wallet detected. Install EVE Vault to continue."
    refute html =~ "Disconnect Wallet"
    refute html =~ "Operational Assets"
  end

  test "single detected wallet auto-connects", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    html = render_hook(view, "wallet_detected", %{"wallets" => [wallet_payload("Eve Vault")]})

    assert_push_event(view, "connect_wallet", %{"index" => 0})
    assert html =~ "Connecting to wallet..."
    assert html =~ "Eve Vault"
  end

  test "multiple detected wallets render picker and allow selection", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    html =
      render_hook(view, "wallet_detected", %{
        "wallets" => [wallet_payload("Eve Vault"), wallet_payload("Sui Wallet")]
      })

    assert html =~ "Available wallets"
    assert html =~ "Eve Vault"
    assert html =~ "Sui Wallet"
    assert html =~ "Connect"
    assert html =~ "https://example.test/Eve-Vault.png"
    assert html =~ "https://example.test/Sui-Wallet.png"

    selected_html =
      view
      |> element(~s(button[phx-click="select_wallet"][phx-value-index="1"]))
      |> render_click()

    assert_push_event(view, "connect_wallet", %{"index" => 1})
    assert selected_html =~ "Connecting to wallet..."
  end

  test "wallet_accounts event renders account picker with addresses and labels", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    labeled_address = unique_wallet_address()
    unlabeled_address = unique_wallet_address()

    html =
      view
      |> element("#wallet-connect")
      |> render_hook("wallet_accounts", %{
        "accounts" => [
          account_payload(labeled_address, "Main Bridge"),
          account_payload(unlabeled_address)
        ]
      })

    assert html =~ "Select Account"
    assert html =~ "Main Bridge"
    assert html =~ truncate_id(unlabeled_address)
    refute html =~ "No Sui wallet detected"
    refute html =~ "Connecting to wallet..."
  end

  test "selecting account pushes select_account to hook", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    view
    |> element("#wallet-connect")
    |> render_hook("wallet_accounts", %{
      "accounts" => [
        account_payload(unique_wallet_address(), "Reserve"),
        account_payload(unique_wallet_address(), "Fleet Command")
      ]
    })

    selected_html =
      view
      |> element(~s(button[phx-click="select_account"][phx-value-index="1"]))
      |> render_click()

    assert_push_event(view, "select_account", %{"index" => 1})
    assert selected_html =~ "Connecting to wallet..."
    refute selected_html =~ "Select Account"
  end

  test "wallet_connected generates nonce and pushes request_sign", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    {:ok, view, _html} =
      live(init_test_session(conn, %{"cache_tables" => cache_tables, "pubsub" => pubsub}), "/")

    view
    |> element("#wallet-connect")
    |> render_hook("wallet_connected", %{"address" => wallet_address, "name" => "Eve Vault"})

    assert_push_event(view, "request_sign", %{"nonce" => _, "message" => _})

    assert [%{address: ^wallet_address, item_id: nil, tenant: nil}] =
             Cache.all(cache_tables.nonces)
  end

  test "mount captures itemId and tenant from URL params", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    {:ok, view, html} =
      live(
        init_test_session(conn, %{"cache_tables" => cache_tables, "pubsub" => pubsub}),
        "/?itemId=0xassembly-123&tenant=stillness"
      )

    assert html =~ "Connect Your Wallet"

    view
    |> element("#wallet-connect")
    |> render_hook("wallet_connected", %{"address" => wallet_address, "name" => "Eve Vault"})

    assert_push_event(view, "request_sign", %{"nonce" => _, "message" => _})

    assert [%{address: ^wallet_address, item_id: "0xassembly-123", tenant: "stillness"}] =
             Cache.all(cache_tables.nonces)
  end

  test "wallet_error shows flash error and retry button", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    view
    |> element("#wallet-connect")
    |> render_hook("wallet_error", %{"reason" => "Signing request timed out"})

    html = render(view)

    # Flash error is rendered (via put_flash, shown in flash_group)
    assert has_element?(view, "[role=alert]", "Signing request timed out")
    # Inline error state with retry
    assert html =~ "Try Again"
    refute html =~ "Wallet Address"
  end

  test "late wallet_detected does not interrupt active signing flow", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    {:ok, view, _html} =
      live(init_test_session(conn, %{"cache_tables" => cache_tables, "pubsub" => pubsub}), "/")

    # Connect a wallet first to enter signing state
    view
    |> element("#wallet-connect")
    |> render_hook("wallet_connected", %{"address" => wallet_address, "name" => "Eve Vault"})

    assert_push_event(view, "request_sign", %{"nonce" => _})

    # Now simulate a late wallet_detected event (new wallet registering after timeout)
    html =
      view
      |> element("#wallet-connect")
      |> render_hook("wallet_detected", %{
        "wallets" => [wallet_payload("Eve Vault"), wallet_payload("Suiet")]
      })

    # Should still show signing state, not reset to wallet picker
    assert html =~ "approve the signing request"
    refute html =~ "Available wallets"
  end

  test "wallet_account_changed shows re-auth notification", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    view
    |> element("#wallet-connect")
    |> render_hook("wallet_account_changed", %{})

    html = render(view)

    assert has_element?(
             view,
             "[role=alert]",
             "Wallet account changed. Re-authenticate to switch."
           )

    assert html =~ "Wallet account changed. Re-authenticate to switch."
    refute html =~ "Selected account not available"
    # wallet_state remains unchanged — only a flash notification is shown
  end

  test "single account wallet skips account picker", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    {:ok, view, _html} =
      live(init_test_session(conn, %{"cache_tables" => cache_tables, "pubsub" => pubsub}), "/")

    view
    |> element("#wallet-connect")
    |> render_hook("wallet_connected", %{"address" => wallet_address, "name" => "Eve Vault"})

    assert_push_event(view, "request_sign", %{"nonce" => _, "message" => _})

    html = render(view)
    assert html =~ "approve the signing request"
    refute html =~ "Select Account"
    refute html =~ "No Sui wallet detected"
  end

  test "authenticated view shows character picker when multiple characters", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    first =
      character_fixture(%{
        "id" => uid("0xcharacter-scout"),
        "tribe_id" => "314",
        "metadata" => %{
          "assembly_id" => "0xcharacter-scout-metadata",
          "name" => "Scout Vega",
          "description" => "Forward scout",
          "url" => "https://example.test/characters/scout-vega"
        }
      })

    second =
      character_fixture(%{
        "id" => uid("0xcharacter-marshal"),
        "tribe_id" => "271828",
        "metadata" => %{
          "assembly_id" => "0xcharacter-marshal-metadata",
          "name" => "Marshal Iona",
          "description" => "Fleet commander",
          "url" => "https://example.test/characters/marshal-iona"
        }
      })

    Cache.put(
      cache_tables.accounts,
      wallet_address,
      account_fixture(wallet_address, [first, second], 314_159)
    )

    stub_dashboard_discovery([])

    assert {:ok, _view, html} =
             live(authenticated_conn(conn, wallet_address, cache_tables, pubsub, second.id), "/")

    assert html =~ "Marshal Iona"
    assert html =~ "Scout Vega"
    assert html =~ "/session/character/#{first.id}"
    refute html =~ "/session/character/#{second.id}"
    refute html =~ "No characters synced"
    refute html =~ "Commander profile"
  end

  test "assembly discovery passes only active character ID", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    first = character_fixture(%{"id" => uid("0xcharacter-alpha")})
    second = character_fixture(%{"id" => uid("0xcharacter-beta")})
    gate = Gate.from_json(gate_json(%{"id" => uid("0xactive-character-gate")}))

    Cache.put(
      cache_tables.accounts,
      wallet_address,
      account_fixture(wallet_address, [first, second], 314)
    )

    expect_dashboard_discovery_for_character(second.id, [gate])

    assert {:ok, _view, html} =
             live(authenticated_conn(conn, wallet_address, cache_tables, pubsub, second.id), "/")

    assert html =~ "Jump Gate Alpha"
    assert html =~ "Operational Assets"
    refute html =~ "Assembly discovery is temporarily unavailable"
    refute html =~ "No assemblies found"
  end

  test "authenticated view shows active character name and tribe", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    first =
      character_fixture(%{
        "id" => uid("0xcharacter-anchor"),
        "tribe_id" => "314",
        "metadata" => %{
          "assembly_id" => "0xcharacter-anchor-metadata",
          "name" => "Anchor Holt",
          "description" => "Anchor pilot",
          "url" => "https://example.test/characters/anchor-holt"
        }
      })

    second =
      character_fixture(%{
        "id" => uid("0xcharacter-vanguard"),
        "tribe_id" => "271828",
        "metadata" => %{
          "assembly_id" => "0xcharacter-vanguard-metadata",
          "name" => "Vanguard Nia",
          "description" => "Active commander",
          "url" => "https://example.test/characters/vanguard-nia"
        }
      })

    Cache.put(
      cache_tables.accounts,
      wallet_address,
      account_fixture(wallet_address, [first, second], 314_159)
    )

    stub_dashboard_discovery([])

    assert {:ok, _view, html} =
             live(authenticated_conn(conn, wallet_address, cache_tables, pubsub, second.id), "/")

    assert html =~ "Vanguard Nia"
    assert html =~ "271828"
    refute html =~ "No characters synced"
  end

  test "authenticated view hides character picker for single character", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    only_character =
      character_fixture(%{
        "id" => uid("0xcharacter-solo"),
        "tribe_id" => "314",
        "metadata" => %{
          "assembly_id" => "0xcharacter-solo-metadata",
          "name" => "Solo Rhea",
          "description" => "Only linked pilot",
          "url" => "https://example.test/characters/solo-rhea"
        }
      })

    Cache.put(
      cache_tables.accounts,
      wallet_address,
      account_fixture(wallet_address, [only_character], 314)
    )

    stub_dashboard_discovery([])

    assert {:ok, _view, html} =
             live(
               authenticated_conn(conn, wallet_address, cache_tables, pubsub, only_character.id),
               "/"
             )

    assert html =~ "Solo Rhea"
    refute html =~ "/session/character/#{only_character.id}"
    refute html =~ "No characters synced"
    refute html =~ "Commander profile"
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
    assert html =~ "Network Node"
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

  test "assembly list updates on monitor PubSub broadcast", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    gate = Gate.from_json(gate_json(%{"id" => uid("0xgate-monitor-broadcast")}))
    registry = unique_registry_name()

    Cache.put(cache_tables.accounts, wallet_address, account)
    expect_dashboard_discovery(wallet_address, [gate])
    start_supervised!({Registry, keys: :unique, name: registry})
    supervisor = start_supervised!({MonitorSupervisor, registry: registry})

    {:ok, view, html} =
      isolated_dashboard_live(
        conn,
        wallet_address,
        cache_tables,
        pubsub,
        monitor_supervisor: supervisor,
        monitor_registry: registry
      )

    assert html =~ "Jump Gate Alpha"

    updated_gate =
      Gate.from_json(
        gate_json(%{
          "id" => uid(gate.id),
          "metadata" => %{
            "assembly_id" => "0xgate-metadata",
            "name" => "Jump Gate Monitor Prime",
            "description" => "Updated via monitor event",
            "url" => "https://example.test/gates/monitor-prime"
          }
        })
      )

    Phoenix.PubSub.broadcast(
      pubsub,
      "assembly:#{gate.id}",
      {:assembly_monitor, gate.id, %{changes: [], assembly: updated_gate, depletion: nil}}
    )

    updated_html = render(view)

    assert updated_html =~ "Jump Gate Monitor Prime"
    refute updated_html =~ ">Jump Gate Alpha<"
  end

  test "assemblies_discovered replaces list and ensures monitors", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    gate = Gate.from_json(gate_json(%{"id" => uid("0xreplace-gate")}))
    turret = Turret.from_json(turret_json(%{"id" => uid("0xreplace-turret")}))
    registry = unique_registry_name()

    Cache.put(cache_tables.accounts, wallet_address, account)
    expect_dashboard_discovery(wallet_address, [gate])
    start_supervised!({Registry, keys: :unique, name: registry})
    supervisor = start_supervised!({MonitorSupervisor, registry: registry})

    {:ok, view, html} =
      isolated_dashboard_live(
        conn,
        wallet_address,
        cache_tables,
        pubsub,
        monitor_supervisor: supervisor,
        monitor_registry: registry
      )

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
    assert {:ok, _monitor} = MonitorSupervisor.get_monitor(registry, turret.id)
  end

  test "discovery triggers ensure_monitors for discovered assemblies", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    gate = Gate.from_json(gate_json(%{"id" => uid("0xmonitor-discovery-gate")}))
    registry = unique_registry_name()

    Cache.put(cache_tables.accounts, wallet_address, account)
    expect_dashboard_discovery(wallet_address, [gate])
    start_supervised!({Registry, keys: :unique, name: registry})
    supervisor = start_supervised!({MonitorSupervisor, registry: registry})

    {:ok, _view, _html} =
      isolated_dashboard_live(
        conn,
        wallet_address,
        cache_tables,
        pubsub,
        monitor_supervisor: supervisor,
        monitor_registry: registry
      )

    assert {:ok, _monitor} = MonitorSupervisor.get_monitor(registry, gate.id)
  end

  test "discovery skips monitors when supervisor is nil", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    gate = Gate.from_json(gate_json(%{"id" => uid("0xnil-supervisor-gate")}))

    Cache.put(cache_tables.accounts, wallet_address, account)
    expect_dashboard_discovery(wallet_address, [gate])

    {:ok, _view, html} =
      isolated_dashboard_live(conn, wallet_address, cache_tables, pubsub)

    assert html =~ "Jump Gate Alpha"
    refute html =~ "Unable to refresh assemblies right now."
    refute html =~ "No assemblies found"
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

  test "authenticated user with tribe sees View Tribe link", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    Cache.put(cache_tables.accounts, wallet_address, account)
    expect_empty_dashboard_discovery(wallet_address)

    assert {:ok, _view, html} =
             live(authenticated_conn(conn, wallet_address, cache_tables, pubsub), "/")

    assert html =~ "View Tribe"
    assert html =~ ~s(/tribe/#{account.tribe_id})
    refute html =~ "Unable to refresh"
  end

  test "authenticated user without tribe sees no tribe link", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    tribeless_character = character_fixture(%{"tribe_id" => "0"})
    account = %Account{address: wallet_address, characters: [tribeless_character], tribe_id: nil}
    Cache.put(cache_tables.accounts, wallet_address, account)
    expect_empty_dashboard_discovery(wallet_address)

    assert {:ok, _view, html} =
             live(authenticated_conn(conn, wallet_address, cache_tables, pubsub), "/")

    refute html =~ "View Tribe"
    refute html =~ "/tribe/"
    assert html =~ wallet_address
  end

  test "authenticated dashboard shows detailed alerts summary", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    Cache.put(cache_tables.accounts, wallet_address, account_fixture(wallet_address))
    expect_empty_dashboard_discovery(wallet_address)

    insert_alert!(%{
      "account_address" => wallet_address,
      "type" => "hostile_activity",
      "severity" => "critical",
      "message" => "Oldest hostile ping",
      "assembly_name" => "Old Assembly"
    })

    older =
      insert_alert!(%{
        "account_address" => wallet_address,
        "type" => "assembly_offline",
        "severity" => "warning",
        "message" => "Older relay disruption",
        "assembly_name" => "Relay Bastion"
      })

    middle =
      insert_alert!(%{
        "account_address" => wallet_address,
        "type" => "fuel_critical",
        "severity" => "critical",
        "message" => "Middle fuel breach",
        "assembly_name" => "Citadel K-7"
      })

    newest =
      insert_alert!(%{
        "account_address" => wallet_address,
        "type" => "fuel_low",
        "severity" => "warning",
        "message" => "Newest low fuel warning",
        "assembly_name" => "Hangar Zero"
      })

    assert {:ok, _view, html} =
             live(authenticated_conn(conn, wallet_address, cache_tables, pubsub), "/")

    assert html =~ "View All Alerts"
    assert html =~ newest.message
    assert html =~ middle.message
    assert html =~ older.message
    assert html =~ "Fuel Low"
    assert html =~ "Fuel Critical"
    assert html =~ "Assembly Offline"
    assert html =~ "Hangar Zero"
    assert html =~ "Just now"
    refute html =~ "Oldest hostile ping"
    refute html =~ "No active alerts"
  end

  test "alerts summary shows empty state when no active alerts", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    Cache.put(cache_tables.accounts, wallet_address, account_fixture(wallet_address))
    expect_empty_dashboard_discovery(wallet_address)

    assert {:ok, _view, html} =
             live(authenticated_conn(conn, wallet_address, cache_tables, pubsub), "/")

    assert html =~ "No active alerts"
    refute html =~ "View All Alerts"
    refute html =~ "Fuel Low"
  end

  test "alerts summary distinguishes unread from acknowledged alerts", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    Cache.put(cache_tables.accounts, wallet_address, account_fixture(wallet_address))
    expect_empty_dashboard_discovery(wallet_address)

    insert_alert!(%{
      "account_address" => wallet_address,
      "status" => "new",
      "message" => "Unread summary alert"
    })

    insert_alert!(%{
      "account_address" => wallet_address,
      "status" => "acknowledged",
      "message" => "Acknowledged summary alert"
    })

    assert {:ok, _view, html} =
             live(authenticated_conn(conn, wallet_address, cache_tables, pubsub), "/")

    assert html =~ "Unread summary alert"
    assert html =~ "Acknowledged summary alert"
    assert html =~ "border-quantum-400/60 bg-space-800/90"
    assert html =~ "border-space-600/80 bg-space-800/70"
    refute html =~ "No active alerts"
  end

  test "alerts summary shows unread count badge", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    Cache.put(cache_tables.accounts, wallet_address, account_fixture(wallet_address))
    expect_empty_dashboard_discovery(wallet_address)

    insert_alert!(%{
      "account_address" => wallet_address,
      "status" => "new",
      "message" => "Unread one"
    })

    insert_alert!(%{
      "account_address" => wallet_address,
      "status" => "new",
      "message" => "Unread two"
    })

    insert_alert!(%{
      "account_address" => wallet_address,
      "status" => "acknowledged",
      "message" => "Read one"
    })

    assert {:ok, _view, html} =
             live(authenticated_conn(conn, wallet_address, cache_tables, pubsub), "/")

    assert html =~ "2 unread"
    refute html =~ "3 unread"
  end

  test "alerts summary includes View All Alerts link", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    Cache.put(cache_tables.accounts, wallet_address, account_fixture(wallet_address))
    expect_empty_dashboard_discovery(wallet_address)

    insert_alert!(%{
      "account_address" => wallet_address,
      "message" => "Linked summary alert"
    })

    assert {:ok, _view, html} =
             live(authenticated_conn(conn, wallet_address, cache_tables, pubsub), "/")

    assert html =~ "View All Alerts"
    assert html =~ ~s(href="/alerts")
    refute html =~ "Connect Your Wallet"
  end

  test "alerts summary updates on PubSub alert_created", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    Cache.put(cache_tables.accounts, wallet_address, account_fixture(wallet_address))
    expect_empty_dashboard_discovery(wallet_address)

    {:ok, view, initial_html} =
      live(authenticated_conn(conn, wallet_address, cache_tables, pubsub), "/")

    assert initial_html =~ "No active alerts"

    created =
      insert_alert!(%{
        "account_address" => wallet_address,
        "message" => "Fresh dashboard broadcast"
      })

    Phoenix.PubSub.broadcast(pubsub, Alerts.topic(wallet_address), {:alert_created, created})

    html = render(view)
    assert html =~ created.message
    assert html =~ "1 unread"
    refute html =~ "No active alerts"
  end

  test "alerts summary refreshes on PubSub alert_acknowledged", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    Cache.put(cache_tables.accounts, wallet_address, account_fixture(wallet_address))
    expect_empty_dashboard_discovery(wallet_address)

    alert =
      insert_alert!(%{
        "account_address" => wallet_address,
        "status" => "new",
        "message" => "Dashboard acknowledge target"
      })

    {:ok, view, _html} =
      live(authenticated_conn(conn, wallet_address, cache_tables, pubsub), "/")

    replacement =
      insert_alert!(%{
        "account_address" => wallet_address,
        "status" => "new",
        "message" => "Replacement after acknowledge"
      })

    assert {:ok, _acknowledged} = Alerts.acknowledge_alert(alert.id, pubsub: pubsub)
    Phoenix.PubSub.broadcast(pubsub, Alerts.topic(wallet_address), {:alert_acknowledged, alert})

    html = render(view)
    assert html =~ replacement.message
    assert html =~ alert.message
    assert html =~ "1 unread"
    refute html =~ "0 unread"
  end

  test "alerts summary refreshes on PubSub alert_dismissed", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    Cache.put(cache_tables.accounts, wallet_address, account_fixture(wallet_address))
    expect_empty_dashboard_discovery(wallet_address)

    alert =
      insert_alert!(%{
        "account_address" => wallet_address,
        "status" => "new",
        "message" => "Dashboard dismiss target"
      })

    {:ok, view, _html} =
      live(authenticated_conn(conn, wallet_address, cache_tables, pubsub), "/")

    replacement =
      insert_alert!(%{
        "account_address" => wallet_address,
        "status" => "new",
        "message" => "Replacement after dismiss"
      })

    assert {:ok, _dismissed} = Alerts.dismiss_alert(alert.id, pubsub: pubsub)
    Phoenix.PubSub.broadcast(pubsub, Alerts.topic(wallet_address), {:alert_dismissed, alert})

    html = render(view)
    assert html =~ replacement.message
    refute html =~ alert.message
    assert html =~ "1 unread"
    refute html =~ "0 unread"
  end

  test "alerts summary ignores foreign account alert events", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    Cache.put(cache_tables.accounts, wallet_address, account_fixture(wallet_address))
    expect_empty_dashboard_discovery(wallet_address)

    own_alert =
      insert_alert!(%{
        "account_address" => wallet_address,
        "message" => "Own dashboard alert"
      })

    foreign_alert =
      insert_alert!(%{
        "account_address" => unique_wallet_address(),
        "message" => "Foreign dashboard alert"
      })

    {:ok, view, html} =
      live(authenticated_conn(conn, wallet_address, cache_tables, pubsub), "/")

    assert html =~ own_alert.message
    refute html =~ foreign_alert.message

    Phoenix.PubSub.broadcast(
      pubsub,
      Alerts.topic(foreign_alert.account_address),
      {:alert_created, foreign_alert}
    )

    refreshed_html = render(view)
    assert refreshed_html =~ own_alert.message
    refute refreshed_html =~ foreign_alert.message
  end

  @tag :acceptance
  test "dashboard alerts summary shows active alerts and updates live", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    Cache.put(cache_tables.accounts, wallet_address, account_fixture(wallet_address))
    expect_empty_dashboard_discovery(wallet_address)

    initial_alert =
      insert_alert!(%{
        "account_address" => wallet_address,
        "type" => "fuel_low",
        "severity" => "warning",
        "message" => "Initial dashboard alert",
        "assembly_name" => "Summary Deck"
      })

    {:ok, view, html} =
      live(authenticated_conn(conn, wallet_address, cache_tables, pubsub), "/")

    assert html =~ "Initial dashboard alert"
    assert html =~ "View All Alerts"
    refute html =~ "No active alerts"
    refute html =~ "Connect Your Wallet"

    fresh_alert =
      insert_alert!(%{
        "account_address" => wallet_address,
        "message" => "Fresh dashboard alert"
      })

    Phoenix.PubSub.broadcast(pubsub, Alerts.topic(wallet_address), {:alert_created, fresh_alert})

    refreshed_html = render(view)
    assert refreshed_html =~ fresh_alert.message
    refute refreshed_html =~ "No active alerts"

    assert {:ok, _alerts_view, alerts_html} =
             view
             |> element(~s(a[href="/alerts"]), "View All Alerts")
             |> render_click()
             |> follow_redirect(
               authenticated_conn(conn, wallet_address, cache_tables, pubsub),
               "/alerts"
             )

    assert alerts_html =~ initial_alert.message
    refute alerts_html =~ "Connect Your Wallet"
    refute alerts_html =~ "Not Found"
  end

  @tag :acceptance
  test "switching active character re-scopes dashboard assemblies", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    first =
      character_fixture(%{
        "id" => uid("0xcharacter-rescope-alpha"),
        "metadata" => %{
          "assembly_id" => "0xcharacter-rescope-alpha-meta",
          "name" => "Scout Vega",
          "description" => "Alpha character",
          "url" => "https://example.test/characters/scout-vega"
        }
      })

    second =
      character_fixture(%{
        "id" => uid("0xcharacter-rescope-beta"),
        "tribe_id" => "271828",
        "metadata" => %{
          "assembly_id" => "0xcharacter-rescope-beta-meta",
          "name" => "Marshal Iona",
          "description" => "Beta character",
          "url" => "https://example.test/characters/marshal-iona"
        }
      })

    alpha_gate = Gate.from_json(gate_json(%{"id" => uid("0xrescope-alpha-gate")}))
    beta_turret = Turret.from_json(turret_json(%{"id" => uid("0xrescope-beta-turret")}))
    owner_cap_type = owner_cap_type()
    first_id = first.id
    second_id = second.id
    alpha_gate_id = alpha_gate.id
    beta_turret_id = beta_turret.id

    Cache.put(
      cache_tables.accounts,
      wallet_address,
      account_fixture(wallet_address, [first, second], 314)
    )

    expect(Sigil.Sui.ClientMock, :get_objects, 2, fn filters, [] ->
      assert Keyword.get(filters, :type) == owner_cap_type

      case Keyword.get(filters, :owner) do
        ^first_id ->
          {:ok, %{data: [owner_cap_json(alpha_gate_id)], has_next_page: false, end_cursor: nil}}

        ^second_id ->
          {:ok, %{data: [owner_cap_json(beta_turret_id)], has_next_page: false, end_cursor: nil}}
      end
    end)

    expect(Sigil.Sui.ClientMock, :get_object, 2, fn assembly_id, [] ->
      case assembly_id do
        ^alpha_gate_id -> {:ok, assembly_json_for(alpha_gate)}
        ^beta_turret_id -> {:ok, assembly_json_for(beta_turret)}
      end
    end)

    conn = authenticated_conn(conn, wallet_address, cache_tables, pubsub, first_id)

    assert {:ok, _view, html} = live(conn, "/")
    assert html =~ "Scout Vega"
    assert html =~ "Jump Gate Alpha"
    refute html =~ "Defense Turret"

    switched_conn = put(conn, "/session/character/#{second.id}")
    assert redirected_to(switched_conn) == "/"

    assert {:ok, _switched_view, switched_html} = live(recycle(switched_conn), "/")
    assert switched_html =~ "Marshal Iona"
    assert switched_html =~ "Defense Turret"
    refute switched_html =~ "Jump Gate Alpha"
    refute switched_html =~ "Connect Your Wallet"
  end

  test "wallet connect event prepares signed auth request for dashboard login", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    {:ok, view, initial_html} =
      live(init_test_session(conn, %{"cache_tables" => cache_tables, "pubsub" => pubsub}), "/")

    assert initial_html =~ "Connect Your Wallet"
    refute initial_html =~ "Operational Assets"

    view
    |> element("#wallet-connect")
    |> render_hook("wallet_connected", %{"address" => wallet_address, "name" => "Eve Vault"})

    assert_push_event(view, "request_sign", %{"nonce" => nonce, "message" => _message})
    assert byte_size(nonce) > 0

    assert [%{address: ^wallet_address, item_id: nil, tenant: nil}] =
             Cache.all(cache_tables.nonces)

    refute initial_html =~ "Invalid authentication request"
  end

  @tag :acceptance
  test "wallet verification → session → dashboard with assemblies", %{
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

    expect(Sigil.Sui.ClientMock, :verify_zklogin_signature, fn _bytes,
                                                               @zklogin_sig,
                                                               "PERSONAL_MESSAGE",
                                                               ^wallet_address,
                                                               [] ->
      {:ok, %{"verifyZkLoginSignature" => %{"success" => true}}}
    end)

    expect(Sigil.Sui.ClientMock, :get_objects, 2, fn filters, [] ->
      case Keyword.get(filters, :type) do
        ^character_type ->
          {:ok,
           %{
             data: [character_json(%{"character_address" => wallet_address})],
             has_next_page: false,
             end_cursor: nil
           }}

        ^owner_cap_type ->
          {:ok,
           %{
             data: [owner_cap_json(gate_id), owner_cap_json(node_id)],
             has_next_page: false,
             end_cursor: nil
           }}
      end
    end)

    expect(Sigil.Sui.ClientMock, :get_object, 2, fn
      ^gate_id, [] -> {:ok, gate_json(%{"id" => uid(gate_id)})}
      ^node_id, [] -> {:ok, network_node_json(%{"id" => uid(node_id)})}
    end)

    {:ok, view, initial_html} =
      live(
        init_test_session(conn, %{"cache_tables" => cache_tables, "pubsub" => pubsub}),
        "/"
      )

    assert initial_html =~ "Connect Your Wallet"
    refute initial_html =~ "Operational Assets"

    view
    |> element("#wallet-connect")
    |> render_hook("wallet_connected", %{"address" => wallet_address, "name" => "Eve Vault"})

    assert_push_event(view, "request_sign", %{"nonce" => nonce, "message" => message})
    assert message == "Sign in to Sigil: #{nonce}"

    conn =
      conn
      |> init_test_session(%{"cache_tables" => cache_tables, "pubsub" => pubsub})
      |> post("/session", %{
        "wallet_address" => wallet_address,
        "bytes" => Base.encode64(message),
        "signature" => zklogin_signature(),
        "nonce" => nonce
      })

    assert redirected_to(conn) == "/"

    assert {:ok, _dashboard_view, html} = live(recycle(conn), "/")

    assert html =~ wallet_address
    assert html =~ truncate_id(wallet_address)
    assert html =~ "Jump Gate Alpha"
    assert html =~ "Node One"
    assert html =~ "Gate"
    assert html =~ "Network Node"
    assert html =~ "online"
    assert html =~ "50 / 5000"
    assert html =~ "/assembly/#{gate.id}"
    refute html =~ "Connect Your Wallet"
    refute html =~ "Invalid authentication request"
    refute html =~ "No assemblies found"
  end

  @tag :acceptance
  test "multi-account wallet selection results in character-scoped dashboard", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    selected_address = unique_wallet_address()
    gate = Gate.from_json(gate_json(%{"id" => uid("0xacceptance-multi-gate")}))

    selected_character =
      character_fixture(%{
        "id" => uid("0xcharacter-selected"),
        "character_address" => selected_address,
        "tribe_id" => "271828",
        "metadata" => %{
          "assembly_id" => "0xcharacter-selected-metadata",
          "name" => "Marshal Iona",
          "description" => "Selected fleet commander",
          "url" => "https://example.test/characters/marshal-iona"
        }
      })

    other_character =
      character_fixture(%{
        "id" => uid("0xcharacter-other"),
        "character_address" => wallet_address,
        "tribe_id" => "314",
        "metadata" => %{
          "assembly_id" => "0xcharacter-other-metadata",
          "name" => "Scout Vega",
          "description" => "Alternate commander",
          "url" => "https://example.test/characters/scout-vega"
        }
      })

    character_type = character_type()
    owner_cap_type = owner_cap_type()
    gate_id = gate.id

    expect(Sigil.Sui.ClientMock, :verify_zklogin_signature, fn _bytes,
                                                               @zklogin_sig,
                                                               "PERSONAL_MESSAGE",
                                                               ^selected_address,
                                                               [] ->
      {:ok, %{"verifyZkLoginSignature" => %{"success" => true}}}
    end)

    expect(Sigil.Sui.ClientMock, :get_objects, 2, fn filters, [] ->
      case Keyword.get(filters, :type) do
        ^character_type ->
          {:ok,
           %{
             data: [character_to_json(other_character), character_to_json(selected_character)],
             has_next_page: false,
             end_cursor: nil
           }}

        ^owner_cap_type ->
          assert Keyword.get(filters, :owner) == selected_character.id

          {:ok,
           %{
             data: [owner_cap_json(gate_id)],
             has_next_page: false,
             end_cursor: nil
           }}
      end
    end)

    expect(Sigil.Sui.ClientMock, :get_object, fn ^gate_id, [] ->
      {:ok, gate_json(%{"id" => uid(gate_id)})}
    end)

    {:ok, view, initial_html} =
      live(
        init_test_session(conn, %{"cache_tables" => cache_tables, "pubsub" => pubsub}),
        "/"
      )

    assert initial_html =~ "Connect Your Wallet"
    refute initial_html =~ "Operational Assets"

    account_selection_html =
      view
      |> element("#wallet-connect")
      |> render_hook("wallet_accounts", %{
        "accounts" => [
          account_payload(wallet_address, "Scout Wing"),
          account_payload(selected_address, "Marshal Bridge")
        ]
      })

    assert account_selection_html =~ "Select Account"
    assert account_selection_html =~ "Marshal Bridge"
    refute account_selection_html =~ "No Sui wallet detected"

    selection_html =
      view
      |> element(~s(button[phx-click="select_account"][phx-value-index="1"]))
      |> render_click()

    assert_push_event(view, "select_account", %{"index" => 1})
    assert selection_html =~ "Connecting to wallet..."
    refute selection_html =~ "Select Account"

    view
    |> element("#wallet-connect")
    |> render_hook("wallet_connected", %{"address" => selected_address, "name" => "Eve Vault"})

    assert_push_event(view, "request_sign", %{"nonce" => nonce, "message" => message})
    assert message == "Sign in to Sigil: #{nonce}"

    conn =
      conn
      |> init_test_session(%{"cache_tables" => cache_tables, "pubsub" => pubsub})
      |> post("/session", %{
        "wallet_address" => selected_address,
        "bytes" => Base.encode64(message),
        "signature" => zklogin_signature(),
        "nonce" => nonce
      })

    assert redirected_to(conn) == "/"

    assert {:ok, _dashboard_view, html} = live(recycle(conn), "/")

    assert html =~ "Marshal Iona"
    assert html =~ "271828"
    assert html =~ "Jump Gate Alpha"
    assert html =~ "/assembly/#{gate.id}"
    refute html =~ "Connect Your Wallet"
    refute html =~ "No assemblies found"
    refute html =~ "314159"
  end

  defp expect_dashboard_discovery(_wallet_address, assemblies) do
    expect_dashboard_discovery_for_character("0xcharacter-dashboard", assemblies)
  end

  defp expect_dashboard_discovery_for_character(character_id, assemblies) do
    owner_cap_type = owner_cap_type()

    expect(Sigil.Sui.ClientMock, :get_objects, fn filters, [] ->
      assert Keyword.get(filters, :type) == owner_cap_type
      assert Keyword.get(filters, :owner) == character_id

      {:ok,
       %{
         data: Enum.map(assemblies, &owner_cap_json(&1.id)),
         has_next_page: false,
         end_cursor: nil
       }}
    end)

    expect(Sigil.Sui.ClientMock, :get_object, length(assemblies), fn assembly_id, [] ->
      assembly = Enum.find(assemblies, &(&1.id == assembly_id))
      {:ok, assembly_json_for(assembly)}
    end)
  end

  defp expect_empty_dashboard_discovery(_wallet_address) do
    owner_cap_type = owner_cap_type()
    character_id = "0xcharacter-dashboard"

    expect(Sigil.Sui.ClientMock, :get_objects, fn [type: type, owner: ^character_id], []
                                                  when type == owner_cap_type ->
      {:ok, %{data: [], has_next_page: false, end_cursor: nil}}
    end)
  end

  defp stub_dashboard_discovery(assemblies) do
    expect(Sigil.Sui.ClientMock, :get_objects, fn filters, [] ->
      assert Keyword.get(filters, :type) == owner_cap_type()

      {:ok,
       %{
         data: Enum.map(assemblies, &owner_cap_json(&1.id)),
         has_next_page: false,
         end_cursor: nil
       }}
    end)

    expect(Sigil.Sui.ClientMock, :get_object, length(assemblies), fn assembly_id, [] ->
      assembly = Enum.find(assemblies, &(&1.id == assembly_id))
      {:ok, assembly_json_for(assembly)}
    end)
  end

  defp expect_dashboard_discovery_failure(_wallet_address) do
    owner_cap_type = owner_cap_type()
    character_id = "0xcharacter-dashboard"

    expect(Sigil.Sui.ClientMock, :get_objects, fn [type: type, owner: ^character_id], []
                                                  when type == owner_cap_type ->
      {:error, :timeout}
    end)
  end

  defp unique_registry_name do
    :"dashboard_live_registry_#{System.unique_integer([:positive])}"
  end

  defp authenticated_conn(conn, wallet_address, cache_tables, pubsub) do
    authenticated_conn(conn, wallet_address, cache_tables, pubsub, nil)
  end

  defp isolated_dashboard_live(conn, wallet_address, cache_tables, pubsub, extra_session \\ []) do
    extra_session =
      extra_session
      |> Enum.map(fn {key, value} -> {to_string(key), value} end)
      |> Map.new()

    live_isolated(conn, SigilWeb.DashboardLiveIsolatedTestLive,
      session:
        authenticated_session(wallet_address, cache_tables, pubsub, nil)
        |> Map.merge(extra_session)
    )
  end

  defp authenticated_conn(conn, wallet_address, cache_tables, pubsub, active_character_id) do
    init_test_session(
      conn,
      authenticated_session(wallet_address, cache_tables, pubsub, active_character_id)
    )
  end

  defp authenticated_session(wallet_address, cache_tables, pubsub, active_character_id) do
    session = %{
      "wallet_address" => wallet_address,
      "cache_tables" => cache_tables,
      "pubsub" => pubsub
    }

    if is_binary(active_character_id) do
      Map.put(session, "active_character_id", active_character_id)
    else
      session
    end
  end

  defp assembly_json_for(%Gate{id: id, status: %{status: status}}) do
    gate_json(%{"id" => uid(id), "status" => %{"status" => status_to_string(status)}})
  end

  defp assembly_json_for(%NetworkNode{id: id}), do: network_node_json(%{"id" => uid(id)})

  defp assembly_json_for(%Turret{id: id, status: %{status: status}}) do
    turret_json(%{"id" => uid(id), "status" => %{"status" => status_to_string(status)}})
  end

  defp account_fixture(wallet_address) do
    account_fixture(wallet_address, [character_fixture()], 314)
  end

  defp account_fixture(wallet_address, characters, tribe_id) do
    %Account{address: wallet_address, characters: characters, tribe_id: tribe_id}
  end

  defp insert_alert!(overrides) do
    %Alert{}
    |> Alert.changeset(valid_alert_attrs(overrides))
    |> Repo.insert!()
  end

  defp valid_alert_attrs(overrides) do
    unique = System.unique_integer([:positive])

    Map.merge(
      %{
        "type" => "fuel_low",
        "severity" => "warning",
        "status" => "new",
        "assembly_id" => "dashboard-assembly-#{unique}",
        "assembly_name" => "Dashboard Assembly #{unique}",
        "account_address" => unique_wallet_address(),
        "tribe_id" => 42,
        "message" => "Dashboard alert #{unique}",
        "metadata" => %{"source" => "monitor"}
      },
      overrides
    )
  end

  defp character_fixture(overrides \\ %{}) do
    Character.from_json(character_json(overrides))
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

  # Base64-encoded bytes starting with zkLogin scheme byte (0x05)
  defp zklogin_signature, do: Base.encode64(<<0x05, 0::size(320)>>)

  defp wallet_payload(name) do
    %{"name" => name, "icon" => "https://example.test/#{String.replace(name, " ", "-")}.png"}
  end

  defp account_payload(address, label \\ nil) do
    %{"address" => address, "label" => label}
  end

  defp character_type do
    "#{@world_package_id}::character::Character"
  end

  defp owner_cap_type do
    "#{@world_package_id}::access::OwnerCap"
  end

  defp character_json(overrides) do
    Map.merge(
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

  defp character_to_json(%Character{} = character) do
    metadata = character.metadata || %{}

    %{
      "id" => uid(character.id),
      "key" => %{"item_id" => character.key.item_id, "tenant" => character.key.tenant},
      "tribe_id" => Integer.to_string(character.tribe_id),
      "character_address" => character.character_address,
      "metadata" => %{
        "assembly_id" => metadata.assembly_id,
        "name" => metadata.name,
        "description" => metadata.description,
        "url" => metadata.url
      },
      "owner_cap_id" => uid(character.owner_cap_id)
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
