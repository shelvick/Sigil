defmodule SigilWeb.IntelMarketLiveTest do
  @moduledoc """
  Verifies marketplace LiveView behavior.
  """

  use Sigil.ConnCase, async: true

  import Hammox

  alias Phoenix.LiveViewTest
  alias Sigil.Accounts.Account
  alias Sigil.Cache
  alias Sigil.Intel.IntelListing
  alias Sigil.Intel.IntelReport
  alias Sigil.Repo
  alias Sigil.StaticData
  alias Sigil.StaticDataTestFixtures, as: StaticDataFixtures
  alias Sigil.Sui.Types.Character
  alias SigilWeb.IntelMarketLive.Components

  @marketplace_type "0x06ce9d6bed77615383575cc7eba4883d32769b30cd5df00561e38434a59611a1::intel_market::IntelMarketplace"
  @listing_type "0x06ce9d6bed77615383575cc7eba4883d32769b30cd5df00561e38434a59611a1::intel_market::IntelListing"
  @tribe_id 314
  @world_package_id "0x1111111111111111111111111111111111111111111111111111111111111111"
  @zklogin_sig Base.encode64(<<0x05, 0::size(320)>>)

  setup :verify_on_exit!

  setup %{sandbox_owner: sandbox_owner} do
    cache_pid =
      start_supervised!(
        {Cache, tables: [:accounts, :characters, :intel, :intel_market, :standings, :nonces]}
      )

    pubsub = unique_pubsub_name()
    start_supervised!({Phoenix.PubSub, name: pubsub})
    :ok = Phoenix.PubSub.subscribe(pubsub, Sigil.IntelMarket.topic())

    static_data =
      start_supervised!(
        {StaticData, test_data: StaticDataFixtures.sample_test_data(), mox_owner: sandbox_owner}
      )

    {:ok,
     cache_tables: Cache.tables(cache_pid),
     pubsub: pubsub,
     static_data: static_data,
     wallet_address: unique_wallet_address()}
  end

  @tag :acceptance
  test "marketplace page loads and displays active listings", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    static_data: static_data,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    nonce = "marketplace-load-nonce"
    seed_nonce(cache_tables, nonce, wallet_address)
    expect_wallet_registration(wallet_address)

    listing =
      insert_listing!(%{
        id: unique_object_id(),
        seller_address: unique_wallet_address(),
        price_mist: 1_250_000_000,
        report_type: 1,
        solar_system_id: 30_000_001,
        description: "Fresh route intel"
      })

    seed_chain_marketplace([listing])

    {:ok, auth_view, initial_html} =
      live(
        init_test_session(conn, %{
          "cache_tables" => cache_tables,
          "pubsub" => pubsub,
          "static_data" => static_data
        }),
        "/"
      )

    assert initial_html =~ "Connect Your Wallet"
    refute initial_html =~ "Fresh route intel"

    auth_view
    |> element("#wallet-connect")
    |> render_hook("wallet_connected", %{"address" => wallet_address, "name" => "Eve Vault"})

    assert_push_event(auth_view, "request_sign", %{"nonce" => nonce, "message" => message})

    conn =
      conn
      |> init_test_session(%{
        "cache_tables" => cache_tables,
        "pubsub" => pubsub,
        "static_data" => static_data
      })
      |> post("/session", signed_auth_params(wallet_address, nonce, message))

    assert redirected_to(conn) == "/"

    assert {:ok, _view, html} = live(recycle(conn), "/marketplace")

    assert html =~ "Fresh route intel"
    assert html =~ "Purchase"
    refute html =~ "Marketplace not yet available"
    refute html =~ "Connect Your Wallet"
    refute html =~ listing.seller_address <> " own listing"
  end

  test "filter by report type shows matching listings only", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    static_data: static_data,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    scout_listing =
      insert_listing!(%{
        id: unique_object_id(),
        seller_address: unique_wallet_address(),
        report_type: 1,
        description: "Scout route intel"
      })

    combat_listing =
      insert_listing!(%{
        id: unique_object_id(),
        seller_address: unique_wallet_address(),
        report_type: 2,
        description: "Combat contact intel"
      })

    seed_chain_marketplace([scout_listing, combat_listing])

    {:ok, view, _html} =
      live(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub, static_data),
        "/marketplace"
      )

    html =
      view
      |> form("#marketplace-filters", %{"filters" => %{"report_type" => "1"}})
      |> render_change()

    assert html =~ scout_listing.description
    refute html =~ combat_listing.description
  end

  test "filter by solar system shows matching listings only", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    static_data: static_data,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    matching_listing =
      insert_listing!(%{
        id: unique_object_id(),
        seller_address: unique_wallet_address(),
        solar_system_id: 30_000_001,
        description: "A 2560 route intel"
      })

    other_listing =
      insert_listing!(%{
        id: unique_object_id(),
        seller_address: unique_wallet_address(),
        solar_system_id: 30_000_002,
        description: "B 31337 route intel"
      })

    seed_chain_marketplace([matching_listing, other_listing])

    {:ok, view, _html} =
      live(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub, static_data),
        "/marketplace"
      )

    html =
      view
      |> form("#marketplace-filters", %{"filters" => %{"solar_system_name" => "A 2560"}})
      |> render_change()

    assert html =~ matching_listing.description
    refute html =~ other_listing.description
  end

  test "filter by price range shows matching listings only", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    static_data: static_data,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    low_price_listing =
      insert_listing!(%{
        id: unique_object_id(),
        seller_address: unique_wallet_address(),
        price_mist: 900_000_000,
        description: "One SUI route intel"
      })

    matching_listing =
      insert_listing!(%{
        id: unique_object_id(),
        seller_address: unique_wallet_address(),
        price_mist: 2_500_000_000,
        description: "Two point five SUI route intel"
      })

    high_price_listing =
      insert_listing!(%{
        id: unique_object_id(),
        seller_address: unique_wallet_address(),
        price_mist: 5_000_000_000,
        description: "Five SUI route intel"
      })

    seed_chain_marketplace([low_price_listing, matching_listing, high_price_listing])

    {:ok, view, _html} =
      live(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub, static_data),
        "/marketplace"
      )

    html =
      view
      |> form("#marketplace-filters", %{
        "filters" => %{"price_min_sui" => "2", "price_max_sui" => "3"}
      })
      |> render_change()

    assert html =~ matching_listing.description
    refute html =~ low_price_listing.description
    refute html =~ high_price_listing.description
  end

  test "sell form lists only seller authored intel reports", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    static_data: static_data,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    own_report =
      insert_location_report!(%{
        label: "My route",
        reported_by: wallet_address,
        reported_by_character_id: hd(account.characters).id
      })

    other_report =
      insert_location_report!(%{
        label: "Corp secret",
        reported_by: unique_wallet_address(),
        reported_by_character_id: "0xother-character"
      })

    seed_chain_marketplace([])

    assert {:ok, _view, html} =
             live(
               authenticated_conn(conn, wallet_address, cache_tables, pubsub, static_data),
               "/marketplace"
             )

    assert html =~ own_report.label
    refute html =~ other_report.label
  end

  test "selecting existing report pre-fills sell form fields", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    static_data: static_data,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    report =
      insert_location_report!(%{
        label: "Prefill route",
        assembly_id: "0xprefill-assembly",
        notes: "Prefilled route notes",
        reported_by: wallet_address,
        reported_by_character_id: hd(account.characters).id
      })

    seed_chain_marketplace([])

    {:ok, view, _html} =
      live(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub, static_data),
        "/marketplace"
      )

    html =
      view
      |> form("#sell-intel-form", %{
        "listing" => %{"entry_mode" => "existing", "report_id" => report.id}
      })
      |> render_change()

    assert html =~ "0xprefill-assembly"
    assert html =~ "Prefilled route notes"
    assert html =~ "30000001"
    refute html =~ "Unknown or ambiguous solar system"
  end

  test "manual-entry sell flow creates intel payload", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    static_data: static_data,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    seed_chain_marketplace([])

    {:ok, view, _html} =
      live(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub, static_data),
        "/marketplace"
      )

    view
    |> form("#sell-intel-form", %{
      "listing" => %{
        "entry_mode" => "manual",
        "report_type" => "1",
        "solar_system_name" => "A 2560",
        "assembly_id" => "0xmanual-assembly",
        "notes" => "Manual fuel report",
        "price_sui" => "1.25",
        "description" => "Fresh manual listing"
      }
    })
    |> render_submit()

    assert_push_event(view, "generate_proof", %{
      "report_type" => 1,
      "solar_system_id" => 30_000_001,
      "assembly_id" => "0xmanual-assembly",
      "notes" => "Manual fuel report"
    })

    assert Repo.aggregate(IntelReport, :count) == 1
  end

  test "sell flow renders ZkProofGenerator hook mount point", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    static_data: static_data,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    seed_chain_marketplace([])

    assert {:ok, _view, html} =
             live(
               authenticated_conn(conn, wallet_address, cache_tables, pubsub, static_data),
               "/marketplace"
             )

    assert html =~ "phx-hook=\"ZkProofGenerator\""
  end

  test "browser UAT sell flow creates visible listing", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    static_data: static_data,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    nonce = "marketplace-sell-nonce"
    seed_nonce(cache_tables, nonce, wallet_address)
    expect_wallet_registration(wallet_address)
    seed_chain_marketplace([])
    :ok = Phoenix.PubSub.subscribe(pubsub, Sigil.IntelMarket.topic())

    created_listing_id = unique_object_id()

    expect(Sigil.Sui.ClientMock, :execute_transaction, fn _tx_bytes, [_signature], [] ->
      {:ok,
       %{
         "bcs" => "effects-bcs-data",
         "status" => "SUCCESS",
         "transaction" => %{"digest" => "marketplace-create-digest"},
         "objectChanges" => [
           %{
             "type" => "created",
             "objectType" => @listing_type,
             "objectId" => created_listing_id,
             "version" => "7"
           }
         ]
       }}
    end)

    {:ok, auth_view, initial_html} =
      live(
        init_test_session(conn, %{
          "cache_tables" => cache_tables,
          "pubsub" => pubsub,
          "static_data" => static_data
        }),
        "/"
      )

    assert initial_html =~ "Connect Your Wallet"
    refute initial_html =~ "Proof-backed market intel"

    auth_view
    |> element("#wallet-connect")
    |> render_hook("wallet_connected", %{"address" => wallet_address, "name" => "Eve Vault"})

    assert_push_event(auth_view, "request_sign", %{"nonce" => nonce, "message" => message})

    conn =
      conn
      |> init_test_session(%{
        "cache_tables" => cache_tables,
        "pubsub" => pubsub,
        "static_data" => static_data
      })
      |> post("/session", signed_auth_params(wallet_address, nonce, message))

    assert redirected_to(conn) == "/"

    {:ok, view, _html} = live(recycle(conn), "/marketplace")

    view
    |> form("#sell-intel-form", %{
      "listing" => %{
        "entry_mode" => "manual",
        "report_type" => "1",
        "solar_system_name" => "A 2560",
        "assembly_id" => "0xbrowser-assembly",
        "notes" => "Proof-backed listing",
        "price_sui" => "2.50",
        "description" => "Proof-backed market intel"
      }
    })
    |> render_submit()

    assert_push_event(view, "generate_proof", %{"assembly_id" => "0xbrowser-assembly"})

    render_hook(view, "proof_generated", %{
      "proof_points" => Base.encode64(:binary.copy(<<1>>, 256)),
      "public_inputs" => Base.encode64(:binary.copy(<<2>>, 32)),
      "commitment" =>
        "15539519021302514881265614457483181390288297695578326223934756601408766449787"
    })

    assert_push_event(view, "request_sign_transaction", %{"tx_bytes" => tx_bytes})

    render_hook(view, "transaction_signed", %{
      "bytes" => tx_bytes,
      "signature" => Base.encode64("wallet-signature")
    })

    assert_push_event(view, "report_transaction_effects", %{effects: "effects-bcs-data"})

    html = render(view)
    assert html =~ "Listing created"
    refute html =~ "Proof generation failed"
    refute html =~ "Transaction failed"
  end

  test "purchase flow marks listing sold and shows success state", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    static_data: static_data,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    listing =
      insert_listing!(%{
        id: unique_object_id(),
        seller_address: unique_wallet_address(),
        price_mist: 200_000_000,
        description: "Purchase target intel"
      })

    seed_chain_marketplace([listing])
    :ok = Phoenix.PubSub.subscribe(pubsub, Sigil.IntelMarket.topic())

    expect(Sigil.Sui.ClientMock, :execute_transaction, fn _tx_bytes, [_signature], [] ->
      {:ok,
       %{
         "bcs" => "purchase-effects-bcs",
         "status" => "SUCCESS",
         "transaction" => %{"digest" => "purchase-digest"}
       }}
    end)

    {:ok, view, _html} =
      live(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub, static_data),
        "/marketplace"
      )

    view
    |> element(~s(button[phx-click="purchase_listing"][phx-value-listing_id="#{listing.id}"]))
    |> render_click()

    assert_push_event(view, "request_sign_transaction", %{"tx_bytes" => tx_bytes})

    render_hook(view, "transaction_signed", %{
      "bytes" => tx_bytes,
      "signature" => "wallet-signature"
    })

    assert_push_event(view, "report_transaction_effects", %{effects: "purchase-effects-bcs"})

    html = render(view)
    assert html =~ "Purchase successful"
    assert html =~ "seller must reveal"
    assert html =~ "sold"
    refute html =~ ~s(phx-click="purchase_listing")
  end

  test "cancel listing changes status to cancelled", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    static_data: static_data,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    listing =
      insert_listing!(%{
        id: unique_object_id(),
        seller_address: wallet_address,
        status: :active,
        description: "Cancelable listing"
      })

    seed_chain_marketplace([listing])
    :ok = Phoenix.PubSub.subscribe(pubsub, Sigil.IntelMarket.topic())

    expect(Sigil.Sui.ClientMock, :execute_transaction, fn _tx_bytes, [_signature], [] ->
      {:ok,
       %{
         "bcs" => "cancel-effects-bcs",
         "status" => "SUCCESS",
         "transaction" => %{"digest" => "cancel-digest"}
       }}
    end)

    {:ok, view, _html} =
      live(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub, static_data),
        "/marketplace"
      )

    render_click(view, "cancel_listing", %{"listing_id" => listing.id})

    assert_push_event(view, "request_sign_transaction", %{"tx_bytes" => tx_bytes})

    render_hook(view, "transaction_signed", %{
      "bytes" => tx_bytes,
      "signature" => "wallet-signature"
    })

    assert_push_event(view, "report_transaction_effects", %{effects: "cancel-effects-bcs"})

    html = render(view)

    assert html =~ "Listing cancelled"
    assert Repo.get!(IntelListing, listing.id).status == :cancelled
    refute html =~ ~s(phx-click="cancel_listing" phx-value-listing_id="#{listing.id}")
  end

  test "purchase action rejects self purchase", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    static_data: static_data,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    own_listing =
      insert_listing!(%{
        id: unique_object_id(),
        seller_address: wallet_address,
        price_mist: 100_000_000,
        description: "My own intel"
      })

    seed_chain_marketplace([own_listing])

    {:ok, _view, html} =
      live(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub, static_data),
        "/marketplace"
      )

    refute html =~ ~s(phx-click="purchase_listing" phx-value-listing_id="#{own_listing.id}")
    refute html =~ "cannot purchase your own listing"
    refute html =~ "Approve in your wallet"
  end

  test "proof_error event displays error message", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    static_data: static_data,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    seed_chain_marketplace([])

    {:ok, view, _html} =
      live(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub, static_data),
        "/marketplace"
      )

    html = render_hook(view, "proof_error", %{"reason" => "Failed to load circuit"})

    assert html =~ "Failed to load circuit"
    refute html =~ "Approve in your wallet"
  end

  test "my listings shows user's listings with status badges", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    static_data: static_data,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    active_listing =
      insert_listing!(%{id: unique_object_id(), seller_address: wallet_address, status: :active})

    sold_listing =
      insert_listing!(%{
        id: unique_object_id(),
        seller_address: wallet_address,
        status: :sold,
        buyer_address: unique_wallet_address()
      })

    other_listing =
      insert_listing!(%{id: unique_object_id(), seller_address: unique_wallet_address()})

    seed_chain_marketplace([active_listing, sold_listing, other_listing])

    {:ok, view, _html} =
      live(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub, static_data),
        "/marketplace"
      )

    html = render_click(view, "show_section", %{"section" => "my_listings"})

    assert html =~ active_listing.id
    assert html =~ sold_listing.id
    assert html =~ "active"
    assert html =~ "sold"
    refute html =~ other_listing.id
  end

  test "restricted sell flow creates tribe restricted listing", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    static_data: static_data,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)
    seed_active_custodian(cache_tables)
    seed_chain_marketplace([])

    restricted_listing_id = unique_object_id()

    expect(Sigil.Sui.ClientMock, :execute_transaction, fn _tx_bytes, [_signature], [] ->
      {:ok,
       %{
         "bcs" => "restricted-effects-bcs",
         "status" => "SUCCESS",
         "transaction" => %{"digest" => "restricted-create-digest"},
         "objectChanges" => [
           %{
             "type" => "created",
             "objectType" => @listing_type,
             "objectId" => restricted_listing_id,
             "version" => "11"
           }
         ]
       }}
    end)

    {:ok, view, _html} =
      live(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub, static_data),
        "/marketplace"
      )

    view
    |> form("#sell-intel-form", %{
      "listing" => %{
        "entry_mode" => "manual",
        "report_type" => "1",
        "solar_system_name" => "A 2560",
        "assembly_id" => "0xrestricted-assembly",
        "notes" => "Tribe-only intel",
        "price_sui" => "3.00",
        "description" => "Restricted intel",
        "restricted" => "true"
      }
    })
    |> render_submit()

    assert_push_event(view, "generate_proof", %{"assembly_id" => "0xrestricted-assembly"})

    render_hook(view, "proof_generated", %{
      "proof_points" => Base.encode64(:binary.copy(<<3>>, 256)),
      "public_inputs" => Base.encode64(:binary.copy(<<4>>, 32)),
      "commitment" => "999999999999999999"
    })

    assert_push_event(view, "request_sign_transaction", %{"tx_bytes" => tx_bytes})

    render_hook(view, "transaction_signed", %{
      "bytes" => tx_bytes,
      "signature" => "wallet-signature"
    })

    assert_receive {:listing_created,
                    %IntelListing{id: restricted_id, restricted_to_tribe_id: restricted_tribe_id}}

    assert restricted_tribe_id == @tribe_id
    assert restricted_id == restricted_listing_id

    html = render(view)
    assert html =~ "Listing created"
    assert html =~ "restricted"
    refute html =~ "active custodian"
  end

  test "restricted purchase succeeds for eligible tribe member", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    static_data: static_data,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)
    seed_active_custodian(cache_tables)

    listing =
      insert_listing!(%{
        id: unique_object_id(),
        seller_address: unique_wallet_address(),
        price_mist: 300_000_000,
        restricted_to_tribe_id: @tribe_id,
        description: "Eligible restricted intel"
      })

    seed_chain_marketplace([listing])
    :ok = Phoenix.PubSub.subscribe(pubsub, Sigil.IntelMarket.topic())

    expect(Sigil.Sui.ClientMock, :execute_transaction, fn _tx_bytes, [_signature], [] ->
      {:ok,
       %{
         "bcs" => "restricted-purchase-effects",
         "status" => "SUCCESS",
         "transaction" => %{"digest" => "restricted-purchase-digest"}
       }}
    end)

    {:ok, view, _html} =
      live(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub, static_data),
        "/marketplace"
      )

    view
    |> element(~s(button[phx-click="purchase_listing"][phx-value-listing_id="#{listing.id}"]))
    |> render_click()

    assert_push_event(view, "request_sign_transaction", %{"tx_bytes" => tx_bytes})

    render_hook(view, "transaction_signed", %{
      "bytes" => tx_bytes,
      "signature" => "wallet-signature"
    })

    html = render(view)
    assert html =~ "Purchase successful"
    assert html =~ "sold"
    refute html =~ "restricted listing"
  end

  test "PubSub listing_created adds new listing to browse view", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    static_data: static_data,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    seed_chain_marketplace([])

    {:ok, view, _html} =
      live(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub, static_data),
        "/marketplace"
      )

    listing =
      insert_listing!(%{
        id: unique_object_id(),
        seller_address: unique_wallet_address(),
        description: "Realtime hostile sighting",
        price_mist: 300_000_000
      })

    Phoenix.PubSub.broadcast(pubsub, Sigil.IntelMarket.topic(), {:listing_created, listing})

    html = render(view)
    assert html =~ listing.description
    refute html =~ "No listings available"
  end

  test "unauthenticated user sees wallet connect prompt", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    static_data: static_data
  } do
    seed_chain_marketplace([])

    assert {:ok, _view, html} =
             live(
               init_test_session(conn, %{
                 "cache_tables" => cache_tables,
                 "pubsub" => pubsub,
                 "static_data" => static_data
               }),
               "/marketplace"
             )

    assert html =~ "Connect wallet to use marketplace"
    refute html =~ "My Listings"
    refute html =~ "Proof-backed market intel"
  end

  test "user without tribe sees buy-only marketplace", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    static_data: static_data,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, nil)
    Cache.put(cache_tables.accounts, wallet_address, account)

    listing =
      insert_listing!(%{
        id: unique_object_id(),
        seller_address: unique_wallet_address(),
        description: "Public route intel"
      })

    seed_chain_marketplace([listing])

    assert {:ok, _view, html} =
             live(
               authenticated_conn(conn, wallet_address, cache_tables, pubsub, static_data),
               "/marketplace"
             )

    assert html =~ "Public route intel"
    assert html =~ "creating listings requires a tribe-backed intel record"
    refute html =~ "Select existing report"
  end

  test "restricted purchase rejects ineligible buyer", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    static_data: static_data,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    listing =
      insert_listing!(%{
        id: unique_object_id(),
        seller_address: unique_wallet_address(),
        restricted_to_tribe_id: 999,
        description: "Restricted intel"
      })

    seed_chain_marketplace([listing])

    {:ok, _view, html} =
      live(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub, static_data),
        "/marketplace"
      )

    assert html =~ ~s(aria-disabled="true")
    assert html =~ "Restricted to another tribe"
    refute html =~ ~s(phx-click="purchase_listing" phx-value-listing_id="#{listing.id}")
  end

  test "restricted listing displays tribe badge", %{
    static_data: static_data
  } do
    html =
      LiveViewTest.render_component(&Components.listing_card/1,
        listing: %IntelListing{
          id: unique_object_id(),
          seller_address: unique_wallet_address(),
          commitment_hash: "1234567890",
          client_nonce: 42,
          price_mist: 150_000_000,
          report_type: 1,
          solar_system_id: 30_000_001,
          description: "Restricted component intel",
          status: :active,
          buyer_address: nil,
          restricted_to_tribe_id: @tribe_id,
          intel_report_id: nil,
          on_chain_digest: nil
        },
        sender: unique_wallet_address(),
        tribe_id: @tribe_id,
        static_data: static_data
      )

    assert html =~ "restricted"
    assert html =~ ~s(phx-click="purchase_listing")
    refute html =~ ~s(aria-disabled="true")
  end

  test "price displays in SUI with proper formatting", %{static_data: static_data} do
    html =
      LiveViewTest.render_component(&Components.listing_card/1,
        listing: %IntelListing{
          id: unique_object_id(),
          seller_address: unique_wallet_address(),
          commitment_hash: "1234567890",
          client_nonce: 7,
          price_mist: 1_000_000_000,
          report_type: 1,
          solar_system_id: 30_000_001,
          description: "One SUI component intel",
          status: :active,
          buyer_address: nil,
          restricted_to_tribe_id: nil,
          intel_report_id: nil,
          on_chain_digest: nil
        },
        sender: unique_wallet_address(),
        tribe_id: @tribe_id,
        static_data: static_data
      )

    assert html =~ "1 SUI"
    refute html =~ "1000000000"
  end

  test "restricted sell flow requires active custodian", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    static_data: static_data,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    seed_chain_marketplace([])

    {:ok, view, _html} =
      live(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub, static_data),
        "/marketplace"
      )

    html =
      view
      |> form("#sell-intel-form", %{
        "listing" => %{
          "entry_mode" => "manual",
          "report_type" => "1",
          "solar_system_name" => "A 2560",
          "assembly_id" => "0xrestricted-assembly",
          "notes" => "Tribe-only intel",
          "price_sui" => "3.00",
          "description" => "Restricted intel",
          "restricted" => "true"
        }
      })
      |> render_submit()

    assert html =~ "active custodian"
    refute html =~ "Approve in your wallet"
  end

  defp authenticated_conn(conn, wallet_address, cache_tables, pubsub, static_data) do
    init_test_session(conn, %{
      "wallet_address" => wallet_address,
      "cache_tables" => cache_tables,
      "pubsub" => pubsub,
      "static_data" => static_data
    })
  end

  defp signed_auth_params(wallet_address, nonce, message) do
    %{
      "wallet_address" => wallet_address,
      "bytes" => Base.encode64(message),
      "signature" => @zklogin_sig,
      "nonce" => nonce
    }
  end

  defp seed_nonce(cache_tables, nonce, wallet_address, opts \\ []) do
    Cache.put(cache_tables.nonces, nonce, %{
      address: wallet_address,
      created_at: Keyword.get(opts, :created_at, System.monotonic_time(:millisecond)),
      expected_message:
        Keyword.get_lazy(opts, :expected_message, fn -> challenge_message(nonce) end),
      item_id: Keyword.get(opts, :item_id),
      tenant: Keyword.get(opts, :tenant)
    })
  end

  defp challenge_message(nonce), do: "Sign in to Sigil: #{nonce}"

  defp expect_wallet_registration(wallet_address) do
    expect(Sigil.Sui.ClientMock, :verify_zklogin_signature, fn _bytes,
                                                               @zklogin_sig,
                                                               "PERSONAL_MESSAGE",
                                                               ^wallet_address,
                                                               [] ->
      {:ok, %{"verifyZkLoginSignature" => %{"success" => true}}}
    end)

    character = character_json(wallet_address, @tribe_id)
    character_type = character_type()

    expect(Sigil.Sui.ClientMock, :get_objects, fn filters, [] ->
      case Keyword.get(filters, :type) do
        ^character_type ->
          {:ok, %{data: [character], has_next_page: false, end_cursor: nil}}

        @marketplace_type ->
          {:ok,
           %{
             data: [
               %{
                 "id" => unique_object_id(),
                 "listing_count" => "0",
                 "shared" => %{"initialSharedVersion" => "7"},
                 "initialSharedVersion" => "7"
               }
             ],
             has_next_page: false,
             end_cursor: nil
           }}
      end
    end)
  end

  defp character_type do
    "#{@world_package_id}::character::Character"
  end

  defp seed_active_custodian(cache_tables) do
    Cache.put(cache_tables.standings, {:active_custodian, @tribe_id}, %{
      object_id: unique_object_id(),
      object_id_bytes: :binary.copy(<<0x33>>, 32),
      initial_shared_version: 41,
      current_leader: unique_wallet_address(),
      tribe_id: @tribe_id
    })
  end

  defp account_fixture(wallet_address, nil) do
    %Account{address: wallet_address, characters: [], tribe_id: nil}
  end

  defp account_fixture(wallet_address, tribe_id) do
    %Account{
      address: wallet_address,
      characters: [Character.from_json(character_json(wallet_address, tribe_id))],
      tribe_id: tribe_id
    }
  end

  defp insert_listing!(attrs) do
    %IntelListing{}
    |> IntelListing.changeset(valid_listing_attrs(attrs))
    |> Repo.insert!()
  end

  defp insert_location_report!(attrs) do
    %IntelReport{}
    |> IntelReport.location_changeset(
      Map.merge(
        %{
          tribe_id: @tribe_id,
          assembly_id: unique_object_id(),
          solar_system_id: 30_000_001,
          label: "Intel report #{System.unique_integer([:positive])}",
          notes: "Intel notes #{System.unique_integer([:positive])}",
          reported_by: unique_wallet_address(),
          reported_by_name: "Scout Prime",
          reported_by_character_id: uid("0xintel-character")
        },
        attrs
      )
    )
    |> Repo.insert!()
  end

  defp seed_chain_marketplace(listings) do
    stub(Sigil.Sui.ClientMock, :get_objects, fn filters, [] ->
      case Keyword.get(filters, :type) do
        @marketplace_type ->
          {:ok,
           %{
             data: [
               %{
                 "id" => unique_object_id(),
                 "listing_count" => Integer.to_string(length(listings)),
                 "shared" => %{"initialSharedVersion" => "7"},
                 "initialSharedVersion" => "7"
               }
             ],
             has_next_page: false,
             end_cursor: nil
           }}

        @listing_type ->
          {:ok,
           %{
             data: Enum.map(listings, &listing_object_json/1),
             has_next_page: false,
             end_cursor: nil
           }}
      end
    end)
  end

  defp listing_object_json(%IntelListing{} = listing) do
    %{
      "id" => listing.id,
      "seller" => listing.seller_address,
      "commitment" => listing.commitment_hash,
      "client_nonce" => Integer.to_string(listing.client_nonce),
      "price" => Integer.to_string(listing.price_mist),
      "report_type" => listing.report_type,
      "solar_system_id" => listing.solar_system_id,
      "description" => listing.description,
      "status" => status_code(listing.status),
      "buyer" => listing.buyer_address,
      "restricted_to_tribe_id" => listing.restricted_to_tribe_id,
      "shared" => %{"initialSharedVersion" => "13"},
      "initialSharedVersion" => "13"
    }
  end

  defp valid_listing_attrs(overrides) do
    Map.merge(
      %{
        id: unique_object_id(),
        seller_address: unique_wallet_address(),
        commitment_hash: "1234567890",
        client_nonce: System.unique_integer([:positive]),
        price_mist: 150_000_000,
        report_type: 1,
        solar_system_id: 30_000_001,
        description: "Encrypted route intel",
        status: :active,
        buyer_address: nil,
        restricted_to_tribe_id: nil,
        intel_report_id: nil,
        on_chain_digest: nil
      },
      overrides
    )
  end

  defp character_json(wallet_address, tribe_id) do
    %{
      "id" => uid("0xmarket-character-#{System.unique_integer([:positive])}"),
      "key" => %{"item_id" => "1", "tenant" => "0xmarket-tenant"},
      "tribe_id" => if(tribe_id, do: Integer.to_string(tribe_id), else: nil),
      "character_address" => wallet_address,
      "metadata" => %{
        "assembly_id" => "0xmarket-character-metadata",
        "name" => "Captain Frontier",
        "description" => "Marketplace pilot",
        "url" => "https://example.test/characters/frontier"
      },
      "owner_cap_id" => uid("0xmarket-character-owner")
    }
  end

  defp status_code(:active), do: "0"
  defp status_code(:sold), do: "1"
  defp status_code(:cancelled), do: "2"

  defp unique_pubsub_name do
    :"intel_market_live_pubsub_#{System.unique_integer([:positive])}"
  end

  defp unique_wallet_address do
    integer = System.unique_integer([:positive])
    suffix = integer |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(64, "0")

    "0x" <> suffix
  end

  defp unique_object_id do
    unique_wallet_address()
  end

  defp uid(id), do: %{"id" => id}
end
