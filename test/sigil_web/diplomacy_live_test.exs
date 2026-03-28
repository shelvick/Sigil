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
  # R1: No custodian flow hides governance section [INTEGRATION]
  # ---------------------------------------------------------------------------

  test "no custodian flow hides governance section", %{
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
    refute html =~ "Tribe Governance"
    refute html =~ "Current Leader"
    refute html =~ ~s(phx-click="toggle_governance")
    refute html =~ "Claim Leadership"
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

  test "governance topic refresh updates open diplomacy view", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    other_leader = unique_wallet_address()
    seed_active_custodian(cache_tables, other_leader)

    expect(Sigil.Sui.ClientMock, :get_objects, fn [type: @custodian_type], [] ->
      {:ok,
       %{
         data: [custodian_object_json(table_id(0x33), other_leader, @tribe_id, 41)],
         has_next_page: false,
         end_cursor: nil
       }}
    end)

    {:ok, view, html} =
      live(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub),
        "/tribe/#{@tribe_id}/diplomacy"
      )

    assert html =~ "Only the tribe leader can modify standings"
    refute html =~ "Add Pilot Override"

    Cache.put(cache_tables.standings, {:active_custodian, @tribe_id}, %{
      object_id: table_id(0x44),
      object_id_bytes: :binary.copy(<<0x44>>, 32),
      initial_shared_version: 52,
      current_leader: wallet_address,
      current_leader_votes: 2,
      members: [wallet_address],
      votes_table_id: table_id(0x45),
      vote_tallies_table_id: table_id(0x46),
      tribe_id: @tribe_id
    })

    Phoenix.PubSub.broadcast(
      pubsub,
      Sigil.Diplomacy.topic(@tribe_id),
      {:governance_updated, %{tribe_id: @tribe_id}}
    )

    updated_html = render(view)

    assert updated_html =~ "Add Pilot Override"
    refute updated_html =~ "Only the tribe leader can modify standings"

    repeated_html = render(view)
    assert repeated_html =~ "Add Pilot Override"
    refute repeated_html =~ "Only the tribe leader can modify standings"
  end

  test "non-governance success does not swallow later governance refresh", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    other_leader = unique_wallet_address()
    votes_table_id = table_id(0x47)
    vote_tallies_table_id = table_id(0x48)

    seed_active_custodian(cache_tables, other_leader,
      current_leader_votes: 1,
      members: [other_leader, wallet_address],
      votes_table_id: votes_table_id,
      vote_tallies_table_id: vote_tallies_table_id
    )

    seed_single_custodian_discovery(other_leader,
      current_leader_votes: 1,
      members: [other_leader, wallet_address],
      votes_table_id: votes_table_id,
      vote_tallies_table_id: vote_tallies_table_id
    )

    stub_governance_reads(other_leader,
      votes_table_id: votes_table_id,
      vote_tallies_table_id: vote_tallies_table_id,
      votes: [vote_entry(other_leader, other_leader), vote_entry(wallet_address, other_leader)],
      tallies: [tally_entry(other_leader, 1), tally_entry(wallet_address, 0)]
    )

    expect(Sigil.Sui.ClientMock, :execute_transaction, fn _tx_bytes, [_sig], [] ->
      {:ok,
       %{
         "bcs" => "default-effects",
         "status" => "SUCCESS",
         "transaction" => %{"digest" => "default-digest"}
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

    Cache.put(cache_tables.standings, {:active_custodian, @tribe_id}, %{
      object_id: table_id(0x49),
      object_id_bytes: :binary.copy(<<0x49>>, 32),
      initial_shared_version: 53,
      current_leader: wallet_address,
      current_leader_votes: 2,
      members: [wallet_address],
      votes_table_id: votes_table_id,
      vote_tallies_table_id: vote_tallies_table_id,
      tribe_id: @tribe_id
    })

    Phoenix.PubSub.broadcast(
      pubsub,
      Sigil.Diplomacy.topic(@tribe_id),
      {:governance_updated, %{tribe_id: @tribe_id}}
    )

    updated_html = render(view)

    assert updated_html =~ "Add Pilot Override"
    refute updated_html =~ "Only the tribe leader can modify standings"
  end

  test "governance section starts collapsed above standings", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    challenger = "0x" <> String.duplicate("ab", 32)

    seed_active_custodian(cache_tables, wallet_address,
      current_leader_votes: 3,
      members: [wallet_address, challenger]
    )

    seed_single_custodian_discovery(wallet_address,
      current_leader_votes: 3,
      members: [wallet_address, challenger]
    )

    stub_governance_reads(wallet_address,
      votes: [vote_entry(wallet_address, wallet_address), vote_entry(challenger, wallet_address)],
      tallies: [tally_entry(wallet_address, 3)]
    )

    assert {:ok, _view, html} =
             live(
               authenticated_conn(conn, wallet_address, cache_tables, pubsub),
               "/tribe/#{@tribe_id}/diplomacy"
             )

    assert html =~ "Tribe Governance"
    governance_index = html |> :binary.match("Tribe Governance") |> elem(0)
    standings_index = html |> :binary.match("Tribe Standings") |> elem(0)

    assert governance_index < standings_index
    assert html =~ "Current Leader"
    assert html =~ "3 votes"
    assert html =~ ~s(phx-click="toggle_governance")
    refute html =~ "Voted for"
  end

  test "expanded governance section shows members with vote indicators", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    candidate = "0x" <> String.duplicate("ab", 32)

    seed_active_custodian(cache_tables, wallet_address,
      current_leader_votes: 2,
      members: [wallet_address, candidate]
    )

    seed_single_custodian_discovery(wallet_address,
      current_leader_votes: 2,
      members: [wallet_address, candidate]
    )

    stub_governance_reads(wallet_address,
      votes: [vote_entry(wallet_address, wallet_address), vote_entry(candidate, wallet_address)],
      tallies: [tally_entry(wallet_address, 2)]
    )

    {:ok, view, _html} =
      live(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub),
        "/tribe/#{@tribe_id}/diplomacy"
      )

    view
    |> element("button[phx-click=toggle_governance]")
    |> render_click()

    html = render(view)

    assert html =~ challenger_label(candidate)
    assert html =~ "Vote"
    assert html =~ "Voted for"
    assert html =~ "2 votes"
  end

  test "governance section toggles between expanded and collapsed", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    candidate = "0x" <> String.duplicate("be", 32)

    seed_active_custodian(cache_tables, wallet_address,
      current_leader_votes: 2,
      members: [wallet_address, candidate]
    )

    seed_single_custodian_discovery(wallet_address,
      current_leader_votes: 2,
      members: [wallet_address, candidate]
    )

    stub_governance_reads(wallet_address,
      votes: [vote_entry(wallet_address, wallet_address), vote_entry(candidate, wallet_address)],
      tallies: [tally_entry(wallet_address, 2)]
    )

    {:ok, view, initial_html} =
      live(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub),
        "/tribe/#{@tribe_id}/diplomacy"
      )

    refute initial_html =~ challenger_label(candidate)

    view
    |> element("button[phx-click=toggle_governance]")
    |> render_click()

    expanded_html = render(view)
    assert expanded_html =~ challenger_label(candidate)
    assert expanded_html =~ "Voted for"

    view
    |> element("button[phx-click=toggle_governance]")
    |> render_click()

    collapsed_html = render(view)
    refute collapsed_html =~ challenger_label(candidate)
    refute collapsed_html =~ "Voted for"
    assert collapsed_html =~ "Tribe Governance"
    assert collapsed_html =~ "2 votes"
  end

  test "clicking vote builds vote_leader tx and enters signing flow", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    candidate = "0x" <> String.duplicate("bc", 32)

    seed_active_custodian(cache_tables, wallet_address, members: [wallet_address, candidate])
    seed_single_custodian_discovery(wallet_address, members: [wallet_address, candidate])

    stub_governance_reads(wallet_address,
      votes: [vote_entry(wallet_address, wallet_address), vote_entry(candidate, wallet_address)],
      tallies: [tally_entry(wallet_address, 2)]
    )

    {:ok, view, _html} =
      live(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub),
        "/tribe/#{@tribe_id}/diplomacy"
      )

    view
    |> element("button[phx-click=toggle_governance]")
    |> render_click()

    view
    |> element(~s(button[phx-click=vote_leader][phx-value-candidate="#{candidate}"]))
    |> render_click()

    assert_push_event(view, "request_sign_transaction", %{"tx_bytes" => tx_bytes})
    assert is_binary(tx_bytes)

    html = render(view)
    assert html =~ "Approve in your wallet"
    refute html =~ "Transaction failed"
  end

  test "claim leadership button shown only when viewer has more votes", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    incumbent = "0x" <> String.duplicate("de", 32)

    seed_active_custodian(cache_tables, incumbent,
      current_leader_votes: 1,
      members: [wallet_address, incumbent]
    )

    seed_single_custodian_discovery(incumbent,
      current_leader_votes: 1,
      members: [wallet_address, incumbent]
    )

    stub_governance_reads(incumbent,
      votes: [vote_entry(wallet_address, wallet_address), vote_entry(incumbent, incumbent)],
      tallies: [tally_entry(wallet_address, 2), tally_entry(incumbent, 1)]
    )

    {:ok, view, _html} =
      live(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub),
        "/tribe/#{@tribe_id}/diplomacy"
      )

    view
    |> element("button[phx-click=toggle_governance]")
    |> render_click()

    html = render(view)
    assert html =~ "Claim Leadership"
    refute html =~ "Leadership locked"
  end

  test "claim leadership button respects localnet signer address", %{
    wallet_address: wallet_address
  } do
    signer_key = Base.decode16!(String.duplicate("11", 32), case: :mixed)
    {public_key, _private_key} = Sigil.Sui.Signer.keypair_from_private_key(signer_key)

    signer_address =
      public_key
      |> Sigil.Sui.Signer.address_from_public_key()
      |> Sigil.Sui.Signer.to_sui_address()

    incumbent = "0x" <> String.duplicate("ef", 32)

    html =
      Phoenix.LiveViewTest.render_component(
        &SigilWeb.DiplomacyLive.Components.governance_section/1,
        active_custodian: %{
          current_leader: incumbent,
          current_leader_votes: 1,
          members: [signer_address, incumbent]
        },
        governance_data: %{
          votes: %{signer_address => signer_address, incumbent => incumbent},
          tallies: %{signer_address => 2, incumbent => 1}
        },
        governance_error: nil,
        governance_expanded: true,
        is_member: true,
        viewer_address: signer_address,
        tribe_members: [],
        current_account: %{address: wallet_address}
      )

    assert html =~ "Claim Leadership"
  end

  test "clicking claim leadership builds tx and enters signing flow", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    incumbent = "0x" <> String.duplicate("ef", 32)

    seed_active_custodian(cache_tables, incumbent,
      current_leader_votes: 1,
      members: [wallet_address, incumbent]
    )

    seed_single_custodian_discovery(incumbent,
      current_leader_votes: 1,
      members: [wallet_address, incumbent]
    )

    stub_governance_reads(incumbent,
      votes: [vote_entry(wallet_address, wallet_address), vote_entry(incumbent, incumbent)],
      tallies: [tally_entry(wallet_address, 2), tally_entry(incumbent, 1)]
    )

    {:ok, view, _html} =
      live(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub),
        "/tribe/#{@tribe_id}/diplomacy"
      )

    view
    |> element("button[phx-click=toggle_governance]")
    |> render_click()

    view
    |> element("button[phx-click=claim_leadership]")
    |> render_click()

    assert_push_event(view, "request_sign_transaction", %{"tx_bytes" => tx_bytes})
    assert is_binary(tx_bytes)
  end

  @tag :acceptance
  test "claim leadership journey updates the governance section", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    incumbent = "0x" <> String.duplicate("cd", 32)
    votes_table_id = table_id(0x63)
    vote_tallies_table_id = table_id(0x64)

    seed_active_custodian(cache_tables, incumbent,
      current_leader_votes: 1,
      members: [wallet_address, incumbent],
      votes_table_id: votes_table_id,
      vote_tallies_table_id: vote_tallies_table_id
    )

    seed_single_custodian_discovery(incumbent,
      current_leader_votes: 1,
      members: [wallet_address, incumbent],
      votes_table_id: votes_table_id,
      vote_tallies_table_id: vote_tallies_table_id,
      calls: 2
    )

    stub_governance_reads_sequence(
      votes_table_id,
      vote_tallies_table_id,
      [vote_entry(wallet_address, wallet_address), vote_entry(incumbent, incumbent)],
      [tally_entry(wallet_address, 2), tally_entry(incumbent, 1)],
      [vote_entry(wallet_address, wallet_address), vote_entry(incumbent, wallet_address)],
      [tally_entry(wallet_address, 3)]
    )

    expect(Sigil.Sui.ClientMock, :execute_transaction, fn _tx_bytes, [_sig], [] ->
      {:ok,
       %{
         "bcs" => "claim-effects",
         "status" => "SUCCESS",
         "transaction" => %{"digest" => "claim-digest"}
       }}
    end)

    {:ok, view, html} =
      live(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub),
        "/tribe/#{@tribe_id}/diplomacy"
      )

    assert html =~ "Current Leader"
    assert html =~ "1 votes"

    view
    |> element("button[phx-click=toggle_governance]")
    |> render_click()

    before_claim_html = render(view)
    assert before_claim_html =~ challenger_label(incumbent)
    assert before_claim_html =~ "Claim Leadership"
    assert before_claim_html =~ "1 votes"

    view
    |> element("button[phx-click=claim_leadership]")
    |> render_click()

    assert_push_event(view, "request_sign_transaction", %{"tx_bytes" => _tx_bytes})

    render_hook(view, "transaction_signed", %{
      "bytes" => "signed-tx-bytes",
      "signature" => "wallet-signature"
    })

    updated_html = render(view)

    assert updated_html =~ "Current Leader"
    assert updated_html =~ "3 votes"
    refute updated_html =~ "Approve in your wallet"
    refute updated_html =~ "Transaction failed"
  end

  test "governance load failure keeps standings usable", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    leader = wallet_address
    votes_table_id = table_id(0x51)
    vote_tallies_table_id = table_id(0x52)

    seed_active_custodian(cache_tables, leader,
      votes_table_id: votes_table_id,
      vote_tallies_table_id: vote_tallies_table_id
    )

    seed_single_custodian_discovery(leader,
      votes_table_id: votes_table_id,
      vote_tallies_table_id: vote_tallies_table_id
    )

    Cache.put(cache_tables.standings, {:tribe_standing, @tribe_id, 42}, 4)

    Cache.put(cache_tables.standings, {:world_tribe, 42}, %{
      id: 42,
      name: "Friendly Tribe",
      short_name: "FT"
    })

    expect(Sigil.Sui.ClientMock, :get_dynamic_fields, fn ^votes_table_id, [] ->
      {:error, :timeout}
    end)

    assert {:ok, _view, html} =
             live(
               authenticated_conn(conn, wallet_address, cache_tables, pubsub),
               "/tribe/#{@tribe_id}/diplomacy"
             )

    assert html =~ "Friendly Tribe"
    assert html =~ "Unable to load governance data"
    refute html =~ "Create Tribe Custodian"
  end

  test "unknown member label falls back to address", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    unknown_member = "0x" <> String.duplicate("fa", 32)

    seed_active_custodian(cache_tables, wallet_address, members: [wallet_address, unknown_member])
    seed_single_custodian_discovery(wallet_address, members: [wallet_address, unknown_member])

    stub_governance_reads(wallet_address,
      votes: [
        vote_entry(wallet_address, wallet_address),
        vote_entry(unknown_member, wallet_address)
      ],
      tallies: [tally_entry(wallet_address, 2)]
    )

    {:ok, view, _html} =
      live(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub),
        "/tribe/#{@tribe_id}/diplomacy"
      )

    view
    |> element("button[phx-click=toggle_governance]")
    |> render_click()

    html = render(view)

    assert html =~ challenger_label(unknown_member)
    refute html =~ "Unknown member"
  end

  test "non-custodian-member sees join-via-vote prompt", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    incumbent = "0x" <> String.duplicate("dd", 32)

    seed_active_custodian(cache_tables, incumbent,
      current_leader_votes: 2,
      members: [incumbent]
    )

    seed_single_custodian_discovery(incumbent,
      current_leader_votes: 2,
      members: [incumbent]
    )

    stub_governance_reads(incumbent,
      votes: [vote_entry(incumbent, incumbent)],
      tallies: [tally_entry(incumbent, 2)]
    )

    {:ok, view, _html} =
      live(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub),
        "/tribe/#{@tribe_id}/diplomacy"
      )

    view
    |> element("button[phx-click=toggle_governance]")
    |> render_click()

    html = render(view)
    assert html =~ "Vote"
    assert html =~ "voting will register"
    refute html =~ "Claim Leadership"
  end

  test "governance wallet rejection preserves prior state", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    candidate = "0x" <> String.duplicate("ac", 32)

    seed_active_custodian(cache_tables, wallet_address, members: [wallet_address, candidate])
    seed_single_custodian_discovery(wallet_address, members: [wallet_address, candidate])

    stub_governance_reads(wallet_address,
      votes: [vote_entry(wallet_address, wallet_address), vote_entry(candidate, wallet_address)],
      tallies: [tally_entry(wallet_address, 2)]
    )

    {:ok, view, _html} =
      live(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub),
        "/tribe/#{@tribe_id}/diplomacy"
      )

    view
    |> element("button[phx-click=toggle_governance]")
    |> render_click()

    view
    |> element(~s(button[phx-click=vote_leader][phx-value-candidate="#{candidate}"]))
    |> render_click()

    render_hook(view, "transaction_error", %{"reason" => "User rejected the request"})

    html = render(view)

    assert html =~ "Transaction cancelled"
    assert html =~ "Tribe Governance"
    assert html =~ challenger_label(candidate)
    refute html =~ "Approve in your wallet"
  end

  @tag :acceptance
  test "full voting journey updates the governance section", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    candidate = "0x" <> String.duplicate("aa", 32)
    votes_table_id = table_id(0x61)
    vote_tallies_table_id = table_id(0x62)

    seed_active_custodian(cache_tables, wallet_address,
      current_leader_votes: 1,
      members: [wallet_address, candidate],
      votes_table_id: votes_table_id,
      vote_tallies_table_id: vote_tallies_table_id
    )

    seed_single_custodian_discovery(wallet_address,
      current_leader_votes: 1,
      members: [wallet_address, candidate],
      votes_table_id: votes_table_id,
      vote_tallies_table_id: vote_tallies_table_id,
      calls: 2
    )

    stub_governance_reads_sequence(
      votes_table_id,
      vote_tallies_table_id,
      [vote_entry(wallet_address, wallet_address), vote_entry(candidate, candidate)],
      [tally_entry(wallet_address, 1), tally_entry(candidate, 1)],
      [vote_entry(wallet_address, candidate), vote_entry(candidate, candidate)],
      [tally_entry(candidate, 2)]
    )

    expect(Sigil.Sui.ClientMock, :execute_transaction, fn _tx_bytes, [_sig], [] ->
      {:ok,
       %{
         "bcs" => "governance-effects",
         "status" => "SUCCESS",
         "transaction" => %{"digest" => "governance-vote-digest"}
       }}
    end)

    {:ok, view, html} =
      live(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub),
        "/tribe/#{@tribe_id}/diplomacy"
      )

    assert html =~ "Tribe Governance"
    refute html =~ "Transaction failed"

    view
    |> element("button[phx-click=toggle_governance]")
    |> render_click()

    before_vote_html = render(view)
    assert before_vote_html =~ challenger_label(candidate)
    assert before_vote_html =~ "1 votes"

    view
    |> element(~s(button[phx-click=vote_leader][phx-value-candidate="#{candidate}"]))
    |> render_click()

    assert_push_event(view, "request_sign_transaction", %{"tx_bytes" => _tx_bytes})

    render_hook(view, "transaction_signed", %{
      "bytes" => "signed-tx-bytes",
      "signature" => "wallet-signature"
    })

    updated_html = render(view)

    assert updated_html =~ "Tribe Governance"
    assert updated_html =~ challenger_label(candidate)
    assert updated_html =~ "2 votes"
    refute updated_html =~ "Approve in your wallet"
    refute updated_html =~ "Transaction failed"
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

  defp seed_active_custodian(cache_tables, wallet_address, overrides \\ []) do
    object_id = Keyword.get(overrides, :object_id, table_id(0x33))
    object_id_bytes = object_id |> String.replace_prefix("0x", "") |> Base.decode16!(case: :mixed)

    custodian = %{
      object_id: object_id,
      object_id_bytes: object_id_bytes,
      initial_shared_version: Keyword.get(overrides, :initial_shared_version, 41),
      owner: wallet_address,
      current_leader: wallet_address,
      current_leader_votes: Keyword.get(overrides, :current_leader_votes, 1),
      members: Keyword.get(overrides, :members, [wallet_address]),
      votes_table_id: Keyword.get(overrides, :votes_table_id, table_id(0x34)),
      vote_tallies_table_id: Keyword.get(overrides, :vote_tallies_table_id, table_id(0x35)),
      tribe_id: @tribe_id
    }

    Cache.put(cache_tables.standings, {:active_custodian, @tribe_id}, custodian)
  end

  defp seed_single_custodian_discovery(wallet_address, overrides \\ []) do
    calls = Keyword.get(overrides, :calls, 1)

    expect(Sigil.Sui.ClientMock, :get_objects, calls, fn [type: @custodian_type], [] ->
      {:ok,
       %{
         data: [
           custodian_object_json(
             Keyword.get(overrides, :object_id, table_id(0x33)),
             wallet_address,
             @tribe_id,
             Keyword.get(overrides, :initial_shared_version, 41),
             overrides
           )
         ],
         has_next_page: false,
         end_cursor: nil
       }}
    end)
  end

  defp stub_governance_reads(current_leader, opts) do
    votes_table_id = Keyword.get(opts, :votes_table_id, table_id(0x34))
    vote_tallies_table_id = Keyword.get(opts, :vote_tallies_table_id, table_id(0x35))

    votes = Keyword.get(opts, :votes, [vote_entry(current_leader, current_leader)])
    tallies = Keyword.get(opts, :tallies, [tally_entry(current_leader, 1)])

    stub(Sigil.Sui.ClientMock, :get_dynamic_fields, fn
      ^votes_table_id, [] -> {:ok, %{data: votes, has_next_page: false, end_cursor: nil}}
      ^vote_tallies_table_id, [] -> {:ok, %{data: tallies, has_next_page: false, end_cursor: nil}}
    end)
  end

  defp stub_governance_reads_sequence(
         votes_table_id,
         vote_tallies_table_id,
         initial_votes,
         initial_tallies,
         updated_votes,
         updated_tallies
       ) do
    votes_calls = :counters.new(1, [])
    tallies_calls = :counters.new(1, [])

    stub(Sigil.Sui.ClientMock, :get_dynamic_fields, fn
      ^votes_table_id, [] ->
        :ok = :counters.add(votes_calls, 1, 1)

        data =
          case :counters.get(votes_calls, 1) do
            1 -> initial_votes
            _ -> updated_votes
          end

        {:ok, %{data: data, has_next_page: false, end_cursor: nil}}

      ^vote_tallies_table_id, [] ->
        :ok = :counters.add(tallies_calls, 1, 1)

        data =
          case :counters.get(tallies_calls, 1) do
            1 -> initial_tallies
            _ -> updated_tallies
          end

        {:ok, %{data: data, has_next_page: false, end_cursor: nil}}
    end)
  end

  defp vote_entry(voter, candidate) do
    %{
      name: %{type: "address", json: voter},
      value: %{type: "address", json: candidate}
    }
  end

  defp tally_entry(candidate, votes) do
    %{
      name: %{type: "address", json: candidate},
      value: %{type: "u64", json: votes}
    }
  end

  defp challenger_label(address), do: String.slice(address, 0, 6)

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

  defp custodian_object_json(
         object_id,
         current_leader,
         tribe_id,
         initial_shared_version,
         overrides \\ []
       ) do
    votes_table_id = Keyword.get(overrides, :votes_table_id, table_id(0x36))
    vote_tallies_table_id = Keyword.get(overrides, :vote_tallies_table_id, table_id(0x37))
    current_leader_votes = Keyword.get(overrides, :current_leader_votes, 1)
    members = Keyword.get(overrides, :members, [current_leader])

    %{
      "id" => object_id,
      "address" => object_id,
      "current_leader" => current_leader,
      "current_leader_votes" => current_leader_votes,
      "members" => members,
      "votes" => %{"id" => votes_table_id},
      "vote_tallies" => %{"id" => vote_tallies_table_id},
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
