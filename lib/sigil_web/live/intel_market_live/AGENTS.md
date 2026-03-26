# lib/sigil_web/live/intel_market_live/

## Modules
- `SigilWeb.IntelMarketLive.State` (`state.ex`) — marketplace assigns, filter normalization, form helpers, and context option builders.
- `SigilWeb.IntelMarketLive.Transactions` (`transactions.ex`) — sell, purchase, cancel, signed-submission, and browser decrypt workflows.
- `SigilWeb.IntelMarketLive.Components` (`components.ex`) — browse cards, filter bar, seller inventory, purchased-intel panels, and shared presentation helpers.
- `SigilWeb.IntelMarketLive.SellForm` (`sell_form.ex`) — extracted sell-form rendering and local display helpers.

## Seal Delivery Flow
- Sell flow builds structured `intel_data`, generates a server-side `seal_id`, then pushes `encrypt_and_upload` to `SealEncrypt`.
- Hook completion returns `blob_id`; `Transactions.build_listing_transaction/3` uses that value to build the unsigned create-listing PTB.
- Purchase flow surfaces `:listing_not_active` before wallet signing when the listing is already sold or cancelled.
- Decrypt flow performs a Walrus preflight through `Sigil.IntelMarket.blob_available?/2`, pushes `decrypt_intel`, and decodes `%{"data" => json}` from the hook on success.

## Key Functions
- `State.sync_and_load_data/1` — syncs from chain, reloads browse/seller/purchased data, and reapplies filters.
- `Transactions.submit_listing/2` — validates listing input and starts the Seal encrypt/upload flow.
- `Transactions.build_listing_transaction/3` — builds create-listing PTBs after the hook returns `blob_id`.
- `Transactions.begin_purchase/2` — starts wallet signing for eligible listings and handles inactive-listing errors.
- `Transactions.begin_decrypt/2` — starts browser decryption for sold listings with available blobs.
- `Components.sell_form/1` — delegates to `SellForm.sell_form/1`.

## Patterns
- Keep LiveView event handlers thin by delegating orchestration to `State` and `Transactions`.
- Preserve buyer decrypt access after refresh by reloading `purchased_listings` from the context.
- Treat hook payloads as the boundary contract: nested `intel_data`, server-generated `seal_id`, returned `blob_id`, decrypted `%{"data" => json}`.
