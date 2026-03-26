defmodule Sigil.IntelMarketTest do
  @moduledoc """
  Verifies intel marketplace context behavior.
  """

  use Sigil.DataCase, async: true

  import Hammox

  @compile {:no_warn_undefined, Sigil.IntelMarket}

  alias Sigil.{Cache, Repo}
  alias Sigil.Intel.IntelListing
  alias Sigil.Intel.IntelReport
  alias Sigil.Sui.{TransactionBuilder, TxIntelMarket}

  @marketplace_topic "intel_market"
  @sigil_package_id "0x06ce9d6bed77615383575cc7eba4883d32769b30cd5df00561e38434a59611a1"
  @marketplace_type "#{@sigil_package_id}::intel_market::IntelMarketplace"
  @listing_type "#{@sigil_package_id}::intel_market::IntelListing"
  @tribe_id 77
  @other_tribe_id 88

  setup :verify_on_exit!

  setup do
    cache_pid = start_supervised!({Cache, tables: [:intel_market, :standings]})
    pubsub = unique_pubsub_name()

    start_supervised!({Phoenix.PubSub, name: pubsub})
    :ok = Phoenix.PubSub.subscribe(pubsub, @marketplace_topic)

    {:ok,
     tables: Cache.tables(cache_pid),
     pubsub: pubsub,
     seller: address(0xA1),
     buyer: address(0xB2),
     tribe_id: @tribe_id,
     other_tribe_id: @other_tribe_id}
  end

  describe "discover_marketplace/1" do
    test "discover_marketplace caches marketplace info in ETS", context do
      expect(Sigil.Sui.ClientMock, :get_objects, fn [type: @marketplace_type], [] ->
        {:ok, page([marketplace_object_json(object_id: address(0x11))])}
      end)

      assert {:ok, marketplace} = Sigil.IntelMarket.discover_marketplace(market_opts(context))
      assert marketplace.object_id == address(0x11)
      assert marketplace.initial_shared_version == 7

      assert Cache.get(context.tables.intel_market, {:marketplace}) == marketplace
      assert_receive {:marketplace_discovered, ^marketplace}
    end
  end

  describe "sync_listings/1" do
    test "sync_listings persists listings with seal fields and preserves local linkage",
         context do
      intel_report_id = Ecto.UUID.generate()

      persisted_listing =
        insert_listing!(%{
          id: address(0x31),
          seller_address: context.seller,
          seal_id: seal_id_hex(0x10),
          encrypted_blob_id: "walrus-persisted-10",
          client_nonce: 7,
          price_mist: 10,
          intel_report_id: intel_report_id,
          description: "stale"
        })

      set_listing_inserted_at!(persisted_listing.id, ~U[2026-03-20 00:00:01.000000Z])

      chain_listing =
        listing_object_json(
          id: address(0x31),
          seller: context.seller,
          seal_id: seal_id_hex(0x91),
          encrypted_blob_id: "walrus-chain-999999999",
          client_nonce: 44,
          price: 125_000_000,
          report_type: 2,
          solar_system_id: 30_001_042,
          description: "Fresh chain listing",
          initial_shared_version: 13
        )

      new_listing =
        listing_object_json(
          id: address(0x32),
          seller: address(0xA2),
          seal_id: seal_id_hex(0x92),
          encrypted_blob_id: "walrus-new-123456789",
          client_nonce: 45,
          price: 225_000_000,
          report_type: 1,
          solar_system_id: 30_001_043,
          description: "New market listing",
          initial_shared_version: 14
        )

      expect(Sigil.Sui.ClientMock, :get_objects, fn [type: @listing_type], [] ->
        {:ok, page([chain_listing, new_listing])}
      end)

      assert {:ok, listings} = Sigil.IntelMarket.sync_listings(market_opts(context))
      assert Enum.map(listings, & &1.id) == [address(0x31), address(0x32)]

      persisted = Repo.get!(IntelListing, address(0x31))
      created = Repo.get!(IntelListing, address(0x32))

      assert persisted.intel_report_id == intel_report_id
      assert persisted.seal_id == seal_id_hex(0x91)
      assert persisted.encrypted_blob_id == "walrus-chain-999999999"
      assert persisted.price_mist == 125_000_000
      assert persisted.client_nonce == 44
      assert persisted.description == "Fresh chain listing"
      assert persisted.status == :active

      assert created.seller_address == address(0xA2)
      assert created.seal_id == seal_id_hex(0x92)
      assert created.encrypted_blob_id == "walrus-new-123456789"

      assert Cache.get(context.tables.intel_market, {:listing, address(0x31)}).id == address(0x31)
      assert Cache.get(context.tables.intel_market, {:listing, address(0x32)}).id == address(0x32)
      refute_receive {:listing_removed, _}
    end

    test "sync_listings removes stale listings when stale_grace_ms is zero", context do
      stale_listing_id = address(0x30)

      insert_listing!(%{
        id: stale_listing_id,
        seller_address: address(0xAF),
        seal_id: seal_id_hex(0x09),
        encrypted_blob_id: "walrus-stale-9",
        client_nonce: 6,
        price_mist: 9,
        description: "remove me"
      })

      Cache.put(
        context.tables.intel_market,
        {:listing, stale_listing_id},
        %IntelListing{id: stale_listing_id}
      )

      Cache.put(
        context.tables.intel_market,
        {:listing_ref, stale_listing_id},
        %{object_id: object_id(0x30), initial_shared_version: 12}
      )

      fresh_chain_listing =
        listing_object_json(
          id: address(0x33),
          seller: address(0xA3),
          seal_id: seal_id_hex(0x93),
          encrypted_blob_id: "walrus-fresh-123456789",
          client_nonce: 46,
          price: 325_000_000,
          report_type: 1,
          solar_system_id: 30_001_044,
          description: "Fresh market listing",
          initial_shared_version: 15
        )

      expect(Sigil.Sui.ClientMock, :get_objects, fn [type: @listing_type], [] ->
        {:ok, page([fresh_chain_listing])}
      end)

      assert {:ok, listings} =
               Sigil.IntelMarket.sync_listings(market_opts(context, stale_grace_ms: 0))

      assert Enum.map(listings, & &1.id) == [address(0x33)]
      assert Repo.get(IntelListing, stale_listing_id) == nil
      assert Cache.get(context.tables.intel_market, {:listing, stale_listing_id}) == nil
      assert Cache.get(context.tables.intel_market, {:listing_ref, stale_listing_id}) == nil
      assert_receive {:listing_removed, ^stale_listing_id}
    end

    test "sync_listings preserves freshly reconciled listings not yet visible on chain",
         context do
      fresh_listing_id = address(0x35)

      insert_listing!(%{
        id: fresh_listing_id,
        seller_address: context.seller,
        seal_id: seal_id_hex(0x93),
        encrypted_blob_id: "walrus-fresh-1234567890",
        client_nonce: 99,
        price_mist: 150_000_000,
        description: "freshly created",
        inserted_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now()
      })

      Cache.put(context.tables.intel_market, {:listing, fresh_listing_id}, %IntelListing{
        id: fresh_listing_id
      })

      Cache.put(
        context.tables.intel_market,
        {:listing_ref, fresh_listing_id},
        %{object_id: object_id(0x35), initial_shared_version: 33}
      )

      chain_listing =
        listing_object_json(id: address(0x36), seller: address(0xA6), initial_shared_version: 17)

      expect(Sigil.Sui.ClientMock, :get_objects, fn [type: @listing_type], [] ->
        {:ok, page([chain_listing])}
      end)

      assert {:ok, listings} = Sigil.IntelMarket.sync_listings(market_opts(context))

      assert Enum.map(listings, & &1.id) == [address(0x36)]
      assert Repo.get!(IntelListing, fresh_listing_id).description == "freshly created"

      assert Cache.get(context.tables.intel_market, {:listing, fresh_listing_id}).id ==
               fresh_listing_id

      assert Cache.get(context.tables.intel_market, {:listing_ref, fresh_listing_id}).initial_shared_version ==
               33
    end

    test "sync_listings paginates through all pages", context do
      first_page_listing =
        listing_object_json(id: address(0x33), seller: address(0xA3), initial_shared_version: 15)

      second_page_listing =
        listing_object_json(id: address(0x34), seller: address(0xA4), initial_shared_version: 16)

      expect(Sigil.Sui.ClientMock, :get_objects, fn filters, [] ->
        assert Keyword.get(filters, :type) == @listing_type
        assert Keyword.get(filters, :cursor) == nil

        {:ok, %{data: [first_page_listing], has_next_page: true, end_cursor: "cursor-1"}}
      end)

      expect(Sigil.Sui.ClientMock, :get_objects, fn filters, [] ->
        assert Keyword.get(filters, :type) == @listing_type
        assert Keyword.get(filters, :cursor) == "cursor-1"

        {:ok, %{data: [second_page_listing], has_next_page: false, end_cursor: nil}}
      end)

      assert {:ok, listings} = Sigil.IntelMarket.sync_listings(market_opts(context))

      assert Enum.map(listings, & &1.id) == [address(0x33), address(0x34)]
      assert Repo.get!(IntelListing, address(0x33)).seller_address == address(0xA3)
      assert Repo.get!(IntelListing, address(0x34)).seller_address == address(0xA4)
    end
  end

  describe "list_listings/1" do
    test "list_listings returns active listings ordered by newest", context do
      older_active = insert_listing!(%{id: address(0x41), status: :active, description: "older"})
      _sold = insert_listing!(%{id: address(0x42), status: :sold, description: "sold"})
      newer_active = insert_listing!(%{id: address(0x43), status: :active, description: "newer"})

      set_listing_inserted_at!(older_active.id, ~U[2026-03-20 00:00:00.000000Z])
      set_listing_inserted_at!(address(0x42), ~U[2026-03-21 00:00:00.000000Z])
      set_listing_inserted_at!(newer_active.id, ~U[2026-03-22 00:00:00.000000Z])

      listings = Sigil.IntelMarket.list_listings(market_opts(context))

      assert Enum.map(listings, & &1.id) == [newer_active.id, older_active.id]
      refute Enum.any?(listings, &(&1.status != :active))
    end

    test "list_seller_listings returns seller listings across statuses", context do
      seller = context.seller

      active_listing =
        insert_listing!(%{id: address(0x44), seller_address: seller, status: :active})

      sold_listing = insert_listing!(%{id: address(0x45), seller_address: seller, status: :sold})

      cancelled_listing =
        insert_listing!(%{id: address(0x46), seller_address: seller, status: :cancelled})

      _other_listing =
        insert_listing!(%{id: address(0x47), seller_address: address(0xDE), status: :active})

      set_listing_inserted_at!(active_listing.id, ~U[2026-03-20 00:00:00.000000Z])
      set_listing_inserted_at!(sold_listing.id, ~U[2026-03-21 00:00:00.000000Z])
      set_listing_inserted_at!(cancelled_listing.id, ~U[2026-03-22 00:00:00.000000Z])

      listings = Sigil.IntelMarket.list_seller_listings(seller, market_opts(context))

      assert Enum.map(listings, & &1.id) == [
               cancelled_listing.id,
               sold_listing.id,
               active_listing.id
             ]
    end

    test "list_purchased_listings returns buyer purchases", context do
      buyer = context.buyer

      older_purchase =
        insert_listing!(%{
          id: address(0x48),
          buyer_address: buyer,
          status: :sold,
          seller_address: address(0xD1)
        })

      newer_purchase =
        insert_listing!(%{
          id: address(0x49),
          buyer_address: buyer,
          status: :sold,
          seller_address: address(0xD2)
        })

      _active_listing =
        insert_listing!(%{id: address(0x4A), buyer_address: buyer, status: :active})

      _other_buyer =
        insert_listing!(%{id: address(0x4B), buyer_address: address(0xEF), status: :sold})

      set_listing_inserted_at!(older_purchase.id, ~U[2026-03-20 00:00:00.000000Z])
      set_listing_inserted_at!(newer_purchase.id, ~U[2026-03-21 00:00:00.000000Z])

      listings = Sigil.IntelMarket.list_purchased_listings(buyer, market_opts(context))

      assert Enum.map(listings, & &1.id) == [newer_purchase.id, older_purchase.id]
      assert Enum.all?(listings, &(&1.status == :sold))
    end
  end

  describe "blob_available?/2" do
    test "blob_available? returns Walrus availability for listing blob", context do
      listing =
        insert_listing!(%{
          id: address(0x58),
          encrypted_blob_id: "walrus-available-blob"
        })

      assert Sigil.IntelMarket.blob_available?(
               listing.id,
               market_opts(context, walrus_client: Sigil.TestSupport.BlobAvailableClient)
             )
    end

    test "blob_available? returns false for missing or expired blob", context do
      listing_without_blob = insert_listing!(%{id: address(0x59), encrypted_blob_id: nil})

      listing_with_missing_blob =
        insert_listing!(%{id: address(0x5A), encrypted_blob_id: "walrus-missing-blob"})

      refute Sigil.IntelMarket.blob_available?(
               listing_without_blob.id,
               market_opts(context, walrus_client: Sigil.TestSupport.BlobMissingClient)
             )

      refute Sigil.IntelMarket.blob_available?(
               listing_with_missing_blob.id,
               market_opts(context, walrus_client: Sigil.TestSupport.BlobMissingClient)
             )

      refute Sigil.IntelMarket.blob_available?(
               address(0x5B),
               market_opts(context, walrus_client: Sigil.TestSupport.BlobMissingClient)
             )
    end
  end

  describe "get_listing/2" do
    test "get_listing checks ETS then falls back to database", context do
      persisted =
        insert_listing!(%{
          id: address(0x51),
          description: "persisted",
          price_mist: 444_000_000,
          client_nonce: 51
        })

      cached = %IntelListing{persisted | description: "cached", price_mist: 555_000_000}
      Cache.put(context.tables.intel_market, {:listing, persisted.id}, cached)

      assert Sigil.IntelMarket.get_listing(persisted.id, market_opts(context)).description ==
               "cached"

      Cache.delete(context.tables.intel_market, {:listing, persisted.id})

      assert Sigil.IntelMarket.get_listing(persisted.id, market_opts(context)).description ==
               "persisted"

      assert Cache.get(context.tables.intel_market, {:listing, persisted.id}).id == persisted.id
    end
  end

  describe "build_seal_config/1" do
    test "build_seal_config returns the browser hook contract" do
      assert Sigil.IntelMarket.build_seal_config([]) == %{
               "seal_package_id" => @sigil_package_id,
               "key_server_object_ids" => [],
               "threshold" => 1,
               "walrus_publisher_url" => "https://publisher.walrus-testnet.walrus.space",
               "walrus_aggregator_url" => "https://aggregator.walrus-testnet.walrus.space",
               "walrus_epochs" => 15,
               "sui_rpc_url" => "https://fullnode.testnet.sui.io:443"
             }
    end

    test "build_seal_config allows undeployed package overrides" do
      assert Sigil.IntelMarket.build_seal_config(
               sigil_package_id: "0x" <> String.duplicate("0", 64),
               seal_config: %{
                 key_server_object_ids: [],
                 threshold: 1,
                 walrus_publisher_url: "https://publisher.walrus-testnet.walrus.space",
                 walrus_aggregator_url: "https://aggregator.walrus-testnet.walrus.space",
                 walrus_epochs: 15,
                 sui_rpc_url: "https://fullnode.testnet.sui.io:443"
               }
             ) == %{
               "seal_package_id" => "0x" <> String.duplicate("0", 64),
               "key_server_object_ids" => [],
               "threshold" => 1,
               "walrus_publisher_url" => "https://publisher.walrus-testnet.walrus.space",
               "walrus_aggregator_url" => "https://aggregator.walrus-testnet.walrus.space",
               "walrus_epochs" => 15,
               "sui_rpc_url" => "https://fullnode.testnet.sui.io:443"
             }
    end
  end

  describe "build_create_listing_tx/2" do
    test "build_create_listing_tx returns base64 tx_bytes", context do
      Cache.put(context.tables.intel_market, {:marketplace}, marketplace_info())

      params = create_listing_params(intel_report_id: Ecto.UUID.generate())

      assert {:ok, %{tx_bytes: tx_bytes, client_nonce: client_nonce}} =
               Sigil.IntelMarket.build_create_listing_tx(
                 params,
                 market_opts(context, sender: context.seller)
               )

      assert is_binary(tx_bytes)
      assert is_integer(client_nonce)
      assert client_nonce >= 0

      assert {:create_listing, pending} =
               Cache.get(context.tables.intel_market, {:pending_tx, context.seller, tx_bytes})

      assert pending.client_nonce == client_nonce
      assert pending.intel_report_id == params.intel_report_id

      assert pending.seal_id ==
               Base.decode16!(String.trim_leading(params.seal_id, "0x"), case: :mixed)

      assert pending.encrypted_blob_id == params.encrypted_blob_id

      assert tx_bytes ==
               expected_create_listing_tx_bytes(%{
                 seal_id: Base.decode16!(String.trim_leading(params.seal_id, "0x"), case: :mixed),
                 encrypted_blob_id: params.encrypted_blob_id,
                 client_nonce: client_nonce,
                 price: params.price,
                 report_type: params.report_type,
                 solar_system_id: params.solar_system_id,
                 description: params.description
               })
    end

    test "build_create_restricted_listing_tx includes custodian ref", context do
      Cache.put(context.tables.intel_market, {:marketplace}, marketplace_info())

      Cache.put(
        context.tables.standings,
        {:active_custodian, context.tribe_id},
        custodian_info(
          tribe_id: context.tribe_id,
          object_id: address(0x25),
          initial_shared_version: 11
        )
      )

      params = create_listing_params(intel_report_id: Ecto.UUID.generate())

      assert {:ok, %{tx_bytes: tx_bytes, client_nonce: client_nonce}} =
               Sigil.IntelMarket.build_create_restricted_listing_tx(
                 params,
                 market_opts(context, sender: context.seller, tribe_id: context.tribe_id)
               )

      assert {:create_listing, pending} =
               Cache.get(context.tables.intel_market, {:pending_tx, context.seller, tx_bytes})

      assert pending.client_nonce == client_nonce
      assert pending.restricted_to_tribe_id == context.tribe_id

      assert pending.seal_id ==
               Base.decode16!(String.trim_leading(params.seal_id, "0x"), case: :mixed)

      assert pending.encrypted_blob_id == params.encrypted_blob_id

      assert tx_bytes ==
               expected_create_restricted_listing_tx_bytes(
                 custodian_ref(),
                 %{
                   seal_id:
                     Base.decode16!(String.trim_leading(params.seal_id, "0x"), case: :mixed),
                   encrypted_blob_id: params.encrypted_blob_id,
                   client_nonce: client_nonce,
                   price: params.price,
                   report_type: params.report_type,
                   solar_system_id: params.solar_system_id,
                   description: params.description
                 }
               )
    end
  end

  describe "build_purchase_tx/2" do
    test "build_purchase_tx creates split-and-purchase PTB", context do
      insert_listing!(%{
        id: address(0x61),
        seller_address: address(0xC1),
        price_mist: 125_000_000,
        status: :active
      })

      Cache.put(context.tables.intel_market, {:listing_ref, address(0x61)}, listing_ref())

      assert {:ok, %{tx_bytes: tx_bytes}} =
               Sigil.IntelMarket.build_purchase_tx(
                 address(0x61),
                 market_opts(context, sender: context.buyer, tribe_id: context.tribe_id)
               )

      assert tx_bytes == expected_purchase_tx_bytes(listing_ref(), 125_000_000)

      assert match?(
               {:purchase, _},
               Cache.get(context.tables.intel_market, {:pending_tx, context.buyer, tx_bytes})
             )
    end

    test "build_purchase_tx requires sender", context do
      assert Sigil.IntelMarket.build_purchase_tx(address(0x62), market_opts(context)) ==
               {:error, :missing_sender}
    end

    test "build_purchase_tx returns error for unknown listing", context do
      assert Sigil.IntelMarket.build_purchase_tx(
               address(0x63),
               market_opts(context, sender: context.buyer)
             ) == {:error, :listing_not_found}
    end

    test "build_purchase_tx rejects self purchase", context do
      insert_listing!(%{
        id: address(0x64),
        seller_address: context.seller,
        price_mist: 125_000_000,
        status: :active
      })

      assert Sigil.IntelMarket.build_purchase_tx(
               address(0x64),
               market_opts(context, sender: context.seller)
             ) == {:error, :cannot_purchase_own_listing}
    end

    test "build_purchase_tx rejects inactive listing", context do
      insert_listing!(%{
        id: address(0x65),
        seller_address: address(0xCA),
        price_mist: 125_000_000,
        status: :sold
      })

      assert Sigil.IntelMarket.build_purchase_tx(
               address(0x65),
               market_opts(context, sender: context.buyer)
             ) == {:error, :listing_not_active}
    end
  end

  describe "build_cancel_listing_tx/2" do
    test "build_cancel_listing_tx returns tx_bytes for active listing", context do
      insert_listing!(%{id: address(0x71), seller_address: context.seller, status: :active})
      Cache.put(context.tables.intel_market, {:listing_ref, address(0x71)}, listing_ref())

      assert {:ok, %{tx_bytes: tx_bytes}} =
               Sigil.IntelMarket.build_cancel_listing_tx(
                 address(0x71),
                 market_opts(context, sender: context.seller)
               )

      assert tx_bytes == expected_cancel_listing_tx_bytes(listing_ref())

      assert match?(
               {:cancel_listing, _},
               Cache.get(context.tables.intel_market, {:pending_tx, context.seller, tx_bytes})
             )
    end

    test "build_cancel_listing_tx rejects inactive listing", context do
      insert_listing!(%{id: address(0x72), seller_address: context.seller, status: :cancelled})

      assert Sigil.IntelMarket.build_cancel_listing_tx(
               address(0x72),
               market_opts(context, sender: context.seller)
             ) == {:error, :listing_not_active}
    end
  end

  describe "submit_signed_transaction/3" do
    test "successful submission reconciles and persists created listing", context do
      Cache.put(context.tables.intel_market, {:marketplace}, marketplace_info())

      params = create_listing_params(intel_report_id: Ecto.UUID.generate())

      assert {:ok, %{tx_bytes: tx_bytes, client_nonce: client_nonce}} =
               Sigil.IntelMarket.build_create_listing_tx(
                 params,
                 market_opts(context, sender: context.seller)
               )

      created_listing_id = address(0x81)

      expect(Sigil.Sui.ClientMock, :execute_transaction, fn ^tx_bytes, ["wallet-signature"], [] ->
        {:ok,
         %{
           "status" => "SUCCESS",
           "transaction" => %{"digest" => "create-digest"},
           "bcs" => "effects-bcs-create",
           "objectChanges" => [
             %{
               "type" => "created",
               "objectType" => @listing_type,
               "objectId" => created_listing_id,
               "version" => "17"
             }
           ]
         }}
      end)

      assert {:ok, %{digest: "create-digest", effects_bcs: "effects-bcs-create"}} =
               Sigil.IntelMarket.submit_signed_transaction(
                 tx_bytes,
                 "wallet-signature",
                 market_opts(context, sender: context.seller)
               )

      persisted = Repo.get!(IntelListing, created_listing_id)

      assert persisted.seller_address == context.seller
      assert persisted.client_nonce == client_nonce
      assert persisted.seal_id == params.seal_id
      assert persisted.encrypted_blob_id == params.encrypted_blob_id
      assert persisted.intel_report_id == params.intel_report_id
      assert persisted.status == :active

      assert Cache.get(context.tables.intel_market, {:listing, created_listing_id}).id ==
               created_listing_id

      assert Cache.get(context.tables.intel_market, {:listing_ref, created_listing_id}) == %{
               object_id: object_id(0x81),
               initial_shared_version: 17
             }

      assert_receive {:listing_created,
                      %IntelListing{id: ^created_listing_id, client_nonce: ^client_nonce}}

      assert Cache.get(context.tables.intel_market, {:pending_tx, context.seller, tx_bytes}) ==
               nil
    end

    test "failed reconciliation preserves pending create operation", context do
      Cache.put(context.tables.intel_market, {:marketplace}, marketplace_info())

      assert {:ok, %{tx_bytes: tx_bytes}} =
               Sigil.IntelMarket.build_create_listing_tx(
                 create_listing_params(intel_report_id: Ecto.UUID.generate()),
                 market_opts(context, sender: context.seller)
               )

      pending = Cache.get(context.tables.intel_market, {:pending_tx, context.seller, tx_bytes})

      expect(Sigil.Sui.ClientMock, :execute_transaction, fn ^tx_bytes, ["wallet-signature"], [] ->
        {:ok,
         %{
           "status" => "SUCCESS",
           "transaction" => %{"digest" => "missing-listing-digest"},
           "bcs" => "effects-bcs-missing"
         }}
      end)

      expect(Sigil.Sui.ClientMock, :get_objects, fn [type: @listing_type], [] ->
        {:ok, page([])}
      end)

      assert {:error, :listing_not_reconciled} =
               Sigil.IntelMarket.submit_signed_transaction(
                 tx_bytes,
                 "wallet-signature",
                 market_opts(context, sender: context.seller)
               )

      assert Cache.get(context.tables.intel_market, {:pending_tx, context.seller, tx_bytes}) ==
               pending
    end

    test "failed submission does not apply pending operation", context do
      Cache.put(context.tables.intel_market, {:marketplace}, marketplace_info())

      assert {:ok, %{tx_bytes: tx_bytes}} =
               Sigil.IntelMarket.build_create_listing_tx(
                 create_listing_params(intel_report_id: Ecto.UUID.generate()),
                 market_opts(context, sender: context.seller)
               )

      pending = Cache.get(context.tables.intel_market, {:pending_tx, context.seller, tx_bytes})

      expect(Sigil.Sui.ClientMock, :execute_transaction, fn ^tx_bytes, ["wallet-signature"], [] ->
        {:ok,
         %{
           "status" => "FAILURE",
           "transaction" => %{"digest" => "failed-digest"},
           "errors" => [%{"message" => "proof rejected"}]
         }}
      end)

      assert {:error, {:tx_failed, %{"status" => "FAILURE"} = _effects}} =
               Sigil.IntelMarket.submit_signed_transaction(
                 tx_bytes,
                 "wallet-signature",
                 market_opts(context, sender: context.seller)
               )

      assert Cache.get(context.tables.intel_market, {:pending_tx, context.seller, tx_bytes}) ==
               pending

      assert Repo.all(IntelListing) == []
      refute_receive {:listing_created, _}
    end

    test "listing events broadcast on PubSub marketplace topic", context do
      Cache.put(context.tables.intel_market, {:marketplace}, marketplace_info())

      params = create_listing_params(intel_report_id: Ecto.UUID.generate())

      assert {:ok, %{tx_bytes: create_tx_bytes}} =
               Sigil.IntelMarket.build_create_listing_tx(
                 params,
                 market_opts(context, sender: context.seller)
               )

      expect(Sigil.Sui.ClientMock, :execute_transaction, fn ^create_tx_bytes,
                                                            ["seller-signature"],
                                                            [] ->
        {:ok,
         %{
           "status" => "SUCCESS",
           "transaction" => %{"digest" => "create-event-digest"},
           "objectChanges" => [
             %{
               "type" => "created",
               "objectType" => @listing_type,
               "objectId" => address(0x82),
               "version" => "19"
             }
           ]
         }}
      end)

      assert {:ok, _result} =
               Sigil.IntelMarket.submit_signed_transaction(
                 create_tx_bytes,
                 "seller-signature",
                 market_opts(context, sender: context.seller)
               )

      assert_receive {:listing_created, %IntelListing{id: created_listing_id}}
      refute created_listing_id == nil

      Cache.put(
        context.tables.intel_market,
        {:listing_ref, created_listing_id},
        %{object_id: hex_to_bytes(created_listing_id), initial_shared_version: 19}
      )

      assert {:ok, %{tx_bytes: purchase_tx_bytes}} =
               Sigil.IntelMarket.build_purchase_tx(
                 created_listing_id,
                 market_opts(context, sender: context.buyer, tribe_id: context.tribe_id)
               )

      expect(Sigil.Sui.ClientMock, :execute_transaction, fn ^purchase_tx_bytes,
                                                            ["buyer-signature"],
                                                            [] ->
        {:ok,
         %{
           "status" => "SUCCESS",
           "transaction" => %{"digest" => "purchase-event-digest"},
           "bcs" => "effects-bcs-purchase"
         }}
      end)

      assert {:ok, _result} =
               Sigil.IntelMarket.submit_signed_transaction(
                 purchase_tx_bytes,
                 "buyer-signature",
                 market_opts(context, sender: context.buyer, tribe_id: context.tribe_id)
               )

      assert_receive {:listing_purchased,
                      %IntelListing{
                        id: ^created_listing_id,
                        buyer_address: buyer_address,
                        status: :sold
                      }}

      assert buyer_address == context.buyer

      sold_listing_id = address(0x83)

      insert_listing!(%{id: sold_listing_id, seller_address: context.seller, status: :active})

      Cache.put(
        context.tables.intel_market,
        {:listing_ref, sold_listing_id},
        %{object_id: object_id(0x83), initial_shared_version: 23}
      )

      assert {:ok, %{tx_bytes: cancel_tx_bytes}} =
               Sigil.IntelMarket.build_cancel_listing_tx(
                 sold_listing_id,
                 market_opts(context, sender: context.seller)
               )

      expect(Sigil.Sui.ClientMock, :execute_transaction, fn ^cancel_tx_bytes,
                                                            ["cancel-signature"],
                                                            [] ->
        {:ok,
         %{
           "status" => "SUCCESS",
           "transaction" => %{"digest" => "cancel-event-digest"},
           "bcs" => "effects-bcs-cancel"
         }}
      end)

      assert {:ok, _result} =
               Sigil.IntelMarket.submit_signed_transaction(
                 cancel_tx_bytes,
                 "cancel-signature",
                 market_opts(context, sender: context.seller)
               )

      assert_receive {:listing_cancelled,
                      %IntelListing{id: ^sold_listing_id, buyer_address: nil, status: :cancelled}}
    end

    test "full workflow: create listing, purchase, verify sold status", context do
      Cache.put(context.tables.intel_market, {:marketplace}, marketplace_info())

      intel_report = insert_location_report!(%{reported_by: context.seller})
      params = create_listing_params(intel_report_id: intel_report.id)

      assert {:ok, %{tx_bytes: create_tx_bytes}} =
               Sigil.IntelMarket.build_create_listing_tx(
                 params,
                 market_opts(context, sender: context.seller)
               )

      created_listing_id = address(0x84)

      expect(Sigil.Sui.ClientMock, :execute_transaction, fn ^create_tx_bytes,
                                                            ["seller-acceptance"],
                                                            [] ->
        {:ok,
         %{
           "status" => "SUCCESS",
           "transaction" => %{"digest" => "acceptance-create-digest"},
           "bcs" => "effects-bcs-create",
           "objectChanges" => [
             %{
               "type" => "created",
               "objectType" => @listing_type,
               "objectId" => created_listing_id,
               "version" => "29"
             }
           ]
         }}
      end)

      assert {:ok, %{digest: "acceptance-create-digest"}} =
               Sigil.IntelMarket.submit_signed_transaction(
                 create_tx_bytes,
                 "seller-acceptance",
                 market_opts(context, sender: context.seller)
               )

      assert {:ok, %{tx_bytes: purchase_tx_bytes}} =
               Sigil.IntelMarket.build_purchase_tx(
                 created_listing_id,
                 market_opts(context, sender: context.buyer, tribe_id: context.tribe_id)
               )

      expect(Sigil.Sui.ClientMock, :execute_transaction, fn ^purchase_tx_bytes,
                                                            ["buyer-acceptance"],
                                                            [] ->
        {:ok,
         %{
           "status" => "SUCCESS",
           "transaction" => %{"digest" => "acceptance-purchase-digest"},
           "bcs" => "effects-bcs-purchase"
         }}
      end)

      assert {:ok, %{digest: "acceptance-purchase-digest", effects_bcs: "effects-bcs-purchase"}} =
               Sigil.IntelMarket.submit_signed_transaction(
                 purchase_tx_bytes,
                 "buyer-acceptance",
                 market_opts(context, sender: context.buyer, tribe_id: context.tribe_id)
               )

      sold_listing = Repo.get!(IntelListing, created_listing_id)

      assert sold_listing.status == :sold
      assert sold_listing.buyer_address == context.buyer
      refute sold_listing.status == :active
      refute sold_listing.buyer_address == nil
    end

    test "create listing re-syncs when effects omit metadata", context do
      Cache.put(context.tables.intel_market, {:marketplace}, marketplace_info())

      params = create_listing_params(intel_report_id: Ecto.UUID.generate())

      assert {:ok, %{tx_bytes: tx_bytes, client_nonce: client_nonce}} =
               Sigil.IntelMarket.build_create_listing_tx(
                 params,
                 market_opts(context, sender: context.seller)
               )

      matching_listing_id = address(0x85)

      expect(Sigil.Sui.ClientMock, :execute_transaction, fn ^tx_bytes, ["wallet-signature"], [] ->
        {:ok,
         %{
           "status" => "SUCCESS",
           "transaction" => %{"digest" => "resync-digest"},
           "bcs" => "effects-bcs-resync"
         }}
      end)

      expect(Sigil.Sui.ClientMock, :get_objects, fn filters, [] ->
        assert Keyword.get(filters, :type) == @listing_type
        assert Keyword.get(filters, :cursor) == nil

        {:ok,
         %{
           data: [
             listing_object_json(
               id: address(0x86),
               seller: context.seller,
               seal_id: params.seal_id,
               encrypted_blob_id: params.encrypted_blob_id,
               client_nonce: client_nonce + 1,
               price: params.price,
               report_type: params.report_type,
               solar_system_id: params.solar_system_id,
               description: "same seller and seal but wrong nonce",
               initial_shared_version: 31
             )
           ],
           has_next_page: true,
           end_cursor: "cursor-1"
         }}
      end)

      expect(Sigil.Sui.ClientMock, :get_objects, fn filters, [] ->
        assert Keyword.get(filters, :type) == @listing_type
        assert Keyword.get(filters, :cursor) == "cursor-1"

        {:ok,
         %{
           data: [
             listing_object_json(
               id: matching_listing_id,
               seller: context.seller,
               seal_id: params.seal_id,
               encrypted_blob_id: params.encrypted_blob_id,
               client_nonce: client_nonce,
               price: params.price,
               report_type: params.report_type,
               solar_system_id: params.solar_system_id,
               description: params.description,
               initial_shared_version: 32
             )
           ],
           has_next_page: false,
           end_cursor: nil
         }}
      end)

      assert {:ok, %{digest: "resync-digest", effects_bcs: "effects-bcs-resync"}} =
               Sigil.IntelMarket.submit_signed_transaction(
                 tx_bytes,
                 "wallet-signature",
                 market_opts(context, sender: context.seller)
               )

      persisted = Repo.get!(IntelListing, matching_listing_id)

      assert persisted.client_nonce == client_nonce
      assert persisted.intel_report_id == params.intel_report_id
      assert persisted.id == matching_listing_id
      refute Repo.get(IntelListing, address(0x86))

      assert_receive {:listing_created,
                      %IntelListing{id: ^matching_listing_id, client_nonce: ^client_nonce}}

      assert Cache.get(context.tables.intel_market, {:pending_tx, context.seller, tx_bytes}) ==
               nil
    end
  end

  defp market_opts(context, overrides \\ []) do
    Keyword.merge(
      [
        tables: context.tables,
        pubsub: context.pubsub
      ],
      overrides
    )
  end

  defp create_listing_params(overrides) do
    base = %{
      seal_id: seal_id_hex(0x91),
      encrypted_blob_id: "walrus-blob-123",
      price: 125_000_000,
      report_type: 1,
      solar_system_id: 30_001_042,
      description: "Frontier gate fuel intel",
      intel_report_id: Ecto.UUID.generate()
    }

    Enum.into(overrides, base)
  end

  defp insert_listing!(attrs) do
    %IntelListing{}
    |> IntelListing.changeset(valid_listing_attrs(attrs))
    |> Repo.insert!()
  end

  defp set_listing_inserted_at!(listing_id, inserted_at) do
    {1, nil} =
      Repo.update_all(
        from(listing in IntelListing, where: listing.id == ^listing_id),
        set: [inserted_at: inserted_at]
      )
  end

  defp insert_location_report!(attrs) do
    %IntelReport{}
    |> IntelReport.location_changeset(
      Map.merge(
        %{
          tribe_id: @tribe_id,
          assembly_id: address(0xD1),
          solar_system_id: 30_001_042,
          label: "Foothold",
          notes: "Gate is online and fueled.",
          reported_by: address(0xA1),
          reported_by_name: "Scout Prime",
          reported_by_character_id: address(0xE1)
        },
        attrs
      )
    )
    |> Repo.insert!()
  end

  defp valid_listing_attrs(overrides) do
    Map.merge(
      %{
        id: address(0xC1),
        seller_address: address(0xA9),
        seal_id: seal_id_hex(0x94),
        encrypted_blob_id: "walrus-default-1234567890",
        client_nonce: 42,
        price_mist: 150_000_000,
        report_type: 1,
        solar_system_id: 30_001_042,
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

  defp marketplace_info(overrides \\ %{}) do
    Map.merge(
      %{
        object_id: address(0x10),
        object_id_bytes: object_id(0x10),
        initial_shared_version: 7
      },
      overrides
    )
  end

  defp listing_ref do
    %{object_id: object_id(0x30), initial_shared_version: 13}
  end

  defp custodian_ref do
    %{object_id: object_id(0x25), initial_shared_version: 11}
  end

  defp custodian_info(overrides) do
    overrides = Enum.into(overrides, %{})
    object_id_hex = Map.get(overrides, :object_id, address(0x25))

    Map.merge(
      %{
        object_id: object_id_hex,
        object_id_bytes: hex_to_bytes(object_id_hex),
        initial_shared_version: 11,
        tribe_id: @tribe_id,
        current_leader: address(0xF1)
      },
      overrides
    )
  end

  defp marketplace_object_json(overrides) do
    object_id_hex = Keyword.get(overrides, :object_id, address(0x10))
    initial_shared_version = Keyword.get(overrides, :initial_shared_version, 7)

    %{
      "id" => object_id_hex,
      "shared" => %{"initialSharedVersion" => Integer.to_string(initial_shared_version)},
      "initialSharedVersion" => Integer.to_string(initial_shared_version)
    }
  end

  defp listing_object_json(overrides) do
    object_id_hex = Keyword.get(overrides, :id, address(0x30))
    initial_shared_version = Keyword.get(overrides, :initial_shared_version, 13)

    %{
      "id" => object_id_hex,
      "seller" => Keyword.get(overrides, :seller, address(0xA1)),
      "seal_id" => Keyword.get(overrides, :seal_id, seal_id_hex(0x95)),
      "encrypted_blob_id" =>
        Keyword.get(overrides, :encrypted_blob_id, "walrus-listing-1234567890"),
      "client_nonce" => to_string(Keyword.get(overrides, :client_nonce, 42)),
      "price" => to_string(Keyword.get(overrides, :price, 125_000_000)),
      "report_type" => Keyword.get(overrides, :report_type, 1),
      "solar_system_id" => Keyword.get(overrides, :solar_system_id, 30_001_042),
      "description" => Keyword.get(overrides, :description, "Frontier gate fuel intel"),
      "status" => to_string(Keyword.get(overrides, :status, 0)),
      "buyer" => Keyword.get(overrides, :buyer, nil),
      "restricted_to_tribe_id" => Keyword.get(overrides, :restricted_to_tribe_id, nil),
      "shared" => %{"initialSharedVersion" => Integer.to_string(initial_shared_version)},
      "initialSharedVersion" => Integer.to_string(initial_shared_version)
    }
  end

  defp page(entries) do
    %{data: entries, has_next_page: false, end_cursor: nil}
  end

  defp expected_create_listing_tx_bytes(params) do
    params
    |> TxIntelMarket.build_create_listing([])
    |> TransactionBuilder.build_kind!()
    |> Base.encode64()
  end

  defp expected_create_restricted_listing_tx_bytes(custodian_ref, params) do
    TxIntelMarket.build_create_restricted_listing(custodian_ref, params, [])
    |> TransactionBuilder.build_kind!()
    |> Base.encode64()
  end

  defp expected_purchase_tx_bytes(listing_ref, amount_mist) do
    listing_ref
    |> TxIntelMarket.build_purchase(amount_mist, [])
    |> TransactionBuilder.build_kind!()
    |> Base.encode64()
  end

  defp expected_cancel_listing_tx_bytes(listing_ref) do
    listing_ref
    |> TxIntelMarket.build_cancel_listing([])
    |> TransactionBuilder.build_kind!()
    |> Base.encode64()
  end

  defp unique_pubsub_name do
    :"intel_market_pubsub_#{System.unique_integer([:positive])}"
  end

  defp address(byte) do
    "0x" <> Base.encode16(:binary.copy(<<byte>>, 32), case: :lower)
  end

  defp object_id(byte), do: :binary.copy(<<byte>>, 32)

  defp hex_to_bytes("0x" <> hex), do: Base.decode16!(hex, case: :mixed)

  defp seal_id_hex(byte) do
    "0x" <> Base.encode16(:binary.copy(<<byte>>, 32), case: :lower)
  end
end
