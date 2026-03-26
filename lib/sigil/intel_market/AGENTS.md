# lib/sigil/intel_market/

## Modules
- `Sigil.IntelMarket.Support` (`support.ex`) — shared cache-table lookup, paginated object fetch, integer parsing, and marketplace/listing type resolution.
- `Sigil.IntelMarket.Listings` (`listings.ex`) — chain-object parsing, Postgres upsert/reconcile helpers, ETS cache writes, and stale-listing removal with configurable grace windows.
- `Sigil.IntelMarket.PendingOps` (`pending_ops.ex`) — applies cached create/purchase/cancel operations after successful wallet-signed transaction submission.

## Seal Delivery Notes
- Chain sync persists `seal_id` and `encrypted_blob_id` while preserving local `intel_report_id` linkage.
- Stale-listing cleanup is deterministic in tests through `stale_grace_ms: 0` and defaults to a 30-second grace window in normal operation.
- Pending create reconciliation matches on seller plus `client_nonce` when execution effects omit created-object metadata.
- Browser decryption relies on `Sigil.IntelMarket.build_seal_config/1` and `Sigil.IntelMarket.blob_available?/2`; the latter uses injectable `:walrus_client` opts.

## Key Functions
- `Support.market_table/1` — returns the ETS table for marketplace cache state.
- `Support.list_objects/3` — paginates Sui object queries across all listing pages.
- `Listings.parse_listing_object!/1` — normalizes chain JSON into `IntelListing` plus shared-object ref.
- `Listings.persist_chain_listing/1` — refreshes chain-synced listings without dropping local linkage metadata.
- `Listings.remove_stale_listings/2` — deletes persisted listings absent from chain after the grace cutoff.
- `PendingOps.apply/4` — reconciles successful create, purchase, and cancel submissions and broadcasts PubSub events.

## Patterns
- Keep marketplace cache keys sender-scoped for pending transactions: `{:pending_tx, sender, tx_bytes}`.
- Treat the marketplace singleton as discovery metadata only; listing creation does not require a marketplace shared-object input.
- Normalize Seal and Walrus data at boundaries: hex `seal_id` for storage/rendering, raw bytes for PTB inputs, string `blob_id` for browser and persistence.
