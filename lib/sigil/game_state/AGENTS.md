# lib/sigil/game_state/

## Modules

- `Sigil.GameState.FuelAnalytics` (`fuel_analytics.ex`) — Pure functions: `compute_depletion/1` (analytical fuel depletion from `Fuel.t()`), `ring_buffer_push/3` (bounded history buffer)
- `Sigil.GameState.AssemblyEventParser` (`assembly_event_parser.ex`) — Pure functions: `assembly_event?/1` (filter), `extract_assembly_id/2` (extract from raw chain event data), `assembly_event_types/0` (list of 3 assembly event atoms)
- `Sigil.GameState.AssemblyEventRouter` (`assembly_event_router.ex`) — GenServer: subscribes to `"chain_events"` PubSub, filters assembly events via parser, dispatches `{:assembly_event, type, id, seq}` to per-assembly monitors via Registry lookup. Singleton child spec.
- `Sigil.GameState.AssemblyMonitor` (`assembly_monitor.ex`) — Per-assembly GenServer: event-driven sync (from AssemblyEventRouter) with monotonic-time debounce + heartbeat polling fallback via injectable `sync_fun`, detects changes (status/fuel/extension), computes depletion via FuelAnalytics, broadcasts `{:assembly_monitor, id, payload}` on `"assembly:#{id}"`, self-terminates after 5 consecutive `:not_found`
- `Sigil.GameState.MonitorSupervisor` (`monitor_supervisor.ex`) — DynamicSupervisor for AssemblyMonitor children: `start_monitor/2`, `stop_monitor/3`, `ensure_monitors/3` (idempotent bulk start), `get_monitor/2`, `list_monitors/1` via Registry lookup

## Key Functions

### FuelAnalytics (fuel_analytics.ex)
- `compute_depletion/1`: Fuel.t() -> `{:depletes_at, DateTime.t()}` | `:not_burning` | `:no_fuel` — analytical prediction from burn_rate, quantity, burn_start_time
- `ring_buffer_push/3`: buffer x entry x max_size -> updated buffer — bounded append with oldest-first eviction

### AssemblyEventParser (assembly_event_parser.ex)
- `assembly_event?/1`: atom -> boolean — checks if event type is assembly lifecycle
- `extract_assembly_id/2`: (atom, map) -> {:ok, String.t()} | {:error, :missing_assembly_id | :not_assembly_event}
- `assembly_event_types/0`: -> [:assembly_status_changed, :assembly_fuel_changed, :assembly_extension_authorized]

### AssemblyEventRouter (assembly_event_router.ex)
- `start_link/1`: opts -> {:ok, pid} — requires `registry:`
- `child_spec/1`: singleton id (`__MODULE__`) for supervision tree
- Subscribes in `handle_continue(:subscribe)`, dispatches via `with` clause + `Registry.lookup`

### AssemblyMonitor (assembly_monitor.ex)
- `start_link/1`: opts -> {:ok, pid} — requires `assembly_id:`, `tables:`, `registry:`
- `child_spec/1`: unique id per instance for DynamicSupervisor
- `get_state/1`: pid -> state map (for testing/introspection)
- `stop/1`: pid -> :ok — graceful shutdown
- `handle_info(:poll, state)`: heartbeat sync -> detect_changes -> compute_depletion -> broadcast -> schedule_next
- `handle_info({:assembly_event, ...}, state)`: event-driven sync with debounce (`min_sync_interval_ms`, default 5s) — shares `perform_poll/3` with heartbeat path, does NOT reschedule poll timer

### MonitorSupervisor (monitor_supervisor.ex)
- `start_link/1`: opts -> {:ok, pid} — unnamed DynamicSupervisor
- `start_monitor/2`: supervisor x opts -> {:ok, pid}
- `stop_monitor/3`: supervisor x assembly_id x registry -> :ok | {:error, :not_found}
- `ensure_monitors/3`: supervisor x [assembly_id] x opts -> :ok — idempotent, skips already-running
- `get_monitor/2`: registry x assembly_id -> {:ok, pid} | {:error, :not_found}
- `list_monitors/1`: registry -> [{assembly_id, pid}]

## Patterns

- Injectable sync_fun: default `&Assemblies.sync_assembly/2`, overridden in tests
- Registry-based monitor lookup: prevents duplicate monitors per assembly; router dispatches directly via Registry
- Event-driven + heartbeat hybrid: chain events trigger immediate sync; heartbeat timer provides fallback polling
- Monotonic-time debounce: `last_sync_at` (nil initially) tracks last sync; events within `min_sync_interval_ms` are skipped
- Composite PubSub event: `{:assembly_monitor, assembly_id, %{changes: [...], assembly: ..., depletion: ...}}`
- Self-termination: 5 consecutive `:not_found` errors -> `:normal` stop
- No named processes: supervisor and monitors use PIDs only; Registry is named but disabled in test env

## Dependencies

- `Sigil.Assemblies` — `sync_assembly/2` as default sync function
- `Sigil.Sui.Types.*` — Assembly struct pattern matching for change detection
- `Phoenix.PubSub` — event broadcasting
- `Registry` — monitor registration and lookup
