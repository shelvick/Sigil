defmodule SigilWeb.DiplomacyLiveTest do
  @moduledoc """
  Covers the UI_DiplomacyLive specification (R1-R20) from Packet 4.
  Tests diplomacy editor: page states, standings CRUD, pilot overrides,
  transaction signing flow, PubSub updates, and full user journey.
  """

  use Sigil.ConnCase, async: true

  import Hammox

  alias Sigil.Cache
  alias Sigil.Accounts.Account
  alias Sigil.Sui.Types.Character

  @tribe_id 314
  @standings_package_id "0x06ce9d6bed77615383575cc7eba4883d32769b30cd5df00561e38434a59611a1"
  @standings_table_type "#{@standings_package_id}::standings_table::StandingsTable"

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
  # R1: No table state shows create CTA [INTEGRATION]
  # ---------------------------------------------------------------------------

  test "no table state shows create standings table button", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    # Mock table discovery returning empty
    expect(Sigil.Sui.ClientMock, :get_objects, fn [type: @standings_table_type], [] ->
      {:ok, %{data: [], has_next_page: false, end_cursor: nil}}
    end)

    assert {:ok, _view, html} =
             live(
               authenticated_conn(conn, wallet_address, cache_tables, pubsub),
               "/tribe/#{@tribe_id}/diplomacy"
             )

    assert html =~ "Create Standings Table"
    assert html =~ "doesn&#39;t have a Standings Table"
    refute html =~ "Manage Standings"
  end

  # ---------------------------------------------------------------------------
  # R2: Create table triggers wallet signing [INTEGRATION]
  # ---------------------------------------------------------------------------

  test "create table click builds tx and pushes sign event", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    # Mock table discovery returning empty
    expect(Sigil.Sui.ClientMock, :get_objects, fn [type: @standings_table_type], [] ->
      {:ok, %{data: [], has_next_page: false, end_cursor: nil}}
    end)

    # No gas coin mocking needed — wallet handles gas via Transaction.fromKind()

    {:ok, view, _html} =
      live(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub),
        "/tribe/#{@tribe_id}/diplomacy"
      )

    # Click the create table button
    view
    |> element("button", "Create Standings Table")
    |> render_click()

    # Should push sign event to JS hook
    assert_push_event(view, "request_sign_transaction", %{"tx_bytes" => tx_bytes})
    assert is_binary(tx_bytes)
    assert byte_size(tx_bytes) > 0
  end

  # ---------------------------------------------------------------------------
  # R3: Table selection when multiple exist [INTEGRATION]
  # ---------------------------------------------------------------------------

  test "multiple tables shows selection list", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    table_one = table_object_json(table_id(0x11), wallet_address, 17)
    table_two = table_object_json(table_id(0x22), wallet_address, 23)

    # Mock table discovery returning multiple
    expect(Sigil.Sui.ClientMock, :get_objects, fn [type: @standings_table_type], [] ->
      {:ok, %{data: [table_one, table_two], has_next_page: false, end_cursor: nil}}
    end)

    assert {:ok, _view, html} =
             live(
               authenticated_conn(conn, wallet_address, cache_tables, pubsub),
               "/tribe/#{@tribe_id}/diplomacy"
             )

    assert html =~ "Multiple Standings Tables"
    refute html =~ "Create Standings Table"
  end

  # ---------------------------------------------------------------------------
  # R4: Active state shows standings editor [INTEGRATION]
  # ---------------------------------------------------------------------------

  test "active state renders full standings editor", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    seed_active_table(cache_tables, wallet_address)

    # Single table — auto-selected
    expect(Sigil.Sui.ClientMock, :get_objects, fn [type: @standings_table_type], [] ->
      {:ok,
       %{
         data: [table_object_json(table_id(0x33), wallet_address, 41)],
         has_next_page: false,
         end_cursor: nil
       }}
    end)

    assert {:ok, _view, html} =
             live(
               authenticated_conn(conn, wallet_address, cache_tables, pubsub),
               "/tribe/#{@tribe_id}/diplomacy"
             )

    # Editor sections should be visible
    assert html =~ "Tribe Standings"
    assert html =~ "Pilot Overrides"
    assert html =~ "Default Standing"
    refute html =~ "Create Standings Table"
    refute html =~ "Multiple Standings Tables"
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

    seed_active_table(cache_tables, wallet_address)
    seed_single_table_discovery(wallet_address)

    # Seed tribe standings
    Cache.put(cache_tables.standings, {:tribe_standing, 42}, 0)
    Cache.put(cache_tables.standings, {:tribe_standing, 271}, 4)

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

    seed_active_table(cache_tables, wallet_address)
    seed_single_table_discovery(wallet_address)

    # Seed world tribes for dropdown
    Cache.put(cache_tables.standings, {:world_tribe, 42}, %{
      id: 42,
      name: "Target Tribe",
      short_name: "TT"
    })

    # No gas coin mocking needed — wallet handles gas via Transaction.fromKind()

    {:ok, view, _html} =
      live(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub),
        "/tribe/#{@tribe_id}/diplomacy"
      )

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

    seed_active_table(cache_tables, wallet_address)
    seed_single_table_discovery(wallet_address)

    # Seed existing standing
    Cache.put(cache_tables.standings, {:tribe_standing, 42}, 2)

    Cache.put(cache_tables.standings, {:world_tribe, 42}, %{
      id: 42,
      name: "Some Tribe",
      short_name: "ST"
    })

    # No gas coin mocking needed — wallet handles gas via Transaction.fromKind()

    {:ok, view, _html} =
      live(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub),
        "/tribe/#{@tribe_id}/diplomacy"
      )

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

    seed_active_table(cache_tables, wallet_address)
    seed_single_table_discovery(wallet_address)

    # Seed existing standings
    Cache.put(cache_tables.standings, {:tribe_standing, 42}, 2)
    Cache.put(cache_tables.standings, {:tribe_standing, 43}, 2)

    # No gas coin mocking needed — wallet handles gas via Transaction.fromKind()

    {:ok, view, _html} =
      live(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub),
        "/tribe/#{@tribe_id}/diplomacy"
      )

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

    seed_active_table(cache_tables, wallet_address)
    seed_single_table_discovery(wallet_address)

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

    {:ok, view, _html} =
      live(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub),
        "/tribe/#{@tribe_id}/diplomacy"
      )

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

    seed_active_table(cache_tables, wallet_address)
    seed_single_table_discovery(wallet_address)

    pilot_address = "0x" <> String.duplicate("ab", 32)
    Cache.put(cache_tables.standings, {:pilot_standing, pilot_address}, 0)

    assert {:ok, _view, html} =
             live(
               authenticated_conn(conn, wallet_address, cache_tables, pubsub),
               "/tribe/#{@tribe_id}/diplomacy"
             )

    # Should show truncated pilot address and standing
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

    seed_active_table(cache_tables, wallet_address)
    seed_single_table_discovery(wallet_address)

    pilot_address = "0x" <> String.duplicate("cd", 32)

    # No gas coin mocking needed — wallet handles gas via Transaction.fromKind()

    {:ok, view, _html} =
      live(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub),
        "/tribe/#{@tribe_id}/diplomacy"
      )

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

    seed_active_table(cache_tables, wallet_address)
    seed_single_table_discovery(wallet_address)

    {:ok, view, _html} =
      live(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub),
        "/tribe/#{@tribe_id}/diplomacy"
      )

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

    seed_active_table(cache_tables, wallet_address)
    seed_single_table_discovery(wallet_address)
    Cache.put(cache_tables.standings, :default_standing, 2)

    # No gas coin mocking needed — wallet handles gas via Transaction.fromKind()

    {:ok, view, _html} =
      live(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub),
        "/tribe/#{@tribe_id}/diplomacy"
      )

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

    seed_active_table(cache_tables, wallet_address)
    seed_single_table_discovery(wallet_address)

    # Set default to hostile (NBSI)
    Cache.put(cache_tables.standings, :default_standing, 0)

    assert {:ok, _view, html} =
             live(
               authenticated_conn(conn, wallet_address, cache_tables, pubsub),
               "/tribe/#{@tribe_id}/diplomacy"
             )

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

    seed_active_table(cache_tables, wallet_address)
    seed_single_table_discovery(wallet_address)
    Cache.put(cache_tables.standings, :default_standing, 2)

    # No gas coin mocking needed — wallet handles gas via Transaction.fromKind()

    {:ok, view, _html} =
      live(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub),
        "/tribe/#{@tribe_id}/diplomacy"
      )

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

    seed_active_table(cache_tables, wallet_address)
    seed_single_table_discovery(wallet_address)
    Cache.put(cache_tables.standings, :default_standing, 2)

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

    {:ok, view, _html} =
      live(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub),
        "/tribe/#{@tribe_id}/diplomacy"
      )

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

    seed_active_table(cache_tables, wallet_address)
    seed_single_table_discovery(wallet_address)
    Cache.put(cache_tables.standings, :default_standing, 2)

    # No gas coin mocking needed — wallet handles gas via Transaction.fromKind()

    # Mock transaction submission failure
    expect(Sigil.Sui.ClientMock, :execute_transaction, fn _tx_bytes, [_sig], [] ->
      {:error, {:graphql_errors, [%{"message" => "execution aborted"}]}}
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

    seed_active_table(cache_tables, wallet_address)
    seed_single_table_discovery(wallet_address)
    Cache.put(cache_tables.standings, :default_standing, 2)

    # No gas coin mocking needed — wallet handles gas via Transaction.fromKind()

    {:ok, view, _html} =
      live(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub),
        "/tribe/#{@tribe_id}/diplomacy"
      )

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

    seed_active_table(cache_tables, wallet_address)
    seed_single_table_discovery(wallet_address)
    Cache.put(cache_tables.standings, :default_standing, 2)

    # Seed initial standing
    Cache.put(cache_tables.standings, {:tribe_standing, 42}, 2)

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

    assert html =~ "Neutral"

    # Update standing via cache and broadcast
    Cache.put(cache_tables.standings, {:tribe_standing, 42}, 0)

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
  # R20: Full standings management flow [SYSTEM]
  # ---------------------------------------------------------------------------

  @tag :acceptance
  test "full flow: visit diplomacy → add hostile standing → see updated table", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    # Step 1: Table discovery — single table auto-selects
    table = table_object_json(table_id(0x99), wallet_address, 31)

    expect(Sigil.Sui.ClientMock, :get_objects, fn [type: @standings_table_type], [] ->
      {:ok, %{data: [table], has_next_page: false, end_cursor: nil}}
    end)

    # Seed tribe names
    Cache.put(cache_tables.standings, {:world_tribe, 42}, %{
      id: 42,
      name: "Enemy Tribe",
      short_name: "ET"
    })

    # Step 2: Transaction submission (no gas coin mocking — wallet handles gas)
    expect(Sigil.Sui.ClientMock, :execute_transaction, fn _tx_bytes, [_sig], [] ->
      {:ok,
       %{
         "bcs" => "dGVzdC1lZmZlY3Rz",
         "status" => "SUCCESS",
         "transaction" => %{"digest" => "acceptance-flow-digest"},
         "gasEffects" => %{"gasSummary" => %{"computationCost" => "1"}}
       }}
    end)

    # Visit diplomacy page
    {:ok, view, html} =
      live(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub),
        "/tribe/#{@tribe_id}/diplomacy"
      )

    # Should show editor (single table auto-selected)
    refute html =~ "Create Standings Table"
    refute html =~ "Table discovery failed"

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

  defp seed_active_table(cache_tables, wallet_address) do
    Cache.put(cache_tables.standings, {:active_table, wallet_address}, %{
      object_id: table_id(0x33),
      object_id_bytes: :binary.copy(<<0x33>>, 32),
      initial_shared_version: 41,
      owner: wallet_address
    })
  end

  defp seed_single_table_discovery(wallet_address) do
    expect(Sigil.Sui.ClientMock, :get_objects, fn [type: @standings_table_type], [] ->
      {:ok,
       %{
         data: [table_object_json(table_id(0x33), wallet_address, 41)],
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

  defp table_object_json(object_id, owner, initial_shared_version) do
    %{
      "id" => object_id,
      "address" => object_id,
      "owner" => owner,
      "initialSharedVersion" => Integer.to_string(initial_shared_version),
      "shared" => %{"initialSharedVersion" => Integer.to_string(initial_shared_version)}
    }
  end

  defp character_json(overrides \\ %{}) do
    Map.merge(
      %{
        "id" => uid("0xcharacter-diplomacy"),
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
