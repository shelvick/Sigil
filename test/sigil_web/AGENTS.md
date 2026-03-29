# test/sigil_web/

## Test Files
- `ui_theme_test.exs` — 4 tests for UI_Theme.
- `root_layout_test.exs` — 5 tests for UI_RootLayout.
- `app_layout_test.exs` — 9 tests for UI_AppLayout.
- `router_wallet_session_test.exs` — 28 tests for APP_Router + AUTH_WalletSession.
- `dashboard_live_test.exs` — 20 tests for UI_DashboardLive.
- `tribe_overview_live_test.exs` — 19 tests for UI_TribeOverviewLive.
- `diplomacy_live_test.exs` — 41 tests for UI_DiplomacyLive including governance voting UI (via Governance + GovernanceComponents submodules).
- `assembly_detail_live_test.exs` — 45 tests for UI_AssemblyDetailLive.
- `alerts_live_test.exs` — 22 tests for UI_AlertsLive.
- `intel_live_test.exs` — 22 tests for UI_IntelLive.
- `intel_helpers_test.exs` — shared intel timestamp helper coverage.
- `intel_market_live_test.exs` — 41 tests for `SigilWeb.IntelMarketLive`, covering browse filters, seller-authored report selection, manual sell flow, restricted listing flows, signed purchase/cancel flows, decrypt-after-purchase flows, inactive-listing errors, PubSub refresh, Layer 4 pseudonym create/activate/error flows, reputation display, feedback submission, pseudonym-cancel flows, and acceptance journeys.
- `galaxy_map_live_test.exs` — 20 tests for UI_GalaxyMapLive, covering mount/render, system selection/deselection, overlay data loading (tribe + marketplace), PubSub updates, overlay toggles, inbound navigation, StaticData fallback, and acceptance journeys.

## Marketplace Test Notes
- Marketplace LiveView tests assert the Seal-era hook contract: nested `intel_data`, server-generated `seal_id`, returned `blob_id`, and decrypted `%{"data" => json}` payloads.
- Acceptance coverage verifies sell, purchase, restricted purchase, and decrypt journeys through real LiveView entry points.
- Session DI remains the primary way to inject `cache_tables`, `pubsub`, `static_data`, and marketplace doubles like `walrus_client`.

## Patterns
- Use isolated Cache and PubSub instances per test with `async: true`.
- Favor acceptance tests for user journeys and hook-event assertions for browser-contract integration.
- Keep marketplace state synchronized by rendering after PubSub broadcasts instead of using timing sleeps.
