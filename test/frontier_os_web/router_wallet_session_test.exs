defmodule FrontierOSWeb.RouterWalletSessionTest do
  @moduledoc """
  Covers the router and wallet session specifications across routes,
  controller actions, and on_mount behavior.
  """

  use FrontierOS.ConnCase, async: true

  import Hammox

  alias FrontierOS.{Accounts.Account, Cache}
  alias FrontierOS.Sui.Types.Assembly

  setup :verify_on_exit!

  setup do
    cache_pid = start_supervised!({Cache, tables: [:accounts, :characters, :assemblies]})
    pubsub = unique_pubsub_name()

    start_supervised!({Phoenix.PubSub, name: pubsub})

    {:ok,
     cache_tables: Cache.tables(cache_pid),
     pubsub: pubsub,
     wallet_address: unique_wallet_address()}
  end

  describe "router routes" do
    test "health check returns ok", %{conn: conn} do
      assert json_response(get(conn, "/api/health"), 200) == %{"status" => "ok"}
    end

    test "/ routes to DashboardLive", %{conn: conn} do
      assert {:ok, view, _html} = live(conn, "/")
      assert view.module == FrontierOSWeb.DashboardLive
    end

    test "/assembly/:id routes to AssemblyDetailLive", %{
      conn: conn,
      cache_tables: cache_tables,
      pubsub: pubsub,
      wallet_address: wallet_address
    } do
      account = %Account{address: wallet_address, characters: [], tribe_id: 314}
      assembly = Assembly.from_json(assembly_json())

      Cache.put(cache_tables.accounts, wallet_address, account)
      Cache.put(cache_tables.assemblies, assembly.id, {wallet_address, assembly})

      conn =
        init_test_session(conn, %{
          "wallet_address" => wallet_address,
          "cache_tables" => cache_tables,
          "pubsub" => pubsub
        })

      assert {:ok, view, _html} = live(conn, "/assembly/#{assembly.id}")
      assert view.module == FrontierOSWeb.AssemblyDetailLive
    end

    @tag :acceptance
    test "stale / session uses injected WalletSession deps", %{
      conn: conn,
      cache_tables: cache_tables,
      pubsub: pubsub,
      wallet_address: wallet_address
    } do
      conn =
        init_test_session(conn, %{
          "wallet_address" => wallet_address,
          "cache_tables" => cache_tables,
          "pubsub" => pubsub
        })

      assert {:ok, _view, html} = live(conn, "/")
      assert html =~ "Connect Your Wallet"
      refute html =~ wallet_address
      refute html =~ "System Online"
    end

    @tag :acceptance
    test "/ falls back to WalletSession default pubsub", %{
      conn: conn,
      cache_tables: cache_tables,
      wallet_address: wallet_address
    } do
      conn =
        init_test_session(conn, %{
          "wallet_address" => wallet_address,
          "cache_tables" => cache_tables
        })

      assert {:ok, _view, html} = live(conn, "/")
      assert html =~ "Connect Your Wallet"
      refute html =~ wallet_address
      refute html =~ "System Online"
    end

    test "/assembly/:id uses injected pubsub resources", %{
      conn: conn,
      cache_tables: cache_tables,
      pubsub: pubsub,
      wallet_address: wallet_address
    } do
      account = %Account{address: wallet_address, characters: [], tribe_id: 314}
      assembly = Assembly.from_json(assembly_json())

      Cache.put(cache_tables.accounts, wallet_address, account)
      Cache.put(cache_tables.assemblies, assembly.id, {wallet_address, assembly})

      conn =
        init_test_session(conn, %{
          "wallet_address" => wallet_address,
          "cache_tables" => cache_tables,
          "pubsub" => pubsub
        })

      assert {:ok, view, html} = live(conn, "/assembly/#{assembly.id}")
      assert view.module == FrontierOSWeb.AssemblyDetailLive
      refute html =~ "Assembly not found"
    end

    test "/assembly/:id falls back to default pubsub", %{
      conn: conn,
      cache_tables: cache_tables,
      wallet_address: wallet_address
    } do
      account = %Account{address: wallet_address, characters: [], tribe_id: 314}
      assembly = Assembly.from_json(assembly_json())

      Cache.put(cache_tables.accounts, wallet_address, account)
      Cache.put(cache_tables.assemblies, assembly.id, {wallet_address, assembly})

      conn =
        init_test_session(conn, %{
          "wallet_address" => wallet_address,
          "cache_tables" => cache_tables
        })

      assert {:ok, view, html} = live(conn, "/assembly/#{assembly.id}")
      assert view.module == FrontierOSWeb.AssemblyDetailLive
      refute html =~ "Assembly not found"
    end
  end

  describe "WalletSession.on_mount/4" do
    test "on_mount assigns current_account when session has a wallet address", %{
      cache_tables: cache_tables,
      pubsub: pubsub,
      wallet_address: wallet_address
    } do
      account = %Account{address: wallet_address, characters: [], tribe_id: 314}
      Cache.put(cache_tables.accounts, wallet_address, account)

      assert {:cont, socket} =
               FrontierOSWeb.WalletSession.on_mount(
                 :default,
                 %{},
                 %{
                   "wallet_address" => wallet_address,
                   "cache_tables" => cache_tables,
                   "pubsub" => pubsub
                 },
                 socket_fixture()
               )

      assert socket.assigns.current_account == account
      assert socket.assigns.cache_tables == cache_tables
      assert socket.assigns.pubsub == pubsub
    end

    test "on_mount assigns nil current_account when wallet is missing from cache", %{
      cache_tables: cache_tables,
      pubsub: pubsub,
      wallet_address: wallet_address
    } do
      assert {:cont, socket} =
               FrontierOSWeb.WalletSession.on_mount(
                 :default,
                 %{},
                 %{
                   "wallet_address" => wallet_address,
                   "cache_tables" => cache_tables,
                   "pubsub" => pubsub
                 },
                 socket_fixture()
               )

      assert socket.assigns.current_account == nil
      assert socket.assigns.cache_tables == cache_tables
      assert socket.assigns.pubsub == pubsub
    end

    test "on_mount assigns nil current_account when session is empty", %{
      cache_tables: cache_tables,
      pubsub: pubsub
    } do
      assert {:cont, socket} =
               FrontierOSWeb.WalletSession.on_mount(
                 :default,
                 %{},
                 %{"cache_tables" => cache_tables, "pubsub" => pubsub},
                 socket_fixture()
               )

      assert socket.assigns.current_account == nil
      assert socket.assigns.cache_tables == cache_tables
      assert socket.assigns.pubsub == pubsub
    end

    test "on_mount assigns default pubsub when session omits it", %{
      cache_tables: cache_tables
    } do
      assert {:cont, socket} =
               FrontierOSWeb.WalletSession.on_mount(
                 :default,
                 %{},
                 %{"cache_tables" => cache_tables},
                 socket_fixture()
               )

      assert socket.assigns.current_account == nil
      assert socket.assigns.cache_tables == cache_tables
      assert socket.assigns.pubsub == FrontierOS.PubSub
    end
  end

  describe "session controller" do
    @tag :acceptance
    test "posting a wallet address starts a session and redirects home", %{
      conn: conn,
      wallet_address: wallet_address
    } do
      expect(FrontierOS.Sui.ClientMock, :get_objects, fn _filters, _opts ->
        {:ok, %{data: [], has_next_page: false, end_cursor: nil}}
      end)

      conn =
        conn
        |> init_test_session(%{})
        |> post("/session", %{"wallet_address" => wallet_address})

      assert conn.status == 302
      assert redirected_to(conn) == "/"
      assert get_session(conn, :wallet_address) == wallet_address
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == nil
      refute get_session(conn, :wallet_address) == nil
    end

    @tag :acceptance
    test "POST /session with invalid address shows an error", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{})
        |> post("/session", %{"wallet_address" => "not-a-wallet"})

      assert conn.status == 302
      assert redirected_to(conn) == "/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Invalid wallet address"
      refute get_session(conn, :wallet_address) == "not-a-wallet"
    end

    @tag :acceptance
    test "DELETE /session clears the session and redirects home", %{
      conn: conn,
      wallet_address: wallet_address
    } do
      conn =
        conn
        |> init_test_session(%{wallet_address: wallet_address})
        |> delete("/session")

      assert conn.status == 302
      assert redirected_to(conn) == "/"
      assert get_session(conn, :wallet_address) == nil
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == nil
    end

    @tag :acceptance
    test "POST /session flashes a friendly timeout message", %{
      conn: conn,
      wallet_address: wallet_address
    } do
      expect(FrontierOS.Sui.ClientMock, :get_objects, fn _filters, _opts ->
        {:error, :timeout}
      end)

      conn =
        conn
        |> init_test_session(%{})
        |> post("/session", %{"wallet_address" => wallet_address})

      assert conn.status == 302
      assert redirected_to(conn) == "/"

      flash = Phoenix.Flash.get(conn.assigns.flash, :error)
      assert flash =~ "timeout reaching the chain service"
      refute flash =~ "inspect"
      refute get_session(conn, :wallet_address) == wallet_address
    end

    @tag :acceptance
    test "POST /session flashes a friendly message for graphql errors", %{
      conn: conn,
      wallet_address: wallet_address
    } do
      expect(FrontierOS.Sui.ClientMock, :get_objects, fn _filters, _opts ->
        {:error, {:graphql_errors, [%{"message" => "internal error"}]}}
      end)

      conn =
        conn
        |> init_test_session(%{})
        |> post("/session", %{"wallet_address" => wallet_address})

      assert conn.status == 302
      assert redirected_to(conn) == "/"

      flash = Phoenix.Flash.get(conn.assigns.flash, :error)
      assert flash =~ "chain query failed"
      refute flash =~ "graphql_errors"
      refute flash =~ "inspect"
      refute get_session(conn, :wallet_address) == wallet_address
    end
  end

  defp socket_fixture do
    %Phoenix.LiveView.Socket{endpoint: FrontierOSWeb.Endpoint}
  end

  defp unique_pubsub_name do
    :"wallet_session_pubsub_#{System.unique_integer([:positive])}"
  end

  defp unique_wallet_address do
    suffix =
      System.unique_integer([:positive])
      |> Integer.to_string(16)
      |> String.downcase()
      |> String.pad_leading(64, "0")

    "0x" <> suffix
  end

  defp assembly_json do
    %{
      "id" => uid("0xassembly-route"),
      "key" => %{"item_id" => "8", "tenant" => "0xassembly-tenant"},
      "owner_cap_id" => uid("0xassembly-owner"),
      "type_id" => "77",
      "status" => %{"status" => "OFFLINE"},
      "location" => %{"location_hash" => :binary.bin_to_list(:binary.copy(<<7>>, 32))},
      "energy_source_id" => "0xassembly-energy",
      "metadata" => %{
        "assembly_id" => "0xassembly-metadata",
        "name" => "Assembly One",
        "description" => "A test assembly",
        "url" => "https://example.test/assemblies/1"
      }
    }
  end

  defp uid(id), do: %{"id" => id}
end
