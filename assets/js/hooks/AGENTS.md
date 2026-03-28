# assets/js/hooks/

## Hooks
- `wallet_hook.js` — wallet discovery, account selection, challenge signing, transaction signing, and transaction-effects reporting for LiveView flows.
- `seal_hook.js` — browser-side Seal encryption/decryption hook for the intel marketplace; uploads encrypted blobs to Walrus, fetches purchased blobs, builds `seal_policy::seal_approve` transaction kinds, and reuses connected wallet-provider state. Imports `getActivePseudonym` from `pseudonym_store` for pseudonym-aware decrypt flows.
- `pseudonym_hook.js` — `PseudonymKey` LiveView hook for browser-side pseudonym identity management: wallet-derived AES-GCM encryption key, Ed25519 keypair generation, encrypted private key persistence, bulk load/decrypt, activate, and pseudonym transaction signing. Events: `create_pseudonym`, `load_pseudonyms`, `activate_pseudonym`, `sign_pseudonym_tx`. Push events: `pseudonym_created`, `pseudonyms_loaded`, `pseudonym_activated`, `pseudonym_tx_signed`, `pseudonym_error`.
- `pseudonym_store.js` — in-memory pseudonym keypair cache: `cachePseudonym/2`, `getPseudonym/1`, `setActivePseudonym/1`, `activatePseudonym/1`, `getActivePseudonym/0`, `clearPseudonyms/0`. Shared between `pseudonym_hook.js` and `seal_hook.js`.
- `fuel_countdown.js` — live countdown rendering for assembly fuel depletion timestamps.
- `infinite_scroll.js` — alerts-feed sentinel observer that pushes `load_more` when the feed bottom enters view.

## Marketplace Hook Contract
- `seal_hook.js` listens for `encrypt_and_upload` and `decrypt_intel`.
- Sell flow payloads use nested `intel_data` plus a server-generated `seal_id`.
- Upload completion returns `blob_id`.
- Decrypt completion returns `%{data: json_string}`.
- Error phases are granular: `init`, `encrypt`, `upload`, `fetch`, `decrypt`.
- Wallet resolution checks already-connected accounts before attempting a new wallet connect.

## Pseudonym Hook Contract
- `pseudonym_hook.js` derives an AES-GCM encryption key from a deterministic `signPersonalMessage("Sigil pseudonym key v1")` call.
- Create flow: generates Ed25519 keypair, encrypts secret key with IV-prefixed AES-GCM, pushes `pseudonym_created` with `{pseudonym_address, encrypted_private_key}`.
- Load flow: decrypts stored encrypted keys, caches keypairs, pushes `pseudonyms_loaded` with `{addresses, active_address}`.
- Sign flow: signs raw transaction bytes using the cached pseudonym keypair, pushes `pseudonym_tx_signed` with `{signature}`.
- Error phases: `encrypt`, `load`, `activate`, `sign`.

## Patterns
- Keep wallet signing, Seal cryptography, and pseudonym key management in separate hooks: `wallet_hook.js` handles transaction approvals; `seal_hook.js` handles payload encryption; `pseudonym_hook.js` handles pseudonym identity lifecycle.
- `pseudonym_store.js` provides shared in-memory state between `pseudonym_hook.js` (writes) and `seal_hook.js` (reads via `getActivePseudonym`).
- Reuse cached Sui/Seal clients within a single `seal_hook.js` page session when the config contract is unchanged.
- Treat `data-address` on the hook root element as the canonical wallet-account selector for decrypt and pseudonym flows.
