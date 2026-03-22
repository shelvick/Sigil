# test/sigil_web/

## Test Files

- `ui_theme_test.exs` — 4 tests for UI_Theme (R1-R4): palette tokens, fonts, CSS vars, acceptance theme shell
- `root_layout_test.exs` — 5 tests for UI_RootLayout (R1-R5): fonts, body classes, CSRF, title suffix, assets
- `app_layout_test.exs` — 7 tests for UI_AppLayout (R1-R7): branding, nav, wallet display, disconnect, flash, content
- `router_wallet_session_test.exs` — 26 tests for APP_Router + AUTH_WalletSession (R1-R12): routes incl. `/tribe/:id`, `/tribe/:id/diplomacy`, `/tribe/:id/intel`, on_mount, session CRUD, chain errors
- `dashboard_live_test.exs` — 20 tests for UI_DashboardLive (R1-R31): wallet form, assembly table, types, status, fuel, row nav, PubSub, tribe nav link, empty/error states, monitor integration, acceptance
- `tribe_overview_live_test.exs` — 19 tests for UI_TribeOverviewLive (R1-R19): auth, members, assemblies, custodian standings summary, intel summary counts, View Intel link, intel PubSub updates, acceptance
- `diplomacy_live_test.exs` — 34 tests for UI_DiplomacyLive: custodian page states, leader/non-leader split, standings CRUD, pilot overrides, tx signing flow, PubSub, acceptance
- `assembly_detail_live_test.exs` — 43 tests for UI_AssemblyDetailLive: all 5 type renderings, fuel/energy/connections panels, fuel depletion display, PubSub (monitor + direct), redirect, back nav, gate extension management, wallet hook handlers, monitor lifecycle, intel location display + Set Location + PubSub sync, acceptance
- `intel_live_test.exs` — 20 tests for UI_IntelLive (R1-R16): auth/redirect, location + scouting submission, solar system resolution, delete (author + non-author), PubSub updates (upsert-aware), report type toggle, empty state, StaticData unavailable, acceptance
- `intel_helpers_test.exs` — tests for SigilWeb.IntelHelpers: relative_timestamp_label/2 buckets (Just now, Xm ago, Xh ago, Xd ago, absolute date)

## Test Patterns

- Isolated Cache per test: `start_supervised!({Cache, tables: [...]})`
- Isolated PubSub per test: `start_supervised!({Phoenix.PubSub, name: unique_name})`
- Unique wallet addresses: `unique_wallet_address/0` with `System.unique_integer`
- Session DI: `init_test_session(conn, %{"cache_tables" => ..., "pubsub" => ...})`
- Hammox mocks: `expect(ClientMock, :get_objects, fn ...)` for Sui chain calls
- JSON fixtures: `gate_json/1`, `turret_json/1`, etc. with `Map.merge` overrides
- Acceptance tests: `@tag :acceptance` — `POST /session` → recycle → `live()` full user journey
- Diplomacy / tribe overview coverage is custodian-first: no legacy `create_table`, `select_table`, or `no_table` expectations remain
- Layout tests: `render_component/2` for isolated template rendering

## Coverage

| Module | Tests | Spec Reqs | Acceptance |
|--------|-------|-----------|------------|
| UI_Theme | 4 | R1-R4 | R4 (theme shell) |
| UI_RootLayout | 5 | R1-R5 | — |
| UI_AppLayout | 7 | R1-R7 | — |
| APP_Router + AUTH_WalletSession | 26 | R1-R12 | R1 (session flow) |
| UI_DashboardLive | 20 | R1-R31 | R27/R31 (wallet→dashboard), R29 (ensure_monitors) |
| UI_TribeOverviewLive | 19 | R1-R19 | R1/R19 (tribe overview + intel entry) |
| UI_DiplomacyLive | 34 | custodian-first flow | leader standings flow, custodian setup flow |
| UI_AssemblyDetailLive | 43 | monitor + intel detail flow | R13 (wallet→detail), R22 (gate ext auth), set-location journey |
| UI_IntelLive | 20 | R1-R16 | R1/R13 (intel page + sharing journey) |
| IntelHelpers | — | — | — |
