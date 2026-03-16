# Sigil

## Overview

Tribe coordination tool for EVE Frontier. Manages diplomacy, infrastructure, and alerts with on-chain enforcement via Sui Move smart contracts.

**Stack:** Elixir 1.18.3 / Phoenix 1.8 / LiveView 1.0 / PostgreSQL 17.8 / Sui Move (testnet)

## Architecture

Monolithic Phoenix app with OTP supervision tree, domain-driven contexts, and dedicated Sui integration layer.

- **Sui Integration** (`lib/sigil/sui/`): GraphQL client, BCS encoder, Ed25519 signer, transaction builder — pure Elixir interface to Sui blockchain
- **Static Data** (`lib/sigil/static_data/`): DETS-backed World API reference data (types, systems, constellations)
- **Data Layer** (`lib/sigil/`): ETS cache for blockchain state, Ecto repo (deferred to alert persistence)
- **Domain Contexts** (`lib/sigil/`): Accounts (wallet session + character lookup), Assemblies (assembly discovery + cached query); planned: Diplomacy, Alerts
- **OTP Monitors** (`lib/sigil/game_state/`): On-demand linked StatePoller for assembly refresh; planned: DynamicSupervisor, alert engine
- **LiveView UI** (`lib/sigil_web/`): Dashboard (wallet form + assembly manifest), assembly detail views (5 types), EVE Frontier themed shell; planned: diplomacy editor, alert feed
- **Move Contracts** (planned): StandingsTable, frontier_gate, frontier_turret

## Key Directories

| Directory | Purpose |
|-----------|---------|
| `lib/sigil/sui/` | Sui blockchain integration (BCS, Signer, Client, TransactionBuilder, Types) |
| `lib/sigil/sui/client/` | HTTP implementation of Sui GraphQL client |
| `lib/sigil/sui/types/` | Elixir structs for Sui Move types (Assembly, Gate, Turret, etc.) |
| `lib/sigil/sui/transaction_builder/` | PTB BCS encoding internals |
| `lib/sigil/static_data/` | DETS-backed static data store + World API client |
| `lib/sigil/` | Application core (OTP app, Repo, EtsCache, Endpoint, Router) |
| `lib/sigil/game_state/` | On-demand linked StatePoller GenServer |
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
| `ecto_sql`, `postgrex` | Database (deferred to Slice 3) |
| `req` | HTTP client (Sui GraphQL, World API) |
| `blake2` | Blake2b-256 hashing (tx digests, address derivation) |
| `hammox` | Behaviour-enforced test mocks |
| `jason` | JSON encoding/decoding |
| `credo`, `dialyxir` | Static analysis + type checking |

