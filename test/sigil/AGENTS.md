# test/sigil/

## Test Files

- `accounts_test.exs` — 14 tests for Sigil.Accounts (R1-R14), async: true
- `assemblies_test.exs` — 39 tests for Sigil.Assemblies (R1-R36 + edge cases), async: true
- `cache_test.exs` — Tests for Sigil.Cache GenServer
- `tribes_test.exs` — 18 tests for Sigil.Tribes (R1-R16 + 2 edge cases), async: true
- `diplomacy_test.exs` — 52 tests for Sigil.Diplomacy (R1-R43 including governance via Diplomacy.Governance submodule), async: true
- `gate_indexer_test.exs` — 25 tests for Sigil.GateIndexer (R1-R24 + restart edge case), async: true
- `intel_test.exs` — 21 tests for Sigil.Intel (R1-R20 + edge): report_location (create + upsert + ETS cache + PubSub), report_scouting, list_intel (tribe-scoped), get_location (cache + DB fallback), delete_intel (author + leader + cross-tribe), load_cache, unauthorized scope rejection, async: true
- `intel/intel_report_test.exs` — 11 tests for Sigil.Intel.IntelReport (R1-R8 + migration/edge), async: true
- `application_test.exs` — 17 tests for OTP supervision tree, including GateIndexer + MonitorRegistry + MonitorSupervisor + AlertEngine + :intel cache table + CacheResolver.application_static_data
- `game_state/fuel_analytics_test.exs` — 10 tests for FuelAnalytics (R1-R10), async: true
- `game_state/assembly_monitor_test.exs` — 20 tests for AssemblyMonitor (R1-R18 + extras), async: true
- `game_state/monitor_supervisor_test.exs` — 13 tests for MonitorSupervisor (R1-R11 + lifecycle), async: true
- `alert_test.exs` — 12 tests for Sigil.Alerts.Alert + WebhookConfig schemas (R1-R12), async: true
- `alerts_test.exs` — 20 tests for Sigil.Alerts context (R1-R20), async: true
- `alerts/engine_test.exs` — 20 tests for Sigil.Alerts.Engine (R1-R19 + edge), async: true
- `alerts/webhook_notifier_discord_test.exs` — 11 tests for WebhookNotifier.Discord (R1-R10 + edge), async: true
- `repo_test.exs` — Repo persistence tests covering migration-backed intel tables and sandbox usage, async: true
- `intel_market_test.exs` — 44 tests for Sigil.IntelMarket covering chain sync, seller/purchased listing queries, Seal config, stale cleanup, signed submission reconciliation, restricted purchases, Walrus blob availability, Layer 4 reputation queries/feedback tx builders, pseudonym create/cancel flows, and relay-sponsored submission, async: true
- `intel/intel_listing_test.exs` — 13 tests for Sigil.Intel.IntelListing schema validation and persistence, async: true
- `walrus_client_test.exs` — 8 tests for Sigil.WalrusClient.HTTP upload/read/existence contracts, async: true
- `pseudonym_test.exs` — 6 tests for Sigil.Pseudonym schema validation (required fields, 0x-prefix, non-empty binary key, valid changeset), async: true
- `pseudonyms_test.exs` — 10 tests for Sigil.Pseudonyms context CRUD (create, list, get, delete, limit enforcement, concurrent limit enforcement), async: true

## Test Patterns

- Isolated Cache per test: `start_supervised!({Cache, tables: [...]})`
- Isolated PubSub per test: `start_supervised!({Phoenix.PubSub, name: unique_name})`
- Hammox mocks: `expect(ClientMock, :get_objects, fn ...)` with `verify_on_exit!`
- JSON fixtures via private helper functions with map merge overrides
- Acceptance tests tagged `@tag :acceptance` — test full flows without pre-populated state
- Ecto sandbox via `Sigil.DataCase` for Repo-backed tests (intel, alerts, engine)
- Injectable funs for engine tests: `create_alert_fun`, `dispatch_fun`, `now_fun`, `subscribe_fun`
- Req.Test plug injection for webhook Discord tests

## Coverage

| Module | Tests | Spec Reqs | Acceptance |
|--------|-------|-----------|------------|
| Accounts | 14 | R1-R14 | R14 (register→get flow) |
| Assemblies | 39 | R1-R36 + edge | R21 (discover→list→get flow), R36 (build→submit→verify) |
| Tribes | 18 | R1-R16 + 2 edge | R16 (register→discover→list→assemblies) |
| Diplomacy | 52 | R1-R43 + acceptance + governance | R22 (discover→build→submit→verify), R41 (vote→governance refresh) |
| TxDiplomacy | 11 | R1-R11 | R11 (build→TransactionBuilder integration) |
| TxGateExtension | 10 | R1-R10 | R8 (PTB→BCS integration) |
| Cache | 11 | R1-R11 | — |
| GateIndexer | 25 | R1-R24 + restart | R24 (start→scan→query→re-scan) |
| Intel | 21 | R1-R20 + edge | R20 (report→list→verify) |
| IntelReport | 11 | R1-R8 + edge | — |
| Application | 17 | R1-R17 | — |
| FuelAnalytics | 10 | R1-R10 | — |
| AssemblyMonitor | 20 | R1-R18 + extras | — |
| MonitorSupervisor | 13 | R1-R11 + lifecycle | R10 (ensure→get round-trip) |
| Alert (schema) | 12 | R1-R12 | R10 (migration integration) |
| Alerts (context) | 20 | R1-R20 | R20 (lifecycle dedup+cooldown) |
| AlertEngine | 20 | R1-R19 + edge | R19 (monitor event→persist→Discord) |
| WebhookNotifier.Discord | 11 | R1-R10 + edge | R10 (end-to-end webhook) |
| IntelMarket | 44 | Seal sync + tx + blob + reputation + pseudonym flows | create→purchase→sold + restricted + stale-sync + reputation + pseudonym relay coverage |
| IntelListing | 13 | Schema validation + persistence | — |
| WalrusClient | 8 | upload/read/existence contract | — |
| Pseudonym | 6 | Schema validation | — |
| Pseudonyms | 10 | CRUD + limit + concurrency | create→list→get→delete + advisory lock concurrency |
