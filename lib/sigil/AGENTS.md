# lib/sigil/

## Modules
- `Sigil.Intel` (`intel.ex`) — tribe-scoped intel CRUD with authorization-bound reads/writes, ETS-cached location lookups, and PubSub fan-out; obsolete `export_for_commitment/1` is removed.
- `Sigil.Intel.IntelListing` (`intel/intel_listing.ex`) — persisted marketplace listing projection with `seal_id`, `encrypted_blob_id`, `client_nonce`, seller/buyer addresses, and seller-local `intel_report_id` linkage.
- `Sigil.IntelMarket` (`intel_market.ex`) — marketplace context for discovery, sync, unsigned PTB building, signed submission reconciliation, Seal/Walrus config generation, seller/purchased listing queries, and blob-availability preflight.
- `Sigil.IntelMarket.Listings` (`intel_market/listings.ex`) — chain parsing, listing upsert/reconcile helpers, cache writes, and stale-listing cleanup under configurable grace windows.
- `Sigil.IntelMarket.PendingOps` (`intel_market/pending_ops.ex`) — applies create/purchase/cancel pending operations after successful signed transactions.
- `Sigil.Diplomacy.Governance` (`diplomacy/governance.ex`) — extracted transaction builders (standings + governance) and governance data loading. Delegated from `Sigil.Diplomacy`.
- `Sigil.WalrusClient` (`walrus_client.ex`) — behavior for Walrus blob storage operations.
- `Sigil.WalrusClient.HTTP` (`walrus_client/http.ex`) — Req-backed Walrus implementation for upload, read, and HEAD existence checks.

## Seal Delivery Notes
- Marketplace create flows now attach a server-generated `seal_id` and a Walrus `blob_id`; no proof export helper remains in `Sigil.Intel`.
- `Sigil.IntelMarket.build_purchase_tx/2` returns `{:error, :listing_not_active}` for sold/cancelled listings before wallet signing.
- `Sigil.IntelMarket.blob_available?/2` uses injectable `:walrus_client` opts so tests can provide isolated availability doubles.
- Marketplace discovery still caches the `IntelMarketplace` singleton, but the shared object is metadata-only and does not track `listing_count`.

## Key Functions
- `Sigil.Intel.topic/1` — exposes the canonical tribe intel PubSub topic.
- `Sigil.IntelMarket.build_seal_config/1` — returns the browser hook contract used by `SealEncrypt`.
- `Sigil.IntelMarket.list_seller_listings/2` — returns active, sold, and cancelled seller-owned listings.
- `Sigil.IntelMarket.list_purchased_listings/2` — returns sold listings purchased by the current buyer for decrypt-after-refresh flows.
- `Sigil.IntelMarket.blob_available?/2` — checks Walrus blob availability through the injected client.

## Patterns
- Keep marketplace dependencies injectable through opts (`:client`, `:walrus_client`, `:seal_config`, `:stale_grace_ms`).
- Preserve local `intel_report_id` linkage when chain sync refreshes marketplace listings.
- Use ETS cache keys `{:listing, id}`, `{:listing_ref, id}`, and sender-scoped `{:pending_tx, sender, tx_bytes}` for marketplace state.
