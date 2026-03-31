# Sigil

Tribe coordination for EVE Frontier, with on-chain enforcement.

Sigil is a real-time operations center that lets EVE Frontier players and tribe leaders manage diplomacy, monitor infrastructure, share intelligence, and trade secrets -- all backed by Sui Move smart contracts that enforce policy on-chain. Connect your wallet, and Sigil detects your tribe automatically. Set a standing to "hostile," and your gates deny them entry. No manual reconfiguration, no in-game alt-tabbing, no trust assumptions.

**Live:** [sigil.gigalixirapp.com](https://sigil.gigalixirapp.com)

**What this is for:** Tribe leaders who want their diplomacy enforced automatically. Solo players who want fuel alerts at 3 AM. Intel traders who want to sell secrets without revealing their identity. Anyone who wishes EVE Frontier had a proper ops tool.

## Table of Contents

- [The Hackathon Story](#the-hackathon-story)
- [What You Can Do](#what-you-can-do)
- [Architecture](#architecture)
- [On-Chain Contracts](#on-chain-contracts)
- [Tech Rundown](#tech-rundown)
- [Setup](#setup)
  - [Prerequisites](#prerequisites)
  - [Development](#development)
  - [Deployment](#deployment)
  - [Move Contracts](#move-contracts)
- [Configuration Reference](#configuration-reference)
- [Project Stats](#project-stats)
- [Current Status](#current-status)
- [License](#license)

## The Hackathon Story

Sigil started with a clear vision: build the tool that EVE Frontier tribes _need_ but nobody has built yet. An always-on operations center with diplomacy-aware infrastructure control, a strategic map with route planning, and real-time monitoring that works while you sleep.

Then I met reality.

**Pivot 1: The OwnerCap Problem.** My original governance design assumed tribe members could deposit their assembly `OwnerCap` objects into a shared contract for collective management -- deposit-weighted voting, delegated assembly enrollment, the works. Then I discovered that `OwnerCap<T>` has `key` but not `store`, meaning it can't be deposited into contracts or transferred programmatically. The entire custody-based governance model was impossible.

I redesigned around a `TribeCustodian` shared object per tribe that _doesn't need_ custody. Members subscribe their assemblies to the tribe's diplomacy policy through extensions. The Custodian holds inline standings and governance state; members retain full ownership of their caps and can detach anytime. This turned out to be a better design -- opt-in policy enforcement rather than cap lockup.

**Pivot 2: The Gate Location Problem.** My flagship feature was diplomacy-aware route planning -- "show me the safe path through hostile space." I built the gate network indexer, scanned all 68 gates on-chain, and discovered that gate locations are Poseidon2 hashes with an undocumented salt. I can't map smart gates to solar systems. Only 4 out of 68 gates have opted into revealing their locations. The strategic map was dead on arrival.

I didn't abandon the map -- I pivoted. Instead of gate routing, I built a **galaxy map** rendering all 24,502 solar systems from the World API with intel overlays. Your tribe's assembly locations, scouting reports, and marketplace listings plotted in 3D space with Three.js. Not what I planned, but arguably more useful for day-to-day operations.

**Pivot 3: The Turret Extension Wall.** I designed a diplomacy-based turret targeting extension -- prioritize hostile tribe ships during combat. Elegant on paper. Then I read the game server source: turret extensions are called with a **fixed 4-parameter signature**. There's no mechanism to pass additional shared objects like a standings table. Gate extensions work because _players_ construct the transaction. Turret extensions are _game-server-invoked_. Dead end.

I focused my energy on making gate extensions bulletproof instead, with full NBSI/NRDS policy support and per-pilot override capability.

**Pivot 4: ZK Proofs to Seal Encryption.** My intel marketplace design originally used Groth16 zero-knowledge proofs so sellers could prove reputation across anonymous identities without linking them. During implementation, I realized the fundamental flaw: the anonymity itself is the problem. A seller with a bad reputation can just abandon the address and start fresh -- the proof system can't force continuity. And self-dealing via alt accounts makes positive reputation meaningless.

I scrapped the entire ZK stack -- Circom circuits, snarkjs integration, browser WASM prover -- and rebuilt on **Mysten's Seal threshold encryption** with persistent pseudonym identities. The key insight: instead of anonymity with portable proofs, use _pseudonymity_ with sticky reputation. Each seller creates named pseudonym addresses, and reputation accrues on those addresses permanently. You _can_ abandon a pseudonym, but you lose all the reputation you built on it -- a real cost that disincentivizes bad behavior. Simpler architecture, better UX, and the economics actually work.

**What survived every pivot:** The core thesis. Elixir's OTP supervision trees map perfectly to "one GenServer per assembly, supervised, self-healing." Phoenix PubSub gives you multi-user real-time collaboration for free. The BEAM VM handles thousands of concurrent monitors without breaking a sweat. Every pivot reinforced that the technology choice was right -- I just had to adapt _what_ I built on top of it.

## What You Can Do

### For Any Player

- **Connect your Sui wallet** and see all your smart assemblies (gates, turrets, nodes, storage units) with real-time status
- **Monitor fuel levels** with server-side burn rate tracking and depletion countdown -- "fuel runs out in 3h17m at current rate"
- **Get alerts** when fuel runs low, assemblies go offline, or extensions change -- delivered to your browser _and_ your Discord channel via webhooks, even when you're not logged in
- **View the galaxy map** -- 24,502 solar systems rendered in 3D with intel overlays showing assembly locations, scouting reports, and marketplace listings

### For Tribe Leaders

- **Automatic tribe detection** -- no "create tribe" button. Sigil reads your `Character.tribe_id` from the chain and finds your fellow tribe members automatically
- **Set diplomatic standings** (Hostile / Unfriendly / Neutral / Friendly / Allied) through a shared on-chain TribeCustodian with leader election and one-person-one-vote governance
- **Enforce standings on your gates** -- authorize the `frontier_gate` extension on any gate you own. Hostile pilots are denied passage. No manual reconfiguration when diplomacy changes
- **Per-pilot overrides** -- your tribe considers them hostile, but _this_ pilot is your spy? Set a pilot-level override that trumps the tribe standing
- **NBSI / NRDS policy** -- set your default standing to decide whether unknowns are welcome or not. Changes propagate to all enrolled gates instantly
- **Share intel** with your tribe -- report assembly locations and scouting data, visible only to verified tribe members
- **View tribe aggregate** -- see all your tribe members' assemblies, standings with reputation scores, and intel summary in one place

### For Intel Traders

- **Sell intelligence pseudonymously** -- create up to 5 Ed25519 pseudonym identities, each with its own on-chain address. Your wallet is never revealed
- **Seal-encrypted delivery** -- intel is encrypted in your browser with Mysten's Seal SDK, uploaded to Walrus, and decryptable only by the buyer after purchase
- **Gas-relayed transactions** -- pseudonym marketplace transactions are sponsored by Sigil's gas relay, so your pseudonym doesn't need its own SUI balance
- **On-chain reputation** -- buyers leave positive/negative feedback tied to your pseudonym. Reputation is persistent and publicly verifiable

### For the Technically Curious

- **Automated reputation scoring** -- a gRPC-fed scoring engine subscribes to the Sui checkpoint stream in real time, processes killmail and jump events, computes per-tribe-pair scores from -1000 to +1000, and auto-submits oracle standings when score tiers cross thresholds
- **Real-time chain event delivery** -- assembly monitors receive push updates from gRPC checkpoint streaming with heartbeat polling as fallback. No 30-second polling loops
- **Pure Elixir blockchain integration** -- BCS encoding, Ed25519 signing, GraphQL queries, gRPC streaming, transaction building. Zero Node.js. Zero sidecars

## Architecture

Monolithic Phoenix application with an OTP supervision tree, domain-driven contexts, and a dedicated Sui integration layer.

```
                    ┌─────────────────────────────────────┐
                    │          Phoenix LiveView UI          │
                    │  Dashboard, Diplomacy, Intel, Map,    │
                    │  Marketplace, Alerts, Assembly Detail  │
                    └──────────────┬───────────────────────┘
                                   │ PubSub
                    ┌──────────────┴───────────────────────┐
                    │         Domain Contexts                │
                    │  Accounts, Tribes, Assemblies,         │
                    │  Diplomacy, Intel, IntelMarket,        │
                    │  Alerts, Pseudonyms                    │
                    └──────────────┬───────────────────────┘
                                   │
              ┌────────────────────┼────────────────────┐
              │                    │                     │
    ┌─────────┴──────┐  ┌─────────┴──────┐   ┌─────────┴──────────┐
    │  ETS Cache +   │  │  OTP Monitors  │   │  Sui Integration   │
    │  Postgres      │  │  Per-assembly  │   │  GraphQL, BCS,     │
    │                │  │  GenServers +  │   │  Ed25519, gRPC,    │
    │                │  │  Alert Engine  │   │  Gas Relay         │
    │                │  │  + Reputation  │   │                    │
    └────────────────┘  └───────┬────────┘   └─────────┬──────────┘
                                │                       │
                    ┌───────────┴───────────────────────┴─┐
                    │         Sui Blockchain (Testnet)      │
                    │  TribeCustodian, frontier_gate,       │
                    │  intel_market, seal_policy,            │
                    │  intel_reputation                      │
                    └──────────────────────────────────────┘
```

**Key design decisions:**

- **GenServer per assembly.** Each monitored assembly gets its own supervised process. One assembly crashing doesn't affect the others. OTP restarts it automatically.
- **ETS as primary read cache.** Blockchain state is cached in ETS for sub-microsecond reads. Successful transactions update ETS and broadcast via PubSub. Postgres persists intel reports, marketplace listings, alerts, and reputation scores.
- **Universal Move contracts.** One published package for all tribes. Per-tribe `TribeCustodian` shared objects are the parameterization, not separate contract deployments.
- **Browser-side crypto, server-side orchestration.** Wallet signing, Seal encryption/decryption, and pseudonym keypair generation happen in the browser. Transaction building, gas relay sponsorship, and state management happen on the server.

## On-Chain Contracts

All contracts are published to **Sui Testnet** (chain ID `4c78adac`).

| Contract | Purpose | Tests |
|----------|---------|-------|
| `tribe_custodian` | Tribe governance, inline standings, oracle role, leader election | 71 |
| `frontier_gate` | Gate access extension -- denies hostile pilots, supports NBSI/NRDS, per-pilot overrides | 9 |
| `intel_market` | Seal-encrypted intel marketplace with exact-payment purchase flow | 12 |
| `seal_policy` | Buyer/seller decrypt authorization for Seal threshold encryption | 6 |
| `intel_reputation` | Per-pseudonym feedback counters (positive/negative), one review per buyer per listing | 12 |
| `standings_table` | _(Obsolete)_ Original standalone standings -- retained as immutable on-chain ballast | 23 |

**Sigil Package:** [`0xc1a830f5c7f9868289ffbbc351426d9848c3ab64e0cbda3bafed38b6ab9a8db7`](https://suiscan.xyz/testnet/object/0xc1a830f5c7f9868289ffbbc351426d9848c3ab64e0cbda3bafed38b6ab9a8db7)

**EVE Frontier World Packages:**
| World | Package ID |
|-------|------------|
| Stillness | `0x28b497559d65ab320d9da4613bf2498d5946b2c0ae3597ccfda3072ce127448c` |
| Utopia | `0xd12a70c74c1e759445d6f209b01d43d860e97fcf2ef72ccbbd00afd828043f75` |

**Reputation Registry (Utopia):** `0x61e1f91705edd31774b7d1308ba6fbae870da07b869e4e717a32e15d49e5e580`

## Tech Rundown

### Pure Elixir Sui Integration

No Node.js. No TypeScript SDK wrapper. No sidecar process. The entire Sui integration is native Elixir:

- **BCS encoder** -- Binary Canonical Serialization for transaction payloads, implemented from the spec
- **Ed25519 signer** -- transaction signing and address derivation via Erlang's `:crypto` module
- **GraphQL client** -- behaviour-based Sui GraphQL client with codec, paging, request building, and dynamic field support
- **Transaction builder** -- Programmable Transaction Block construction with `SplitCoins`, `MoveCall`, `NestedResult` chaining
- **gRPC checkpoint stream** -- persistent `SubscribeCheckpoint` stream for real-time chain event delivery with cursor persistence and exponential backoff
- **Gas relay** -- server-side sponsored transactions for pseudonymous marketplace operations

### OTP Supervision

The monitoring system is the "why Elixir" showcase:

- **DynamicSupervisor** manages one `AssemblyMonitor` GenServer per assembly
- **Registry** enables O(1) lookup and direct event dispatch from the gRPC stream
- **AssemblyEventRouter** fans out checkpoint events to the correct monitor via Registry
- **AlertEngine** subscribes to monitor broadcasts, evaluates fuel/offline/extension rules, and dispatches Discord webhooks
- **ReputationEngine** subscribes to killmail and jump events from the gRPC stream, computes per-tribe-pair scores, and auto-submits oracle standings on tier crossings
- If any process crashes, OTP restarts it. The rest of the system keeps running.

### Real-Time Everything

Phoenix LiveView + PubSub means every connected browser sees changes instantly:

- Diplomacy changes propagate to all tribe members viewing the editor
- Intel reports appear in the feed without refresh
- Assembly status updates stream from gRPC to monitor to PubSub to LiveView
- Marketplace listings update across all viewers on purchase/cancel
- Alert acknowledgments sync across sessions

### Browser Crypto

Security-sensitive operations stay in the browser:

- **Wallet signing** via Sui Wallet Standard (EVE Vault preferred)
- **Seal encryption/decryption** via `@mysten/seal` for marketplace intel
- **Pseudonym Ed25519 keypair generation** via `@mysten/sui` -- keys are encrypted with a wallet-derived AES key before server-side storage
- **Seal SessionKey creation** for pseudonym decrypt authorization

### Galaxy Map

Three.js point-cloud rendering of 24,502 solar systems from World API coordinate data:

- Orbit/pan/zoom controls with constellation clustering
- Intel overlay layers (tribe assembly locations, scouting reports, marketplace listings)
- Bidirectional navigation -- click "View on Map" from any assembly, intel report, or marketplace listing
- System detail panel with cross-page navigation links
- PubSub-driven real-time overlay updates
- Iterative coordinate normalization (no stack overflow at 24K+ points)

## Setup

### Prerequisites

- **Elixir** 1.18+ with **OTP** 27
- **PostgreSQL** 17+
- **Sui CLI** 1.67+ (for Move contract development only)

### Development

```bash
git clone https://github.com/shelvick/Sigil.git
cd Sigil
```

Install dependencies and set up the database:

```bash
mix deps.get
mix ecto.create
mix ecto.migrate
```

Populate static reference data (solar systems, constellations, item types) from the World API:

```bash
mix sigil.populate_static_data
```

Set the required environment variables, either via shell exports or your preferred env management:

```bash
export EVE_WORLD=stillness
export SECRET_KEY_BASE=$(mix phx.gen.secret)
```

See the [Configuration Reference](#configuration-reference) for all available variables and their defaults.

Start the dev server:

```bash
iex -S mix phx.server
```

Open [http://localhost:4000](http://localhost:4000). You'll need an EVE Frontier-compatible Sui wallet (EVE Vault recommended) to authenticate.

Run the test suite:

```bash
mix test                          # 1,189 tests, all async
mix format --check-formatted      # Code formatting
mix credo --min-priority=high     # Linting
mix dialyzer                      # Type checking
```

Move contract tests:

```bash
cd contracts && sui move test     # 133 Move tests
```

JavaScript tests:

```bash
cd assets && npx vitest run       # ~60 JS tests
```

### Deployment

Sigil is deployed to [Gigalixir](https://gigalixir.com) (free tier). For your own deployment:

1. Create a Gigalixir app and Postgres database
2. Set environment variables via `gigalixir config:set`
3. Push to the Gigalixir remote

```bash
# Required production env vars:
gigalixir config:set SECRET_KEY_BASE="$(mix phx.gen.secret)"
gigalixir config:set DATABASE_URL="your-database-url"
gigalixir config:set EVE_WORLD="stillness"
gigalixir config:set PHX_HOST="your-app.gigalixirapp.com"

# Optional (for full marketplace + relay functionality):
gigalixir config:set RELAY_KEYPAIR="base64-encoded-keypair"
gigalixir config:set SEAL_KEY_SERVER_OBJECT_IDS="0x...,0x..."
gigalixir config:set SEAL_THRESHOLD="2"
gigalixir config:set SUI_STILLNESS_SIGIL_PACKAGE_ID="0x..."

# Deploy
git push gigalixir main
```

After first deploy, run the migration:

```bash
gigalixir run mix ecto.migrate
```

The health endpoint is at `/api/health`.

### Move Contracts

To publish your own instance of the Sigil contracts:

```bash
cd contracts
sui move build
sui client publish --gas-budget 100000000
```

Note the published package ID and update your `SUI_*_SIGIL_PACKAGE_ID` environment variable accordingly. All tribes share the same package -- per-tribe `TribeCustodian` shared objects are created at runtime.

## Configuration Reference

Configuration is via environment variables. In development, most values have sensible defaults in `config/dev.exs` and `config/config.exs` -- you typically only need to set `EVE_WORLD`. In production, `SECRET_KEY_BASE`, `DATABASE_URL`, and `PHX_HOST` are required.

**Core:**

| Variable | Default | Description |
|----------|---------|-------------|
| `EVE_WORLD` | `stillness` | Active world context: `stillness`, `utopia`, `internal`, `localnet` |
| `SECRET_KEY_BASE` | hardcoded in dev | Phoenix session signing key. **Required in prod.** Generate: `mix phx.gen.secret` |
| `DATABASE_URL` | hardcoded in dev | Ecto connection URL. **Required in prod.** |
| `PHX_HOST` | `localhost` | Hostname for URL generation. **Required in prod.** |
| `PORT` | `4000` | HTTP listen port |
| `POOL_SIZE` | `10` | Database connection pool size (prod only) |

**Sui / Seal / Walrus:**

| Variable | Default | Description |
|----------|---------|-------------|
| `SUI_STILLNESS_SIGIL_PACKAGE_ID` | unpublished | Sigil contract package ID for Stillness world |
| `SUI_UTOPIA_SIGIL_PACKAGE_ID` | unpublished | Sigil contract package ID for Utopia world |
| `SUI_INTERNAL_SIGIL_PACKAGE_ID` | unpublished | Sigil contract package ID for Internal world |
| `RELAY_KEYPAIR` | auto-generated | Base64-encoded Ed25519 keypair for gas relay. Falls back to `.sigil/relay_key` file, then generates a fresh keypair |
| `SEAL_KEY_SERVER_OBJECT_IDS` | _(none)_ | Comma-separated Seal key server object IDs. Required for marketplace encrypt/decrypt |
| `SEAL_THRESHOLD` | key server count | Number of Seal key servers needed for threshold decrypt |
| `WALRUS_PUBLISHER_URL` | testnet endpoint | Walrus blob upload endpoint |
| `WALRUS_AGGREGATOR_URL` | testnet endpoint | Walrus blob read endpoint |
| `WALRUS_EPOCHS` | `15` | Number of Walrus epochs for blob storage |
| `SUI_RPC_URL` | testnet fullnode | Sui RPC URL used by Seal config |

**Localnet only:**

| Variable | Description |
|----------|-------------|
| `SUI_LOCALNET_PACKAGE_ID` | World package ID for local Sui network |
| `SUI_LOCALNET_SIGIL_PACKAGE_ID` | Sigil package ID for local Sui network |
| `SUI_LOCALNET_SIGNER_KEY` | Hex-encoded signer key for localnet seed task |

**Application config** (set in `config/config.exs`, not via env vars):

| Key | Default | Description |
|-----|---------|-------------|
| `:start_monitor_supervisor` | `true` | Start the per-assembly monitor DynamicSupervisor |
| `:start_assembly_event_router` | `false` | Start the gRPC-to-monitor event router |
| `:start_alert_engine` | `true` | Start the alert rule evaluation engine |
| `:start_grpc_stream` | `false` | Start the gRPC checkpoint stream (checked at GenServer init) |

## Project Stats

| Metric | Count |
|--------|-------|
| Elixir source | ~27,000 lines across 106 modules |
| Elixir tests | 1,189 (all `async: true`, verified 10x deterministic) |
| Test code | ~37,000 lines (1.4x source ratio) |
| Move contracts | 7 modules, ~1,050 lines |
| Move tests | 133 |
| JavaScript | ~4,800 lines (hooks + Three.js galaxy map) |
| JS tests | ~2,650 lines |
| Component specs | 85 detailed specifications |

All 1,189 Elixir tests run fully parallel with zero global state. The IMPLEMENT phase git hook runs the entire suite 10 times to catch non-deterministic failures. No `async: false` anywhere.

## Current Status

Sigil is a **hackathon project** built for the March 2026 EVE Frontier Hackathon. It's functional and deployed, but should be treated as a proof of concept rather than production infrastructure.

**What works well:**
- Full wallet authentication flow with zkLogin verification
- Real-time assembly monitoring with fuel depletion forecasting
- On-chain diplomacy with gate access enforcement
- Tribe auto-detection and aggregate views
- Intel sharing with tribe-scoped access control
- Seal-encrypted marketplace with pseudonymous trading
- Automated reputation scoring from chain events
- Discord webhook alerts
- Galaxy map with intel overlays
- 1,322 total tests (Elixir + Move + JS) all passing

**Known limitations:**
- Gate locations remain unresolvable (Poseidon2 hash, undocumented salt) -- route planning deferred
- Turret extensions impossible (game server fixed signature) -- platform-level blocker
- Gas relay is stateless (no rate limiting) -- acceptable for hackathon scope

**Deferred features** (blocked by external dependencies, not by implementation capacity):
- Diplomacy-aware route planning (needs gate location hash encoding to be published)
- Turret targeting extension (needs extension configuration support at the platform level)
- OwnerCap custody and deposit-weighted voting (needs `store` ability on OwnerCap)

## License

Sigil is licensed under the [MIT License](LICENSE).
