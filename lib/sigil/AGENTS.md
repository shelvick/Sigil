# lib/sigil/

## Modules

- `Sigil.Application` (`application.ex`) — OTP app: Telemetry, Repo, PubSub, Cache(8 tables incl `:intel`), StaticData, GateIndexer, MonitorRegistry, MonitorSupervisor, AlertEngine, Endpoint
- `Sigil.Repo` (`repo.ex`) — Ecto Postgres adapter, sandbox-ready and actively used for intel report + alert persistence
- `Sigil.Cache` (`cache.ex`) — Process-owned ETS GenServer: start_link/1, tables/1, put/3, get/2, delete/2, all/1, match/2
- `Sigil.Accounts` (`accounts.ex`) — Wallet session + character lookup over ETS
- `Sigil.Accounts.Account` (inline in `accounts.ex`) — Struct: address, characters, tribe_id
- `Sigil.Assemblies` (`assemblies.ex`) — Assembly discovery + cached query + gate extension authorization over ETS
- `Sigil.Tribes` (`tribes.ex`) — Tribe member discovery + aggregation over ETS
- `Sigil.Tribes.Tribe` (inline in `tribes.ex`) — Struct: tribe_id, members, discovered_at
- `Sigil.Tribes.TribeMember` (inline in `tribes.ex`) — Struct: character_id, character_name, character_address, tribe_id, connected, wallet_address
- `Sigil.Diplomacy` (`diplomacy.ex`) — Tribe-scoped Custodian diplomacy context: custodian discovery, standings reads, tx building via `TxCustodian`, signed submission reconciliation, World API tribe names
- `Sigil.Diplomacy.ObjectCodec` (`diplomacy/object_codec.ex`) — Shared object parsing + ref conversion helpers for custodian, registry, standing, and hex decoding
- `Sigil.Diplomacy.PendingOps` (`diplomacy/pending_ops.ex`) — Applies pending diplomacy operations after tx success and broadcasts refresh events
- `Sigil.Intel` (`intel.ex`) — Tribe-scoped intel CRUD: `report_location` (upsert), `report_scouting`, `list_intel`, `get_location` (ETS cached), `delete_intel`, `load_cache`, `topic/1`. Postgres persistence + ETS write-through + PubSub broadcast
- `Sigil.Intel.IntelReport` (`intel/intel_report.ex`) — Ecto schema for `intel_reports` table: :string primary key with UUID autogeneration, `location_changeset/2`, `scouting_changeset/2`
- `Sigil.StaticData` (`static_data.ex`) — DETS-backed GenServer for World API reference data + `search_solar_systems/3`, `get_solar_system_by_name/2`
- `Sigil.GateIndexer` (`gate_indexer.ex`) — Always-on GenServer: periodic full-chain gate scan, bidirectional topology graph, location index, PubSub broadcast. Query API: list_gates/1, get_gate/2, get_topology/1, gates_at_location/2
- `Sigil.GameState.FuelAnalytics` (`game_state/fuel_analytics.ex`) — Pure functions: compute_depletion/1 (analytical fuel depletion), ring_buffer_push/3 (bounded history)
- `Sigil.GameState.AssemblyMonitor` (`game_state/assembly_monitor.ex`) — Per-assembly GenServer: poll/diff/depletion/broadcast via injectable sync_fun, self-terminates after 5 consecutive :not_found
- `Sigil.GameState.MonitorSupervisor` (`game_state/monitor_supervisor.ex`) — DynamicSupervisor for AssemblyMonitor children with Registry-based idempotent lifecycle management
- `Sigil.Alerts` (`alerts.ex`) — Alert lifecycle context: create/dedup/cooldown/acknowledge/dismiss, webhook config upsert, PubSub broadcast. First Repo-backed context
- `Sigil.Alerts.Alert` (`alerts/alert.ex`) — Ecto schema: alerts table with type/severity/status enums, partial unique index for active dedup
- `Sigil.Alerts.WebhookConfig` (`alerts/webhook_config.ex`) — Ecto schema: per-tribe Discord webhook config
- `Sigil.Alerts.Engine` (`alerts/engine.ex`) — Singleton GenServer: monitor discovery, rule evaluation, alert persistence, webhook dispatch
- `Sigil.Alerts.Engine.Dispatcher` (`alerts/engine/dispatcher.ex`) — Async webhook delivery with test ownership wiring
- `Sigil.Alerts.Engine.RuleEvaluator` (`alerts/engine/rule_evaluator.ex`) — Pure rule evaluation: fuel_low, fuel_critical, assembly_offline, extension_changed
- `Sigil.Alerts.WebhookNotifier` (`alerts/webhook_notifier.ex`) — Behaviour: `deliver/3` callback for webhook providers
- `Sigil.Alerts.WebhookNotifier.Discord` (`alerts/webhook_notifier/discord.ex`) — Discord webhook delivery with embed formatting and retry
- `Sigil.IntelMarket` (`intel_market.ex`) — Intel marketplace context: discover marketplace, sync/cache listings, build unsigned create/purchase/cancel transactions, submit signed transactions with pending-op reconciliation, PubSub broadcast on `"intel_market"` topic
- `Sigil.IntelMarket.Support` (`intel_market/support.ex`) — Shared cache table access, paginated object fetching, integer/status parsing, Sui type string resolution
- `Sigil.IntelMarket.Listings` (`intel_market/listings.ex`) — Listing persistence (chain upsert, created listing reconciliation, status updates), ETS caching, stale listing cleanup with 30s grace window
- `Sigil.IntelMarket.PendingOps` (`intel_market/pending_ops.ex`) — Applies create/purchase/cancel pending operations after wallet-signed transaction settlement
- `Sigil.Intel.IntelListing` (`intel/intel_listing.ex`) — Ecto schema for `intel_listings` table: string PK (on-chain object ID), changeset/2, status_changeset/2, status enum (active/sold/cancelled)

## Key Functions

### Accounts (accounts.ex)
- `register_wallet/2`: address × opts → `{:ok, Account.t()} | {:error, reason}` — validates, queries chain, caches, broadcasts
- `get_account/2`: address × opts → `{:ok, Account.t()} | {:error, :not_found}` — ETS read
- `active_character/2`: Account × character_id → `Character.t() | nil` — resolve active character by ID with first-character fallback
- `sync_from_chain/2`: address × opts → `{:ok, Account.t()} | {:error, reason}` — refresh registered account

### Assemblies (assemblies.ex)
- `discover_for_owner/2`: owner × opts → `{:ok, [assembly()]} | {:error, reason}` — OwnerCap query → resolve → cache → broadcast
- `list_for_owner/2`: owner × opts → `[assembly()]` — ETS match by owner
- `get_assembly/2`: id × opts → `{:ok, assembly()} | {:error, :not_found}` — ETS read
- `assembly_owned_by?/3`: id × owner × opts → boolean — cached ownership check
- `sync_assembly/2`: id × opts → `{:ok, assembly()} | {:error, reason}` — refresh cached assembly
- `build_authorize_gate_extension_tx/3`: gate_id × character_id × opts → `{:ok, %{tx_bytes: base64}} | {:error, reason}` — build unsigned gate extension tx
- `submit_signed_extension_tx/3`: tx_bytes × signature × opts → `{:ok, %{digest, effects_bcs}} | {:error, reason}` — submit signed tx, sync cache

### Tribes (tribes.ex)
- `discover_members/2`: tribe_id × opts → `{:ok, Tribe.t()} | {:error, reason}` — paginate chain Characters, filter by tribe_id, cross-ref accounts, cache, broadcast
- `list_members/2`: tribe_id × opts → `[TribeMember.t()]` — ETS read, `[]` if undiscovered
- `get_tribe/2`: tribe_id × opts → `Tribe.t() | nil` — ETS read
- `list_tribe_assemblies/2`: tribe_id × opts → `[{TribeMember.t(), [assembly()]}]` — cross-ref assemblies ETS for connected members

### Diplomacy (diplomacy.ex)
- `discover_custodian/2`: tribe_id × opts → `{:ok, custodian_info() | nil} | {:error, reason}` — query chain for tribe `Custodian`, cache active custodian, broadcast discovery
- `resolve_character_ref/2`: character_id × opts → `{:ok, character_ref()} | {:error, reason}` — opts → ETS → chain shared-object resolution
- `resolve_registry_ref/1`: opts → `{:ok, registry_ref()} | {:error, reason}` — opts → ETS → chain registry resolution
- `set_active_custodian/2`, `get_active_custodian/1`: custodian lifecycle over ETS using tribe-scoped keys
- `leader?/1`: opts → boolean — sender matches cached `current_leader`
- `list_standings/1`, `get_standing/2`: tribe-scoped ETS reads, default `:neutral`
- `list_pilot_standings/1`, `get_pilot_standing/2`: pilot override reads, default `:neutral`
- `get_default_standing/1`: tribe-scoped default policy read
- `build_create_custodian_tx/1`, `build_set_standing_tx/3`, `build_batch_set_standings_tx/2`, `build_set_pilot_standing_tx/3`, `build_set_default_standing_tx/2`, `build_batch_set_pilot_standings_tx/2`: unsigned Custodian tx bytes for wallet signing
- `submit_signed_transaction/3`: submit wallet-signed tx, apply pending op, broadcast PubSub
- `sign_and_submit_locally/2`: localnet signer shortcut with the same pending-op apply path
- `resolve_tribe_names/1`, `get_tribe_name/2`: World API tribe-name resolution + ETS cache

### Diplomacy.ObjectCodec (diplomacy/object_codec.ex)
- `parse_shared_version/1`: chain JSON → shared object version or nil
- `parse_tribe_id/1`: chain JSON → integer tribe id or nil
- `standing_to_atom/1`: `0..4` → `:hostile | :unfriendly | :neutral | :friendly | :allied`
- `hex_to_bytes/1`: `0x...` hex string → raw bytes
- `to_custodian_ref/1`: cached custodian map → `TxCustodian` shared-object ref
- `to_custodian_info/1`: raw chain object → normalized cached custodian map
- `build_registry_ref/1`: chain object page → registry shared-object ref

### Diplomacy.PendingOps (diplomacy/pending_ops.ex)
- `apply/3`: standings table tid × opts × tx_bytes → consume pending op, mutate ETS, broadcast one of `:standing_updated`, `:pilot_standing_updated`, `:default_standing_updated`, `:custodian_created`

### Intel (intel.ex)
- `report_location/2`: params × opts → {:ok, IntelReport.t()} | {:error, changeset | :unauthorized} — upsert via partial unique index
- `report_scouting/2`: params × opts → {:ok, IntelReport.t()} | {:error, changeset | :unauthorized}
- `list_intel/2`: tribe_id × opts → [IntelReport.t()] — ordered newest first
- `get_location/3`: tribe_id × assembly_id × opts → IntelReport.t() | nil — ETS cache with DB fallback
- `delete_intel/3`: id × delete_params × opts → :ok | {:error, :not_found | :unauthorized}
- `load_cache/2`: tribe_id × opts → :ok — warm ETS from Postgres location reports
- `topic/1`: tribe_id → "intel:#{tribe_id}" — public PubSub topic

### GateIndexer (gate_indexer.ex)
- `list_gates/1`: opts → `[Gate.t()]` — all cached gates from `:gate_network` table
- `get_gate/2`: gate_id × opts → `Gate.t() | nil` — single gate by id
- `get_topology/1`: opts → `%{gate_id => MapSet.t(gate_id)}` — bidirectional adjacency map
- `gates_at_location/2`: location_hash × opts → `[Gate.t()]` — gates at a specific location
- `build_topology/1`: `[Gate.t()]` → topology() — pure function, bidirectional from linked_gate_id
- `build_location_index/1`: `[Gate.t()]` → location_index() — pure function, group by location_hash
- GenServer: periodic scan via `Process.send_after`, paginated get_objects, stale removal, PubSub broadcast on `"gate_network"`

### Alerts (alerts.ex)
- `create_alert/2`: attrs × opts → {:ok, Alert.t()} | {:ok, :duplicate} | {:ok, :cooldown} | {:error, changeset}
- `list_alerts/2`: filters × opts → [Alert.t()] — account-scoped, newest first
- `acknowledge_alert/2`, `dismiss_alert/2`: lifecycle transitions, idempotent
- `unread_count/2`: account_address × opts → non_neg_integer()
- `upsert_webhook_config/3`: tribe_id × attrs × opts → {:ok, WebhookConfig.t()} | {:error, changeset}
- `purge_old_dismissed/2`: days × opts → {count, nil}

### IntelMarket (intel_market.ex)
- `topic/0`: → `"intel_market"` PubSub topic
- `discover_marketplace/1`: opts → `{:ok, marketplace_info() | nil} | {:error, reason}`
- `sync_listings/1`: opts → `{:ok, [IntelListing.t()]} | {:error, term()}`
- `list_listings/1`: opts → `[IntelListing.t()]` — active only, newest first
- `get_listing/2`: listing_id × opts → `IntelListing.t() | nil` — ETS cache-aside
- `build_create_listing_tx/2`: params × opts → `{:ok, %{tx_bytes, client_nonce}} | {:error, reason}`
- `build_create_restricted_listing_tx/2`: params × opts → as above, with custodian ref
- `build_purchase_tx/2`: listing_id × opts → `{:ok, %{tx_bytes}} | {:error, reason}`
- `build_cancel_listing_tx/2`: listing_id × opts → `{:ok, %{tx_bytes}} | {:error, reason}`
- `submit_signed_transaction/3`: tx_bytes × signature × opts → `{:ok, %{digest, effects_bcs}} | {:error, term()}`
- `resolve_listing_ref/2`: listing_id × opts → `{:ok, listing_ref()} | {:error, term()}`

### Cache (cache.ex)
- `start_link/1`: opts with tables keyword → `{:ok, pid}`
- `tables/1`: pid → `%{table_name => tid}`
- `put/3`, `get/2`, `delete/2`, `all/1`, `match/2`: direct ETS operations

## Patterns

- Domain contexts are pure function modules (not GenServers) operating over injected ETS tables
- DI via `@sui_client Application.compile_env!(:sigil, :sui_client)`
- Options keyword list: `tables:` (required), `pubsub:` (optional), `req_options:` (optional); diplomacy also uses `tribe_id:`, `sender:`, `character_id:`, `character_ref:`, `registry_ref:`
- PubSub topics: `"accounts"`, `"assemblies:#{owner}"`, `"assembly:#{id}"`, `"tribes"`, `"diplomacy"`, `"gate_network"`, `"alerts:#{account_address}"`, `"intel:#{tribe_id}"`, `"monitors:lifecycle"`
- Diplomacy cache keys are tribe-scoped: `{:active_custodian, tribe_id}`, `{:tribe_standing, source_tribe_id, target_tribe_id}`, `{:pilot_standing, source_tribe_id, pilot}`, `{:default_standing, source_tribe_id}`
- Pending ops use `{:pending_tx, tx_bytes}` and are applied by `Sigil.Diplomacy.PendingOps`
- IntelMarket follows CTX_Diplomacy pattern: options keyword list, ETS caching, pending ops, PubSub broadcast
- PubSub topics: `"intel_market"` for all marketplace events
- IntelMarket cache keys: `{:marketplace}`, `{:listing, id}`, `{:listing_ref, id}`, `{:pending_tx, sender, tx_bytes}`
- Type dispatch in Assemblies via multi-clause `parse_assembly/1` with field-presence pattern matching
- Cache values: accounts `{address, Account.t()}`, assemblies `{id, {owner, assembly()}}` + `{:pending_ext_tx, tx_bytes} -> {:authorize_gate_extension, gate_id}`, tribes `{tribe_id, Tribe.t()}`, diplomacy `{:active_custodian, tribe_id} | {:tribe_standing, source_tribe_id, target_tribe_id} | {:pilot_standing, source_tribe_id, pilot} | {:default_standing, source_tribe_id} | {:world_tribe, tribe_id} | {:pending_tx, tx_bytes} -> value`, gate_network `{gate_id, Gate.t()}` + `{:topology, topology()}` + `{:location_index, location_index()}`, intel `{:location, tribe_id, assembly_id} -> IntelReport.t()`

## Dependencies

- `Sigil.Sui.Client` behaviour (via compile_env mock)
- `Sigil.Sui.TransactionBuilder` for PTB encoding (`build_kind!`)
- `Sigil.Sui.TxCustodian` for Custodian PTB construction
- `Sigil.Sui.TxGateExtension` for gate extension PTB construction
- `Sigil.Sui.Types.*` structs (Character, Gate, Turret, NetworkNode, StorageUnit, Assembly)
- `Sigil.Cache` for ETS operations
- `Phoenix.PubSub` for event broadcasting
- `Sigil.Repo` for Postgres persistence (intel and alerts contexts)
