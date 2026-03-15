# test/frontier_os_web/

## Test Files

- `ui_theme_test.exs` — 4 tests for UI_Theme (R1-R4): palette tokens, fonts, CSS vars, acceptance theme shell
- `root_layout_test.exs` — 5 tests for UI_RootLayout (R1-R5): fonts, body classes, CSRF, title suffix, assets
- `app_layout_test.exs` — 7 tests for UI_AppLayout (R1-R7): branding, nav, wallet display, disconnect, flash, content
- `router_wallet_session_test.exs` — 15 tests for APP_Router + AUTH_WalletSession (R1-R8): routes, on_mount, session CRUD, chain errors
- `dashboard_live_test.exs` — 14 tests for UI_DashboardLive (R1-R12): wallet form, assembly table, types, status, fuel, row nav, PubSub, empty/error states, acceptance
- `assembly_detail_live_test.exs` — 15 tests for UI_AssemblyDetailLive (R1-R13): all 5 type renderings, fuel/energy/connections panels, PubSub, redirect, back nav, edge cases, acceptance
- `poller_test.exs` → in `test/frontier_os/game_state/` — 10 tests for PROC_StatePoller (R1-R10)

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
| APP_Router + AUTH_WalletSession | 15 | R1-R8 | R1 (session flow) |
| UI_DashboardLive | 14 | R1-R12 | R12 (wallet→dashboard) |
| UI_AssemblyDetailLive | 15 | R1-R13 | R13 (wallet→detail) |
| PROC_StatePoller | 10 | R1-R10 | — |
