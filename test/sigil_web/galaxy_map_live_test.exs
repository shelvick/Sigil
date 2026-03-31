defmodule SigilWeb.GalaxyMapLiveTest do
  @moduledoc """
  Covers UI_GalaxyMapLive packet 2 behavior (route, core mount, and detail panel).
  """

  use Sigil.ConnCase, async: true

  alias Sigil.Accounts.Account
  alias Sigil.Cache
  alias Sigil.Intel.IntelListing
  alias Sigil.Intel.IntelReport
  alias Sigil.Repo
  alias Sigil.StaticData
  alias Sigil.StaticDataTestFixtures, as: StaticDataFixtures
  alias Sigil.Sui.Types.Character

  @tribe_id 314
  @system_id 30_000_001
  @other_system_id 30_000_002

  setup %{sandbox_owner: sandbox_owner} do
    cache_pid =
      start_supervised!({Cache, tables: [:accounts, :characters, :intel, :intel_market]})

    pubsub = unique_pubsub_name()
    start_supervised!({Phoenix.PubSub, name: pubsub})

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
  test "authenticated user views galaxy map and selects a system", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    static_data: static_data,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    active_character = hd(account.characters)

    seed_location_report!(wallet_address, active_character.id)
    seed_scouting_report!(wallet_address, active_character.id)
    insert_active_listing!(%{id: "listing-active-acceptance", solar_system_id: @system_id})

    insert_sold_listing!(%{
      id: "listing-sold-acceptance",
      solar_system_id: @system_id,
      buyer_address: wallet_address
    })

    Cache.put(cache_tables.accounts, wallet_address, account)

    {:ok, view, html} =
      live(
        authenticated_conn(
          conn,
          wallet_address,
          cache_tables,
          pubsub,
          static_data,
          active_character.id
        ),
        "/map"
      )

    assert html =~ "galaxy-map"

    view
    |> render_hook("system_selected", %{"system_id" => Integer.to_string(@system_id)})

    selected_html = render(view)

    assert selected_html =~ "A 2560"
    assert selected_html =~ "20000001"
    assert selected_html =~ "1 assembly locations, 1 scouting reports"
    assert selected_html =~ "2 marketplace intel entries"
    refute selected_html =~ "Galaxy data unavailable"
    refute selected_html =~ "Not Found"
  end

  test "authenticated user sees galaxy map page", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    static_data: static_data,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    active_character = hd(account.characters)
    Cache.put(cache_tables.accounts, wallet_address, account)

    assert {:ok, view, html} =
             live(
               authenticated_conn(
                 conn,
                 wallet_address,
                 cache_tables,
                 pubsub,
                 static_data,
                 active_character.id
               ),
               "/map"
             )

    assert view.module == SigilWeb.GalaxyMapLive
    assert html =~ ~s(id="galaxy-map")
    assert html =~ ~s(phx-hook="GalaxyMap")
  end

  test "selecting a system shows detail panel with system info", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    static_data: static_data,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    active_character = hd(account.characters)
    Cache.put(cache_tables.accounts, wallet_address, account)

    {:ok, view, _html} =
      live(
        authenticated_conn(
          conn,
          wallet_address,
          cache_tables,
          pubsub,
          static_data,
          active_character.id
        ),
        "/map"
      )

    html =
      view
      |> render_hook("system_selected", %{"system_id" => Integer.to_string(@system_id)})

    assert html =~ "A 2560"
    assert html =~ "20000001"
  end

  test "detail panel lists assemblies linked to detail pages", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    static_data: static_data,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    active_character = hd(account.characters)
    report = seed_location_report!(wallet_address, active_character.id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    {:ok, view, _html} =
      live(
        authenticated_conn(
          conn,
          wallet_address,
          cache_tables,
          pubsub,
          static_data,
          active_character.id
        ),
        "/map"
      )

    html =
      view
      |> render_hook("system_selected", %{"system_id" => Integer.to_string(@system_id)})

    assert html =~ report.assembly_id
    assert html =~ "/assembly/#{report.assembly_id}"
  end

  test "deselecting system hides detail panel", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    static_data: static_data,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    active_character = hd(account.characters)
    Cache.put(cache_tables.accounts, wallet_address, account)

    {:ok, view, _html} =
      live(
        authenticated_conn(
          conn,
          wallet_address,
          cache_tables,
          pubsub,
          static_data,
          active_character.id
        ),
        "/map"
      )

    view
    |> render_hook("system_selected", %{"system_id" => Integer.to_string(@system_id)})

    html =
      view
      |> render_hook("system_deselected", %{})

    refute html =~ "A 2560"
    refute html =~ "20000001"
  end

  test "map_ready triggers overlay push to hook", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    static_data: static_data,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    active_character = hd(account.characters)
    Cache.put(cache_tables.accounts, wallet_address, account)

    {:ok, view, _html} =
      live(
        authenticated_conn(
          conn,
          wallet_address,
          cache_tables,
          pubsub,
          static_data,
          active_character.id
        ),
        "/map"
      )

    view
    |> render_hook("map_ready", %{})

    assert_push_event(view, "update_overlays", %{
      "tribe_locations" => _,
      "tribe_scouting" => _,
      "marketplace" => _
    })

    assert_push_event(view, "update_system_colors", %{"categories" => categories})
    assert is_map(categories)
  end

  test "tribe overlay data separates location and scouting reports", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    static_data: static_data,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    active_character = hd(account.characters)
    location_report = seed_location_report!(wallet_address, active_character.id)
    seed_scouting_report!(wallet_address, active_character.id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    {:ok, view, _html} =
      live(
        authenticated_conn(
          conn,
          wallet_address,
          cache_tables,
          pubsub,
          static_data,
          active_character.id
        ),
        "/map"
      )

    view
    |> render_hook("map_ready", %{})

    assert_push_event(view, "update_overlays", %{
      "tribe_locations" => tribe_locations,
      "tribe_scouting" => tribe_scouting,
      "marketplace" => []
    })

    assert_push_event(view, "update_system_colors", %{"categories" => categories})

    assert categories[Integer.to_string(@system_id)] in [
             "both",
             "assembly",
             "fuel_low",
             "fuel_critical"
           ]

    assert [%{"assembly_id" => assembly_id, "label" => label, "system_id" => @system_id}] =
             tribe_locations

    assert assembly_id == location_report.assembly_id
    assert label == location_report.label
    assert [%{"system_id" => @system_id}] = tribe_scouting

    new_scouting_report = seed_scouting_report!(wallet_address, active_character.id)

    Phoenix.PubSub.broadcast(
      pubsub,
      Sigil.Intel.topic(@tribe_id),
      {:intel_updated, new_scouting_report}
    )

    render(view)

    assert_push_event(view, "update_overlays", %{
      "tribe_locations" => [
        %{"assembly_id" => ^assembly_id, "label" => ^label, "system_id" => @system_id}
      ],
      "tribe_scouting" => updated_scouting,
      "marketplace" => []
    })

    assert length(updated_scouting) == 2
    assert Enum.all?(updated_scouting, &(&1["system_id"] == @system_id))
  end

  test "marketplace overlay includes active and user-purchased listings", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    static_data: static_data,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    active_character = hd(account.characters)

    listing_to_purchase =
      insert_active_listing!(%{
        id: "listing-market-active-#{System.unique_integer([:positive])}",
        solar_system_id: @system_id
      })

    insert_sold_listing!(%{
      id: "listing-market-owned-#{System.unique_integer([:positive])}",
      solar_system_id: @other_system_id,
      buyer_address: wallet_address
    })

    insert_sold_listing!(%{
      id: "listing-market-other-#{System.unique_integer([:positive])}",
      solar_system_id: 30_000_003,
      buyer_address: unique_wallet_address()
    })

    insert_cancelled_listing!(%{
      id: "listing-market-cancelled-#{System.unique_integer([:positive])}",
      solar_system_id: 30_000_004
    })

    Cache.put(cache_tables.accounts, wallet_address, account)

    {:ok, view, _html} =
      live(
        authenticated_conn(
          conn,
          wallet_address,
          cache_tables,
          pubsub,
          static_data,
          active_character.id
        ),
        "/map"
      )

    view
    |> render_hook("map_ready", %{})

    assert_push_event(view, "update_overlays", %{
      "tribe_locations" => [],
      "tribe_scouting" => [],
      "marketplace" => marketplace
    })

    marketplace_system_ids =
      marketplace
      |> Enum.map(& &1["system_id"])
      |> Enum.sort()

    assert marketplace_system_ids == Enum.sort([@system_id, @other_system_id])
    refute 30_000_003 in marketplace_system_ids
    refute 30_000_004 in marketplace_system_ids

    purchased_listing = %IntelListing{
      listing_to_purchase
      | status: :sold,
        buyer_address: wallet_address
    }

    Phoenix.PubSub.broadcast(
      pubsub,
      Sigil.IntelMarket.topic(),
      {:listing_purchased, purchased_listing}
    )

    render(view)

    assert_push_event(view, "update_overlays", %{
      "tribe_locations" => [],
      "tribe_scouting" => [],
      "marketplace" => [%{"system_id" => @system_id}, %{"system_id" => @other_system_id}]
    })
  end

  test "intel deletion updates overlay and detail panel", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    static_data: static_data,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    active_character = hd(account.characters)
    report = seed_location_report!(wallet_address, active_character.id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    {:ok, view, _html} =
      live(
        authenticated_conn(
          conn,
          wallet_address,
          cache_tables,
          pubsub,
          static_data,
          active_character.id
        ),
        "/map"
      )

    view
    |> render_hook("map_ready", %{})

    expected_location = %{
      "assembly_id" => report.assembly_id,
      "label" => report.label,
      "system_id" => @system_id
    }

    assert_push_event(view, "update_overlays", %{
      "tribe_locations" => [^expected_location],
      "tribe_scouting" => [],
      "marketplace" => []
    })

    view
    |> render_hook("system_selected", %{"system_id" => Integer.to_string(@system_id)})

    assert render(view) =~ "1 assembly locations, 0 scouting reports"

    Phoenix.PubSub.broadcast(pubsub, Sigil.Intel.topic(@tribe_id), {:intel_deleted, report})

    html = render(view)

    assert_push_event(view, "update_overlays", %{
      "tribe_locations" => [],
      "tribe_scouting" => [],
      "marketplace" => []
    })

    assert html =~ "0 assembly locations, 0 scouting reports"
  end

  @tag :acceptance
  test "unauthenticated user sees map without tribe overlays", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    static_data: static_data
  } do
    insert_active_listing!(%{
      id: "listing-market-unauth-#{System.unique_integer([:positive])}",
      solar_system_id: @system_id
    })

    unauth_conn =
      init_test_session(conn, %{
        "cache_tables" => cache_tables,
        "pubsub" => pubsub,
        "static_data" => static_data
      })

    {:ok, view, html} = live(unauth_conn, "/map")

    assert html =~ ~s(id="galaxy-map")

    view
    |> render_hook("map_ready", %{})

    assert_push_event(view, "update_overlays", %{
      "tribe_locations" => [],
      "tribe_scouting" => [],
      "marketplace" => [%{"system_id" => @system_id}]
    })

    detail_html =
      view
      |> render_hook("system_selected", %{"system_id" => Integer.to_string(@system_id)})

    assert detail_html =~ "1 marketplace intel entries"
    refute detail_html =~ "assembly locations"
    refute detail_html =~ "/tribe/"
  end

  test "inbound system_id param triggers select_system push", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    static_data: static_data,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    active_character = hd(account.characters)
    Cache.put(cache_tables.accounts, wallet_address, account)

    {:ok, view, _html} =
      live(
        authenticated_conn(
          conn,
          wallet_address,
          cache_tables,
          pubsub,
          static_data,
          active_character.id
        ),
        "/map?system_id=#{@system_id}"
      )

    view
    |> render_hook("map_ready", %{})

    assert_push_event(view, "select_system", %{"system_id" => @system_id})
  end

  test "overlay toggle stays hidden after PubSub overlay refresh", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    static_data: static_data,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    active_character = hd(account.characters)

    listing =
      insert_active_listing!(%{
        id: "listing-toggle-refresh-#{System.unique_integer([:positive])}",
        solar_system_id: @system_id
      })

    Cache.put(cache_tables.accounts, wallet_address, account)

    {:ok, view, _html} =
      live(
        authenticated_conn(
          conn,
          wallet_address,
          cache_tables,
          pubsub,
          static_data,
          active_character.id
        ),
        "/map"
      )

    view
    |> render_hook("map_ready", %{})

    assert_push_event(view, "update_overlays", %{
      "tribe_locations" => [],
      "tribe_scouting" => [],
      "marketplace" => [%{"system_id" => @system_id}],
      "overlay_toggles" => %{"marketplace" => true}
    })

    view
    |> render_hook("toggle_overlay", %{"layer" => "marketplace"})

    assert_push_event(view, "toggle_overlay", %{"layer" => "marketplace", "visible" => false})

    assert_push_event(view, "update_overlays", %{
      "tribe_locations" => [],
      "tribe_scouting" => [],
      "marketplace" => [%{"system_id" => @system_id}],
      "overlay_toggles" => %{"marketplace" => false}
    })

    Phoenix.PubSub.broadcast(pubsub, Sigil.IntelMarket.topic(), {:listing_created, listing})

    render(view)

    assert_push_event(view, "update_overlays", %{
      "tribe_locations" => [],
      "tribe_scouting" => [],
      "marketplace" => [%{"system_id" => @system_id}],
      "overlay_toggles" => %{"marketplace" => false}
    })
  end

  test "intel PubSub update refreshes tribe overlay", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    static_data: static_data,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    active_character = hd(account.characters)
    Cache.put(cache_tables.accounts, wallet_address, account)

    {:ok, view, _html} =
      live(
        authenticated_conn(
          conn,
          wallet_address,
          cache_tables,
          pubsub,
          static_data,
          active_character.id
        ),
        "/map"
      )

    view
    |> render_hook("map_ready", %{})

    assert_push_event(view, "update_overlays", %{
      "tribe_locations" => [],
      "tribe_scouting" => [],
      "marketplace" => []
    })

    report = seed_location_report!(wallet_address, active_character.id)

    expected_location = %{
      "assembly_id" => report.assembly_id,
      "label" => report.label,
      "system_id" => @system_id
    }

    Phoenix.PubSub.broadcast(pubsub, Sigil.Intel.topic(@tribe_id), {:intel_updated, report})

    render(view)

    assert_push_event(view, "update_overlays", %{
      "tribe_locations" => [^expected_location],
      "tribe_scouting" => [],
      "marketplace" => []
    })
  end

  test "marketplace PubSub update refreshes overlay", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    static_data: static_data,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    active_character = hd(account.characters)
    Cache.put(cache_tables.accounts, wallet_address, account)

    {:ok, view, _html} =
      live(
        authenticated_conn(
          conn,
          wallet_address,
          cache_tables,
          pubsub,
          static_data,
          active_character.id
        ),
        "/map"
      )

    view
    |> render_hook("map_ready", %{})

    assert_push_event(view, "update_overlays", %{
      "tribe_locations" => [],
      "tribe_scouting" => [],
      "marketplace" => []
    })

    listing =
      insert_active_listing!(%{
        id: "listing-created-#{System.unique_integer([:positive])}",
        solar_system_id: @system_id
      })

    Phoenix.PubSub.broadcast(pubsub, Sigil.IntelMarket.topic(), {:listing_created, listing})

    render(view)

    assert_push_event(view, "update_overlays", %{
      "tribe_locations" => [],
      "tribe_scouting" => [],
      "marketplace" => [%{"system_id" => @system_id}]
    })
  end

  test "listing purchased by other user removed from overlay", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    static_data: static_data,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    active_character = hd(account.characters)

    listing =
      insert_active_listing!(%{
        id: "listing-remove-on-purchase-#{System.unique_integer([:positive])}",
        solar_system_id: @system_id
      })

    Cache.put(cache_tables.accounts, wallet_address, account)

    {:ok, view, _html} =
      live(
        authenticated_conn(
          conn,
          wallet_address,
          cache_tables,
          pubsub,
          static_data,
          active_character.id
        ),
        "/map"
      )

    view
    |> render_hook("map_ready", %{})

    assert_push_event(view, "update_overlays", %{
      "tribe_locations" => [],
      "tribe_scouting" => [],
      "marketplace" => [%{"system_id" => @system_id}]
    })

    purchased_by_other = %IntelListing{
      listing
      | status: :sold,
        buyer_address: unique_wallet_address()
    }

    Phoenix.PubSub.broadcast(
      pubsub,
      Sigil.IntelMarket.topic(),
      {:listing_purchased, purchased_by_other}
    )

    render(view)

    assert_push_event(view, "update_overlays", %{
      "tribe_locations" => [],
      "tribe_scouting" => [],
      "marketplace" => []
    })
  end

  test "tribeless user hides tribe overlay toggles but keeps marketplace toggle", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    static_data: static_data,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address, nil)
    Cache.put(cache_tables.accounts, wallet_address, account)

    assert {:ok, _view, html} =
             live(
               authenticated_conn(conn, wallet_address, cache_tables, pubsub, static_data),
               "/map"
             )

    assert html =~ ~s(phx-click="toggle_overlay")
    assert html =~ ~s(phx-value-layer="marketplace")
    refute html =~ ~s(phx-value-layer="tribe_locations")
    refute html =~ ~s(phx-value-layer="tribe_scouting")
  end

  test "map shows fallback when StaticData unavailable", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    Cache.put(cache_tables.accounts, wallet_address, account)

    assert {:ok, _view, html} =
             live(
               authenticated_conn(conn, wallet_address, cache_tables, pubsub),
               "/map"
             )

    assert html =~ "Galaxy data unavailable"
    refute html =~ ~s(id="galaxy-map")
  end

  defp authenticated_conn(
         conn,
         wallet_address,
         cache_tables,
         pubsub,
         static_data \\ nil,
         active_character_id \\ nil
       ) do
    session = %{
      "wallet_address" => wallet_address,
      "cache_tables" => cache_tables,
      "pubsub" => pubsub
    }

    session = if static_data, do: Map.put(session, "static_data", static_data), else: session

    session =
      if is_binary(active_character_id) do
        Map.put(session, "active_character_id", active_character_id)
      else
        session
      end

    init_test_session(conn, session)
  end

  defp account_fixture(wallet_address, tribe_id \\ @tribe_id) do
    characters =
      if is_integer(tribe_id) do
        [Character.from_json(character_json(tribe_id, wallet_address))]
      else
        []
      end

    %Account{
      address: wallet_address,
      characters: characters,
      tribe_id: tribe_id
    }
  end

  defp character_json(tribe_id, wallet_address) do
    %{
      "id" => uid("0xgalaxy-character"),
      "key" => %{"item_id" => "1", "tenant" => "0xcharacter-tenant"},
      "tribe_id" => if(is_integer(tribe_id), do: Integer.to_string(tribe_id), else: nil),
      "character_address" => wallet_address,
      "metadata" => %{
        "assembly_id" => "0xcharacter-metadata",
        "name" => "Map Pilot",
        "description" => "Galaxy map pilot",
        "url" => "https://example.test/characters/galaxy"
      },
      "owner_cap_id" => uid("0xcharacter-owner")
    }
  end

  defp seed_location_report!(wallet_address, character_id) do
    assembly_id = "0xassembly-#{System.unique_integer([:positive])}"

    %IntelReport{}
    |> IntelReport.location_changeset(%{
      tribe_id: @tribe_id,
      assembly_id: assembly_id,
      solar_system_id: @system_id,
      label: "Forward Base",
      notes: "Location intel",
      reported_by: wallet_address,
      reported_by_name: "Map Pilot",
      reported_by_character_id: character_id
    })
    |> Repo.insert!()
  end

  defp seed_scouting_report!(wallet_address, character_id) do
    %IntelReport{}
    |> IntelReport.scouting_changeset(%{
      tribe_id: @tribe_id,
      assembly_id: nil,
      solar_system_id: @system_id,
      label: "Scout Wing",
      notes: "Scouting intel",
      reported_by: wallet_address,
      reported_by_name: "Map Pilot",
      reported_by_character_id: character_id
    })
    |> Repo.insert!()
  end

  defp insert_active_listing!(attrs) do
    defaults = %{
      id: "listing-#{System.unique_integer([:positive])}",
      seller_address: unique_wallet_address(),
      seal_id: "0x" <> String.duplicate("1", 64),
      encrypted_blob_id: "blob-#{System.unique_integer([:positive])}",
      client_nonce: System.unique_integer([:positive]),
      price_mist: 1_250_000_000,
      report_type: 1,
      solar_system_id: @system_id,
      description: "Active listing",
      status: :active,
      buyer_address: nil
    }

    %IntelListing{}
    |> IntelListing.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp insert_sold_listing!(attrs) do
    defaults = %{
      id: "listing-#{System.unique_integer([:positive])}",
      seller_address: unique_wallet_address(),
      seal_id: "0x" <> String.duplicate("2", 64),
      encrypted_blob_id: "blob-#{System.unique_integer([:positive])}",
      client_nonce: System.unique_integer([:positive]),
      price_mist: 2_500_000_000,
      report_type: 1,
      solar_system_id: @system_id,
      description: "Sold listing",
      status: :sold,
      buyer_address: unique_wallet_address()
    }

    %IntelListing{}
    |> IntelListing.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp insert_cancelled_listing!(attrs) do
    defaults = %{
      id: "listing-#{System.unique_integer([:positive])}",
      seller_address: unique_wallet_address(),
      seal_id: "0x" <> String.duplicate("3", 64),
      encrypted_blob_id: "blob-#{System.unique_integer([:positive])}",
      client_nonce: System.unique_integer([:positive]),
      price_mist: 900_000_000,
      report_type: 2,
      solar_system_id: @system_id,
      description: "Cancelled listing",
      status: :cancelled,
      buyer_address: nil
    }

    %IntelListing{}
    |> IntelListing.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp unique_pubsub_name do
    :"galaxy_map_live_pubsub_#{System.unique_integer([:positive])}"
  end

  defp unique_wallet_address do
    suffix =
      System.unique_integer([:positive])
      |> Integer.to_string(16)
      |> String.downcase()
      |> String.pad_leading(64, "0")

    "0x" <> suffix
  end

  defp uid(id), do: %{"id" => id}
end
