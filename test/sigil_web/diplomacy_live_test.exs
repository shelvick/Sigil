defmodule SigilWeb.DiplomacyLiveTest do
  @moduledoc """
  Covers the UI_DiplomacyLive specification (R1-R26) from Packet 3.
  Tests diplomacy editor: custodian page states, leader/non-leader paths,
  standings CRUD, pilot overrides, transaction signing flow, PubSub updates,
  and full user journey.
  """

  use Sigil.ConnCase, async: true

  import Hammox

  alias Sigil.Cache
  alias Sigil.Accounts.Account
  alias Sigil.Sui.Types.Character

  @tribe_id 314
  @custodian_type "0x06ce9d6bed77615383575cc7eba4883d32769b30cd5df00561e38434a59611a1::tribe_custodian::Custodian"
  @character_id "0x" <> String.duplicate("cc", 32)

  setup :verify_on_exit!

  setup do
    cache_pid =
      start_supervised!(
        {Cache, tables: [:accounts, :characters, :assemblies, :nonces, :tribes, :standings]}
      )

    pubsub = unique_pubsub_name()

    start_supervised!({Phoenix.PubSub, name: pubsub})

    cache_tables = Cache.tables(cache_pid)

    stub(Sigil.StaticData.WorldClientMock, :fetch_tribes, fn _opts -> {:ok, []} end)

    # Seed character ref so load_standings can resolve it without chain calls
    Cache.put(cache_tables.standings, {:character_ref, @character_id}, %{
      object_id: :binary.copy(<<0xCC>>, 32),
      initial_shared_version: 100
    })

    {:ok, cache_tables: cache_tables, pubsub: pubsub, wallet_address: unique_wallet_address()}
  end

  # ---------------------------------------------------------------------------
  # R1: No custodian state shows create CTA [INTEGRATION]
  # ---------------------------------------------------------------------------

  test "no custodian state shows create custodian button", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    stub(Sigil.Sui.ClientMock, :get_objects, fn
      [type: @custodian_type], [] ->
        {:ok, %{data: [], has_next_page: false, end_cursor: nil}}
    end)

    assert {:ok, _view, html} =
             live(
               authenticated_conn(conn, wallet_address, cache_tables, pubsub),
               "/tribe/#{@tribe_id}/diplomacy"
             )

    assert html =~ "Your tribe doesn't have a Tribe Custodian yet"
    assert html =~ "Create Tribe Custodian"
    assert html =~ "Hostile"
    assert html =~ "Allied"
    refute html =~ "Create Standings Table"
  end

  # ---------------------------------------------------------------------------
  # R2: Create custodian triggers wallet signing [INTEGRATION]
  # ---------------------------------------------------------------------------

  test "create custodian click starts approval flow", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    stub(Sigil.Sui.ClientMock, :get_objects, fn
      [type: @custodian_type], [] ->
        {:ok, %{data: [], has_next_page: false, end_cursor: nil}}
    end)

    Cache.put(cache_tables.standings, {:registry_ref}, %{
      object_id: :binary.copy(<<0xDD>>, 32),
      initial_shared_version: 50
    })

    {:ok, view, _html} =
      live(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub),
        "/tribe/#{@tribe_id}/diplomacy"
      )

    view
    |> element("button", "Create Tribe Custodian")
    |> render_click()

    assert_push_event(view, "request_sign_transaction", %{"tx_bytes" => tx_bytes})
    assert is_binary(tx_bytes)
    assert byte_size(tx_bytes) > 0

    html = render(view)
    assert html =~ "Approve in your wallet"
    refute html =~ "Create Standings Table"
  end

  # ---------------------------------------------------------------------------
  # R3/R4: Leader and non-leader state split [INTEGRATION]
  # ---------------------------------------------------------------------------

  test "leader and non-leader see different diplomacy controls", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    expect(Sigil.Sui.ClientMock, :get_objects, fn [type: @custodian_type], [] ->
      {:ok,
       %{
         data: [custodian_object_json(table_id(0x11), wallet_address, @tribe_id, 17)],
         has_next_page: false,
         end_cursor: nil
       }}
    end)

    assert {:ok, _leader_view, leader_html} =
             live(
               authenticated_conn(conn, wallet_address, cache_tables, pubsub),
               "/tribe/#{@tribe_id}/diplomacy"
             )

    assert leader_html =~ "Add Pilot Override"
    refute leader_html =~ "Only the tribe leader can modify standings"

    expect(Sigil.Sui.ClientMock, :get_objects, fn [type: @custodian_type], [] ->
      {:ok,
       %{
         data: [custodian_object_json(table_id(0x22), unique_wallet_address(), @tribe_id, 23)],
         has_next_page: false,
         end_cursor: nil
       }}
    end)

    assert {:ok, _readonly_view, readonly_html} =
             live(
               authenticated_conn(conn, wallet_address, cache_tables, pubsub),
               "/tribe/#{@tribe_id}/diplomacy"
             )

    assert readonly_html =~ "Only the tribe leader can modify standings"
    refute readonly_html =~ "Add Pilot Override"
    refute readonly_html =~ "Create Standings Table"
    refute readonly_html =~ "Change..."
  end

  # ---------------------------------------------------------------------------
  # R3: Active state shows standings editor for leader [INTEGRATION]
  # ---------------------------------------------------------------------------

  test "leader sees full standings editor with edit controls", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    seed_active_custodian(cache_tables, wallet_address)
    seed_single_custodian_discovery(wallet_address)

    assert {:ok, _view, html} =
             live(
               authenticated_conn(conn, wallet_address, cache_tables, pubsub),
               "/tribe/#{@tribe_id}/diplomacy"
             )

    assert html =~ "Tribe Standings"
    assert html =~ "Pilot Overrides"
    assert html =~ "Default Standing"
    assert html =~ "Add Pilot Override"
    assert html =~ "Tribe Custodian"
    refute html =~ "Only the tribe leader can modify standings"
    refute html =~ "Create Tribe Custodian"
  end

  # ---------------------------------------------------------------------------
  # R5: Tribe standings table displays entries [INTEGRATION]
  # ---------------------------------------------------------------------------

  test "tribe standings table shows all entries with names and badges", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    seed_active_custodian(cache_tables, wallet_address)
    seed_single_custodian_discovery(wallet_address)

    # Seed tribe standings
    Cache.put(cache_tables.standings, {:tribe_standing, @tribe_id, 42}, 0)
    Cache.put(cache_tables.standings, {:tribe_standing, @tribe_id, 271}, 4)

    # Seed tribe names
    Cache.put(cache_tables.standings, {:world_tribe, 42}, %{
      id: 42,
      name: "Hostile Corp",
      short_name: "HC"
    })

    Cache.put(cache_tables.standings, {:world_tribe, 271}, %{
      id: 271,
      name: "Frontier Defense Union",
      short_name: "FDU"
    })

    assert {:ok, _view, html} =
             live(
               authenticated_conn(conn, wallet_address, cache_tables, pubsub),
               "/tribe/#{@tribe_id}/diplomacy"
             )

    assert html =~ "Tribe Custodian"
    assert html =~ "Hostile Corp"
    assert html =~ "Frontier Defense Union"
    assert html =~ "Hostile"
    assert html =~ "Allied"
    refute html =~ "No standings"
  end

  # ---------------------------------------------------------------------------
  # R6: Add tribe standing [INTEGRATION]
  # ---------------------------------------------------------------------------

  test "adding tribe standing builds transaction for wallet signing", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    seed_active_custodian(cache_tables, wallet_address)
    seed_single_custodian_discovery(wallet_address)

    # Seed world tribes for dropdown
    Cache.put(cache_tables.standings, {:world_tribe, 42}, %{
      id: 42,
      name: "Target Tribe",
      short_name: "TT"
    })

    # No gas coin mocking needed — wallet handles gas via Transaction.fromKind()

    {:ok, view, html} =
      live(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub),
        "/tribe/#{@tribe_id}/diplomacy"
      )

    assert html =~ "Tribe Custodian"

    # Submit add standing form
    view
    |> form("#add-tribe-standing-form", %{"tribe_id" => "42", "standing" => "0"})
    |> render_submit()

    # Should push sign event
    assert_push_event(view, "request_sign_transaction", %{"tx_bytes" => tx_bytes})
    assert is_binary(tx_bytes)
  end

  # ---------------------------------------------------------------------------
  # R7: Edit tribe standing inline [INTEGRATION]
  # ---------------------------------------------------------------------------

  test "editing standing inline builds update transaction", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    seed_active_custodian(cache_tables, wallet_address)
    seed_single_custodian_discovery(wallet_address)

    # Seed existing standing
    Cache.put(cache_tables.standings, {:tribe_standing, @tribe_id, 42}, 2)

    Cache.put(cache_tables.standings, {:world_tribe, 42}, %{
      id: 42,
      name: "Some Tribe",
      short_name: "ST"
    })

    # No gas coin mocking needed — wallet handles gas via Transaction.fromKind()

    {:ok, view, html} =
      live(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub),
        "/tribe/#{@tribe_id}/diplomacy"
      )

    assert html =~ "Tribe Custodian"

    # Trigger inline edit event
    render_click(view, "set_standing", %{"tribe_id" => "42", "standing" => "0"})

    assert_push_event(view, "request_sign_transaction", %{"tx_bytes" => _tx_bytes})
  end

  # ---------------------------------------------------------------------------
  # R8: Batch set standings [INTEGRATION]
  # ---------------------------------------------------------------------------

  test "batch standing change builds single batch transaction", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    seed_active_custodian(cache_tables, wallet_address)
    seed_single_custodian_discovery(wallet_address)

    # Seed existing standings
    Cache.put(cache_tables.standings, {:tribe_standing, @tribe_id, 42}, 2)
    Cache.put(cache_tables.standings, {:tribe_standing, @tribe_id, 43}, 2)

    # No gas coin mocking needed — wallet handles gas via Transaction.fromKind()

    {:ok, view, html} =
      live(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub),
        "/tribe/#{@tribe_id}/diplomacy"
      )

    assert html =~ "Tribe Custodian"

    # Trigger batch set event
    render_click(view, "batch_set_standings", %{
      "updates" => [
        %{"tribe_id" => "42", "standing" => "0"},
        %{"tribe_id" => "43", "standing" => "4"}
      ]
    })

    assert_push_event(view, "request_sign_transaction", %{"tx_bytes" => _tx_bytes})
  end

  # ---------------------------------------------------------------------------
  # R9: Tribe search filter [INTEGRATION]
  # ---------------------------------------------------------------------------

  test "tribe search filters by name and ID", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    seed_active_custodian(cache_tables, wallet_address)
    seed_single_custodian_discovery(wallet_address)

    # Seed world tribes
    Cache.put(cache_tables.standings, {:world_tribe, 42}, %{
      id: 42,
      name: "Alpha Corp",
      short_name: "AC"
    })

    Cache.put(cache_tables.standings, {:world_tribe, 43}, %{
      id: 43,
      name: "Beta Industries",
      short_name: "BI"
    })

    {:ok, view, html} =
      live(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub),
        "/tribe/#{@tribe_id}/diplomacy"
      )

    assert html =~ "Tribe Custodian"

    # Type in search filter
    filtered_html = render_change(view, "filter_tribes", %{"query" => "Alpha"})

    assert filtered_html =~ "Alpha Corp"
    refute filtered_html =~ "Beta Industries"
  end

  # ---------------------------------------------------------------------------
  # R10: Pilot overrides table displays entries [INTEGRATION]
  # ---------------------------------------------------------------------------

  test "pilot overrides table shows all entries", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    seed_active_custodian(cache_tables, wallet_address)
    seed_single_custodian_discovery(wallet_address)

    pilot_address = "0x" <> String.duplicate("ab", 32)
    Cache.put(cache_tables.standings, {:pilot_standing, @tribe_id, pilot_address}, 0)

    assert {:ok, _view, html} =
             live(
               authenticated_conn(conn, wallet_address, cache_tables, pubsub),
               "/tribe/#{@tribe_id}/diplomacy"
             )

    # Should show truncated pilot address and standing
    assert html =~ "Tribe Custodian"
    assert html =~ "0xabab"
    assert html =~ "Hostile"
    refute html =~ "No pilot overrides"
  end

  # ---------------------------------------------------------------------------
  # R11: Add pilot override [INTEGRATION]
  # ---------------------------------------------------------------------------

  test "adding pilot override builds transaction", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    seed_active_custodian(cache_tables, wallet_address)
    seed_single_custodian_discovery(wallet_address)

    pilot_address = "0x" <> String.duplicate("cd", 32)

    # No gas coin mocking needed — wallet handles gas via Transaction.fromKind()

    {:ok, view, html} =
      live(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub),
        "/tribe/#{@tribe_id}/diplomacy"
      )

    assert html =~ "Tribe Custodian"

    view
    |> form("#add-pilot-override-form", %{"pilot_address" => pilot_address, "standing" => "1"})
    |> render_submit()

    assert_push_event(view, "request_sign_transaction", %{"tx_bytes" => _tx_bytes})
  end

  # ---------------------------------------------------------------------------
  # R12: Invalid pilot address rejected [INTEGRATION]
  # ---------------------------------------------------------------------------

  test "invalid pilot address shows validation error", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    seed_active_custodian(cache_tables, wallet_address)
    seed_single_custodian_discovery(wallet_address)

    {:ok, view, mount_html} =
      live(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub),
        "/tribe/#{@tribe_id}/diplomacy"
      )

    assert mount_html =~ "Tribe Custodian"

    html =
      view
      |> form("#add-pilot-override-form", %{
        "pilot_address" => "not-a-valid-address",
        "standing" => "1"
      })
      |> render_submit()

    assert html =~ "Invalid address format"
    refute html =~ "request_sign_transaction"
  end

  # ---------------------------------------------------------------------------
  # R13: Default standing selector [INTEGRATION]
  # ---------------------------------------------------------------------------

  test "changing default standing builds transaction", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    seed_active_custodian(cache_tables, wallet_address)
    seed_single_custodian_discovery(wallet_address)
    Cache.put(cache_tables.standings, {:default_standing, @tribe_id}, 2)

    # No gas coin mocking needed — wallet handles gas via Transaction.fromKind()

    {:ok, view, html} =
      live(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub),
        "/tribe/#{@tribe_id}/diplomacy"
      )

    assert html =~ "Tribe Custodian"

    render_click(view, "set_default_standing", %{"standing" => "0"})

    assert_push_event(view, "request_sign_transaction", %{"tx_bytes" => _tx_bytes})
  end

  # ---------------------------------------------------------------------------
  # R14: NBSI/NRDS labels [INTEGRATION]
  # ---------------------------------------------------------------------------

  test "default standing shows NBSI or NRDS label", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    seed_active_custodian(cache_tables, wallet_address)
    seed_single_custodian_discovery(wallet_address)

    # Set default to hostile (NBSI)
    Cache.put(cache_tables.standings, {:default_standing, @tribe_id}, 0)

    assert {:ok, _view, html} =
             live(
               authenticated_conn(conn, wallet_address, cache_tables, pubsub),
               "/tribe/#{@tribe_id}/diplomacy"
             )

    assert html =~ "Tribe Custodian"
    assert html =~ "NBSI"
    refute html =~ "NRDS"
  end

  # ---------------------------------------------------------------------------
  # R15: Signing overlay during wallet approval [INTEGRATION]
  # ---------------------------------------------------------------------------

  test "signing state shows wallet approval overlay", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    seed_active_custodian(cache_tables, wallet_address)
    seed_single_custodian_discovery(wallet_address)
    Cache.put(cache_tables.standings, {:default_standing, @tribe_id}, 2)

    # No gas coin mocking needed — wallet handles gas via Transaction.fromKind()

    {:ok, view, mount_html} =
      live(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub),
        "/tribe/#{@tribe_id}/diplomacy"
      )

    assert mount_html =~ "Tribe Custodian"

    # Trigger a standings change to enter signing state
    render_click(view, "set_default_standing", %{"standing" => "4"})

    html = render(view)
    assert html =~ "Approve in your wallet"
  end

  # ---------------------------------------------------------------------------
  # R16: Successful transaction updates UI [INTEGRATION]
  # ---------------------------------------------------------------------------

  test "successful transaction updates standings and shows flash", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    seed_active_custodian(cache_tables, wallet_address)
    seed_single_custodian_discovery(wallet_address)
    Cache.put(cache_tables.standings, {:default_standing, @tribe_id}, 2)

    # No gas coin mocking needed — wallet handles gas via Transaction.fromKind()

    # Mock transaction submission
    expect(Sigil.Sui.ClientMock, :execute_transaction, fn _tx_bytes, [_sig], [] ->
      {:ok,
       %{
         "bcs" => "dGVzdC1lZmZlY3Rz",
         "status" => "SUCCESS",
         "transaction" => %{"digest" => "success-digest"},
         "gasEffects" => %{"gasSummary" => %{"computationCost" => "1"}}
       }}
    end)

    {:ok, view, mount_html} =
      live(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub),
        "/tribe/#{@tribe_id}/diplomacy"
      )

    assert mount_html =~ "Tribe Custodian"

    # Trigger standing change
    render_click(view, "set_default_standing", %{"standing" => "4"})

    # Simulate wallet signing the transaction
    render_hook(view, "transaction_signed", %{
      "bytes" => "signed-tx-bytes",
      "signature" => "wallet-signature"
    })

    html = render(view)
    # Should show success and return to active state
    refute html =~ "Approve in your wallet"
    refute html =~ "Transaction failed"
  end

  # ---------------------------------------------------------------------------
  # R17: Failed transaction shows error [INTEGRATION]
  # ---------------------------------------------------------------------------

  test "failed transaction shows error and returns to editor", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    seed_active_custodian(cache_tables, wallet_address)
    seed_single_custodian_discovery(wallet_address)
    Cache.put(cache_tables.standings, {:default_standing, @tribe_id}, 2)

    # No gas coin mocking needed — wallet handles gas via Transaction.fromKind()

    # Mock transaction submission failure
    expect(Sigil.Sui.ClientMock, :execute_transaction, fn _tx_bytes, [_sig], [] ->
      {:error, {:graphql_errors, [%{"message" => "execution aborted"}]}}
    end)

    {:ok, view, mount_html} =
      live(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub),
        "/tribe/#{@tribe_id}/diplomacy"
      )

    assert mount_html =~ "Tribe Custodian"

    render_click(view, "set_default_standing", %{"standing" => "4"})

    render_hook(view, "transaction_signed", %{
      "bytes" => "signed-tx-bytes",
      "signature" => "wallet-signature"
    })

    html = render(view)

    # Should show error but remain on editor
    assert has_element?(view, "[role=alert]")
    refute html =~ "Approve in your wallet"
  end

  # ---------------------------------------------------------------------------
  # R18: Wallet rejection handled [INTEGRATION]
  # ---------------------------------------------------------------------------

  test "wallet rejection shows cancellation message", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    seed_active_custodian(cache_tables, wallet_address)
    seed_single_custodian_discovery(wallet_address)
    Cache.put(cache_tables.standings, {:default_standing, @tribe_id}, 2)

    # No gas coin mocking needed — wallet handles gas via Transaction.fromKind()

    {:ok, view, mount_html} =
      live(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub),
        "/tribe/#{@tribe_id}/diplomacy"
      )

    assert mount_html =~ "Tribe Custodian"

    render_click(view, "set_default_standing", %{"standing" => "4"})

    # Simulate wallet rejection
    render_hook(view, "transaction_error", %{"reason" => "User rejected the request"})

    html = render(view)

    assert html =~ "Transaction cancelled"
    refute html =~ "Approve in your wallet"
  end

  # ---------------------------------------------------------------------------
  # R19: PubSub standing update refreshes display [INTEGRATION]
  # ---------------------------------------------------------------------------

  test "PubSub standing update refreshes standings display", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    seed_active_custodian(cache_tables, wallet_address)
    seed_single_custodian_discovery(wallet_address)
    Cache.put(cache_tables.standings, {:default_standing, @tribe_id}, 2)

    # Seed initial standing
    Cache.put(cache_tables.standings, {:tribe_standing, @tribe_id, 42}, 2)

    Cache.put(cache_tables.standings, {:world_tribe, 42}, %{
      id: 42,
      name: "Neutral Corp",
      short_name: "NC"
    })

    {:ok, view, html} =
      live(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub),
        "/tribe/#{@tribe_id}/diplomacy"
      )

    assert html =~ "Tribe Custodian"
    assert html =~ "Neutral"

    # Update standing via cache and broadcast
    Cache.put(cache_tables.standings, {:tribe_standing, @tribe_id, 42}, 0)

    Phoenix.PubSub.broadcast(
      pubsub,
      "diplomacy",
      {:standing_updated, %{tribe_id: 42, standing: :hostile}}
    )

    updated_html = render(view)

    assert updated_html =~ "Hostile"
    refute updated_html =~ "Standing update failed"
  end

  # ---------------------------------------------------------------------------
  # R20: Hook discovery events are safe no-ops [INTEGRATION]
  # ---------------------------------------------------------------------------

  test "wallet hook discovery events are ignored safely", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    seed_active_custodian(cache_tables, wallet_address)
    seed_single_custodian_discovery(wallet_address)

    {:ok, view, _html} =
      live(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub),
        "/tribe/#{@tribe_id}/diplomacy"
      )

    render_hook(view, "wallet_detected", %{"wallets" => ["EVE Vault"]})
    html = render_hook(view, "wallet_error", %{"reason" => "ignored"})

    assert html =~ "Tribe Custodian"
    assert html =~ "Tribe Standings"
    refute html =~ "Transaction cancelled"
  end

  # ---------------------------------------------------------------------------
  # R21: Successful submission reports effects when available [INTEGRATION]
  # ---------------------------------------------------------------------------

  test "successful diplomacy tx reports effects to wallet hook", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    seed_active_custodian(cache_tables, wallet_address)
    seed_single_custodian_discovery(wallet_address)
    Cache.put(cache_tables.standings, {:default_standing, @tribe_id}, 2)

    expect(Sigil.Sui.ClientMock, :execute_transaction, fn _tx_bytes, [_sig], [] ->
      {:ok,
       %{
         "bcs" => "effects-bcs-data",
         "status" => "SUCCESS",
         "transaction" => %{"digest" => "effects-digest"}
       }}
    end)

    {:ok, view, _html} =
      live(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub),
        "/tribe/#{@tribe_id}/diplomacy"
      )

    render_click(view, "set_default_standing", %{"standing" => "4"})

    render_hook(view, "transaction_signed", %{
      "bytes" => "signed-tx-bytes",
      "signature" => "wallet-signature"
    })

    html = render(view)
    assert html =~ "Tribe Custodian"
    assert_push_event(view, "report_transaction_effects", %{effects: "effects-bcs-data"})
  end

  # ---------------------------------------------------------------------------
  # R22: Full standings management flow [SYSTEM]
  # ---------------------------------------------------------------------------

  @tag :acceptance
  test "leader adds hostile standing and sees updated table", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    # Step 1: Custodian discovery — single custodian with wallet_address as leader
    expect(Sigil.Sui.ClientMock, :get_objects, fn [type: @custodian_type], [] ->
      {:ok,
       %{
         data: [custodian_object_json(table_id(0x99), wallet_address, @tribe_id, 31)],
         has_next_page: false,
         end_cursor: nil
       }}
    end)

    # Seed tribe names
    Cache.put(cache_tables.standings, {:world_tribe, 42}, %{
      id: 42,
      name: "Enemy Tribe",
      short_name: "ET"
    })

    # Step 2: Transaction submission
    expect(Sigil.Sui.ClientMock, :execute_transaction, fn _tx_bytes, [_sig], [] ->
      {:ok,
       %{
         "bcs" => "dGVzdC1lZmZlY3Rz",
         "status" => "SUCCESS",
         "transaction" => %{"digest" => "acceptance-flow-digest"}
       }}
    end)

    # Visit diplomacy page — custodian discovered, leader sees editor
    {:ok, view, html} =
      live(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub),
        "/tribe/#{@tribe_id}/diplomacy"
      )

    assert html =~ "Tribe Custodian"
    refute html =~ "Create Tribe Custodian"
    refute html =~ "Only the tribe leader can modify standings"

    # Add a hostile standing for tribe 42
    view
    |> form("#add-tribe-standing-form", %{"tribe_id" => "42", "standing" => "0"})
    |> render_submit()

    assert_push_event(view, "request_sign_transaction", %{"tx_bytes" => _tx_bytes})

    # Simulate wallet signing
    render_hook(view, "transaction_signed", %{
      "bytes" => "signed-tx-bytes",
      "signature" => "wallet-signature"
    })

    final_html = render(view)

    # Verify standing appears in the table
    assert final_html =~ "Enemy Tribe"
    assert final_html =~ "Hostile"
    refute final_html =~ "Approve in your wallet"
    refute final_html =~ "Transaction failed"
  end

  # ---------------------------------------------------------------------------
  # R24: Authorization guard redirects invalid visitors [INTEGRATION]
  # ---------------------------------------------------------------------------

  test "invalid or unauthorized diplomacy visit redirects with custodian-aware error", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    # Invalid tribe_id (not a number)
    assert {:error, {:redirect, %{to: "/", flash: %{"error" => invalid_error}}}} =
             live(
               authenticated_conn(conn, wallet_address, cache_tables, pubsub),
               "/tribe/not-a-number/diplomacy"
             )

    assert invalid_error =~ "Tribe Custodian"

    # Wrong tribe_id (not the user's tribe)
    assert {:error, {:redirect, %{to: "/", flash: %{"error" => unauthorized_error}}}} =
             live(
               authenticated_conn(conn, wallet_address, cache_tables, pubsub),
               "/tribe/999/diplomacy"
             )

    assert unauthorized_error =~ "Tribe Custodian"
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

  defp account_fixture(wallet_address, tribe_id, character_overrides \\ %{}) do
    %Account{
      address: wallet_address,
      characters: [
        Character.from_json(
          character_json(Map.put(character_overrides, "character_address", wallet_address))
        )
      ],
      tribe_id: tribe_id
    }
  end

  test "custodian discovery failure shows retry path", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    stub(Sigil.Sui.ClientMock, :get_objects, fn
      [type: @custodian_type], [] -> {:error, :timeout}
    end)

    assert {:ok, _view, html} =
             live(
               authenticated_conn(conn, wallet_address, cache_tables, pubsub),
               "/tribe/#{@tribe_id}/diplomacy"
             )

    assert html =~ "Custodian discovery failed"
    assert html =~ "Retry discovery"
    refute html =~ "Create Tribe Custodian"
  end

  test "missing character ref blocks signing", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id, %{"id" => uid("0xmissing-character")})
    Cache.put(cache_tables.accounts, wallet_address, account)

    stub(Sigil.Sui.ClientMock, :get_objects, fn
      [type: @custodian_type], [] ->
        {:ok, %{data: [], has_next_page: false, end_cursor: nil}}
    end)

    expect(Sigil.Sui.ClientMock, :get_object_with_ref, fn "0xmissing-character", [] ->
      {:error, :not_found}
    end)

    Cache.put(cache_tables.standings, {:registry_ref}, %{
      object_id: :binary.copy(<<0xDD>>, 32),
      initial_shared_version: 50
    })

    {:ok, view, _html} =
      live(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub),
        "/tribe/#{@tribe_id}/diplomacy"
      )

    view
    |> element("button", "Create Tribe Custodian")
    |> render_click()

    html = render(view)
    assert html =~ "Active character reference unavailable"
    refute html =~ "Approve in your wallet"
  end

  @tag :acceptance
  test "member creates custodian and reaches active editor", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    # Initially no custodian — mount shows create CTA
    expect(Sigil.Sui.ClientMock, :get_objects, fn [type: @custodian_type], [] ->
      {:ok, %{data: [], has_next_page: false, end_cursor: nil}}
    end)

    Cache.put(cache_tables.standings, {:registry_ref}, %{
      object_id: :binary.copy(<<0xDD>>, 32),
      initial_shared_version: 50
    })

    expect(Sigil.Sui.ClientMock, :execute_transaction, fn _tx_bytes, [_sig], [] ->
      # Seed the custodian in cache to simulate on-chain creation
      Cache.put(cache_tables.standings, {:active_custodian, @tribe_id}, %{
        object_id: table_id(0xFE),
        object_id_bytes: :binary.copy(<<0xFE>>, 32),
        initial_shared_version: 99,
        current_leader: wallet_address,
        tribe_id: @tribe_id
      })

      {:ok,
       %{
         "bcs" => "created-custodian-effects",
         "status" => "SUCCESS",
         "transaction" => %{"digest" => "created-custodian"}
       }}
    end)

    # After creation, re-discovery finds the new custodian
    expect(Sigil.Sui.ClientMock, :get_objects, fn [type: @custodian_type], [] ->
      {:ok,
       %{
         data: [custodian_object_json(table_id(0xFE), wallet_address, @tribe_id, 99)],
         has_next_page: false,
         end_cursor: nil
       }}
    end)

    {:ok, view, html} =
      live(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub),
        "/tribe/#{@tribe_id}/diplomacy"
      )

    assert html =~ "Create Tribe Custodian"
    refute html =~ "Only the tribe leader can modify standings"

    view
    |> element("button", "Create Tribe Custodian")
    |> render_click()

    render_hook(view, "transaction_signed", %{
      "bytes" => "signed-tx-bytes",
      "signature" => "wallet-signature"
    })

    final_html = render(view)
    assert final_html =~ "Tribe Standings"
    assert final_html =~ "Add Pilot Override"
    refute final_html =~ "Create Tribe Custodian"
    refute final_html =~ "Only the tribe leader can modify standings"
    refute final_html =~ "Transaction failed"
  end

  defp seed_active_custodian(cache_tables, wallet_address) do
    custodian = %{
      object_id: table_id(0x33),
      object_id_bytes: :binary.copy(<<0x33>>, 32),
      initial_shared_version: 41,
      owner: wallet_address,
      current_leader: wallet_address,
      tribe_id: @tribe_id
    }

    Cache.put(cache_tables.standings, {:active_custodian, @tribe_id}, custodian)
  end

  defp seed_single_custodian_discovery(wallet_address) do
    expect(Sigil.Sui.ClientMock, :get_objects, fn [type: @custodian_type], [] ->
      {:ok,
       %{
         data: [custodian_object_json(table_id(0x33), wallet_address, @tribe_id, 41)],
         has_next_page: false,
         end_cursor: nil
       }}
    end)
  end

  defp unique_pubsub_name do
    :"diplomacy_live_pubsub_#{System.unique_integer([:positive])}"
  end

  defp unique_wallet_address do
    suffix =
      System.unique_integer([:positive])
      |> Integer.to_string(16)
      |> String.downcase()
      |> String.pad_leading(64, "0")

    "0x" <> suffix
  end

  defp table_id(byte) do
    "0x" <> Base.encode16(:binary.copy(<<byte>>, 32), case: :lower)
  end

  defp custodian_object_json(object_id, current_leader, tribe_id, initial_shared_version) do
    %{
      "id" => object_id,
      "address" => object_id,
      "current_leader" => current_leader,
      "tribe_id" => tribe_id,
      "initialSharedVersion" => Integer.to_string(initial_shared_version),
      "shared" => %{"initialSharedVersion" => Integer.to_string(initial_shared_version)}
    }
  end

  defp character_json(overrides) do
    Map.merge(
      %{
        "id" => uid(@character_id),
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

  defp uid(id), do: %{"id" => id}
end
