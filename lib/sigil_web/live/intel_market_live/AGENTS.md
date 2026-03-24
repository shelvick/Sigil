# lib/sigil_web/live/intel_market_live/

## Modules

- `SigilWeb.IntelMarketLive.State` (`state.ex`) — State management, form helpers, filtering logic for marketplace LiveView
- `SigilWeb.IntelMarketLive.Transactions` (`transactions.ex`) — Transaction-oriented workflows: submit listing, build tx, purchase, cancel, finalize
- `SigilWeb.IntelMarketLive.Components` (`components.ex`) — Template function components for marketplace UI

## Key Functions

### State (state.ex)
- `assign_base_state/1`: socket → initialize all marketplace assigns (page_section, page_state, listings, filters, etc.)
- `sync_and_load_data/1`: socket → sync from chain + load listings + load reports + apply filters
- `refresh_marketplace/1`: socket → reload listings/reports without chain sync
- `apply_filters/2`: socket × filters → filter listings by report_type, solar_system, price range
- `assign_listing_form/2`: socket × params → normalize and store Phoenix form
- `intel_opts/1`, `market_opts/1`, `diplomacy_opts/1`: socket → context option keyword lists
- `parse_price_sui/1`: SUI string → `{:ok, mist_integer}` | `:error`
- `humanize_status/1`: proof status string normalization
- `changeset_error/1`: changeset → user-facing error string
- `report_type_value/1`: `:scouting → 2`, `_ → 1`
- `blank_to_nil/1`: empty/whitespace string → nil

### Transactions (transactions.ex)
- `submit_listing/2`: socket × params → validate + resolve report + push `generate_proof` event
- `build_listing_transaction/3`: socket × pending × payload → build unsigned tx + push `request_sign_transaction`
- `begin_purchase/2`: socket × listing_id → build purchase tx + push signing event
- `cancel_listing/2`: socket × listing_id → build cancel tx + push signing event
- `finalize_transaction/3`: socket × tx_bytes × signature → submit signed tx + refresh marketplace

### Components (components.ex)
- `filter_bar/1`: browse filters (report_type, solar_system, price range)
- `listing_card/1`: listing display with price, type, system, seller, description, purchase action
- `sell_form/1`: sell intel form with report selector + manual entry + tribe restriction toggle
- `proof_status/1`: proof generation progress indicator
- `my_listings_panel/1`: seller's listings with status badges and cancel action
- `listing_status_badge/1`: active/sold/cancelled badge

## Patterns
- Follows `UI_DiplomacyLive` pattern for wallet signing flow (page_state machine)
- State/Transactions split keeps LiveView event handlers as thin dispatchers
- Components receive assigns as props, no direct socket access
- Price display converts mist to SUI (÷1,000,000,000) with Decimal formatting
- Purchase action disabled for own listings and ineligible tribe-restricted listings

## Dependencies
- `Sigil.IntelMarket` for marketplace operations
- `Sigil.Intel` for report resolution and export
- `Sigil.Diplomacy` for custodian checks
- `Sigil.StaticData` for solar system name resolution
- `Phoenix.PubSub` for real-time listing updates
