defmodule SigilWeb.IntelLiveTest do
  @moduledoc """
  Covers the UI_IntelLive specification (R1-R16) for the packet 3 intel UI.
  """

  use Sigil.ConnCase, async: true

  alias Sigil.Cache
  alias Sigil.Repo
  alias Sigil.Accounts.Account
  alias Sigil.Intel.IntelReport
  alias Sigil.StaticData
  alias Sigil.StaticDataTestFixtures, as: StaticDataFixtures
  alias Sigil.Sui.Types.Character

  @tribe_id 314

  setup %{sandbox_owner: sandbox_owner} do
    cache_pid = start_supervised!({Cache, tables: [:accounts, :characters, :intel]})
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
  test "authenticated tribe member sees intel page", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    static_data: static_data,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    Cache.put(cache_tables.accounts, wallet_address, account)

    assert {:ok, _view, html} =
             live(
               authenticated_conn(conn, wallet_address, cache_tables, pubsub, static_data),
               "/tribe/#{@tribe_id}/intel"
             )

    assert html =~ "No intel reports yet. Be the first to share!"
    assert html =~ "Location"
    refute html =~ "Not your tribe"
    refute html =~ "Connect Your Wallet"
  end

  test "unauthorized user redirected from intel page", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    static_data: static_data,
    wallet_address: wallet_address
  } do
    account = %Account{
      address: wallet_address,
      characters: [Character.from_json(character_json(%{"tribe_id" => "999"}))],
      tribe_id: 999
    }

    Cache.put(cache_tables.accounts, wallet_address, account)

    assert {:error, {:redirect, %{to: "/", flash: %{"error" => error_msg}}}} =
             live(
               authenticated_conn(conn, wallet_address, cache_tables, pubsub, static_data),
               "/tribe/#{@tribe_id}/intel"
             )

    assert error_msg =~ "Not your tribe"
  end

  test "unauthenticated user redirected from intel", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub
  } do
    assert {:error, {:redirect, %{to: "/"}}} =
             live(
               init_test_session(conn, %{"cache_tables" => cache_tables, "pubsub" => pubsub}),
               "/tribe/#{@tribe_id}/intel"
             )
  end

  test "submitting location report adds it to feed", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    static_data: static_data,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    Cache.put(cache_tables.accounts, wallet_address, account)

    {:ok, view, _html} =
      live(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub, static_data),
        "/tribe/#{@tribe_id}/intel"
      )

    html =
      view
      |> render_submit("submit_report", %{
        "report" => %{
          "report_type" => "location",
          "assembly_id" => "0xassembly-intel-1",
          "solar_system_name" => "A 2560",
          "label" => "Forward base",
          "notes" => "Tower online"
        }
      })

    assert html =~ "A 2560"
    assert html =~ "Forward base"
    refute html =~ "Unknown or ambiguous solar system"
  end

  test "location submit uses exact system match", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    static_data: static_data,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    Cache.put(cache_tables.accounts, wallet_address, account)

    {:ok, view, _html} =
      live(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub, static_data),
        "/tribe/#{@tribe_id}/intel"
      )

    html =
      view
      |> render_submit("submit_report", %{
        "report" => %{
          "report_type" => "location",
          "assembly_id" => "0xassembly-intel-2",
          "solar_system_name" => "a 2560",
          "label" => "Fallback cache",
          "notes" => "Exact case-insensitive match"
        }
      })

    assert html =~ "A 2560"
    refute html =~ "Unknown or ambiguous solar system"
  end

  test "submitting scouting report adds it to feed", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    static_data: static_data,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    Cache.put(cache_tables.accounts, wallet_address, account)

    {:ok, view, _html} =
      live(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub, static_data),
        "/tribe/#{@tribe_id}/intel"
      )

    html =
      view
      |> render_submit("submit_report", %{
        "report" => %{
          "report_type" => "scouting",
          "assembly_id" => "",
          "solar_system_name" => "B 31337",
          "label" => "Scout wing",
          "notes" => "Enemy scout wing on scan"
        }
      })

    assert html =~ "Enemy scout wing on scan"
    assert html =~ "B 31337"
    refute html =~ "Unknown or ambiguous solar system"
  end

  test "invalid or ambiguous solar system name shows error", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    static_data: static_data,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    Cache.put(cache_tables.accounts, wallet_address, account)

    {:ok, view, _html} =
      live(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub, static_data),
        "/tribe/#{@tribe_id}/intel"
      )

    html =
      view
      |> render_submit("submit_report", %{
        "report" => %{
          "report_type" => "location",
          "assembly_id" => "0xassembly-intel-3",
          "solar_system_name" => "Z 9999",
          "label" => "Bad intel",
          "notes" => "No match"
        }
      })

    assert html =~ "Unknown or ambiguous solar system"
    # Form preserves entered values per spec
    assert html =~ "Z 9999"
    # The empty state message should still be visible (no report added)
    assert html =~ "No intel reports yet"
  end

  test "user can delete their own report", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    static_data: static_data,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    report = seed_location_report!(wallet_address, hd(account.characters).id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    {:ok, view, _html} =
      live(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub, static_data),
        "/tribe/#{@tribe_id}/intel"
      )

    html = render_click(view, "delete_report", %{"report_id" => report.id})

    refute html =~ report.label
    refute html =~ report.notes
  end

  test "non-leader cannot delete another member's report", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    static_data: static_data,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    report = seed_location_report!("0x" <> String.duplicate("ab", 32), "0xother-character")
    Cache.put(cache_tables.accounts, wallet_address, account)

    {:ok, view, _html} =
      live(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub, static_data),
        "/tribe/#{@tribe_id}/intel"
      )

    html = render_click(view, "delete_report", %{"report_id" => report.id})

    assert html =~ "Not authorized to delete this report"
    assert html =~ report.label
  end

  test "without role data only report authors can delete reports", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    static_data: static_data,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    own_report = seed_location_report!(wallet_address, hd(account.characters).id)
    other_report = seed_scouting_report!("0x" <> String.duplicate("cd", 32), "0xother-character")
    Cache.put(cache_tables.accounts, wallet_address, account)

    assert {:ok, _view, html} =
             live(
               authenticated_conn(conn, wallet_address, cache_tables, pubsub, static_data),
               "/tribe/#{@tribe_id}/intel"
             )

    assert html =~ own_report.label
    refute html =~ "delete-#{other_report.id}"
  end

  test "PubSub intel update replaces existing row", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    static_data: static_data,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    original = seed_location_report!(wallet_address, hd(account.characters).id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    {:ok, view, _html} =
      live(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub, static_data),
        "/tribe/#{@tribe_id}/intel"
      )

    replacement = %IntelReport{
      original
      | id: Ecto.UUID.generate(),
        label: "Updated Forward Base",
        notes: "Replacement row"
    }

    draft_params = %{
      "report_type" => "location",
      "assembly_id" => "0xdraft-assembly",
      "solar_system_name" => "A 2560",
      "label" => "Draft label",
      "notes" => "Draft notes"
    }

    draft_html =
      view
      |> render_change("validate", %{"report" => draft_params})

    assert draft_html =~ "Draft label"
    assert draft_html =~ "Draft notes"

    Phoenix.PubSub.broadcast(pubsub, "intel:#{@tribe_id}", {:intel_updated, replacement})

    html = render(view)
    assert html =~ "Updated Forward Base"
    refute html =~ original.label
    assert html =~ "Draft label"
    assert html =~ "Draft notes"
  end

  test "reports display solar system names from StaticData", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    static_data: static_data,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    seed_location_report!(wallet_address, hd(account.characters).id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    assert {:ok, _view, html} =
             live(
               authenticated_conn(conn, wallet_address, cache_tables, pubsub, static_data),
               "/tribe/#{@tribe_id}/intel"
             )

    assert html =~ "A 2560"
    assert html =~ "Just now"
    assert html =~ "0xreport-"
    assert html =~ "..."
    refute html =~ ">30000001<"
  end

  test "toggling report type changes form fields", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    static_data: static_data,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    Cache.put(cache_tables.accounts, wallet_address, account)

    {:ok, view, _html} =
      live(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub, static_data),
        "/tribe/#{@tribe_id}/intel"
      )

    html = render_click(view, "toggle_report_type", %{"report_type" => "scouting"})

    assert html =~ "Scouting"
    assert html =~ "Notes"
    assert html =~ "Assembly ID"
  end

  test "form disabled when no active character", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    static_data: static_data,
    wallet_address: wallet_address
  } do
    account = %Account{address: wallet_address, characters: [], tribe_id: @tribe_id}
    Cache.put(cache_tables.accounts, wallet_address, account)

    assert {:ok, _view, html} =
             live(
               authenticated_conn(conn, wallet_address, cache_tables, pubsub, static_data),
               "/tribe/#{@tribe_id}/intel"
             )

    assert html =~ "Select a character to submit reports"
    refute html =~ "Submit report"
  end

  @tag :acceptance
  test "full journey: submit report, verify visible to tribe", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    static_data: static_data,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    second_wallet_address = unique_wallet_address()
    second_account = account_fixture(second_wallet_address)

    Cache.put(cache_tables.accounts, wallet_address, account)
    Cache.put(cache_tables.accounts, second_wallet_address, second_account)

    {:ok, view, _html} =
      live(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub, static_data),
        "/tribe/#{@tribe_id}/intel"
      )

    html =
      view
      |> form("#intel-report-form", %{
        "report" => %{
          "report_type" => "location",
          "assembly_id" => "0xacceptance-intel",
          "solar_system_name" => "A 2560",
          "label" => "Acceptance forward base",
          "notes" => "Visible to tribe"
        }
      })
      |> render_submit()

    assert html =~ "Acceptance forward base"
    assert html =~ "A 2560"
    refute html =~ "Unknown or ambiguous solar system"
    refute html =~ "Solar system data not available"

    assert {:ok, _second_view, second_html} =
             live(
               authenticated_conn(conn, second_wallet_address, cache_tables, pubsub, static_data),
               "/tribe/#{@tribe_id}/intel"
             )

    assert second_html =~ "Acceptance forward base"
    assert second_html =~ "A 2560"
  end

  test "empty intel feed shows empty state", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    static_data: static_data,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    Cache.put(cache_tables.accounts, wallet_address, account)

    assert {:ok, _view, html} =
             live(
               authenticated_conn(conn, wallet_address, cache_tables, pubsub, static_data),
               "/tribe/#{@tribe_id}/intel"
             )

    assert html =~ "No intel reports yet. Be the first to share!"
    assert html =~ "Location"
    refute html =~ "Report not found"
  end

  test "intel page disables picker when StaticData unavailable", %{
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
               "/tribe/#{@tribe_id}/intel"
             )

    assert html =~ "Solar system data not available"
    refute html =~ "solar-systems"
  end

  test "intel page rejects forged submit events when injected cache tables omit intel", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    static_data: static_data,
    wallet_address: wallet_address
  } do
    trimmed_tables = Map.delete(cache_tables, :intel)
    account = account_fixture(wallet_address)
    Cache.put(cache_tables.accounts, wallet_address, account)

    {:ok, view, html} =
      live(
        authenticated_conn(conn, wallet_address, trimmed_tables, pubsub, static_data),
        "/tribe/#{@tribe_id}/intel"
      )

    assert html =~ "Intel storage not available"
    refute html =~ "Submit report"

    html =
      render_submit(view, "submit_report", %{
        "report" => %{
          "report_type" => "location",
          "assembly_id" => "0xforged-report",
          "solar_system_name" => "A 2560",
          "label" => "Forged report",
          "notes" => "Should not persist"
        }
      })

    assert html =~ "Intel storage not available"
    assert html =~ "No intel reports yet. Be the first to share!"
    refute html =~ "Forged report"
    assert Repo.aggregate(IntelReport, :count) == 0
  end

  test "intel delete broadcast removes report row", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    static_data: static_data,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    report = seed_location_report!(wallet_address, hd(account.characters).id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    {:ok, view, _html} =
      live(
        authenticated_conn(conn, wallet_address, cache_tables, pubsub, static_data),
        "/tribe/#{@tribe_id}/intel"
      )

    Phoenix.PubSub.broadcast(pubsub, "intel:#{@tribe_id}", {:intel_deleted, report})

    html = render(view)
    refute html =~ report.label
    refute html =~ report.notes
  end

  @tag :acceptance
  test "intel report card shows View on Map link", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    static_data: static_data,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    report = seed_location_report!(wallet_address, hd(account.characters).id)
    Cache.put(cache_tables.accounts, wallet_address, account)

    assert {:ok, _view, html} =
             live(
               authenticated_conn(conn, wallet_address, cache_tables, pubsub, static_data),
               "/tribe/#{@tribe_id}/intel"
             )

    assert html =~ report.label
    assert html =~ "View on Map"
    assert html =~ ~s(href="/map?system_id=#{report.solar_system_id}")
    refute html =~ "No intel reports yet. Be the first to share!"
  end

  test "intel report card without solar_system_id has no map link", %{
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)

    map_report = %IntelReport{
      id: Ecto.UUID.generate(),
      tribe_id: @tribe_id,
      assembly_id: nil,
      solar_system_id: 30_000_001,
      label: "Map scouting report",
      report_type: :scouting,
      notes: "Has a solar system id",
      reported_by: wallet_address,
      reported_by_name: "Scout Prime",
      reported_by_character_id: hd(account.characters).id,
      inserted_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }

    undisclosed_report = %IntelReport{
      id: Ecto.UUID.generate(),
      tribe_id: @tribe_id,
      assembly_id: nil,
      solar_system_id: 0,
      label: "Undisclosed scouting report",
      report_type: :scouting,
      notes: "Undisclosed location",
      reported_by: wallet_address,
      reported_by_name: "Scout Prime",
      reported_by_character_id: hd(account.characters).id,
      inserted_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }

    no_map_report = %IntelReport{
      id: Ecto.UUID.generate(),
      tribe_id: @tribe_id,
      assembly_id: nil,
      solar_system_id: nil,
      label: "No map scouting report",
      report_type: :scouting,
      notes: "No solar system id",
      reported_by: wallet_address,
      reported_by_name: "Scout Prime",
      reported_by_character_id: hd(account.characters).id,
      inserted_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }

    html =
      Phoenix.LiveViewTest.render_component(&SigilWeb.IntelLive.Components.report_feed_panel/1,
        reports: [map_report, undisclosed_report, no_map_report],
        system_names: %{30_000_001 => "A 2560"},
        current_account: account,
        is_leader_or_operator: false
      )

    assert html =~ "Map scouting report"
    assert html =~ "Undisclosed scouting report"
    assert html =~ "No map scouting report"
    assert html =~ "Location undisclosed"
    assert html =~ ~s(href="/map?system_id=30000001")
    assert length(Regex.scan(~r/View on Map/, html)) == 1
    refute html =~ ~s(href="/map?system_id=0")
    refute html =~ ~s(href="/map?system_id=nil")
  end

  defp authenticated_conn(conn, wallet_address, cache_tables, pubsub, static_data \\ nil) do
    session = %{
      "wallet_address" => wallet_address,
      "cache_tables" => cache_tables,
      "pubsub" => pubsub
    }

    session = if static_data, do: Map.put(session, "static_data", static_data), else: session
    init_test_session(conn, session)
  end

  defp account_fixture(wallet_address) do
    %Account{
      address: wallet_address,
      characters: [Character.from_json(character_json())],
      tribe_id: @tribe_id
    }
  end

  defp seed_location_report!(reported_by, character_id) do
    %IntelReport{}
    |> IntelReport.location_changeset(%{
      tribe_id: @tribe_id,
      assembly_id: "0xreport-#{System.unique_integer([:positive])}",
      solar_system_id: 30_000_001,
      label: "Forward Base #{System.unique_integer([:positive])}",
      notes: "Location report #{System.unique_integer([:positive])}",
      reported_by: reported_by,
      reported_by_name: "Scout Prime",
      reported_by_character_id: character_id
    })
    |> Repo.insert!()
  end

  defp seed_scouting_report!(reported_by, character_id) do
    %IntelReport{}
    |> IntelReport.scouting_changeset(%{
      tribe_id: @tribe_id,
      assembly_id: nil,
      solar_system_id: 30_000_002,
      label: "Scout Wing #{System.unique_integer([:positive])}",
      notes: "Scouting report #{System.unique_integer([:positive])}",
      reported_by: reported_by,
      reported_by_name: "Scout Prime",
      reported_by_character_id: character_id
    })
    |> Repo.insert!()
  end

  defp unique_pubsub_name do
    :"intel_live_pubsub_#{System.unique_integer([:positive])}"
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
        "id" => uid("0xintel-character"),
        "key" => %{"item_id" => "1", "tenant" => "0xcharacter-tenant"},
        "tribe_id" => "#{@tribe_id}",
        "character_address" => "0xcharacter-address",
        "metadata" => %{
          "assembly_id" => "0xcharacter-metadata",
          "name" => "Captain Frontier",
          "description" => "Primary intel pilot",
          "url" => "https://example.test/characters/frontier"
        },
        "owner_cap_id" => uid("0xcharacter-owner")
      },
      overrides
    )
  end

  defp uid(id), do: %{"id" => id}
end
