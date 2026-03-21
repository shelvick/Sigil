# lib/sigil/

## Modules

- `Sigil.Application` (`application.ex`) — OTP app: Telemetry, Repo, PubSub, Cache(7 tables), StaticData, GateIndexer, MonitorRegistry, MonitorSupervisor, Endpoint
- `Sigil.Repo` (`repo.ex`) — Ecto Postgres adapter (deferred to Slice 3 alerts)
- `Sigil.Cache` (`cache.ex`) — Process-owned ETS GenServer: start_link/1, tables/1, put/3, get/2, delete/2, all/1, match/2
- `Sigil.Accounts` (`accounts.ex`) — Wallet session + character lookup over ETS
- `Sigil.Accounts.Account` (inline in `accounts.ex`) — Struct: address, characters, tribe_id
- `Sigil.Assemblies` (`assemblies.ex`) — Assembly discovery + cached query + gate extension authorization over ETS
- `Sigil.Tribes` (`tribes.ex`) — Tribe member discovery + aggregation over ETS
- `Sigil.Tribes.Tribe` (inline in `tribes.ex`) — Struct: tribe_id, members, discovered_at
- `Sigil.Tribes.TribeMember` (inline in `tribes.ex`) — Struct: character_id, character_name, character_address, tribe_id, connected, wallet_address
- `Sigil.Diplomacy` (`diplomacy.ex`) — Diplomacy standings CRUD over ETS, tx building via TxDiplomacy, chain submission, tribe name resolution from World API
- `Sigil.StaticData` (`static_data.ex`) — DETS-backed GenServer for World API reference data
- `Sigil.GateIndexer` (`gate_indexer.ex`) — Always-on GenServer: periodic full-chain gate scan, bidirectional topology graph, location index, PubSub broadcast. Query API: list_gates/1, get_gate/2, get_topology/1, gates_at_location/2
- `Sigil.GameState.FuelAnalytics` (`game_state/fuel_analytics.ex`) — Pure functions: compute_depletion/1 (analytical fuel depletion), ring_buffer_push/3 (bounded history)
- `Sigil.GameState.AssemblyMonitor` (`game_state/assembly_monitor.ex`) — Per-assembly GenServer: poll/diff/depletion/broadcast via injectable sync_fun, self-terminates after 5 consecutive :not_found
- `Sigil.GameState.MonitorSupervisor` (`game_state/monitor_supervisor.ex`) — DynamicSupervisor for AssemblyMonitor children with Registry-based idempotent lifecycle management

## Key Functions

### Accounts (accounts.ex)
- `register_wallet/2`: address × opts → {:ok, Account.t()} | {:error, reason} — validates, queries chain, caches, broadcasts
- `get_account/2`: address × opts → {:ok, Account.t()} | {:error, :not_found} — ETS read
- `active_character/2`: Account × character_id → Character.t() | nil — resolve active character by ID with first-character fallback
- `sync_from_chain/2`: address × opts → {:ok, Account.t()} | {:error, reason} — refresh registered account

### Assemblies (assemblies.ex)
- `discover_for_owner/2`: owner × opts → {:ok, [assembly()]} | {:error, reason} — OwnerCap query → resolve → cache → broadcast
- `list_for_owner/2`: owner × opts → [assembly()] — ETS match by owner
- `get_assembly/2`: id × opts → {:ok, assembly()} | {:error, :not_found} — ETS read
- `assembly_owned_by?/3`: id × owner × opts → boolean — cached ownership check
- `sync_assembly/2`: id × opts → {:ok, assembly()} | {:error, reason} — refresh cached assembly
- `build_authorize_gate_extension_tx/3`: gate_id × character_id × opts → {:ok, %{tx_bytes: base64}} | {:error, reason} — build unsigned gate extension tx
- `submit_signed_extension_tx/3`: tx_bytes × signature × opts → {:ok, %{digest, effects_bcs}} | {:error, reason} — submit signed tx, sync cache

### Tribes (tribes.ex)
- `discover_members/2`: tribe_id × opts → {:ok, Tribe.t()} | {:error, reason} — paginate chain Characters, filter by tribe_id, cross-ref accounts, cache, broadcast
- `list_members/2`: tribe_id × opts → [TribeMember.t()] — ETS read, [] if undiscovered
- `get_tribe/2`: tribe_id × opts → Tribe.t() | nil — ETS read
- `list_tribe_assemblies/2`: tribe_id × opts → [{TribeMember.t(), [assembly()]}] — cross-ref assemblies ETS for connected members

### Diplomacy (diplomacy.ex)
- `discover_tables/2`: address × opts → {:ok, [table_info()]} — query chain for StandingsTable objects
- `list_standings/1`, `get_standing/2`: ETS cache reads, default :neutral
- `list_pilot_standings/1`, `get_pilot_standing/2`: pilot override reads
- `get_default_standing/1`, `set_active_table/2`, `get_active_table/1`: table lifecycle
- `build_set_standing_tx/3`, `build_create_table_tx/1`, `build_batch_set_standings_tx/2`, `build_set_pilot_standing_tx/3`, `build_set_default_standing_tx/2`, `build_batch_set_pilot_standings_tx/2`: unsigned tx bytes for wallet signing
- `submit_signed_transaction/3`: submit wallet-signed tx, update ETS, broadcast PubSub
- `resolve_tribe_names/1`, `get_tribe_name/2`: World API tribe name resolution + ETS cache

### GateIndexer (gate_indexer.ex)
- `list_gates/1`: opts → [Gate.t()] — all cached gates from :gate_network table
- `get_gate/2`: gate_id × opts → Gate.t() | nil — single gate by id
- `get_topology/1`: opts → %{gate_id => MapSet.t(gate_id)} — bidirectional adjacency map
- `gates_at_location/2`: location_hash × opts → [Gate.t()] — gates at a specific location
- `build_topology/1`: [Gate.t()] → topology() — pure function, bidirectional from linked_gate_id
- `build_location_index/1`: [Gate.t()] → location_index() — pure function, group by location_hash
- GenServer: periodic scan via Process.send_after, paginated get_objects, stale removal, PubSub broadcast on "gate_network"

### Cache (cache.ex)
- `start_link/1`: opts with tables keyword → {:ok, pid}
- `tables/1`: pid → %{table_name => tid}
- `put/3`, `get/2`, `delete/2`, `all/1`, `match/2`: direct ETS operations

## Patterns

- Domain contexts are pure function modules (not GenServers) operating over injected ETS tables
- DI via `@sui_client Application.compile_env!(:sigil, :sui_client)`
- Options keyword list: `tables:` (required), `pubsub:` (optional), `req_options:` (optional)
- PubSub topics: `"accounts"`, `"assemblies:#{owner}"`, `"assembly:#{id}"`, `"tribes"`, `"diplomacy"`, `"gate_network"`
- Type dispatch in Assemblies via multi-clause `parse_assembly/1` with field-presence pattern matching
- Cache values: accounts `{address, Account.t()}`, assemblies `{id, {owner, assembly()}}` + `{:pending_ext_tx, tx_bytes} → {:authorize_gate_extension, gate_id}`, tribes `{tribe_id, Tribe.t()}`, standings `{:tribe_standing|:pilot_standing|:active_table|:default_standing|:world_tribe|:pending_tx, key} → value`, gate_network `{gate_id, Gate.t()}` + `{:topology, topology()}` + `{:location_index, location_index()}`

## Dependencies

- `Sigil.Sui.Client` behaviour (via compile_env mock)
- `Sigil.Sui.TransactionBuilder` for PTB encoding (`build_kind!`)
- `Sigil.Sui.TxGateExtension` for gate extension PTB construction
- `Sigil.Sui.Types.*` structs (Character, Gate, Turret, NetworkNode, StorageUnit, Assembly)
- `Sigil.Cache` for ETS operations
- `Phoenix.PubSub` for event broadcasting
