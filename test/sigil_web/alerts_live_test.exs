defmodule SigilWeb.AlertsLiveTest do
  @moduledoc """
  Covers the packet 1 alerts feed specification.
  """

  use Sigil.ConnCase, async: true

  @moduletag capture_log: true

  alias Sigil.Accounts.Account
  alias Sigil.Alerts
  alias Sigil.Alerts.Alert
  alias Sigil.Cache
  alias Sigil.Repo

  setup do
    cache_pid = start_supervised!({Cache, tables: [:accounts, :characters]})
    pubsub = unique_pubsub_name()
    start_supervised!({Phoenix.PubSub, name: pubsub})

    {:ok,
     cache_tables: Cache.tables(cache_pid),
     pubsub: pubsub,
     wallet_address: unique_wallet_address()}
  end

  test "unauthenticated user redirected from alerts", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub
  } do
    assert {:error, {:redirect, %{to: "/"}}} =
             live(
               init_test_session(conn, %{"cache_tables" => cache_tables, "pubsub" => pubsub}),
               "/alerts"
             )
  end

  test "authenticated user sees alerts feed", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    Cache.put(cache_tables.accounts, wallet_address, account)

    older =
      insert_alert!(%{
        "account_address" => wallet_address,
        "message" => "Older warning",
        "assembly_name" => "Assembly Older"
      })

    newer =
      insert_alert!(%{
        "account_address" => wallet_address,
        "message" => "Newest critical",
        "type" => "fuel_critical",
        "severity" => "critical",
        "assembly_name" => "Assembly Newer"
      })

    assert {:ok, _view, html} =
             mount_alerts_live(conn, wallet_address, cache_tables, pubsub)

    assert html =~ "Newest critical"
    assert html =~ "Older warning"
    {newer_pos, _} = :binary.match(html, newer.message)
    {older_pos, _} = :binary.match(html, older.message)
    assert newer_pos < older_pos
  end

  test "shows empty state when no alerts exist", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    Cache.put(cache_tables.accounts, wallet_address, account)

    assert {:ok, _view, html} =
             mount_alerts_live(conn, wallet_address, cache_tables, pubsub)

    assert html =~ "No alerts yet"
    refute html =~ "Connect Your Wallet"
  end

  test "alerts page ignores foreign account alerts", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    Cache.put(cache_tables.accounts, wallet_address, account)

    own_alert =
      insert_alert!(%{
        "account_address" => wallet_address,
        "message" => "Own alert",
        "assembly_name" => "Own Assembly"
      })

    foreign_alert =
      insert_alert!(%{
        "account_address" => unique_wallet_address(),
        "message" => "Foreign alert",
        "assembly_name" => "Foreign Assembly"
      })

    {:ok, view, html} =
      mount_alerts_live(conn, wallet_address, cache_tables, pubsub)

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

  test "alert card displays type severity assembly and message", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    Cache.put(cache_tables.accounts, wallet_address, account)

    alert =
      insert_alert!(%{
        "account_address" => wallet_address,
        "type" => "fuel_critical",
        "severity" => "critical",
        "message" => "Fuel reserves are collapsing",
        "assembly_id" => "assembly-display",
        "assembly_name" => "Citadel K-7"
      })

    assert {:ok, _view, html} =
             mount_alerts_live(conn, wallet_address, cache_tables, pubsub)

    assert html =~ "Fuel Critical"
    assert html =~ "Citadel K-7"
    assert html =~ alert.message
    assert html =~ "Just now"
    refute html =~ "No alerts yet"
  end

  test "alert card links to assembly detail page", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    Cache.put(cache_tables.accounts, wallet_address, account)

    alert =
      insert_alert!(%{
        "account_address" => wallet_address,
        "assembly_id" => "assembly-link-target",
        "assembly_name" => "Citadel Link"
      })

    assert {:ok, _view, html} =
             mount_alerts_live(conn, wallet_address, cache_tables, pubsub)

    assert html =~ alert.assembly_name
    assert html =~ "/assembly/#{alert.assembly_id}"
    assert html =~ ~s(title="#{alert.assembly_id}")
  end

  test "new alerts have unread styling and acknowledged alerts have muted styling", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    Cache.put(cache_tables.accounts, wallet_address, account)

    insert_alert!(%{
      "account_address" => wallet_address,
      "status" => "new",
      "message" => "Unread alert"
    })

    insert_alert!(%{
      "account_address" => wallet_address,
      "status" => "acknowledged",
      "message" => "Read alert"
    })

    assert {:ok, _view, html} =
             mount_alerts_live(conn, wallet_address, cache_tables, pubsub)

    assert html =~ "Unread alert"
    assert html =~ "Read alert"
    assert html =~ "border-quantum-400/60 bg-space-800/90"
    assert html =~ "border-space-600/80 bg-space-800/70"
    refute html =~ "No alerts yet"
  end

  test "acknowledging alert updates card to acknowledged styling", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    Cache.put(cache_tables.accounts, wallet_address, account)

    alert =
      insert_alert!(%{
        "account_address" => wallet_address,
        "status" => "new",
        "message" => "Acknowledge me"
      })

    {:ok, view, _html} =
      mount_alerts_live(conn, wallet_address, cache_tables, pubsub)

    html = render_click(view, "acknowledge", %{"id" => Integer.to_string(alert.id)})

    assert html =~ "Acknowledge me"
    assert html =~ "border-space-600/80 bg-space-800/70"
    refute html =~ "border-quantum-400/60 bg-space-800/90"
  end

  test "dismissing alert removes it from active feed", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    Cache.put(cache_tables.accounts, wallet_address, account)

    alert =
      insert_alert!(%{
        "account_address" => wallet_address,
        "status" => "new",
        "message" => "Dismiss me"
      })

    {:ok, view, _html} =
      mount_alerts_live(conn, wallet_address, cache_tables, pubsub)

    html = render_click(view, "dismiss", %{"id" => Integer.to_string(alert.id)})

    refute html =~ alert.message
    assert html =~ "No alerts yet"
  end

  test "toggling show dismissed resets pagination and reveals dismissed alerts", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    Cache.put(cache_tables.accounts, wallet_address, account)

    dismissed =
      insert_alert!(%{
        "account_address" => wallet_address,
        "status" => "dismissed",
        "dismissed_at" => DateTime.add(DateTime.utc_now(), -300, :second),
        "message" => "Dismissed history"
      })

    {:ok, view, initial_html} =
      mount_alerts_live(conn, wallet_address, cache_tables, pubsub)

    refute initial_html =~ dismissed.message

    html = render_click(view, "toggle_dismissed", %{})

    assert html =~ dismissed.message
    assert html =~ "border-space-700/50 bg-space-900/50"
    refute html =~ "No alerts yet"
  end

  test "unread count badge shows count of new alerts", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    Cache.put(cache_tables.accounts, wallet_address, account)

    insert_alert!(%{
      "account_address" => wallet_address,
      "status" => "new",
      "message" => "New one"
    })

    insert_alert!(%{
      "account_address" => wallet_address,
      "status" => "new",
      "message" => "New two"
    })

    insert_alert!(%{
      "account_address" => wallet_address,
      "status" => "acknowledged",
      "message" => "Read"
    })

    assert {:ok, _view, html} =
             mount_alerts_live(conn, wallet_address, cache_tables, pubsub)

    assert html =~ "2 unread"
    refute html =~ "3 unread"
  end

  test "PubSub alert_created refreshes feed and unread count", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    Cache.put(cache_tables.accounts, wallet_address, account)

    {:ok, view, html} =
      mount_alerts_live(conn, wallet_address, cache_tables, pubsub)

    assert html =~ "No alerts yet"

    created =
      insert_alert!(%{
        "account_address" => wallet_address,
        "status" => "new",
        "message" => "Fresh broadcast alert"
      })

    Phoenix.PubSub.broadcast(pubsub, Alerts.topic(wallet_address), {:alert_created, created})

    refreshed_html = render(view)
    assert refreshed_html =~ created.message
    assert refreshed_html =~ "1 unread"
    refute refreshed_html =~ "No alerts yet"
  end

  test "PubSub dismiss refreshes active feed and unread count", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    Cache.put(cache_tables.accounts, wallet_address, account)

    alert =
      insert_alert!(%{
        "account_address" => wallet_address,
        "status" => "new",
        "message" => "Dismissed by broadcast"
      })

    {:ok, view, _html} =
      mount_alerts_live(conn, wallet_address, cache_tables, pubsub)

    replacement =
      insert_alert!(%{
        "account_address" => wallet_address,
        "status" => "new",
        "message" => "DB-backed replacement"
      })

    assert {:ok, _dismissed} = Alerts.dismiss_alert(alert.id, pubsub: pubsub)

    Phoenix.PubSub.broadcast(pubsub, Alerts.topic(wallet_address), {:alert_dismissed, alert})

    html = render(view)
    assert html =~ replacement.message
    refute html =~ alert.message
    assert html =~ "1 unread"
    refute html =~ "0 unread"
  end

  test "PubSub dismiss refreshes dismissed view and unread count", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    Cache.put(cache_tables.accounts, wallet_address, account)

    alert =
      insert_alert!(%{
        "account_address" => wallet_address,
        "status" => "new",
        "message" => "Dismissed by broadcast history"
      })

    {:ok, view, _html} =
      mount_alerts_live(conn, wallet_address, cache_tables, pubsub)

    render_click(view, "toggle_dismissed", %{})

    assert {:ok, dismissed} = Alerts.dismiss_alert(alert.id, pubsub: pubsub)

    Phoenix.PubSub.broadcast(pubsub, Alerts.topic(wallet_address), {:alert_dismissed, alert})

    html = render(view)
    assert html =~ dismissed.message
    assert html =~ "0 unread"
    refute html =~ "border-quantum-400/60 bg-space-800/90"
  end

  test "acknowledging alert refreshes unread count", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    Cache.put(cache_tables.accounts, wallet_address, account)

    alert =
      insert_alert!(%{
        "account_address" => wallet_address,
        "status" => "new",
        "message" => "Count after acknowledge"
      })

    {:ok, view, _html} =
      mount_alerts_live(conn, wallet_address, cache_tables, pubsub)

    before_html = render(view)
    assert before_html =~ "1 unread"
    assert before_html =~ alert.message

    newer_alert =
      insert_alert!(%{
        "account_address" => wallet_address,
        "status" => "new",
        "message" => "Appears only after refresh"
      })

    html = render_click(view, "acknowledge", %{"id" => Integer.to_string(alert.id)})

    assert html =~ "1 unread"
    assert html =~ newer_alert.message
    refute html =~ alert.message
  end

  test "dismissing alert refreshes unread count", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    Cache.put(cache_tables.accounts, wallet_address, account)

    alert =
      insert_alert!(%{
        "account_address" => wallet_address,
        "status" => "new",
        "message" => "Count after dismiss"
      })

    {:ok, view, _html} =
      mount_alerts_live(conn, wallet_address, cache_tables, pubsub)

    before_html = render(view)
    assert before_html =~ "1 unread"
    assert before_html =~ alert.message

    newer_alert =
      insert_alert!(%{
        "account_address" => wallet_address,
        "status" => "new",
        "message" => "Replacement after dismiss"
      })

    html = render_click(view, "dismiss", %{"id" => Integer.to_string(alert.id)})

    assert html =~ "1 unread"
    assert html =~ newer_alert.message
    refute html =~ alert.message
  end

  test "PubSub alert_acknowledged refreshes feed and unread count", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    Cache.put(cache_tables.accounts, wallet_address, account)

    alert =
      insert_alert!(%{
        "account_address" => wallet_address,
        "status" => "new",
        "message" => "Acknowledged by broadcast"
      })

    {:ok, view, _html} =
      mount_alerts_live(conn, wallet_address, cache_tables, pubsub)

    replacement =
      insert_alert!(%{
        "account_address" => wallet_address,
        "status" => "new",
        "message" => "Appears after acknowledge refresh"
      })

    assert {:ok, acknowledged} = Alerts.acknowledge_alert(alert.id, pubsub: pubsub)

    Phoenix.PubSub.broadcast(pubsub, Alerts.topic(wallet_address), {:alert_acknowledged, alert})

    html = render(view)
    assert html =~ replacement.message
    refute html =~ acknowledged.message
    assert html =~ "1 unread"
    refute html =~ "0 unread"
  end

  test "alerts feed renders InfiniteScroll sentinel contract", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    Cache.put(cache_tables.accounts, wallet_address, account)

    Enum.each(1..26, fn index ->
      insert_alert!(%{
        "account_address" => wallet_address,
        "message" => "Queued alert #{index}",
        "assembly_name" => "Queued Assembly #{index}"
      })
    end)

    assert {:ok, _view, html} =
             mount_alerts_live(conn, wallet_address, cache_tables, pubsub)

    assert html =~ ~s(id="alerts-feed-sentinel")
    assert html =~ ~s(phx-hook="InfiniteScroll")
    assert html =~ ~s(data-has-more="true")
    refute html =~ "No alerts yet"
  end

  test "load_more event appends next page of alerts", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    Cache.put(cache_tables.accounts, wallet_address, account)

    Enum.each(1..26, fn index ->
      label = String.pad_leading(Integer.to_string(index), 2, "0")

      insert_alert!(%{
        "account_address" => wallet_address,
        "message" => "Queued alert #{label}",
        "assembly_name" => "Queued Assembly #{label}"
      })
    end)

    {:ok, view, initial_html} =
      mount_alerts_live(conn, wallet_address, cache_tables, pubsub)

    assert initial_html =~ ~s(id="alerts-feed-sentinel")
    assert initial_html =~ ~s(data-has-more="true")
    refute initial_html =~ "Queued alert 01"
    assert initial_html =~ "Queued alert 26"

    html = render_hook(view, "load_more", %{})

    assert html =~ "Queued alert 01"
    assert html =~ "Queued alert 26"
    refute html =~ "No alerts yet"
  end

  test "exhausted alerts feed hides sentinel and stops load_more", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    Cache.put(cache_tables.accounts, wallet_address, account)

    Enum.each(1..26, fn index ->
      label = String.pad_leading(Integer.to_string(index), 2, "0")

      insert_alert!(%{
        "account_address" => wallet_address,
        "message" => "Exhaustion alert #{label}",
        "assembly_name" => "Exhaustion Assembly #{label}"
      })
    end)

    {:ok, view, _html} =
      mount_alerts_live(conn, wallet_address, cache_tables, pubsub)

    html = render_hook(view, "load_more", %{})

    assert html =~ ~s(data-has-more="false")
    assert html =~ ~s(id="alerts-feed-sentinel")
    assert html =~ "hidden"
    refute html =~ ~s(data-has-more="true")

    repeated_html = render_hook(view, "load_more", %{})

    assert repeated_html =~ ~s(data-has-more="false")
    assert repeated_html =~ ~s(id="alerts-feed-sentinel")
    assert repeated_html =~ "hidden"
    assert String.contains?(repeated_html, "Exhaustion alert 01")
    assert String.contains?(repeated_html, "Exhaustion alert 26")
    assert String.split(repeated_html, "Exhaustion alert 01") |> length() == 2
  end

  test "alerts page cannot mutate foreign account alert ids", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    Cache.put(cache_tables.accounts, wallet_address, account)

    foreign_alert =
      insert_alert!(%{
        "account_address" => unique_wallet_address(),
        "status" => "new",
        "message" => "Foreign mutation target"
      })

    {:ok, acknowledge_view, _html} =
      mount_alerts_live(conn, wallet_address, cache_tables, pubsub)

    acknowledge_html =
      render_click(acknowledge_view, "acknowledge", %{"id" => Integer.to_string(foreign_alert.id)})

    assert acknowledge_html =~ "Alert not found"
    assert Repo.get!(Alert, foreign_alert.id).status == "new"

    {:ok, dismiss_view, _html} =
      mount_alerts_live(conn, wallet_address, cache_tables, pubsub)

    dismiss_html =
      render_click(dismiss_view, "dismiss", %{"id" => Integer.to_string(foreign_alert.id)})

    assert dismiss_html =~ "Alert not found"
    assert Repo.get!(Alert, foreign_alert.id).status == "new"
  end

  @tag :acceptance
  test "full alerts journey: view, acknowledge, dismiss, real-time update", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub,
    wallet_address: wallet_address
  } do
    account = account_fixture(wallet_address)
    Cache.put(cache_tables.accounts, wallet_address, account)

    alert =
      insert_alert!(%{
        "account_address" => wallet_address,
        "status" => "new",
        "type" => "fuel_low",
        "severity" => "warning",
        "message" => "Journey alert",
        "assembly_name" => "Journey Assembly"
      })

    {:ok, view, html} =
      mount_alerts_live(conn, wallet_address, cache_tables, pubsub)

    assert html =~ "Journey alert"
    assert html =~ "Fuel Low"
    refute html =~ "No alerts yet"
    refute html =~ "Connect Your Wallet"

    acknowledged_html = render_click(view, "acknowledge", %{"id" => Integer.to_string(alert.id)})
    assert acknowledged_html =~ "border-space-600/80 bg-space-800/70"

    dismissed_html = render_click(view, "dismiss", %{"id" => Integer.to_string(alert.id)})
    refute dismissed_html =~ "Journey alert"

    fresh_alert =
      insert_alert!(%{
        "account_address" => wallet_address,
        "status" => "new",
        "message" => "Fresh realtime alert"
      })

    Phoenix.PubSub.broadcast(pubsub, Alerts.topic(wallet_address), {:alert_created, fresh_alert})

    refreshed_html = render(view)
    assert refreshed_html =~ "Fresh realtime alert"
    refute refreshed_html =~ "No alerts yet"
  end

  defp authenticated_conn(conn, wallet_address, cache_tables, pubsub) do
    init_test_session(conn, %{
      "wallet_address" => wallet_address,
      "cache_tables" => cache_tables,
      "pubsub" => pubsub
    })
  end

  defp mount_alerts_live(conn, wallet_address, cache_tables, pubsub) do
    {:ok, view, html} =
      live(authenticated_conn(conn, wallet_address, cache_tables, pubsub), "/alerts")

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

  defp account_fixture(wallet_address) do
    %Account{address: wallet_address, characters: [], tribe_id: nil}
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
        "assembly_id" => "assembly-#{unique}",
        "assembly_name" => "Assembly #{unique}",
        "account_address" => unique_wallet_address(),
        "tribe_id" => 42,
        "message" => "Alert #{unique}",
        "metadata" => %{"source" => "monitor"}
      },
      overrides
    )
  end

  defp unique_pubsub_name do
    :"alerts_live_pubsub_#{System.unique_integer([:positive])}"
  end

  defp unique_wallet_address do
    suffix =
      System.unique_integer([:positive])
      |> Integer.to_string(16)
      |> String.downcase()
      |> String.pad_leading(64, "0")

    "0x" <> suffix
  end
end
