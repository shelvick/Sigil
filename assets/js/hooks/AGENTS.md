# assets/js/hooks/

## Hooks
- `wallet_hook.js` — wallet discovery, account selection, challenge signing, transaction signing, and transaction-effects reporting for LiveView flows.
- `seal_hook.js` — browser-side Seal encryption/decryption hook for the intel marketplace; uploads encrypted blobs to Walrus, fetches purchased blobs, builds `seal_policy::seal_approve` transaction kinds, and reuses connected wallet-provider state.
- `fuel_countdown.js` — live countdown rendering for assembly fuel depletion timestamps.
- `infinite_scroll.js` — alerts-feed sentinel observer that pushes `load_more` when the feed bottom enters view.

## Marketplace Hook Contract
- `seal_hook.js` listens for `encrypt_and_upload` and `decrypt_intel`.
- Sell flow payloads use nested `intel_data` plus a server-generated `seal_id`.
- Upload completion returns `blob_id`.
- Decrypt completion returns `%{data: json_string}`.
- Error phases are granular: `init`, `encrypt`, `upload`, `fetch`, `decrypt`.
- Wallet resolution checks already-connected accounts before attempting a new wallet connect.

## Patterns
- Keep wallet signing and Seal cryptography in separate hooks: `wallet_hook.js` handles transaction approvals; `seal_hook.js` handles payload encryption and SessionKey-based decrypt authorization.
- Reuse cached Sui/Seal clients within a single `seal_hook.js` page session when the config contract is unchanged.
- Treat `data-address` on the hook root element as the canonical wallet-account selector for decrypt flows.
