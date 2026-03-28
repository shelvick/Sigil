# lib/sigil_web/

## Modules
- `SigilWeb.Router` (`router.ex`) — wallet-session LiveView routes including dashboard, diplomacy, tribe intel, alerts, and marketplace.
- `SigilWeb.WalletSession` (`wallet_session.ex`) — resolves cache tables, PubSub, account, active character, and optional test-injected marketplace dependencies from session state.
- `SigilWeb.IntelMarketLive` (`live/intel_market_live.ex`) — marketplace page for browse, sell, purchase, cancel, and decrypt flows.
  - `.State` (`live/intel_market_live/state.ex`) — assign helpers, filter logic, and context opts.
  - `.Transactions` (`live/intel_market_live/transactions.ex`) — Seal upload orchestration, wallet signing, signed submission, and decrypt handling.
  - `.Components` (`live/intel_market_live/components.ex`) — listing cards, seller inventory, purchased intel, filter bar, and status helpers.
  - `.SellForm` (`live/intel_market_live/sell_form.ex`) — extracted sell-form module.
- `SigilWeb.DiplomacyLive` (`live/diplomacy_live.ex`) — diplomacy editor with governance voting section.
  - `.Governance` (`live/diplomacy_live/governance.ex`) — extracted governance state management, tx building, and signing flow.
  - `.GovernanceComponents` (`live/diplomacy_live/governance_components.ex`) — governance section HEEx components.
- `SigilWeb.IntelLive`, `SigilWeb.TribeOverviewLive`, and `SigilWeb.AssemblyDetailLive` — tribe intel views that share data with the marketplace seller workflow.
- `assets/js/hooks/seal_hook.js`, `assets/js/hooks/wallet_hook.js`, `assets/js/hooks/pseudonym_hook.js`, and `assets/js/hooks/pseudonym_store.js` are the browser contracts for marketplace encryption/decryption, transaction signing, and pseudonym identity management.

## Marketplace Notes
- Marketplace sell flow no longer generates browser ZK proofs.
- `IntelMarketLive.Transactions` now generates `seal_id` server-side, pushes nested `intel_data` to `SealEncrypt`, and accepts `blob_id` from the hook.
- Purchased-intel decrypt flow decodes `%{"data" => json}` from the hook and keeps decrypt access in the `My Listings` section after refresh.
- `Components.sell_form/1` delegates to the extracted `SellForm` module.

## JS Hooks
- `assets/js/hooks/wallet_hook.js` — wallet discovery, account selection, `signPersonalMessage`, `signTransaction`, and `reportTransactionEffects` support.
- `assets/js/hooks/seal_hook.js` — browser-side Seal encryption/decryption plus Walrus upload/fetch for marketplace flows; imports `getActivePseudonym` from pseudonym store.
- `assets/js/hooks/pseudonym_hook.js` — browser-side pseudonym identity management: wallet-derived AES-GCM key derivation, Ed25519 keypair lifecycle, encrypted key persistence, and pseudonym transaction signing.
- `assets/js/hooks/pseudonym_store.js` — shared in-memory pseudonym keypair cache used by both `pseudonym_hook.js` and `seal_hook.js`.
- `assets/js/hooks/fuel_countdown.js` — assembly fuel countdown display.
- `assets/js/hooks/infinite_scroll.js` — alert-feed pagination sentinel.

## Patterns
- Marketplace UI keeps wallet signing, browser crypto, and pseudonym key management in separate hooks: `WalletConnect` signs transactions, `SealEncrypt` handles encrypted payloads, `PseudonymKey` manages pseudonym identities.
- Session DI remains the preferred test hook for `cache_tables`, `pubsub`, `static_data`, and marketplace-specific doubles such as `walrus_client` overrides.
