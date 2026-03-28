# lib/sigil/

## Modules
- `Sigil.Intel` (`intel.ex`) — tribe-scoped intel CRUD with authorization-bound reads/writes, ETS-cached location lookups, and PubSub fan-out; obsolete `export_for_commitment/1` is removed.
- `Sigil.Intel.IntelListing` (`intel/intel_listing.ex`) — persisted marketplace listing projection with `seal_id`, `encrypted_blob_id`, `client_nonce`, seller/buyer addresses, and seller-local `intel_report_id` linkage.
- `Sigil.IntelMarket` (`intel_market.ex`) — marketplace facade delegating tx building to `Transactions`, reputation queries to `Reputation`, and retaining discovery, sync, Seal/Walrus config, and listing query APIs.
- `Sigil.IntelMarket.Listings` (`intel_market/listings.ex`) — chain parsing, listing upsert/reconcile helpers, cache writes, and stale-listing cleanup under configurable grace windows.
- `Sigil.IntelMarket.PendingOps` (`intel_market/pending_ops.ex`) — applies create/purchase/cancel pending operations after successful signed transactions.
- `Sigil.Diplomacy.Governance` (`diplomacy/governance.ex`) — extracted transaction builders (standings + governance) and governance data loading. Delegated from `Sigil.Diplomacy`.
- `Sigil.IntelMarket.Transactions` (`intel_market/transactions.ex`) — tx building (create/purchase/cancel), signed submission with pending-op reconciliation, pseudonym/relay-sponsored flows, and listing-ref resolution.
- `Sigil.IntelMarket.Reputation` (`intel_market/reputation.ex`) — seller reputation counter queries, feedback-recorded checks, and confirm/report feedback tx builders.
- `Sigil.Pseudonym` (`pseudonym.ex`) — Ecto schema for pseudonym identity records with `account_address`, `pseudonym_address`, and `encrypted_private_key` fields; validates 0x-prefix and non-empty binary key.
- `Sigil.Pseudonyms` (`pseudonyms.ex`) — context for pseudonym CRUD with `pg_advisory_xact_lock`-based account-scoped 5-identity cap enforcement; provides `create_pseudonym/2`, `list_pseudonyms/1`, `get_pseudonym/2`, `delete_pseudonym/2`, and `pseudonym_addresses/1`.
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
- `Sigil.IntelMarket.get_reputation/2` — delegates to `Reputation.get_reputation/2` for seller reputation counters.
- `Sigil.IntelMarket.feedback_recorded?/3` — delegates to `Reputation.feedback_recorded?/3`.
- `Sigil.IntelMarket.build_pseudonym_create_listing_tx/2` — delegates to `Transactions` for relay-sponsored pseudonym listings.
- `Sigil.IntelMarket.resolve_listing_ref/2` — delegates to `Transactions.resolve_listing_ref/2`.
- `Sigil.Pseudonyms.create_pseudonym/2` — creates a pseudonym within the per-account 5-identity cap (advisory lock protected).
- `Sigil.Pseudonyms.list_pseudonyms/1` — returns ordered pseudonyms for an account.
- `Sigil.Pseudonyms.pseudonym_addresses/1` — returns ordered address list for an account.

## Patterns
- Keep marketplace dependencies injectable through opts (`:client`, `:walrus_client`, `:seal_config`, `:stale_grace_ms`, `:reputation_registry_id`, `:pseudonym_address`).
- Preserve local `intel_report_id` linkage when chain sync refreshes marketplace listings.
- Use ETS cache keys `{:listing, id}`, `{:listing_ref, id}`, and sender-scoped `{:pending_tx, sender, tx_bytes}` for marketplace state.
- Pseudonym limit enforcement uses `pg_advisory_xact_lock(hashtext(account_address))` for serializable concurrency control.
