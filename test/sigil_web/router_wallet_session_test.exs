defmodule SigilWeb.RouterWalletSessionTest do
  @moduledoc """
  Covers the router and wallet session specifications across routes,
  controller actions, and on_mount behavior.
  """

  use Sigil.ConnCase, async: true

  import Hammox

  alias Sigil.{Accounts.Account, Cache}
  alias Sigil.Sui.Types.{Assembly, Character}

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

  describe "router routes" do
    test "health check returns ok", %{conn: conn} do
      assert json_response(get(conn, "/api/health"), 200) == %{"status" => "ok"}
    end

    test "/ routes to DashboardLive", %{conn: conn} do
      assert {:ok, view, _html} = live(conn, "/")
      assert view.module == SigilWeb.DashboardLive
    end

    test "/tribe/:tribe_id routes to TribeOverviewLive", %{
      conn: conn,
      cache_tables: cache_tables,
      pubsub: pubsub,
      wallet_address: wallet_address
    } do
      char = %Character{
        id: "0xchar-tribe42",
        key: %Sigil.Sui.Types.TenantItemId{item_id: 1, tenant: "test"},
        tribe_id: 42,
        character_address: wallet_address,
        metadata: nil,
        owner_cap_id: "0xowner"
      }

      account = %Account{address: wallet_address, characters: [char], tribe_id: 42}
      Cache.put(cache_tables.accounts, wallet_address, account)

      conn =
        init_test_session(conn, %{
          "wallet_address" => wallet_address,
          "cache_tables" => cache_tables,
          "pubsub" => pubsub
        })

      assert {:ok, view, _html} = live(conn, "/tribe/42")
      assert view.module == SigilWeb.TribeOverviewLive
    end

    test "/tribe/:tribe_id/diplomacy routes to DiplomacyLive", %{
      conn: conn,
      cache_tables: cache_tables,
      pubsub: pubsub,
      wallet_address: wallet_address
    } do
      char = %Character{
        id: "0xchar-tribe42",
        key: %Sigil.Sui.Types.TenantItemId{item_id: 1, tenant: "test"},
        tribe_id: 42,
        character_address: wallet_address,
        metadata: nil,
        owner_cap_id: "0xowner"
      }

      account = %Account{address: wallet_address, characters: [char], tribe_id: 42}
      Cache.put(cache_tables.accounts, wallet_address, account)

      conn =
        init_test_session(conn, %{
          "wallet_address" => wallet_address,
          "cache_tables" => cache_tables,
          "pubsub" => pubsub
        })

      assert {:ok, view, _html} = live(conn, "/tribe/42/diplomacy")
      assert view.module == SigilWeb.DiplomacyLive
    end

    test "/tribe/:tribe_id/intel routes to IntelLive", %{
      conn: conn,
      cache_tables: cache_tables,
      pubsub: pubsub,
      wallet_address: wallet_address
    } do
      char = %Character{
        id: "0xchar-tribe42",
        key: %Sigil.Sui.Types.TenantItemId{item_id: 1, tenant: "test"},
        tribe_id: 42,
        character_address: wallet_address,
        metadata: nil,
        owner_cap_id: "0xowner"
      }

      account = %Account{address: wallet_address, characters: [char], tribe_id: 42}
      Cache.put(cache_tables.accounts, wallet_address, account)

      conn =
        init_test_session(conn, %{
          "wallet_address" => wallet_address,
          "cache_tables" => cache_tables,
          "pubsub" => pubsub
        })

      assert {:ok, view, _html} = live(conn, "/tribe/42/intel")
      assert view.module == SigilWeb.IntelLive
    end

    test "tribe routes reject mismatched active character tribe even when account tribe differs",
         %{
           conn: conn,
           cache_tables: cache_tables,
           pubsub: pubsub,
           wallet_address: wallet_address
         } do
      first =
        %Character{
          id: "0xchar-tribe42",
          key: %Sigil.Sui.Types.TenantItemId{item_id: 1, tenant: "test"},
          tribe_id: 42,
          character_address: wallet_address,
          metadata: nil,
          owner_cap_id: "0xowner-1"
        }

      second =
        %Character{
          id: "0xchar-no-tribe",
          key: %Sigil.Sui.Types.TenantItemId{item_id: 2, tenant: "test"},
          tribe_id: nil,
          character_address: wallet_address,
          metadata: nil,
          owner_cap_id: "0xowner-2"
        }

      account = %Account{address: wallet_address, characters: [first, second], tribe_id: 42}
      Cache.put(cache_tables.accounts, wallet_address, account)

      conn =
        init_test_session(conn, %{
          "wallet_address" => wallet_address,
          "active_character_id" => second.id,
          "cache_tables" => cache_tables,
          "pubsub" => pubsub
        })

      assert {:error, {:redirect, %{to: "/", flash: %{"error" => "Not your tribe"}}}} =
               live(conn, "/tribe/42")

      assert {:error,
              {:redirect, %{to: "/", flash: %{"error" => "Tribe Custodian access denied"}}}} =
               live(conn, "/tribe/42/diplomacy")

      assert {:error, {:redirect, %{to: "/", flash: %{"error" => "Not your tribe"}}}} =
               live(conn, "/tribe/42/intel")
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
      assert view.module == SigilWeb.AssemblyDetailLive
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
      assert view.module == SigilWeb.AssemblyDetailLive
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
      assert view.module == SigilWeb.AssemblyDetailLive
      refute html =~ "Assembly not found"
    end

    test "PUT /session/character/:character_id routes to SessionController", %{
      conn: conn,
      cache_tables: cache_tables,
      pubsub: pubsub,
      wallet_address: wallet_address
    } do
      first =
        character_fixture(%{"id" => uid("0xcharacter-1"), "character_address" => wallet_address})

      second =
        character_fixture(%{
          "id" => uid("0xcharacter-2"),
          "character_address" => wallet_address,
          "tribe_id" => "271"
        })

      account = account_fixture(wallet_address, [first, second])
      Cache.put(cache_tables.accounts, wallet_address, account)

      conn =
        conn
        |> init_test_session(%{
          "wallet_address" => wallet_address,
          "cache_tables" => cache_tables,
          "pubsub" => pubsub
        })
        |> put("/session/character/#{second.id}")

      assert conn.status == 302
      assert redirected_to(conn) == "/"
      assert get_session(conn, :active_character_id) == second.id
      refute get_session(conn, :active_character_id) == first.id
    end

    test "character switch route enforces CSRF protection" do
      assert %{
               plug: SigilWeb.SessionController,
               plug_opts: :update_character,
               route: "/session/character/:character_id",
               pipe_through: [:browser]
             } =
               Phoenix.Router.route_info(
                 SigilWeb.Router,
                 "PUT",
                 "/session/character/0xcharacter-1",
                 "localhost"
               )
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
               SigilWeb.WalletSession.on_mount(
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
               SigilWeb.WalletSession.on_mount(
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
               SigilWeb.WalletSession.on_mount(
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
               SigilWeb.WalletSession.on_mount(
                 :default,
                 %{},
                 %{"cache_tables" => cache_tables},
                 socket_fixture()
               )

      assert socket.assigns.current_account == nil
      assert socket.assigns.cache_tables == cache_tables
      assert socket.assigns.pubsub == Sigil.PubSub
    end

    test "on_mount assigns active_character matching session character_id", %{
      cache_tables: cache_tables,
      pubsub: pubsub,
      wallet_address: wallet_address
    } do
      first =
        character_fixture(%{"id" => uid("0xcharacter-1"), "character_address" => wallet_address})

      second =
        character_fixture(%{
          "id" => uid("0xcharacter-2"),
          "character_address" => wallet_address,
          "tribe_id" => "271"
        })

      account = account_fixture(wallet_address, [first, second])
      Cache.put(cache_tables.accounts, wallet_address, account)

      assert {:cont, socket} =
               SigilWeb.WalletSession.on_mount(
                 :default,
                 %{},
                 %{
                   "wallet_address" => wallet_address,
                   "active_character_id" => second.id,
                   "cache_tables" => cache_tables,
                   "pubsub" => pubsub
                 },
                 socket_fixture()
               )

      assert socket.assigns.current_account == account
      assert socket.assigns.active_character == second
      assert socket.assigns.cache_tables == cache_tables
      assert socket.assigns.pubsub == pubsub
    end

    test "on_mount assigns first character when no active_character_id in session", %{
      cache_tables: cache_tables,
      pubsub: pubsub,
      wallet_address: wallet_address
    } do
      first =
        character_fixture(%{"id" => uid("0xcharacter-1"), "character_address" => wallet_address})

      second =
        character_fixture(%{
          "id" => uid("0xcharacter-2"),
          "character_address" => wallet_address,
          "tribe_id" => "271"
        })

      account = account_fixture(wallet_address, [first, second])
      Cache.put(cache_tables.accounts, wallet_address, account)

      assert {:cont, socket} =
               SigilWeb.WalletSession.on_mount(
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
      assert socket.assigns.active_character == first
      refute socket.assigns.active_character == second
    end

    test "on_mount assigns nil active_character when not authenticated", %{
      cache_tables: cache_tables,
      pubsub: pubsub
    } do
      assert {:cont, socket} =
               SigilWeb.WalletSession.on_mount(
                 :default,
                 %{},
                 %{"cache_tables" => cache_tables, "pubsub" => pubsub},
                 socket_fixture()
               )

      assert socket.assigns.current_account == nil
      assert socket.assigns.active_character == nil
      assert socket.assigns.cache_tables == cache_tables
      assert socket.assigns.pubsub == pubsub
    end
  end

  describe "session controller" do
    test "valid wallet verification redirects user to dashboard", %{
      conn: conn,
      cache_tables: cache_tables,
      pubsub: pubsub,
      wallet_address: wallet_address
    } do
      nonce = "session-success-nonce"
      seed_nonce(cache_tables, nonce, wallet_address)

      expect(Sigil.Sui.ClientMock, :verify_zklogin_signature, fn _bytes,
                                                                 @zklogin_sig,
                                                                 "PERSONAL_MESSAGE",
                                                                 ^wallet_address,
                                                                 [] ->
        {:ok, %{"verifyZkLoginSignature" => %{"success" => true}}}
      end)

      expect(Sigil.Sui.ClientMock, :get_objects, fn _filters, _opts ->
        {:ok, %{data: [], has_next_page: false, end_cursor: nil}}
      end)

      conn =
        conn
        |> init_test_session(%{"cache_tables" => cache_tables, "pubsub" => pubsub})
        |> post("/session", signed_auth_params(wallet_address, nonce))

      assert conn.status == 302
      assert redirected_to(conn) == "/"
      assert get_session(conn, :wallet_address) == wallet_address
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == nil
      refute get_session(conn, :wallet_address) == nil
    end

    test "missing params shows invalid request error message", %{
      conn: conn,
      cache_tables: cache_tables,
      pubsub: pubsub,
      wallet_address: wallet_address
    } do
      stub(Sigil.Sui.ClientMock, :get_objects, fn _filters, _opts ->
        {:ok, %{data: [], has_next_page: false, end_cursor: nil}}
      end)

      conn =
        conn
        |> init_test_session(%{"cache_tables" => cache_tables, "pubsub" => pubsub})
        |> post("/session", %{"wallet_address" => wallet_address, "nonce" => "missing-bytes"})

      assert conn.status == 302
      assert redirected_to(conn) == "/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Invalid authentication request"
      refute get_session(conn, :wallet_address) == wallet_address
    end

    test "unknown nonce shows authentication expired message", %{
      conn: conn,
      cache_tables: cache_tables,
      pubsub: pubsub,
      wallet_address: wallet_address
    } do
      stub(Sigil.Sui.ClientMock, :get_objects, fn _filters, _opts ->
        {:ok, %{data: [], has_next_page: false, end_cursor: nil}}
      end)

      conn =
        conn
        |> init_test_session(%{"cache_tables" => cache_tables, "pubsub" => pubsub})
        |> post("/session", signed_auth_params(wallet_address, "unknown-nonce"))

      assert conn.status == 302
      assert redirected_to(conn) == "/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Authentication expired"
      refute get_session(conn, :wallet_address) == wallet_address
    end

    test "expired nonce shows authentication expired message", %{
      conn: conn,
      cache_tables: cache_tables,
      pubsub: pubsub,
      wallet_address: wallet_address
    } do
      nonce = "expired-session-nonce"

      seed_nonce(cache_tables, nonce, wallet_address,
        created_at: System.monotonic_time(:millisecond) - 300_001
      )

      stub(Sigil.Sui.ClientMock, :get_objects, fn _filters, _opts ->
        {:ok, %{data: [], has_next_page: false, end_cursor: nil}}
      end)

      conn =
        conn
        |> init_test_session(%{"cache_tables" => cache_tables, "pubsub" => pubsub})
        |> post("/session", signed_auth_params(wallet_address, nonce))

      assert conn.status == 302
      assert redirected_to(conn) == "/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Authentication expired"
      refute get_session(conn, :wallet_address) == wallet_address
    end

    test "address mismatch shows authentication failed message", %{
      conn: conn,
      cache_tables: cache_tables,
      pubsub: pubsub,
      wallet_address: wallet_address
    } do
      nonce = "mismatch-session-nonce"
      seed_nonce(cache_tables, nonce, alternate_wallet_address())

      stub(Sigil.Sui.ClientMock, :get_objects, fn _filters, _opts ->
        {:ok, %{data: [], has_next_page: false, end_cursor: nil}}
      end)

      conn =
        conn
        |> init_test_session(%{"cache_tables" => cache_tables, "pubsub" => pubsub})
        |> post("/session", signed_auth_params(wallet_address, nonce))

      assert conn.status == 302
      assert redirected_to(conn) == "/"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "Authentication failed — address mismatch"

      refute get_session(conn, :wallet_address) == wallet_address
    end

    test "tampered message bytes shows authentication failed message", %{
      conn: conn,
      cache_tables: cache_tables,
      pubsub: pubsub,
      wallet_address: wallet_address
    } do
      nonce = "tampered-bytes-session-nonce"
      seed_nonce(cache_tables, nonce, wallet_address)

      conn =
        conn
        |> init_test_session(%{"cache_tables" => cache_tables, "pubsub" => pubsub})
        |> post("/session", %{
          "wallet_address" => wallet_address,
          "bytes" => Base.encode64("Approve transaction: transfer 100 SUI"),
          "signature" => zklogin_signature(),
          "nonce" => nonce
        })

      assert conn.status == 302
      assert redirected_to(conn) == "/"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "Authentication failed — message tampered"

      refute get_session(conn, :wallet_address) == wallet_address
    end

    test "chain registration failure shows friendly error to user", %{
      conn: conn,
      cache_tables: cache_tables,
      pubsub: pubsub,
      wallet_address: wallet_address
    } do
      nonce = "registration-failure-session-nonce"
      seed_nonce(cache_tables, nonce, wallet_address)

      expect(Sigil.Sui.ClientMock, :verify_zklogin_signature, fn _, _, _, _, [] ->
        {:ok, %{"verifyZkLoginSignature" => %{"success" => true}}}
      end)

      # zkLogin auth succeeds, then get_objects fails during registration.
      expect(Sigil.Sui.ClientMock, :get_objects, fn _filters, _opts ->
        {:error, {:graphql_errors, [%{"message" => "internal error"}]}}
      end)

      conn =
        conn
        |> init_test_session(%{"cache_tables" => cache_tables, "pubsub" => pubsub})
        |> post("/session", signed_auth_params(wallet_address, nonce))

      assert conn.status == 302
      assert redirected_to(conn) == "/"

      flash = Phoenix.Flash.get(conn.assigns.flash, :error)
      assert flash =~ "chain query failed"
      refute flash =~ "graphql_errors"
      refute flash =~ "inspect"
      refute get_session(conn, :wallet_address) == wallet_address
    end

    test "in-game context redirects user to assembly detail after auth", %{
      conn: conn,
      cache_tables: cache_tables,
      pubsub: pubsub,
      wallet_address: wallet_address
    } do
      nonce = "assembly-redirect-session-nonce"

      seed_nonce(cache_tables, nonce, wallet_address,
        item_id: "0xassembly-route",
        tenant: "stillness"
      )

      expect(Sigil.Sui.ClientMock, :verify_zklogin_signature, fn _, _, _, _, [] ->
        {:ok, %{"verifyZkLoginSignature" => %{"success" => true}}}
      end)

      expect(Sigil.Sui.ClientMock, :get_objects, fn _filters, _opts ->
        {:ok, %{data: [], has_next_page: false, end_cursor: nil}}
      end)

      conn =
        conn
        |> init_test_session(%{"cache_tables" => cache_tables, "pubsub" => pubsub})
        |> post("/session", signed_auth_params(wallet_address, nonce))

      assert conn.status == 302
      assert redirected_to(conn) == "/assembly/0xassembly-route"
      assert get_session(conn, :wallet_address) == wallet_address
      refute Phoenix.Flash.get(conn.assigns.flash, :error)
    end

    test "invalid signature shows wallet verification error message", %{
      conn: conn,
      cache_tables: cache_tables,
      pubsub: pubsub,
      wallet_address: wallet_address
    } do
      nonce = "invalid-sig-session-nonce"
      seed_nonce(cache_tables, nonce, wallet_address)

      expect(Sigil.Sui.ClientMock, :verify_zklogin_signature, fn _, _, _, _, [] ->
        {:ok, %{"verifyZkLoginSignature" => %{"success" => false}}}
      end)

      conn =
        conn
        |> init_test_session(%{"cache_tables" => cache_tables, "pubsub" => pubsub})
        |> post("/session", signed_auth_params(wallet_address, nonce))

      assert conn.status == 302
      assert redirected_to(conn) == "/"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "Wallet signature could not be verified"

      refute get_session(conn, :wallet_address) == wallet_address
    end

    test "Sui endpoint timeout shows friendly timeout message", %{
      conn: conn,
      cache_tables: cache_tables,
      pubsub: pubsub,
      wallet_address: wallet_address
    } do
      nonce = "timeout-session-nonce"
      seed_nonce(cache_tables, nonce, wallet_address)

      expect(Sigil.Sui.ClientMock, :verify_zklogin_signature, fn _, _, _, _, [] ->
        {:error, :timeout}
      end)

      conn =
        conn
        |> init_test_session(%{"cache_tables" => cache_tables, "pubsub" => pubsub})
        |> post("/session", signed_auth_params(wallet_address, nonce))

      assert conn.status == 302
      assert redirected_to(conn) == "/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "timeout reaching the chain service"
      refute get_session(conn, :wallet_address) == wallet_address
    end

    @tag :acceptance
    test "PUT /session/character stores active_character_id and redirects", %{
      conn: conn,
      cache_tables: cache_tables,
      pubsub: pubsub,
      wallet_address: wallet_address
    } do
      first =
        character_fixture(%{"id" => uid("0xcharacter-1"), "character_address" => wallet_address})

      second =
        character_fixture(%{
          "id" => uid("0xcharacter-2"),
          "character_address" => wallet_address,
          "tribe_id" => "271"
        })

      account = account_fixture(wallet_address, [first, second])
      Cache.put(cache_tables.accounts, wallet_address, account)

      conn =
        conn
        |> init_test_session(%{
          "wallet_address" => wallet_address,
          "cache_tables" => cache_tables,
          "pubsub" => pubsub
        })
        |> put("/session/character/#{second.id}")

      assert conn.status == 302
      assert redirected_to(conn) == "/"
      assert get_session(conn, :active_character_id) == second.id
      refute get_session(conn, :active_character_id) == first.id
    end

    test "PUT /session/character ignores character_id not in account", %{
      conn: conn,
      cache_tables: cache_tables,
      pubsub: pubsub,
      wallet_address: wallet_address
    } do
      first =
        character_fixture(%{"id" => uid("0xcharacter-1"), "character_address" => wallet_address})

      account = account_fixture(wallet_address, [first])
      Cache.put(cache_tables.accounts, wallet_address, account)

      conn =
        conn
        |> init_test_session(%{
          "wallet_address" => wallet_address,
          "active_character_id" => first.id,
          "cache_tables" => cache_tables,
          "pubsub" => pubsub
        })
        |> put("/session/character/0xmissing-character")

      assert conn.status == 302
      assert redirected_to(conn) == "/"
      assert get_session(conn, :active_character_id) == first.id
      refute get_session(conn, :active_character_id) == "0xmissing-character"
    end

    test "PUT /session/character redirects without session when not authenticated", %{
      conn: conn,
      cache_tables: cache_tables,
      pubsub: pubsub
    } do
      conn =
        conn
        |> init_test_session(%{"cache_tables" => cache_tables, "pubsub" => pubsub})
        |> put("/session/character/0xmissing-character")

      assert conn.status == 302
      assert redirected_to(conn) == "/"
      assert get_session(conn, :wallet_address) == nil
      assert get_session(conn, :active_character_id) == nil
    end

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
  end

  defp socket_fixture do
    %Phoenix.LiveView.Socket{endpoint: SigilWeb.Endpoint}
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

  defp alternate_wallet_address do
    "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  end

  defp signed_auth_params(wallet_address, nonce) do
    message = challenge_message(nonce)

    %{
      "wallet_address" => wallet_address,
      "bytes" => Base.encode64(message),
      "signature" => zklogin_signature(),
      "nonce" => nonce
    }
  end

  # Base64-encoded bytes starting with zkLogin scheme byte (0x05)
  defp zklogin_signature, do: Base.encode64(<<0x05, 0::size(320)>>)

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

  defp account_fixture(address, characters) do
    %Account{address: address, characters: characters, tribe_id: first_tribe_id(characters)}
  end

  defp character_fixture(overrides) do
    overrides
    |> character_json()
    |> Character.from_json()
  end

  defp first_tribe_id([%Character{tribe_id: tribe_id} | _rest]), do: tribe_id
  defp first_tribe_id([]), do: nil

  defp character_json(overrides) do
    Map.merge(
      %{
        "id" => uid("0xcharacter"),
        "key" => %{"item_id" => "10", "tenant" => "0xcharacter-tenant"},
        "tribe_id" => "314",
        "character_address" => "0xcharacter-address",
        "metadata" => %{
          "assembly_id" => "0xcharacter-metadata",
          "name" => "Pilot One",
          "description" => "Character metadata",
          "url" => "https://example.test/characters/1"
        },
        "owner_cap_id" => uid("0xcharacter-owner")
      },
      overrides
    )
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
