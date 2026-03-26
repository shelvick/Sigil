# lib/sigil_web/

## Modules
- `SigilWeb.Router` (`router.ex`) — wallet-session LiveView routes including dashboard, diplomacy, tribe intel, alerts, and marketplace.
- `SigilWeb.WalletSession` (`wallet_session.ex`) — resolves cache tables, PubSub, account, active character, and optional test-injected marketplace dependencies from session state.
- `SigilWeb.IntelMarketLive` (`live/intel_market_live.ex`) — marketplace page for browse, sell, purchase, cancel, and decrypt flows.
  - `.State` (`live/intel_market_live/state.ex`) — assign helpers, filter logic, and context opts.
  - `.Transactions` (`live/intel_market_live/transactions.ex`) — Seal upload orchestration, wallet signing, signed submission, and decrypt handling.
  - `.Components` (`live/intel_market_live/components.ex`) — listing cards, seller inventory, purchased intel, filter bar, and status helpers.
  - `.SellForm` (`live/intel_market_live/sell_form.ex`) — extracted sell-form module.
- `SigilWeb.IntelLive`, `SigilWeb.TribeOverviewLive`, and `SigilWeb.AssemblyDetailLive` — tribe intel views that share data with the marketplace seller workflow.
- `assets/js/hooks/seal_hook.js` and `assets/js/hooks/wallet_hook.js` are the paired browser contracts for marketplace encryption/decryption and transaction signing.

## Marketplace Notes
- Marketplace sell flow no longer generates browser ZK proofs.
- `IntelMarketLive.Transactions` now generates `seal_id` server-side, pushes nested `intel_data` to `SealEncrypt`, and accepts `blob_id` from the hook.
- Purchased-intel decrypt flow decodes `%{"data" => json}` from the hook and keeps decrypt access in the `My Listings` section after refresh.
- `Components.sell_form/1` delegates to the extracted `SellForm` module.

## JS Hooks
- `assets/js/hooks/wallet_hook.js` — wallet discovery, account selection, `signPersonalMessage`, `signTransaction`, and `reportTransactionEffects` support.
- `assets/js/hooks/seal_hook.js` — browser-side Seal encryption/decryption plus Walrus upload/fetch for marketplace flows.
- `assets/js/hooks/fuel_countdown.js` — assembly fuel countdown display.
- `assets/js/hooks/infinite_scroll.js` — alert-feed pagination sentinel.

## Patterns
- Marketplace UI keeps wallet signing and browser crypto separated: `WalletConnect` signs transactions, `SealEncrypt` handles encrypted payloads.
- Session DI remains the preferred test hook for `cache_tables`, `pubsub`, `static_data`, and marketplace-specific doubles such as `walrus_client` overrides.
