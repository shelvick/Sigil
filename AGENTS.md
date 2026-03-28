# Sigil

## Overview

Tribe coordination tool for EVE Frontier. Manages diplomacy, infrastructure, intel sharing, and alerts with on-chain enforcement via Sui Move smart contracts.

**Stack:** Elixir 1.18.3 / Phoenix 1.8 / LiveView 1.0 / PostgreSQL 17.8 / Sui Move (testnet)

## Architecture

Monolithic Phoenix app with OTP supervision tree, domain-driven contexts, and dedicated Sui integration layer.

- **Sui Integration** (`lib/sigil/sui/`): GraphQL client (behaviour + HTTP impl with Codec/Paging/Request/DynamicFields submodules), BCS encoder, Ed25519 signer, transaction builder, gas relay (sponsored pseudonym transactions), gRPC checkpoint stream (GenServer with Codec/Connector/CursorStore submodules for real-time chain event delivery) — pure Elixir interface to Sui blockchain
- **Static Data** (`lib/sigil/static_data/`): DETS-backed World API reference data (types, 24,502 solar systems with x/y/z coordinates, constellations)
- **Data Layer** (`lib/sigil/`): ETS cache for blockchain state plus Ecto repo for intel reports, intel marketplace listings, alerts, webhook configs, reputation scores, and checkpoint cursors
- **Domain Contexts** (`lib/sigil/`): Accounts (wallet session + character lookup), Assemblies (assembly discovery + cached query + gate extension auth), Tribes (automatic formation + member aggregation), Diplomacy (facade with Discovery/TransactionOps/ReputationOps/Governance submodules — custodian-first standings CRUD, reputation pin/oracle management, leader voting), Intel (tribe-scoped location + scouting reports with ETS cache + Postgres + PubSub), IntelMarket (Seal marketplace with Transactions/Reputation submodules — sell/purchase/cancel, Walrus blob preflight, pseudonym sell/cancel via gas relay, reputation feedback), Pseudonyms (encrypted keypair lifecycle, max 5 per account), Alerts (lifecycle CRUD + dedup/cooldown + webhook config)
- **Reputation Engine** (`lib/sigil/reputation/`): gRPC-fed scoring GenServer with Scorer/OracleSubmitter/Persistence/ScoreState/Tables submodules. Subscribes to chain events (kills, jumps), computes per-tribe-pair scores (-1000 to +1000), auto-submits oracle standings on tier crossings
- **OTP Monitors** (`lib/sigil/game_state/`): DynamicSupervisor + Registry for per-assembly AssemblyMonitor GenServers with fuel depletion prediction via FuelAnalytics; AlertEngine (Runtime/Dispatcher/RuleEvaluator submodules) subscribes to monitor activity and dispatches Discord/webhook notifications including reputation threshold alerts
- **LiveView UI** (`lib/sigil_web/`): Dashboard (multi-account wallet connect + character picker + assembly manifest + alerts summary), assembly detail views (5 types + fuel depletion countdown + intel location + gate extension management), diplomacy editor (Events/State/Transactions/Sections submodules + Governance/GovernanceComponents — standings, reputation scores, pin toggle, oracle management, leader voting), tribe overview (custodian standings + reputation scores + intel summary), intel feed (location + scouting reports), intel marketplace (Seal-encrypted listing + purchase + pseudonym sell/cancel + reputation display + buyer feedback), alerts feed (account-scoped + ack/dismiss + infinite scroll), EVE Frontier themed shell
- **Auth** (`lib/sigil_web/`): zkLogin wallet session with active character hydration, pseudonym management (browser Ed25519 keypair generation + encrypted server-side storage + Seal SessionKey creation)
- **Move Contracts**: TribeCustodian (governance + inline standings + oracle role), frontier_gate (standings-based access control), IntelMarket (Seal-era encrypted marketplace), SealPolicy (buyer/seller decrypt authorization), IntelReputation (per-pseudonym feedback counters). Published to testnet. StandingsTable + TxDiplomacy retained as compatibility ballast (immutable on-chain)

## Key Directories

| Directory | Purpose |
|-----------|---------|
| `lib/sigil/sui/` | Sui blockchain integration (BCS, Signer, Client, TransactionBuilder, GasRelay, GrpcStream, Types) |
| `lib/sigil/sui/client/` | HTTP implementation of Sui GraphQL client (Codec, Paging, Request, DynamicFields submodules) |
| `lib/sigil/sui/grpc_stream/` | gRPC checkpoint stream internals (Codec, Connector, CursorStore) |
| `lib/sigil/sui/types/` | Elixir structs for Sui Move types (Assembly, Gate, Turret, etc.) |
| `lib/sigil/sui/transaction_builder/` | PTB BCS encoding internals |
| `lib/sigil/static_data/` | DETS-backed static data store + World API client |
| `lib/sigil/` | Application core (OTP app, Repo, EtsCache, Endpoint, Router) + domain contexts |
| `lib/sigil/diplomacy/` | Diplomacy submodules (Discovery, TransactionOps, ReputationOps, Governance) |
| `lib/sigil/intel/` | Intel report Ecto schema |
| `lib/sigil/intel_market/` | Intel marketplace submodules (Transactions, Reputation) |
| `lib/sigil/reputation/` | Reputation engine (Engine with Scorer/OracleSubmitter/Persistence/ScoreState/Tables, EventParser, Scoring algorithms) |
| `lib/sigil/alerts/` | Alert pipeline: schema, context, engine GenServer (Runtime/Dispatcher/RuleEvaluator), webhook notifier (Discord) |
| `lib/sigil/game_state/` | FuelAnalytics, AssemblyMonitor, MonitorSupervisor — persistent per-assembly monitoring |
| `lib/sigil/walrus_client/` | Walrus HTTP client for blob upload/read/existence checks |
| `lib/sigil_web/` | Phoenix web layer: router, session, layouts, LiveViews, shared helpers |
| `lib/sigil_web/live/` | LiveView modules: dashboard, assembly detail, diplomacy, tribe overview, intel, intel marketplace, alerts |
| `assets/js/hooks/` | JS hooks: wallet_connect, seal_hook, pseudonym_key, fuel_countdown, infinite_scroll |
| `contracts/sources/` | Sui Move contracts: tribe_custodian, frontier_gate, intel_market, seal_policy, intel_reputation, standings_table |
| `lib/mix/tasks/sigil/` | Mix tasks (populate_static_data) |
| `test/` | Tests mirroring lib/ structure |

## Development Patterns

- **Behaviour + DI:** `@callback` contracts with `Hammox.defmock` for test doubles; `Application.compile_env!` for injection
- **Req.Test plug injection:** Tests pass `req_options: [plug: {Req.Test, stub}]` for HTTP stubbing
- **All tests `async: true`**: No named processes, no named ETS, no global state
- **Error tuples:** `{:ok, result} | {:error, reason}` throughout
- **@spec mandatory:** All public functions require typespecs

## Dependencies

| Library | Purpose |
|---------|---------|
| `phoenix`, `phoenix_live_view` | Web framework + real-time UI |
| `ecto_sql`, `postgrex` | Database (intel reports, listings, alerts, reputation scores, checkpoint cursors) |
| `req` | HTTP client (Sui GraphQL, World API, Walrus, Discord webhooks) |
| `blake2` | Blake2b-256 hashing (tx digests, address derivation) |
| `hammox` | Behaviour-enforced test mocks |
| `jason` | JSON encoding/decoding |
| `credo`, `dialyxir` | Static analysis + type checking |
| `grpc`, `protobuf` | Sui gRPC checkpoint streaming for real-time chain event delivery |
