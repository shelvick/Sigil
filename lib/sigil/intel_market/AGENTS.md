# lib/sigil/intel_market/

## Modules
- `Sigil.IntelMarket.Support` (`support.ex`) — shared cache-table lookup, paginated object fetch, integer parsing, and marketplace/listing type resolution.
- `Sigil.IntelMarket.Listings` (`listings.ex`) — chain-object parsing, Postgres upsert/reconcile helpers, ETS cache writes, and stale-listing removal with configurable grace windows.
- `Sigil.IntelMarket.PendingOps` (`pending_ops.ex`) — applies cached create/purchase/cancel operations after successful wallet-signed transaction submission.
- `Sigil.IntelMarket.Transactions` (`transactions.ex`) — tx building (create/purchase/cancel), signed submission with pending-op reconciliation, pseudonym/relay-sponsored flows via `GasRelay`, and listing-ref resolution from cache or chain.
- `Sigil.IntelMarket.Reputation` (`reputation.ex`) — seller reputation counter queries, per-listing feedback-recorded checks, `confirm_quality`/`report_bad_quality` tx builders using `TxIntelReputation`, and on-chain registry parsing with address normalization.

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
- `Transactions.build_create_listing_tx/2` — builds unsigned public create-listing PTB with client nonce.
- `Transactions.build_create_restricted_listing_tx/2` — builds unsigned tribe-restricted create-listing PTB with custodian discovery.
- `Transactions.build_pseudonym_create_listing_tx/2` — builds relay-sponsored pseudonymous create-listing PTB via `GasRelay.prepare_sponsored/3`.
- `Transactions.build_purchase_tx/2` — builds unsigned purchase PTB with self-purchase and active-listing guards.
- `Transactions.build_cancel_listing_tx/2` — builds unsigned cancel PTB for seller-owned listings.
- `Transactions.build_pseudonym_cancel_listing_tx/2` — builds relay-sponsored pseudonymous cancel PTB with ownership check.
- `Transactions.submit_signed_transaction/3` — submits wallet-signed tx and applies pending-op reconciliation.
- `Transactions.submit_pseudonym_transaction/4` — submits pseudonym+relay dual-signed tx via `GasRelay.submit_sponsored/4`.
- `Transactions.submit_feedback_transaction/3` — submits feedback tx without pending-op reconciliation.
- `Transactions.resolve_listing_ref/2` — resolves shared-object ref from cache or chain with automatic caching.
- `Reputation.get_reputation/2` — returns `%{positive, negative}` counters for a seller address from the on-chain registry.
- `Reputation.feedback_recorded?/3` — checks whether feedback for a listing is already recorded for the seller.
- `Reputation.build_confirm_quality_tx/2` — builds positive feedback PTB via `TxIntelReputation`.
- `Reputation.build_report_bad_quality_tx/2` — builds negative feedback PTB via `TxIntelReputation`.

## Patterns
- Keep marketplace cache keys sender-scoped for pending transactions: `{:pending_tx, sender, tx_bytes}`.
- Treat the marketplace singleton as discovery metadata only; listing creation does not require a marketplace shared-object input.
- Normalize Seal and Walrus data at boundaries: hex `seal_id` for storage/rendering, raw bytes for PTB inputs, string `blob_id` for browser and persistence.
- Pseudonym flows use `GasRelay` for sponsored gas; relay errors map to `:relay_failed`.
- Reputation registry ID is injectable via `:reputation_registry_id` opt or falls back to world config.
- Registry JSON parsing handles multiple Sui Move struct formats (string keys, atom keys, `fields` wrapper, collection wrappers).
