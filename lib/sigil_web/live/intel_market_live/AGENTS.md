# lib/sigil_web/live/intel_market_live/

## Modules
- `SigilWeb.IntelMarketLive.State` (`state.ex`) — marketplace assigns, filter normalization, form helpers, and context option builders.
- `SigilWeb.IntelMarketLive.Transactions` (`transactions.ex`) — sell, purchase, cancel, signed-submission, and browser decrypt workflows.
- `SigilWeb.IntelMarketLive.Components` (`components.ex`) — browse cards, filter bar, seller inventory, purchased-intel panels, and shared presentation helpers.
- `SigilWeb.IntelMarketLive.SellForm` (`sell_form.ex`) — extracted sell-form rendering and local display helpers.
- `SigilWeb.IntelMarketLive.PageHelpers` (`page_helpers.ex`) — shared mount/subscription/error helpers: `assign_seal_config_json/1`, `maybe_load_marketplace/1`, `maybe_subscribe_marketplace/1`, `handle_pseudonym_error/3`, `normalize_section/1`, `section_button_classes/1`.
- `SigilWeb.IntelMarketLive.State.Filtering` (`state/filtering.ex`) — browse filter matching (`matches_filters?/3`), default filter map, and form prefill from existing intel reports (`maybe_fill_from_report/2`, `maybe_fill_solar_system_id/2`).
- `SigilWeb.IntelMarketLive.State.MarketData` (`state/market_data.ex`) — listing/pseudonym/reputation data loading: `load_listings/1`, `load_reports/1`, `load_pseudonyms/1`, `reload_pseudonyms/1`, `sync_loaded_pseudonyms/3`, `current_sender/1`, `current_tribe_id/1`, `load_solar_systems/1`.
- `SigilWeb.IntelMarketLive.Transactions.ListingFlow` (`transactions/listing_flow.ex`) — sell form validation, manual report persistence, and Seal encrypt-upload orchestration: `submit_listing/2`, `build_listing_transaction/3`.

## Seal Delivery Flow
- Sell flow builds structured `intel_data`, generates a server-side `seal_id`, then pushes `encrypt_and_upload` to `SealEncrypt`.
- Hook completion returns `blob_id`; `ListingFlow.build_listing_transaction/3` uses that value to build the relay-sponsored pseudonym create-listing PTB.
- Purchase flow surfaces `:listing_not_active` before wallet signing when the listing is already sold or cancelled.
- Decrypt flow performs a Walrus preflight through `Sigil.IntelMarket.blob_available?/2`, pushes `decrypt_intel`, and decodes `%{"data" => json}` from the hook on success.

## Key Functions
- `State.sync_and_load_data/1` — syncs from chain, reloads browse/seller/purchased data, and reapplies filters.
- `ListingFlow.submit_listing/2` — validates listing input, enforces pseudonym requirement, and starts the Seal encrypt/upload flow.
- `ListingFlow.build_listing_transaction/3` — builds relay-sponsored create-listing PTBs after the hook returns `blob_id`.
- `Transactions.begin_purchase/2` — starts wallet signing for eligible listings and handles inactive-listing errors.
- `Transactions.begin_decrypt/2` — starts browser decryption for sold listings with available blobs.
- `Components.sell_form/1` — delegates to `SellForm.sell_form/1`.
- `PageHelpers.maybe_load_marketplace/1` — discovers marketplace and triggers data sync on successful discovery.
- `MarketData.load_listings/1` — reloads active, seller, purchased listings plus reputation cache and feedback flags.
- `MarketData.load_pseudonyms/1` — loads persisted pseudonyms and pushes encrypted keys to browser for decrypt.
- `Filtering.matches_filters?/3` — evaluates listing against report type, solar system, and price range filters.

## Patterns
- Keep LiveView event handlers thin by delegating orchestration to `State`, `Transactions`, `PageHelpers`, and extracted submodules.
- Preserve buyer decrypt access after refresh by reloading `purchased_listings` from the context.
- Treat hook payloads as the boundary contract: nested `intel_data`, server-generated `seal_id`, returned `blob_id`, decrypted `%{"data" => json}`.
- Pseudonym error handling is phase-specific (load/encrypt/activate) with user-facing messages routed through `PageHelpers.handle_pseudonym_error/3`.
- Seller address aggregation includes both the primary sender and all pseudonym addresses for `list_all_seller_listings`.
