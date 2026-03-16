defmodule Sigil.AccountsTest do
  @moduledoc """
  Covers the packet 1 accounts context contract from the approved spec.
  """

  use ExUnit.Case, async: true

  import Hammox

  alias Sigil.{Accounts, Cache}
  alias Sigil.Sui.Types.Character

  @world_package_id "0xtest_world"

  setup :verify_on_exit!

  setup do
    cache_pid = start_supervised!({Cache, tables: [:accounts, :characters]})
    pubsub = unique_pubsub_name()
    character_type = expected_character_type()

    start_supervised!({Phoenix.PubSub, name: pubsub})
    :ok = Phoenix.PubSub.subscribe(pubsub, "accounts")

    {:ok, tables: Cache.tables(cache_pid), pubsub: pubsub, character_type: character_type}
  end

  describe "register_wallet/2" do
    test "register_wallet/2 caches account in ETS", %{
      tables: tables,
      pubsub: pubsub,
      character_type: character_type
    } do
      address = wallet_address()
      page = character_page([character_json()])

      expect(Sigil.Sui.ClientMock, :get_objects, fn [type: ^character_type, owner: ^address],
                                                    [] ->
        {:ok, page}
      end)

      assert {:ok, account} = Accounts.register_wallet(address, tables: tables, pubsub: pubsub)
      assert is_struct(account, Sigil.Accounts.Account)
      assert account.address == address
      assert Cache.get(tables.accounts, address) == account
    end

    test "register_wallet/2 queries characters from chain", %{
      tables: tables,
      pubsub: pubsub,
      character_type: character_type
    } do
      address = wallet_address()

      req_options = [
        url: "http://accounts.test/graphql",
        req_options: [plug: {Req.Test, :accounts_register_stub}]
      ]

      expect(Sigil.Sui.ClientMock, :get_objects, fn [type: ^character_type, owner: ^address],
                                                    ^req_options ->
        {:ok, character_page([character_json()])}
      end)

      assert {:ok, _account} =
               Accounts.register_wallet(address,
                 tables: tables,
                 pubsub: pubsub,
                 req_options: req_options
               )
    end

    test "register_wallet/2 parses and caches characters", %{
      tables: tables,
      pubsub: pubsub,
      character_type: character_type
    } do
      address = wallet_address()

      expect(Sigil.Sui.ClientMock, :get_objects, fn [type: ^character_type, owner: ^address],
                                                    [] ->
        {:ok,
         character_page([
           character_json(),
           character_json(%{"id" => uid("0xcharacter-2"), "tribe_id" => "271"})
         ])}
      end)

      assert {:ok, account} = Accounts.register_wallet(address, tables: tables, pubsub: pubsub)

      assert characters = Cache.get(tables.characters, address)
      assert characters == account.characters
      assert Enum.all?(characters, &is_struct(&1, Character))
      assert Enum.map(characters, & &1.id) == ["0xcharacter", "0xcharacter-2"]
    end

    test "register_wallet/2 broadcasts account_registered", %{
      tables: tables,
      pubsub: pubsub,
      character_type: character_type
    } do
      address = wallet_address()

      expect(Sigil.Sui.ClientMock, :get_objects, fn [type: ^character_type, owner: ^address],
                                                    [] ->
        {:ok, character_page([character_json()])}
      end)

      assert {:ok, account} = Accounts.register_wallet(address, tables: tables, pubsub: pubsub)
      assert_receive {:account_registered, ^account}
    end

    test "register_wallet/2 derives tribe_id from first character", %{
      tables: tables,
      pubsub: pubsub,
      character_type: character_type
    } do
      address = wallet_address()

      expect(Sigil.Sui.ClientMock, :get_objects, fn [type: ^character_type, owner: ^address],
                                                    [] ->
        {:ok,
         character_page([
           character_json(%{"tribe_id" => "314"}),
           character_json(%{"id" => uid("0xcharacter-2"), "tribe_id" => "999"})
         ])}
      end)

      assert {:ok, account} = Accounts.register_wallet(address, tables: tables, pubsub: pubsub)
      assert account.tribe_id == 314
    end

    test "register_wallet/2 returns error on chain failure", %{
      tables: tables,
      pubsub: pubsub,
      character_type: character_type
    } do
      address = wallet_address()

      expect(Sigil.Sui.ClientMock, :get_objects, fn [type: ^character_type, owner: ^address],
                                                    [] ->
        {:error, :timeout}
      end)

      assert Accounts.register_wallet(address, tables: tables, pubsub: pubsub) ==
               {:error, :timeout}

      assert Cache.get(tables.accounts, address) == nil
      assert Cache.get(tables.characters, address) == nil
      refute_receive {:account_registered, _account}
    end

    test "register_wallet/2 rejects invalid address format", %{tables: tables, pubsub: pubsub} do
      expect(Sigil.Sui.ClientMock, :get_objects, 0, fn _filters, _opts ->
        {:ok, character_page([])}
      end)

      Enum.each(invalid_wallet_addresses(), fn invalid_address ->
        assert Accounts.register_wallet(invalid_address, tables: tables, pubsub: pubsub) ==
                 {:error, :invalid_address}
      end)
    end

    test "register_wallet/2 handles address with no characters", %{
      tables: tables,
      pubsub: pubsub,
      character_type: character_type
    } do
      address = wallet_address()

      expect(Sigil.Sui.ClientMock, :get_objects, fn [type: ^character_type, owner: ^address],
                                                    [] ->
        {:ok, character_page([])}
      end)

      assert {:ok, account} = Accounts.register_wallet(address, tables: tables, pubsub: pubsub)
      assert account.characters == []
      assert account.tribe_id == nil
      assert Cache.get(tables.characters, address) == []
    end
  end

  describe "get_account/2" do
    test "get_account/2 returns cached account", %{
      tables: tables,
      pubsub: pubsub,
      character_type: character_type
    } do
      address = wallet_address()

      expect(Sigil.Sui.ClientMock, :get_objects, fn [type: ^character_type, owner: ^address],
                                                    [] ->
        {:ok, character_page([character_json()])}
      end)

      assert {:ok, registered_account} =
               Accounts.register_wallet(address, tables: tables, pubsub: pubsub)

      assert Accounts.get_account(address, tables: tables) == {:ok, registered_account}
    end

    test "get_account/2 returns error for unknown address", %{tables: tables} do
      assert Accounts.get_account(wallet_address(), tables: tables) == {:error, :not_found}
    end
  end

  describe "sync_from_chain/2" do
    test "sync_from_chain/2 updates cached account", %{
      tables: tables,
      pubsub: pubsub,
      character_type: character_type
    } do
      address = wallet_address()
      register_opts = [url: "http://accounts.test/register"]
      sync_opts = [url: "http://accounts.test/sync"]

      expect(Sigil.Sui.ClientMock, :get_objects, 2, fn [
                                                         type: ^character_type,
                                                         owner: ^address
                                                       ],
                                                       opts ->
        case opts do
          ^register_opts ->
            {:ok, character_page([character_json()])}

          ^sync_opts ->
            {:ok,
             character_page([
               character_json(%{"id" => uid("0xcharacter-updated"), "tribe_id" => "777"})
             ])}
        end
      end)

      assert {:ok, _account} =
               Accounts.register_wallet(address,
                 tables: tables,
                 pubsub: pubsub,
                 req_options: register_opts
               )

      assert {:ok, synced_account} =
               Accounts.sync_from_chain(address,
                 tables: tables,
                 pubsub: pubsub,
                 req_options: sync_opts
               )

      assert Cache.get(tables.accounts, address) == synced_account
      assert Enum.map(Cache.get(tables.characters, address), & &1.id) == ["0xcharacter-updated"]
      assert synced_account.tribe_id == 777
    end

    test "sync_from_chain/2 broadcasts account_updated", %{
      tables: tables,
      pubsub: pubsub,
      character_type: character_type
    } do
      address = wallet_address()
      register_opts = [url: "http://accounts.test/register"]
      sync_opts = [url: "http://accounts.test/sync"]

      expect(Sigil.Sui.ClientMock, :get_objects, 2, fn [
                                                         type: ^character_type,
                                                         owner: ^address
                                                       ],
                                                       opts ->
        case opts do
          ^register_opts ->
            {:ok, character_page([character_json()])}

          ^sync_opts ->
            {:ok, character_page([character_json(%{"id" => uid("0xcharacter-updated")})])}
        end
      end)

      assert {:ok, _account} =
               Accounts.register_wallet(address,
                 tables: tables,
                 pubsub: pubsub,
                 req_options: register_opts
               )

      assert {:ok, updated_account} =
               Accounts.sync_from_chain(address,
                 tables: tables,
                 pubsub: pubsub,
                 req_options: sync_opts
               )

      assert_receive {:account_updated, ^updated_account}
    end

    test "sync_from_chain/2 returns error for unregistered address", %{
      tables: tables,
      pubsub: pubsub
    } do
      expect(Sigil.Sui.ClientMock, :get_objects, 0, fn _filters, _opts ->
        {:ok, character_page([])}
      end)

      assert Accounts.sync_from_chain(wallet_address(), tables: tables, pubsub: pubsub) ==
               {:error, :not_found}
    end
  end

  @tag :acceptance
  test "full registration flow: register -> get_account returns complete data", %{
    tables: tables,
    pubsub: pubsub,
    character_type: character_type
  } do
    address = wallet_address()

    expect(Sigil.Sui.ClientMock, :get_objects, fn [type: ^character_type, owner: ^address], [] ->
      {:ok,
       character_page([
         character_json(%{"tribe_id" => "314"}),
         character_json(%{"id" => uid("0xcharacter-2"), "tribe_id" => "271"})
       ])}
    end)

    assert {:ok, registered_account} =
             Accounts.register_wallet(address, tables: tables, pubsub: pubsub)

    assert {:ok, fetched_account} = Accounts.get_account(address, tables: tables)
    assert fetched_account == registered_account
    assert fetched_account.address == address
    assert Enum.map(fetched_account.characters, & &1.id) == ["0xcharacter", "0xcharacter-2"]
    assert fetched_account.tribe_id == 314
    refute fetched_account.characters == []
    refute fetched_account.tribe_id == nil
  end

  defp expected_character_type do
    "#{@world_package_id}::character::Character"
  end

  defp unique_pubsub_name do
    :"accounts_pubsub_#{System.unique_integer([:positive])}"
  end

  defp wallet_address do
    "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  end

  defp invalid_wallet_addresses do
    [
      "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      "0xgggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggg"
    ]
  end

  defp character_page(characters_json) do
    %{data: characters_json, has_next_page: false, end_cursor: nil}
  end

  defp character_json(overrides \\ %{}) do
    Map.merge(
      %{
        "id" => uid("0xcharacter"),
        "key" => %{"item_id" => "10", "tenant" => "0xcharacter-tenant"},
        "tribe_id" => "314",
        "character_address" => "0xcharacter-address",
        "metadata" => %{
          "assembly_id" => "0xassembly-metadata",
          "name" => "Pilot One",
          "description" => "Character metadata",
          "url" => "https://example.test/characters/1"
        },
        "owner_cap_id" => uid("0xcharacter-owner")
      },
      overrides
    )
  end

  defp uid(id), do: %{"id" => id}
end
