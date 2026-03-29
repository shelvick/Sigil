defmodule SigilWeb.IntelMarketLiveTest do
  @moduledoc """
  Verifies marketplace LiveView behavior.
  """

  use Sigil.ConnCase, async: true

  import Hammox

  @compile {:no_warn_undefined, Sigil.Pseudonym}
  @compile {:no_warn_undefined, Sigil.Pseudonyms}

  alias Phoenix.LiveViewTest
  alias Sigil.Accounts.Account
  alias Sigil.Cache
  alias Sigil.Intel.IntelListing
  alias Sigil.Intel.IntelReport
  alias Sigil.{Pseudonym, Repo}
  alias Sigil.StaticData
  alias Sigil.StaticDataTestFixtures, as: StaticDataFixtures
  alias Sigil.Sui.Types.Character
  alias SigilWeb.IntelMarketLive.Components

  @sigil_package_id "0x06ce9d6bed77615383575cc7eba4883d32769b30cd5df00561e38434a59611a1"
  @marketplace_type "#{@sigil_package_id}::intel_market::IntelMarketplace"
  @listing_type "#{@sigil_package_id}::intel_market::IntelListing"
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
      mount_live_with_cleanup(
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

    assert {:ok, _view, html} = mount_live_with_cleanup(recycle(conn), "/marketplace")

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
      mount_live_with_cleanup(
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

  test "filter by solar system query shows matching listings only", %{
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
      mount_live_with_cleanup(
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
        price_mist: 6_000_000_000,
        description: "Six SUI route intel"
      })

    seed_chain_marketplace([low_price_listing, matching_listing, high_price_listing])

    {:ok, view, _html} =
      mount_live_with_cleanup(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub, static_data),
        "/marketplace"
      )

    html =
      view
      |> form("#marketplace-filters", %{
        "filters" => %{"price_min_sui" => "1", "price_max_sui" => "5"}
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
             mount_live_with_cleanup(
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
      mount_live_with_cleanup(
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

  test "manual-entry sell flow enters encrypting state", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    static_data: static_data,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    insert_pseudonym!(
      account_address: wallet_address,
      pseudonym_address: unique_wallet_address(),
      encrypted_private_key: <<1, 2, 3, 4>>
    )

    seed_chain_marketplace([])

    {:ok, view, _html} =
      mount_live_with_cleanup(
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
          "assembly_id" => "0xmanual-assembly",
          "notes" => "Manual fuel report",
          "price_sui" => "1.25",
          "description" => "Fresh manual listing"
        }
      })
      |> render_submit()

    assert_push_event(view, "encrypt_and_upload", %{
      "intel_data" => %{
        "report_type" => 1,
        "solar_system_id" => 30_000_001,
        "assembly_id" => "0xmanual-assembly",
        "notes" => "Manual fuel report",
        "label" => "Fresh manual listing"
      },
      "seal_id" => seal_id,
      "config" => %{
        "seal_package_id" => @sigil_package_id,
        "walrus_publisher_url" => "https://publisher.walrus-testnet.walrus.space",
        "walrus_aggregator_url" => "https://aggregator.walrus-testnet.walrus.space",
        "walrus_epochs" => 15,
        "sui_rpc_url" => "https://fullnode.testnet.sui.io:443"
      },
      "report_type" => 1,
      "solar_system_id" => 30_000_001,
      "assembly_id" => "0xmanual-assembly",
      "notes" => "Manual fuel report"
    })

    assert seal_id =~ ~r/^0x[0-9a-f]{64}$/

    assert html =~ "encrypting"
    refute html =~ "Unknown or ambiguous solar system"
    assert Repo.aggregate(IntelReport, :count) == 1
  end

  test "sell flow renders SealEncrypt and PseudonymKey hook mount points", %{
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
             mount_live_with_cleanup(
               authenticated_conn(conn, wallet_address, cache_tables, pubsub, static_data),
               "/marketplace"
             )

    assert html =~ "phx-hook=\"SealEncrypt\""
    assert html =~ "phx-hook=\"PseudonymKey\""
    assert html =~ "Create Pseudonym"
    refute html =~ "Failed to create pseudonym"
  end

  @tag :acceptance
  test "user creates pseudonym and sees it in marketplace", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    static_data: static_data,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    seed_chain_marketplace([])

    {:ok, view, initial_html} =
      mount_live_with_cleanup(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub, static_data),
        "/marketplace"
      )

    assert initial_html =~ "Create Pseudonym"
    refute initial_html =~ "Active pseudonym"

    assert_push_event(view, "load_pseudonyms", %{
      "encrypted_keys" => initial_encrypted_keys,
      "active_address" => initial_active_address
    })

    assert initial_encrypted_keys == []
    assert initial_active_address == nil

    view
    |> element("button[phx-click=\"create_pseudonym\"]")
    |> render_click()

    assert_push_event(view, "create_pseudonym", %{})

    pseudonym_address = unique_wallet_address()
    encrypted_private_key = Base.encode64(<<9, 8, 7, 6>>)

    created_html =
      render_hook(view, "pseudonym_created", %{
        "pseudonym_address" => pseudonym_address,
        "encrypted_private_key" => encrypted_private_key
      })

    pseudonyms = apply(Sigil.Pseudonyms, :list_pseudonyms, [wallet_address])

    assert Enum.map(pseudonyms, & &1.pseudonym_address) == [pseudonym_address]
    assert created_html =~ pseudonym_address
    refute created_html =~ "Create a pseudonymous identity to sell intel"
    refute created_html =~ "Failed to create pseudonym"

    assert_push_event(view, "load_pseudonyms", %{
      "encrypted_keys" => encrypted_keys,
      "active_address" => active_address
    })

    assert active_address == pseudonym_address
    assert Enum.map(encrypted_keys, & &1["address"]) == [pseudonym_address]

    loaded_html =
      render_hook(view, "pseudonyms_loaded", %{
        "addresses" => Enum.map(encrypted_keys, & &1["address"]),
        "active_address" => active_address
      })

    assert loaded_html =~ pseudonym_address
    refute loaded_html =~ "Failed to load pseudonyms"
  end

  @tag :acceptance
  test "user can create an additional pseudonym while under the five identity cap", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    static_data: static_data,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    existing_pseudonym =
      insert_pseudonym!(
        account_address: wallet_address,
        pseudonym_address: unique_wallet_address(),
        encrypted_private_key: <<1, 2, 3, 4>>
      )

    seed_chain_marketplace([])

    {:ok, view, initial_html} =
      mount_live_with_cleanup(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub, static_data),
        "/marketplace"
      )

    assert initial_html =~ existing_pseudonym.pseudonym_address
    assert initial_html =~ "Create Pseudonym"

    view
    |> element("button[phx-click=\"create_pseudonym\"]")
    |> render_click()

    assert_push_event(view, "create_pseudonym", %{})

    new_pseudonym_address = unique_wallet_address()

    created_html =
      render_hook(view, "pseudonym_created", %{
        "pseudonym_address" => new_pseudonym_address,
        "encrypted_private_key" => Base.encode64(<<5, 6, 7, 8>>)
      })

    pseudonyms = apply(Sigil.Pseudonyms, :list_pseudonyms, [wallet_address])

    assert Enum.map(pseudonyms, & &1.pseudonym_address) == [
             existing_pseudonym.pseudonym_address,
             new_pseudonym_address
           ]

    assert created_html =~ existing_pseudonym.pseudonym_address
    assert created_html =~ new_pseudonym_address
    assert created_html =~ "Create Pseudonym"
    refute created_html =~ "Failed to create pseudonym"
  end

  @tag :acceptance
  test "failed pseudonym reload clears the active pseudonym and surfaces a load error", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    static_data: static_data,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    pseudonym =
      insert_pseudonym!(
        account_address: wallet_address,
        pseudonym_address: unique_wallet_address(),
        encrypted_private_key: <<1, 2, 3, 4>>
      )

    seed_chain_marketplace([])

    {:ok, view, _initial_html} =
      mount_live_with_cleanup(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub, static_data),
        "/marketplace"
      )

    assert_push_event(view, "load_pseudonyms", %{
      "encrypted_keys" => encrypted_keys,
      "active_address" => active_address
    })

    loaded_html =
      render_hook(view, "pseudonyms_loaded", %{
        "addresses" => Enum.map(encrypted_keys, & &1["address"]),
        "active_address" => active_address
      })

    assert active_address == pseudonym.pseudonym_address
    assert loaded_html =~ pseudonym.pseudonym_address

    error_html =
      render_hook(view, "pseudonym_error", %{
        "phase" => "load",
        "reason" => "decrypt_failed"
      })

    assert error_html =~ "Failed to load pseudonyms"
    refute error_html =~ "Active pseudonym"
  end

  @tag :acceptance
  test "switching pseudonym updates active identity in marketplace", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    static_data: static_data,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    first_pseudonym =
      insert_pseudonym!(
        account_address: wallet_address,
        pseudonym_address: unique_wallet_address(),
        encrypted_private_key: <<1, 2, 3, 4>>
      )

    second_pseudonym =
      insert_pseudonym!(
        account_address: wallet_address,
        pseudonym_address: unique_wallet_address(),
        encrypted_private_key: <<5, 6, 7, 8>>
      )

    seed_chain_marketplace([])

    {:ok, view, initial_html} =
      mount_live_with_cleanup(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub, static_data),
        "/marketplace"
      )

    assert initial_html =~ first_pseudonym.pseudonym_address
    assert initial_html =~ second_pseudonym.pseudonym_address
    assert initial_html =~ "Create Pseudonym"

    assert_push_event(view, "load_pseudonyms", %{
      "encrypted_keys" => encrypted_keys,
      "active_address" => active_address
    })

    assert active_address == first_pseudonym.pseudonym_address

    assert Enum.map(encrypted_keys, & &1["address"]) == [
             first_pseudonym.pseudonym_address,
             second_pseudonym.pseudonym_address
           ]

    loaded_html =
      render_hook(view, "pseudonyms_loaded", %{
        "addresses" => Enum.map(encrypted_keys, & &1["address"]),
        "active_address" => active_address
      })

    assert loaded_html =~ first_pseudonym.pseudonym_address
    refute loaded_html =~ "Failed to load pseudonyms"

    view
    |> form("#pseudonym-switcher", %{
      "pseudonym" => %{"active_address" => second_pseudonym.pseudonym_address}
    })
    |> render_change()

    second_address = second_pseudonym.pseudonym_address

    assert_push_event(view, "activate_pseudonym", %{
      "pseudonym_address" => ^second_address
    })

    switched_html =
      render_hook(view, "pseudonym_activated", %{
        "pseudonym_address" => second_address
      })

    assert switched_html =~ second_pseudonym.pseudonym_address
    refute switched_html =~ "Failed to switch pseudonym"
  end

  @tag :acceptance
  test "marketplace requires active pseudonym before sell submission", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    static_data: static_data,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    seed_chain_marketplace([])

    {:ok, view, html} =
      mount_live_with_cleanup(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub, static_data),
        "/marketplace"
      )

    assert html =~ "Create Pseudonym"
    refute html =~ "Active pseudonym"
    assert html =~ "Create and activate a pseudonym before publishing a listing."
    assert html =~ ~s(aria-disabled="true")

    blocked_html =
      view
      |> form("#sell-intel-form", %{
        "listing" => %{
          "entry_mode" => "manual",
          "report_type" => "1",
          "solar_system_name" => "A 2560",
          "assembly_id" => "0xno-pseudonym",
          "notes" => "Blocked listing",
          "price_sui" => "1.25",
          "description" => "Should not publish"
        }
      })
      |> render_submit()

    assert blocked_html =~ "Create and activate a pseudonym before listing intel"
    refute blocked_html =~ "encrypt_and_upload"
  end

  @tag :acceptance
  test "seller listing flow requests pseudonym transaction signature", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    static_data: static_data,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    pseudonym =
      insert_pseudonym!(
        account_address: wallet_address,
        pseudonym_address: unique_wallet_address(),
        encrypted_private_key: <<1, 2, 3, 4>>
      )

    seed_chain_marketplace([])

    expect(Sigil.Sui.ClientMock, :get_coins, fn relay_owner, client_opts ->
      assert is_binary(relay_owner)
      assert is_list(client_opts)

      {:ok,
       [
         %{
           object_id: :binary.copy(<<0x11>>, 32),
           version: 7,
           digest: :binary.copy(<<0x21>>, 32),
           balance: 12_000_000
         }
       ]}
    end)

    {:ok, view, initial_html} =
      mount_live_with_cleanup(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub, static_data),
        "/marketplace"
      )

    assert initial_html =~ pseudonym.pseudonym_address
    refute initial_html =~ "Create a pseudonymous identity to sell intel"

    view
    |> form("#sell-intel-form", %{
      "listing" => %{
        "entry_mode" => "manual",
        "report_type" => "1",
        "solar_system_name" => "A 2560",
        "assembly_id" => "0xpseudonym-assembly",
        "notes" => "Pseudonymous listing",
        "price_sui" => "1.75",
        "description" => "Pseudonym market listing"
      }
    })
    |> render_submit()

    assert_push_event(view, "encrypt_and_upload", %{"seal_id" => seal_id})
    assert seal_id =~ ~r/^0x[0-9a-f]{64}$/

    render_hook(view, "seal_upload_complete", %{
      "seal_id" => seal_id,
      "blob_id" => "walrus-pseudonym-blob"
    })

    assert_push_event(view, "sign_pseudonym_tx", %{
      "pseudonym_address" => pseudonym_address,
      "tx_bytes" => tx_bytes
    })

    assert pseudonym_address == pseudonym.pseudonym_address
    assert is_binary(tx_bytes)
  end

  test "decrypted purchased intel renders buyer feedback controls", %{
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
        buyer_address: wallet_address,
        status: :sold,
        seal_id: seal_id_hex(0xD5),
        encrypted_blob_id: "walrus-feedback-blob",
        description: "Feedback target intel"
      })

    seed_chain_marketplace([listing])
    reputation_registry_id = unique_object_id()

    expect(Sigil.Sui.ClientMock, :get_object, 2, fn ^reputation_registry_id, [] ->
      {:ok,
       %{
         "scores" => [
           %{
             "key" => listing.seller_address,
             "value" => %{"positive" => 0, "negative" => 0, "reviewed_listings" => []}
           }
         ]
       }}
    end)

    {:ok, view, _html} =
      mount_live_with_cleanup(
        init_test_session(conn, %{
          "wallet_address" => wallet_address,
          "cache_tables" => cache_tables,
          "pubsub" => pubsub,
          "static_data" => static_data,
          "walrus_client" => Sigil.TestSupport.BlobAvailableClient,
          "reputation_registry_id" => reputation_registry_id
        }),
        "/marketplace"
      )

    render_click(view, "show_section", %{"section" => "my_listings"})
    render_click(view, "decrypt_listing", %{"listing_id" => listing.id})

    render_hook(view, "seal_decrypt_complete", %{
      "data" =>
        Jason.encode!(%{"notes" => "Recovered feedback intel", "assembly_id" => "0xassembly"})
    })

    html = render(view)

    assert html =~ "Recovered feedback intel"
    assert html =~ ~s(phx-click="confirm_quality")
    assert html =~ ~s(phx-click="report_bad_quality")
    refute html =~ "Feedback already submitted"
  end

  test "listing card shows reputation summary when provided", %{static_data: static_data} do
    seller_address = unique_wallet_address()

    html =
      LiveViewTest.render_component(&Components.listing_card/1,
        listing: %IntelListing{
          id: unique_object_id(),
          seller_address: seller_address,
          seal_id: seal_id_hex(0xD6),
          encrypted_blob_id: "walrus-reputation-blob",
          client_nonce: 15,
          price_mist: 200_000_000,
          report_type: 1,
          solar_system_id: 30_000_001,
          description: "Reputation listing",
          status: :active,
          buyer_address: nil,
          restricted_to_tribe_id: nil,
          intel_report_id: nil,
          on_chain_digest: nil
        },
        sender: unique_wallet_address(),
        active_pseudonym: nil,
        tribe_id: @tribe_id,
        static_data: static_data,
        reputation: %{positive: 12, negative: 2}
      )

    assert html =~ "+12 / -2 (86%)"
    refute html =~ "No reputation data"

    hidden_html =
      LiveViewTest.render_component(&Components.listing_card/1,
        listing: %IntelListing{
          id: unique_object_id(),
          seller_address: seller_address,
          seal_id: seal_id_hex(0xD7),
          encrypted_blob_id: "walrus-hidden-seller-blob",
          client_nonce: 16,
          price_mist: 250_000_000,
          report_type: 1,
          solar_system_id: 30_000_001,
          description: "Other user view",
          status: :sold,
          buyer_address: unique_wallet_address(),
          restricted_to_tribe_id: nil,
          intel_report_id: nil,
          on_chain_digest: nil
        },
        sender: unique_wallet_address(),
        active_pseudonym: nil,
        tribe_id: @tribe_id,
        static_data: static_data,
        reputation: %{positive: 12, negative: 2}
      )

    pseudonym_decrypt_html =
      LiveViewTest.render_component(&Components.listing_card/1,
        listing: %IntelListing{
          id: unique_object_id(),
          seller_address: seller_address,
          seal_id: seal_id_hex(0xDA),
          encrypted_blob_id: "walrus-pseudonym-visible-blob",
          client_nonce: 17,
          price_mist: 300_000_000,
          report_type: 1,
          solar_system_id: 30_000_001,
          description: "Pseudonym seller decrypt",
          status: :sold,
          buyer_address: unique_wallet_address(),
          restricted_to_tribe_id: nil,
          intel_report_id: nil,
          on_chain_digest: nil
        },
        sender: unique_wallet_address(),
        active_pseudonym: seller_address,
        tribe_id: @tribe_id,
        static_data: static_data,
        reputation: %{positive: 12, negative: 2}
      )

    refute hidden_html =~ "Decrypt Intel"
    assert pseudonym_decrypt_html =~ "Decrypt Intel"
  end

  test "feedback submission locks controls and refreshes reputation", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    static_data: static_data,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    seller_address = unique_wallet_address()

    sold_listing =
      insert_listing!(%{
        id: unique_object_id(),
        seller_address: seller_address,
        buyer_address: wallet_address,
        status: :sold,
        seal_id: seal_id_hex(0xD8),
        encrypted_blob_id: "walrus-feedback-lock-blob",
        description: "Feedback lock target"
      })

    active_listing =
      insert_listing!(%{
        id: unique_object_id(),
        seller_address: seller_address,
        status: :active,
        seal_id: seal_id_hex(0xD9),
        encrypted_blob_id: "walrus-reputation-refresh-blob",
        description: "Reputation refresh target"
      })

    seed_chain_marketplace([sold_listing, active_listing])

    reputation_registry_id = unique_object_id()

    {:ok, reputation_state} = Agent.start_link(fn -> 9 end)

    on_exit(fn ->
      if Process.alive?(reputation_state) do
        try do
          Agent.stop(reputation_state, :normal, :infinity)
        catch
          :exit, _ -> :ok
        end
      end
    end)

    stub(Sigil.Sui.ClientMock, :get_object, fn ^reputation_registry_id, [] ->
      positive = Agent.get(reputation_state, & &1)

      {:ok,
       %{
         "scores" => [
           %{
             "key" => seller_address,
             "value" => %{"positive" => positive, "negative" => 1, "reviewed_listings" => []}
           }
         ]
       }}
    end)

    expect(Sigil.Sui.ClientMock, :get_object_with_ref, fn ^reputation_registry_id, [] ->
      {:ok,
       %{
         json: %{"id" => reputation_registry_id},
         ref: {:binary.copy(<<0x99>>, 32), 7, :binary.copy(<<0x55>>, 32)}
       }}
    end)

    expect(Sigil.Sui.ClientMock, :execute_transaction, fn _tx_bytes, [_signature], [] ->
      Agent.update(reputation_state, fn _previous -> 10 end)

      {:ok,
       %{
         "bcs" => "feedback-effects-bcs",
         "status" => "SUCCESS",
         "transaction" => %{"digest" => "feedback-digest"}
       }}
    end)

    {:ok, view, _html} =
      mount_live_with_cleanup(
        init_test_session(conn, %{
          "wallet_address" => wallet_address,
          "cache_tables" => cache_tables,
          "pubsub" => pubsub,
          "static_data" => static_data,
          "walrus_client" => Sigil.TestSupport.BlobAvailableClient,
          "reputation_registry_id" => reputation_registry_id
        }),
        "/marketplace"
      )

    before_feedback_html = render(view)
    assert before_feedback_html =~ "+9 / -1 (90%)"

    render_click(view, "show_section", %{"section" => "my_listings"})
    render_click(view, "decrypt_listing", %{"listing_id" => sold_listing.id})

    render_hook(view, "seal_decrypt_complete", %{
      "data" => Jason.encode!(%{"notes" => "Feedback lock intel", "assembly_id" => "0xassembly"})
    })

    my_listings_html = render(view)
    assert my_listings_html =~ ~s(phx-click="confirm_quality")

    render_click(view, "confirm_quality", %{"listing_id" => sold_listing.id})
    assert_push_event(view, "request_sign_transaction", %{"tx_bytes" => tx_bytes})

    render_hook(view, "transaction_signed", %{
      "bytes" => tx_bytes,
      "signature" => "wallet-signature"
    })

    assert_push_event(view, "report_transaction_effects", %{effects: "feedback-effects-bcs"})

    after_feedback_html = render(view)

    assert after_feedback_html =~ "Feedback submitted"
    assert after_feedback_html =~ "Feedback submitted</p>"
    assert after_feedback_html =~ "disabled"

    replay_html = render_click(view, "confirm_quality", %{"listing_id" => sold_listing.id})
    assert replay_html =~ "Feedback already submitted"

    refreshed_browse_html = render_click(view, "show_section", %{"section" => "browsing"})
    assert refreshed_browse_html =~ "+10 / -1 (91%)"
  end

  test "marketplace emits undeployed seal config when session overrides package id", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    static_data: static_data,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    insert_pseudonym!(
      account_address: wallet_address,
      pseudonym_address: unique_wallet_address(),
      encrypted_private_key: <<1, 2, 3, 4>>
    )

    seed_chain_marketplace([])

    zero_package_id = "0x" <> String.duplicate("0", 64)

    {:ok, view, html} =
      mount_live_with_cleanup(
        init_test_session(conn, %{
          "wallet_address" => wallet_address,
          "cache_tables" => cache_tables,
          "pubsub" => pubsub,
          "static_data" => static_data,
          "seal_package_id" => zero_package_id
        }),
        "/marketplace"
      )

    assert html =~ ~s(data-config=)
    assert html =~ zero_package_id

    view
    |> form("#sell-intel-form", %{
      "listing" => %{
        "entry_mode" => "manual",
        "report_type" => "1",
        "solar_system_name" => "A 2560",
        "assembly_id" => "0xoverride-assembly",
        "notes" => "Override package test",
        "price_sui" => "1.25",
        "description" => "Undeployed override listing"
      }
    })
    |> render_submit()

    assert_push_event(view, "encrypt_and_upload", %{
      "intel_data" => %{
        "assembly_id" => "0xoverride-assembly",
        "report_type" => 1,
        "solar_system_id" => 30_000_001,
        "notes" => "Override package test",
        "label" => "Undeployed override listing"
      },
      "seal_id" => seal_id,
      "config" => %{"seal_package_id" => ^zero_package_id},
      "assembly_id" => "0xoverride-assembly",
      "report_type" => 1,
      "solar_system_id" => 30_000_001,
      "notes" => "Override package test"
    })

    assert seal_id =~ ~r/^0x[0-9a-f]{64}$/
  end

  @tag :acceptance
  test "browser UAT sell flow creates visible listing via Seal", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    static_data: static_data,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    pseudonym =
      insert_pseudonym!(
        account_address: wallet_address,
        pseudonym_address: unique_wallet_address(),
        encrypted_private_key: <<1, 2, 3, 4>>
      )

    nonce = "marketplace-sell-nonce"
    seed_nonce(cache_tables, nonce, wallet_address)
    expect_wallet_registration(wallet_address)
    seed_chain_marketplace([])
    :ok = Phoenix.PubSub.subscribe(pubsub, Sigil.IntelMarket.topic())

    created_listing_id = unique_object_id()

    expect(Sigil.Sui.ClientMock, :get_coins, fn relay_owner, [] ->
      assert is_binary(relay_owner)

      {:ok,
       [
         %{
           object_id: :binary.copy(<<0x11>>, 32),
           version: 7,
           digest: :binary.copy(<<0x21>>, 32),
           balance: 12_000_000
         }
       ]}
    end)

    expect(Sigil.Sui.ClientMock, :execute_transaction, fn _tx_bytes, signatures, [] ->
      assert length(signatures) == 2

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
      mount_live_with_cleanup(
        init_test_session(conn, %{
          "cache_tables" => cache_tables,
          "pubsub" => pubsub,
          "static_data" => static_data
        }),
        "/"
      )

    assert initial_html =~ "Connect Your Wallet"
    refute initial_html =~ "Seal-encrypted market intel"

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

    {:ok, view, _html} = mount_live_with_cleanup(recycle(conn), "/marketplace")

    view
    |> form("#sell-intel-form", %{
      "listing" => %{
        "entry_mode" => "manual",
        "report_type" => "1",
        "solar_system_name" => "A 2560",
        "assembly_id" => "0xbrowser-assembly",
        "notes" => "Sealed listing",
        "price_sui" => "2.50",
        "description" => "Seal-encrypted market intel"
      }
    })
    |> render_submit()

    assert_push_event(view, "encrypt_and_upload", %{
      "intel_data" => %{
        "report_type" => 1,
        "solar_system_id" => 30_000_001,
        "assembly_id" => "0xbrowser-assembly",
        "notes" => "Sealed listing",
        "label" => "Seal-encrypted market intel"
      },
      "seal_id" => seal_id,
      "config" => %{
        "seal_package_id" => @sigil_package_id,
        "walrus_publisher_url" => "https://publisher.walrus-testnet.walrus.space",
        "walrus_aggregator_url" => "https://aggregator.walrus-testnet.walrus.space",
        "walrus_epochs" => 15,
        "sui_rpc_url" => "https://fullnode.testnet.sui.io:443"
      },
      "report_type" => 1,
      "solar_system_id" => 30_000_001,
      "assembly_id" => "0xbrowser-assembly",
      "notes" => "Sealed listing"
    })

    assert seal_id =~ ~r/^0x[0-9a-f]{64}$/

    render_hook(view, "seal_upload_complete", %{
      "seal_id" => seal_id,
      "blob_id" => "walrus-browser-blob"
    })

    assert_push_event(view, "sign_pseudonym_tx", %{
      "pseudonym_address" => pseudonym_address,
      "tx_bytes" => _tx_bytes
    })

    assert pseudonym_address == pseudonym.pseudonym_address

    render_hook(view, "pseudonym_tx_signed", %{"signature" => Base.encode64("wallet-signature")})

    assert_push_event(view, "report_transaction_effects", %{effects: "effects-bcs-data"})

    html = render(view)
    assert html =~ "Listing created"
    refute html =~ "Failed to load circuit"
    refute html =~ "Transaction failed"
  end

  @tag :acceptance
  test "purchase and decrypt flow shows decrypted intel", %{
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
      mount_live_with_cleanup(
        init_test_session(conn, %{
          "wallet_address" => wallet_address,
          "cache_tables" => cache_tables,
          "pubsub" => pubsub,
          "static_data" => static_data,
          "walrus_client" => Sigil.TestSupport.BlobAvailableClient
        }),
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

    html = render_click(view, "show_section", %{"section" => "my_listings"})
    assert html =~ "Purchase successful"
    assert html =~ "seller must reveal"
    assert html =~ "sold"
    refute html =~ ~s(phx-click="purchase_listing")

    render_click(view, "decrypt_listing", %{"listing_id" => listing.id})

    listing_id = listing.id
    encrypted_blob_id = listing.encrypted_blob_id
    seal_id = listing.seal_id

    assert_push_event(view, "decrypt_intel", %{
      "listing_id" => ^listing_id,
      "blob_id" => ^encrypted_blob_id,
      "seal_id" => ^seal_id
    })

    render_hook(view, "seal_decrypt_complete", %{
      "data" => Jason.encode!(%{"notes" => "Recovered route", "assembly_id" => "0xassembly"})
    })

    decrypted_html = render(view)
    assert decrypted_html =~ "Recovered route"
    refute decrypted_html =~ "Encrypted blob is unavailable"
  end

  test "decrypt flow pushes overridden seal package config", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    static_data: static_data,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    zero_package_id = "0x" <> String.duplicate("0", 64)

    listing =
      insert_listing!(%{
        id: unique_object_id(),
        seller_address: unique_wallet_address(),
        buyer_address: wallet_address,
        status: :sold,
        seal_id: seal_id_hex(0xD1),
        encrypted_blob_id: "walrus-decrypt-blob",
        description: "Decrypt target intel"
      })

    seed_chain_marketplace([listing])

    listing_id = listing.id
    seal_id = listing.seal_id
    encrypted_blob_id = listing.encrypted_blob_id

    {:ok, view, _html} =
      mount_live_with_cleanup(
        init_test_session(conn, %{
          "wallet_address" => wallet_address,
          "cache_tables" => cache_tables,
          "pubsub" => pubsub,
          "static_data" => static_data,
          "seal_package_id" => zero_package_id,
          "walrus_client" => Sigil.TestSupport.BlobAvailableClient
        }),
        "/marketplace"
      )

    my_listings_html = render_click(view, "show_section", %{"section" => "my_listings"})
    assert my_listings_html =~ listing.id

    render_click(view, "decrypt_listing", %{"listing_id" => listing.id})

    assert_push_event(view, "decrypt_intel", %{
      "listing_id" => ^listing_id,
      "seal_id" => ^seal_id,
      "blob_id" => ^encrypted_blob_id,
      "config" => %{"seal_package_id" => ^zero_package_id}
    })
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

    pseudonym =
      insert_pseudonym!(
        account_address: wallet_address,
        pseudonym_address: unique_wallet_address(),
        encrypted_private_key: <<9, 8, 7, 6>>
      )

    listing =
      insert_listing!(%{
        id: unique_object_id(),
        seller_address: pseudonym.pseudonym_address,
        status: :active,
        description: "Cancelable listing"
      })

    seed_chain_marketplace([listing])
    :ok = Phoenix.PubSub.subscribe(pubsub, Sigil.IntelMarket.topic())

    expect(Sigil.Sui.ClientMock, :get_coins, fn relay_owner, [] ->
      assert is_binary(relay_owner)

      {:ok,
       [
         %{
           object_id: :binary.copy(<<0x31>>, 32),
           version: 7,
           digest: :binary.copy(<<0x41>>, 32),
           balance: 12_000_000
         }
       ]}
    end)

    expect(Sigil.Sui.ClientMock, :execute_transaction, fn _tx_bytes, signatures, [] ->
      assert length(signatures) == 2

      {:ok,
       %{
         "bcs" => "cancel-effects-bcs",
         "status" => "SUCCESS",
         "transaction" => %{"digest" => "cancel-digest"}
       }}
    end)

    {:ok, view, _html} =
      mount_live_with_cleanup(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub, static_data),
        "/marketplace"
      )

    render_click(view, "cancel_listing", %{"listing_id" => listing.id})

    assert_push_event(view, "sign_pseudonym_tx", %{
      "pseudonym_address" => pseudonym_address,
      "tx_bytes" => _tx_bytes
    })

    assert pseudonym_address == pseudonym.pseudonym_address

    render_hook(view, "pseudonym_tx_signed", %{"signature" => "wallet-signature"})

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

    {:ok, view, html} =
      mount_live_with_cleanup(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub, static_data),
        "/marketplace"
      )

    refute html =~ ~s(phx-click="purchase_listing" phx-value-listing_id="#{own_listing.id}")
    refute html =~ "cannot purchase your own listing"
    refute html =~ "Approve in your wallet"

    forced_html = render_click(view, "purchase_listing", %{"listing_id" => own_listing.id})

    assert forced_html =~ "cannot purchase your own listing"
    refute forced_html =~ "Approve in your wallet"
  end

  test "seal_error event displays error message", %{
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
      mount_live_with_cleanup(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub, static_data),
        "/marketplace"
      )

    html = render_hook(view, "seal_error", %{"reason" => "Failed to load circuit"})

    assert html =~ "Failed to load circuit"
    refute html =~ "Approve in your wallet"
  end

  test "my listings shows seller and purchased listings", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    static_data: static_data,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    pseudonym_one =
      insert_pseudonym!(
        account_address: wallet_address,
        pseudonym_address: unique_wallet_address(),
        encrypted_private_key: <<1, 2, 3, 4>>
      )

    pseudonym_two =
      insert_pseudonym!(
        account_address: wallet_address,
        pseudonym_address: unique_wallet_address(),
        encrypted_private_key: <<5, 6, 7, 8>>
      )

    active_listing =
      insert_listing!(%{
        id: unique_object_id(),
        seller_address: pseudonym_one.pseudonym_address,
        status: :active
      })

    sold_listing =
      insert_listing!(%{
        id: unique_object_id(),
        seller_address: pseudonym_two.pseudonym_address,
        status: :sold,
        buyer_address: unique_wallet_address()
      })

    other_listing =
      insert_listing!(%{id: unique_object_id(), seller_address: unique_wallet_address()})

    seed_chain_marketplace([active_listing, sold_listing, other_listing])

    {:ok, view, _html} =
      mount_live_with_cleanup(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub, static_data),
        "/marketplace"
      )

    html = render_click(view, "show_section", %{"section" => "my_listings"})

    assert html =~ active_listing.id
    assert html =~ sold_listing.id
    assert html =~ "active"
    assert html =~ "sold"
    assert html =~ "Purchased Intel"
    refute html =~ other_listing.id
  end

  test "expired blob preflight shows decrypt error", %{
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
        buyer_address: wallet_address,
        status: :sold,
        seal_id: seal_id_hex(0xD2),
        encrypted_blob_id: "walrus-missing-blob",
        description: "Unavailable decrypt target"
      })

    seed_chain_marketplace([listing])

    {:ok, view, _html} =
      mount_live_with_cleanup(
        init_test_session(conn, %{
          "wallet_address" => wallet_address,
          "cache_tables" => cache_tables,
          "pubsub" => pubsub,
          "static_data" => static_data,
          "walrus_client" => Sigil.TestSupport.BlobMissingClient
        }),
        "/marketplace"
      )

    my_listings_html = render_click(view, "show_section", %{"section" => "my_listings"})
    assert my_listings_html =~ "Purchased Intel"
    assert my_listings_html =~ listing.id

    html = render_click(view, "decrypt_listing", %{"listing_id" => listing.id})

    assert html =~ "Encrypted blob is unavailable right now — retry in a moment"
  end

  test "decrypt button shown only for buyer of purchased listing", %{static_data: static_data} do
    buyer_address = unique_wallet_address()
    seller_address = unique_wallet_address()

    buyer_html =
      LiveViewTest.render_component(&Components.listing_card/1,
        listing: %IntelListing{
          id: unique_object_id(),
          seller_address: seller_address,
          seal_id: seal_id_hex(0xD3),
          encrypted_blob_id: "walrus-decrypted-blob",
          client_nonce: 13,
          price_mist: 200_000_000,
          report_type: 1,
          solar_system_id: 30_000_001,
          description: "Buyer-only decrypt target",
          status: :sold,
          buyer_address: buyer_address,
          restricted_to_tribe_id: nil,
          intel_report_id: nil,
          on_chain_digest: nil
        },
        sender: buyer_address,
        tribe_id: @tribe_id,
        static_data: static_data
      )

    other_html =
      LiveViewTest.render_component(&Components.listing_card/1,
        listing: %IntelListing{
          id: unique_object_id(),
          seller_address: seller_address,
          seal_id: seal_id_hex(0xD4),
          encrypted_blob_id: "walrus-hidden-blob",
          client_nonce: 14,
          price_mist: 200_000_000,
          report_type: 1,
          solar_system_id: 30_000_001,
          description: "Hidden decrypt target",
          status: :sold,
          buyer_address: buyer_address,
          restricted_to_tribe_id: nil,
          intel_report_id: nil,
          on_chain_digest: nil
        },
        sender: unique_wallet_address(),
        tribe_id: @tribe_id,
        static_data: static_data
      )

    assert buyer_html =~ "Decrypt Intel"
    refute other_html =~ "Decrypt Intel"
  end

  test "decrypted intel displays in ephemeral modal", %{
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
        buyer_address: wallet_address,
        status: :sold,
        seal_id: seal_id_hex(0xD3),
        encrypted_blob_id: "walrus-decrypted-blob",
        description: "Visible decrypt target"
      })

    seed_chain_marketplace([listing])

    {:ok, view, _html} =
      mount_live_with_cleanup(
        init_test_session(conn, %{
          "wallet_address" => wallet_address,
          "cache_tables" => cache_tables,
          "pubsub" => pubsub,
          "static_data" => static_data,
          "walrus_client" => Sigil.TestSupport.BlobAvailableClient
        }),
        "/marketplace"
      )

    render_click(view, "show_section", %{"section" => "my_listings"})
    render_click(view, "decrypt_listing", %{"listing_id" => listing.id})

    render_hook(view, "seal_decrypt_complete", %{
      "data" => Jason.encode!(%{"notes" => "Recovered route", "assembly_id" => "0xassembly"})
    })

    html = render(view)
    assert html =~ "Decrypted Intel"
    assert html =~ "Recovered route"
    assert html =~ "Assembly 0xassembly"

    cleared = render_click(view, "dismiss_decrypted_intel", %{"listing_id" => listing.id})
    refute cleared =~ "Recovered route"
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

    pseudonym =
      insert_pseudonym!(
        account_address: wallet_address,
        pseudonym_address: unique_wallet_address(),
        encrypted_private_key: <<1, 2, 3, 4>>
      )

    seed_chain_marketplace([])

    expect(Sigil.Sui.ClientMock, :get_coins, fn relay_owner, client_opts ->
      assert is_binary(relay_owner)
      assert is_list(client_opts)

      {:ok,
       [
         %{
           object_id: :binary.copy(<<0x12>>, 32),
           version: 7,
           digest: :binary.copy(<<0x22>>, 32),
           balance: 12_000_000
         }
       ]}
    end)

    restricted_listing_id = unique_object_id()

    expect(Sigil.Sui.ClientMock, :execute_transaction, fn _tx_bytes, signatures, [] ->
      assert length(signatures) == 2

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
      mount_live_with_cleanup(
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

    assert_push_event(view, "encrypt_and_upload", %{
      "intel_data" => %{
        "report_type" => 1,
        "solar_system_id" => 30_000_001,
        "assembly_id" => "0xrestricted-assembly",
        "notes" => "Tribe-only intel",
        "label" => "Restricted intel"
      },
      "seal_id" => seal_id,
      "config" => _config,
      "report_type" => 1,
      "solar_system_id" => 30_000_001,
      "assembly_id" => "0xrestricted-assembly",
      "notes" => "Tribe-only intel"
    })

    assert seal_id =~ ~r/^0x[0-9a-f]{64}$/

    render_hook(view, "seal_upload_complete", %{
      "seal_id" => seal_id,
      "blob_id" => "walrus-restricted-blob"
    })

    assert_push_event(view, "sign_pseudonym_tx", %{
      "pseudonym_address" => pseudonym_address,
      "tx_bytes" => _tx_bytes
    })

    assert pseudonym_address == pseudonym.pseudonym_address

    render_hook(view, "pseudonym_tx_signed", %{"signature" => "pseudonym-signature"})

    assert_receive {:listing_created,
                    %IntelListing{id: restricted_id, restricted_to_tribe_id: restricted_tribe_id}}

    assert restricted_tribe_id == @tribe_id
    assert restricted_id == restricted_listing_id
    assert Repo.get!(IntelListing, restricted_id).seller_address == pseudonym.pseudonym_address

    html = render(view)
    assert html =~ "Listing created"
    assert html =~ "restricted"
    refute html =~ "active custodian"
  end

  @tag :acceptance
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
      mount_live_with_cleanup(
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

    html = render_click(view, "show_section", %{"section" => "my_listings"})
    assert html =~ "Purchase successful"
    assert html =~ "Purchased Intel"
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
      mount_live_with_cleanup(
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

  test "PubSub listing state changes update marketplace views", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    static_data: static_data,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    active_listing =
      insert_listing!(%{
        id: unique_object_id(),
        seller_address: unique_wallet_address(),
        description: "Volatile listing",
        price_mist: 300_000_000
      })

    removed_listing =
      insert_listing!(%{
        id: unique_object_id(),
        seller_address: unique_wallet_address(),
        description: "Removed listing",
        price_mist: 400_000_000
      })

    seed_chain_marketplace([active_listing, removed_listing])

    {:ok, view, initial_html} =
      mount_live_with_cleanup(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub, static_data),
        "/marketplace"
      )

    assert initial_html =~ ~s(phx-click="purchase_listing")
    assert initial_html =~ removed_listing.description

    sold_listing =
      Repo.get!(IntelListing, active_listing.id)
      |> Ecto.Changeset.change(status: :sold)
      |> Repo.update!()

    Phoenix.PubSub.broadcast(
      pubsub,
      Sigil.IntelMarket.topic(),
      {:listing_purchased, sold_listing}
    )

    sold_html = render(view)

    refute sold_html =~
             ~s(phx-click="purchase_listing" phx-value-listing_id="#{active_listing.id}")

    Repo.delete!(removed_listing)

    Phoenix.PubSub.broadcast(
      pubsub,
      Sigil.IntelMarket.topic(),
      {:listing_removed, removed_listing.id}
    )

    removed_html = render(view)
    refute removed_html =~ removed_listing.description
  end

  test "inactive listing purchase shows validation error", %{
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
        status: :sold,
        description: "Inactive listing"
      })

    seed_chain_marketplace([listing])

    {:ok, view, _html} =
      mount_live_with_cleanup(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub, static_data),
        "/marketplace"
      )

    html = render_click(view, "purchase_listing", %{"listing_id" => listing.id})

    assert html =~ "Listing is no longer active"
    refute html =~ "Approve in your wallet"
  end

  test "unauthenticated user sees wallet connect prompt", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    static_data: static_data
  } do
    seed_chain_marketplace([])

    assert {:ok, _view, html} =
             mount_live_with_cleanup(
               init_test_session(conn, %{
                 "cache_tables" => cache_tables,
                 "pubsub" => pubsub,
                 "static_data" => static_data
               }),
               "/marketplace"
             )

    assert html =~ "Connect wallet to use marketplace"
    refute html =~ "My Listings"
    refute html =~ "Seal-encrypted market intel"
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
             mount_live_with_cleanup(
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

    {:ok, view, html} =
      mount_live_with_cleanup(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub, static_data),
        "/marketplace"
      )

    assert html =~ ~s(aria-disabled="true")
    assert html =~ "Restricted to another tribe"
    refute html =~ ~s(phx-click="purchase_listing" phx-value-listing_id="#{listing.id}")

    forced_html = render_click(view, "purchase_listing", %{"listing_id" => listing.id})

    assert forced_html =~ "Restricted to another tribe"
    refute forced_html =~ "Approve in your wallet"
  end

  test "restricted listing displays tribe badge", %{
    static_data: static_data
  } do
    html =
      LiveViewTest.render_component(&Components.listing_card/1,
        listing: %IntelListing{
          id: unique_object_id(),
          seller_address: unique_wallet_address(),
          seal_id: seal_id_hex(0xB1),
          encrypted_blob_id: "walrus-component-restricted",
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
          seal_id: seal_id_hex(0xB2),
          encrypted_blob_id: "walrus-component-price",
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

  test "listing card shows View on Map link", %{static_data: static_data} do
    html =
      LiveViewTest.render_component(&Components.listing_card/1,
        listing: %IntelListing{
          id: unique_object_id(),
          seller_address: unique_wallet_address(),
          seal_id: seal_id_hex(0xB3),
          encrypted_blob_id: "walrus-component-map-link",
          client_nonce: 8,
          price_mist: 500_000_000,
          report_type: 1,
          solar_system_id: 30_000_001,
          description: "Map link listing",
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

    assert html =~ "View on Map"
    assert html =~ ~s(href="/map?system_id=30000001")
  end

  test "listing card without solar_system_id has no map link", %{static_data: static_data} do
    map_listing_html =
      LiveViewTest.render_component(&Components.listing_card/1,
        listing: %IntelListing{
          id: unique_object_id(),
          seller_address: unique_wallet_address(),
          seal_id: seal_id_hex(0xB4),
          encrypted_blob_id: "walrus-component-with-map-link",
          client_nonce: 9,
          price_mist: 500_000_000,
          report_type: 2,
          solar_system_id: 30_000_001,
          description: "Has map link listing",
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

    undisclosed_listing_html =
      LiveViewTest.render_component(&Components.listing_card/1,
        listing: %IntelListing{
          id: unique_object_id(),
          seller_address: unique_wallet_address(),
          seal_id: seal_id_hex(0xB5),
          encrypted_blob_id: "walrus-component-undisclosed-map-link",
          client_nonce: 10,
          price_mist: 500_000_000,
          report_type: 2,
          solar_system_id: 0,
          description: "Undisclosed listing",
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

    no_map_listing_html =
      LiveViewTest.render_component(&Components.listing_card/1,
        listing: %IntelListing{
          id: unique_object_id(),
          seller_address: unique_wallet_address(),
          seal_id: seal_id_hex(0xB6),
          encrypted_blob_id: "walrus-component-no-map-link",
          client_nonce: 11,
          price_mist: 500_000_000,
          report_type: 2,
          solar_system_id: nil,
          description: "No map link listing",
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

    assert map_listing_html =~ "View on Map"
    assert map_listing_html =~ ~s(href="/map?system_id=30000001")
    assert undisclosed_listing_html =~ "Location undisclosed"
    refute undisclosed_listing_html =~ "View on Map"
    refute undisclosed_listing_html =~ ~s(href="/map?system_id=0")
    refute no_map_listing_html =~ "View on Map"
    refute no_map_listing_html =~ ~s(/map?system_id=)
  end

  test "active pseudonym deletion warns before confirm and rebinds seller UI", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    static_data: static_data,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, @tribe_id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    first_pseudonym =
      insert_pseudonym!(
        account_address: wallet_address,
        pseudonym_address: unique_wallet_address(),
        encrypted_private_key: <<1, 2, 3, 4>>
      )

    second_pseudonym =
      insert_pseudonym!(
        account_address: wallet_address,
        pseudonym_address: unique_wallet_address(),
        encrypted_private_key: <<5, 6, 7, 8>>
      )

    seed_chain_marketplace([])

    {:ok, view, _html} =
      mount_live_with_cleanup(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub, static_data),
        "/marketplace"
      )

    assert_push_event(view, "load_pseudonyms", %{"active_address" => active_address})

    assert active_address in [
             first_pseudonym.pseudonym_address,
             second_pseudonym.pseudonym_address
           ]

    warning_html =
      render_click(view, "request_delete_pseudonym", %{"pseudonym_address" => active_address})

    assert warning_html =~ "orphan active listings"

    assert Repo.get_by(Pseudonym,
             account_address: wallet_address,
             pseudonym_address: active_address
           )

    cancelled_html = render_click(view, "cancel_delete_pseudonym", %{})

    refute cancelled_html =~ "Confirm Delete"

    assert Repo.get_by(Pseudonym,
             account_address: wallet_address,
             pseudonym_address: active_address
           )

    _warning_again_html =
      render_click(view, "request_delete_pseudonym", %{"pseudonym_address" => active_address})

    confirmed_html =
      render_click(view, "delete_pseudonym", %{"pseudonym_address" => active_address})

    assert confirmed_html =~ "Pseudonym deleted"

    assert Repo.get_by(Pseudonym,
             account_address: wallet_address,
             pseudonym_address: active_address
           ) == nil

    remaining_pseudonym =
      [first_pseudonym.pseudonym_address, second_pseudonym.pseudonym_address]
      |> Enum.find(&(&1 != active_address))

    assert Repo.get_by(Pseudonym,
             account_address: wallet_address,
             pseudonym_address: remaining_pseudonym
           )

    assert confirmed_html =~ remaining_pseudonym
    refute confirmed_html =~ ~s(aria-disabled="true")
  end

  defp mount_live_with_cleanup(conn, path) do
    {:ok, view, html} = live(conn, path)

    on_exit(fn ->
      if Process.alive?(view.pid) do
        try do
          GenServer.stop(view.pid, :normal, :infinity)
        catch
          :exit, _ -> :ok
        end
      end
    end)

    {:ok, view, html}
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

  defp insert_pseudonym!(attrs) do
    attrs = attrs |> Map.new() |> Map.put_new(:encrypted_private_key, <<1, 2, 3, 4>>)

    apply(Pseudonym, :__struct__, [])
    |> Pseudonym.changeset(attrs)
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
      "seal_id" => listing.seal_id,
      "encrypted_blob_id" => listing.encrypted_blob_id,
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
        seal_id: seal_id_hex(0xC1),
        encrypted_blob_id: "walrus-default-listing",
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

  defp seal_id_hex(byte) do
    "0x" <> Base.encode16(:binary.copy(<<byte>>, 32), case: :lower)
  end

  defp uid(id), do: %{"id" => id}
end
