# Sigil

## Overview

Tribe coordination tool for EVE Frontier. Manages diplomacy, infrastructure, intel sharing, and alerts with on-chain enforcement via Sui Move smart contracts.

**Stack:** Elixir 1.18.3 / Phoenix 1.8 / LiveView 1.0 / PostgreSQL 17.8 / Sui Move (testnet)

## Architecture

Monolithic Phoenix app with OTP supervision tree, domain-driven contexts, and dedicated Sui integration layer.

- **Sui Integration** (`lib/sigil/sui/`): GraphQL client, BCS encoder, Ed25519 signer, transaction builder — pure Elixir interface to Sui blockchain. Planned: gRPC checkpoint stream for real-time event delivery (replaces polling for monitors)
- **Static Data** (`lib/sigil/static_data/`): DETS-backed World API reference data (types, systems, constellations)
- **Data Layer** (`lib/sigil/`): ETS cache for blockchain state plus Ecto repo for intel report and alert persistence
- **Domain Contexts** (`lib/sigil/`): Accounts (wallet session + character lookup), Assemblies (assembly discovery + cached query + gate extension auth), Tribes (automatic formation + member aggregation), Diplomacy (custodian-first standings CRUD + tx building), Intel (tribe-scoped location + scouting reports with ETS cache + Postgres + PubSub), Alerts (lifecycle CRUD + dedup/cooldown + webhook config)
- **OTP Monitors** (`lib/sigil/game_state/`): DynamicSupervisor + Registry for per-assembly AssemblyMonitor GenServers with fuel depletion prediction via FuelAnalytics; AlertEngine subscribes to monitor activity and dispatches Discord/webhook notifications; planned: gRPC-fed monitors (replaces polling)
- **LiveView UI** (`lib/sigil_web/`): Dashboard (wallet form + assembly manifest + monitor-driven updates), assembly detail views (5 types + fuel depletion countdown + intel location), diplomacy editor, tribe overview (custodian standings + intel summary), intel feed (location + scouting reports), EVE Frontier themed shell; planned: alert feed
- **Move Contracts**: StandingsTable + TribeCustodian + frontier_gate (published to testnet); planned: frontier_turret (deferred)

## Key Directories

| Directory | Purpose |
|-----------|---------|
| `lib/sigil/sui/` | Sui blockchain integration (BCS, Signer, Client, TransactionBuilder, Types) |
| `lib/sigil/sui/client/` | HTTP implementation of Sui GraphQL client |
| `lib/sigil/sui/types/` | Elixir structs for Sui Move types (Assembly, Gate, Turret, etc.) |
| `lib/sigil/sui/transaction_builder/` | PTB BCS encoding internals |
| `lib/sigil/static_data/` | DETS-backed static data store + World API client |
| `lib/sigil/` | Application core (OTP app, Repo, EtsCache, Endpoint, Router) + domain contexts |
| `lib/sigil/intel/` | Intel report Ecto schema |
| `lib/sigil/alerts/` | Alert pipeline: schema, context, engine GenServer, webhook notifier (Discord) |
| `lib/sigil/game_state/` | FuelAnalytics, AssemblyMonitor, MonitorSupervisor — persistent per-assembly monitoring |
| `lib/sigil_web/` | Phoenix web layer: router, session, layouts, LiveViews, shared helpers |
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
| `ecto_sql`, `postgrex` | Database (intel report + alert persistence) |
| `req` | HTTP client (Sui GraphQL, World API, Discord webhooks) |
| `blake2` | Blake2b-256 hashing (tx digests, address derivation) |
| `hammox` | Behaviour-enforced test mocks |
| `jason` | JSON encoding/decoding |
| `credo`, `dialyxir` | Static analysis + type checking |
| `grpc`, `protobuf` | (planned) Sui gRPC checkpoint streaming for real-time monitors |
