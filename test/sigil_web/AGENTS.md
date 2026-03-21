# test/sigil_web/

## Test Files

- `ui_theme_test.exs` — 4 tests for UI_Theme (R1-R4): palette tokens, fonts, CSS vars, acceptance theme shell
- `root_layout_test.exs` — 5 tests for UI_RootLayout (R1-R5): fonts, body classes, CSRF, title suffix, assets
- `app_layout_test.exs` — 7 tests for UI_AppLayout (R1-R7): branding, nav, wallet display, disconnect, flash, content
- `router_wallet_session_test.exs` — 17 tests for APP_Router + AUTH_WalletSession (R1-R9): routes incl. /tribe/:id and /tribe/:id/diplomacy, on_mount, session CRUD, chain errors
- `dashboard_live_test.exs` — 20 tests for UI_DashboardLive (R1-R31): wallet form, assembly table, types, status, fuel, row nav, PubSub, tribe nav link, empty/error states, monitor integration, acceptance
- `tribe_overview_live_test.exs` — 14 tests for UI_TribeOverviewLive (R1-R14): auth, members, assemblies, standings summary, PubSub, acceptance
- `diplomacy_live_test.exs` — 20 tests for UI_DiplomacyLive (R1-R20): page states, standings CRUD, pilot overrides, tx signing flow, PubSub, acceptance
- `assembly_detail_live_test.exs` — 35 tests for UI_AssemblyDetailLive (R1-R32): all 5 type renderings, fuel/energy/connections panels, fuel depletion display, PubSub (monitor + direct), redirect, back nav, gate extension management (authorize/sign/submit), wallet hook handlers, monitor lifecycle, acceptance

## Test Patterns

- Isolated Cache per test: `start_supervised!({Cache, tables: [...]})`
- Isolated PubSub per test: `start_supervised!({Phoenix.PubSub, name: unique_name})`
- Unique wallet addresses: `unique_wallet_address/0` with `System.unique_integer`
- Session DI: `init_test_session(conn, %{"cache_tables" => ..., "pubsub" => ...})`
- Hammox mocks: `expect(ClientMock, :get_objects, fn ...)` for Sui chain calls
- JSON fixtures: `gate_json/1`, `turret_json/1`, etc. with Map.merge overrides
- Acceptance tests: `@tag :acceptance` — POST /session → recycle → live() full user journey
- Layout tests: `render_component/2` for isolated template rendering

## Coverage

| Module | Tests | Spec Reqs | Acceptance |
|--------|-------|-----------|------------|
| UI_Theme | 4 | R1-R4 | R4 (theme shell) |
| UI_RootLayout | 5 | R1-R5 | — |
| UI_AppLayout | 7 | R1-R7 | — |
| APP_Router + AUTH_WalletSession | 17 | R1-R9 | R1 (session flow) |
| UI_DashboardLive | 20 | R1-R31 | R27/R31 (wallet→dashboard), R29 (ensure_monitors) |
| UI_TribeOverviewLive | 14 | R1-R14 | R1 (tribe overview) |
| UI_DiplomacyLive | 20 | R1-R20 | R20 (standings flow) |
| UI_AssemblyDetailLive | 35 | R1-R32 | R13 (wallet→detail), R22 (gate ext auth), R32 (ensure monitor) |
