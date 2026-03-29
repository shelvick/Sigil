# assets/js/__tests__/

## Test Files
- `wallet_hook.test.js` — wallet discovery, multi-account selection, challenge signing, transaction signing, and wallet cache-effect reporting.
- `seal_hook.test.js` — Seal encrypt/upload, Walrus fetch/decrypt, client reuse, wallet reuse, approval-transaction construction, and phase-specific error handling.
- `app_hooks.test.js` — hook registration smoke test for `WalletConnect`, `SealEncrypt`, `FuelCountdown`, and `InfiniteScroll`.
- `fuel_countdown.test.js` — countdown lifecycle and display behavior.
- `infinite_scroll.test.js` — sentinel observation, disconnect/rebind behavior, and stop conditions.
- `galaxy_map.test.js` — 13 tests: 8 pure utility tests (normalizeCoordinates, buildSystemIndex, buildOverlayPositions, resolveSystemId, createDefaultCamera, shouldShowConstellations) + 5 hook integration tests (map_ready, system_selected, system_deselected, select_system, WebGL fallback).
- `support/` — hook mounting and wallet mock helpers shared across browser-hook tests.

## Marketplace Coverage Notes
- `seal_hook.test.js` verifies the as-built contract: nested `intel_data`, server-provided `seal_id`, returned `blob_id`, decrypted `%{data: json_string}`, granular error phases, and reuse of already-connected wallet accounts.
- `app_hooks.test.js` ensures `seal_hook.js` remains registered in `assets/js/app.js` under `SealEncrypt`.

## Patterns
- Keep hook tests isolated with mocked browser APIs, mocked Wallet Standard providers, and mocked `@mysten/seal` / `@mysten/sui` dependencies.
- Assert emitted hook events rather than internal implementation details whenever possible.
