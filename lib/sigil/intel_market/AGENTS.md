# lib/sigil/intel_market/

## Modules

- `Sigil.IntelMarket.Support` (`support.ex`) — Shared cache, pagination, and parsing helpers for marketplace modules
- `Sigil.IntelMarket.Listings` (`listings.ex`) — Listing persistence, caching, chain parsing, stale cleanup with 30-second grace window
- `Sigil.IntelMarket.PendingOps` (`pending_ops.ex`) — Applies cached marketplace operations after wallet-signed transaction succeeds

## Key Functions

### Support (support.ex)
- `market_table/1`: opts → ETS table ID for `:intel_market`
- `broadcast/2`: opts × event → PubSub broadcast on `"intel_market"` topic
- `list_objects/3`: client × filters × req_options → paginated Sui object fetch
- `parse_integer/1-2`, `parse_optional_integer/1`: chain value normalization
- `parse_listing_status/1`: `0→:active`, `1→:sold`, `2→:cancelled`
- `marketplace_type/0`, `listing_type/0`: fully qualified Sui Move type strings

### Listings (listings.ex)
- `marketplace_from_object/1`: raw chain object → `marketplace_info()` | nil
- `parse_listing_object!/1`: raw chain object → `%{listing: IntelListing.t(), ref: listing_ref()}`
- `persist_chain_listing/1`: upsert from chain, preserving local `intel_report_id` linkage
- `persist_created_listing/1`: upsert reconciled listing after tx settlement
- `update_listing_status/2`: status-only update for purchase/cancel
- `cache_listing/3`: listing × opts × ref → ETS cache write
- `cached_listing_ref/2`: opts × listing_id → ref from ETS or default
- `remove_stale_listings/2`: delete listings older than 30s that are absent from chain
- `clear_listing_cache/2`: remove ETS entries for a listing

### PendingOps (pending_ops.ex)
- `apply/4`: opts × operation × effects × digest → reconcile create/purchase/cancel, broadcast PubSub event
- Operations: `{:create_listing, pending}`, `{:purchase, %{listing_id, buyer_address}}`, `{:cancel_listing, %{listing_id}}`
- Create reconciliation: extract from tx effects or fallback to chain re-sync by seller + client_nonce

## Patterns
- Follows `Sigil.Diplomacy.PendingOps` pattern for post-tx reconciliation
- All functions accept `IntelMarket.options()` keyword list for DI
- `@sui_client Application.compile_env!(:sigil, :sui_client)` for chain client injection
- ETS cache keys: `{:marketplace}`, `{:listing, id}`, `{:listing_ref, id}`, `{:pending_tx, sender, tx_bytes}`

## Dependencies
- `Sigil.Cache` for ETS operations
- `Sigil.Diplomacy.ObjectCodec` for shared version parsing and hex decoding
- `Sigil.Intel.IntelListing` Ecto schema
- `Sigil.Repo` for Postgres persistence
- `Phoenix.PubSub` for event broadcasting
