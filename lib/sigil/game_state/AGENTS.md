# lib/sigil/game_state/

## Modules

- `Sigil.GameState.FuelAnalytics` (`fuel_analytics.ex`) — Pure functions: `compute_depletion/1` (analytical fuel depletion from `Fuel.t()`), `ring_buffer_push/3` (bounded history buffer)
- `Sigil.GameState.AssemblyMonitor` (`assembly_monitor.ex`) — Per-assembly GenServer: polls via injectable `sync_fun`, detects changes (status/fuel/extension), computes depletion via FuelAnalytics, broadcasts `{:assembly_monitor, id, payload}` on `"assembly:#{id}"`, self-terminates after 5 consecutive `:not_found`
- `Sigil.GameState.MonitorSupervisor` (`monitor_supervisor.ex`) — DynamicSupervisor for AssemblyMonitor children: `start_monitor/2`, `stop_monitor/3`, `ensure_monitors/3` (idempotent bulk start), `get_monitor/2`, `list_monitors/1` via Registry lookup

## Key Functions

### FuelAnalytics (fuel_analytics.ex)
- `compute_depletion/1`: Fuel.t() -> `{:depletes_at, DateTime.t()}` | `:not_burning` | `:no_fuel` — analytical prediction from burn_rate, quantity, burn_start_time
- `ring_buffer_push/3`: buffer x entry x max_size -> updated buffer — bounded append with oldest-first eviction

### AssemblyMonitor (assembly_monitor.ex)
- `start_link/1`: opts -> {:ok, pid} — requires `assembly_id:`, `tables:`, `registry:`
- `child_spec/1`: unique id per instance for DynamicSupervisor
- `get_state/1`: pid -> state map (for testing/introspection)
- `stop/1`: pid -> :ok — graceful shutdown
- `handle_info(:poll, state)`: sync -> detect_changes -> compute_depletion -> broadcast -> schedule_next

### MonitorSupervisor (monitor_supervisor.ex)
- `start_link/1`: opts -> {:ok, pid} — unnamed DynamicSupervisor
- `start_monitor/2`: supervisor x opts -> {:ok, pid}
- `stop_monitor/3`: supervisor x assembly_id x registry -> :ok | {:error, :not_found}
- `ensure_monitors/3`: supervisor x [assembly_id] x opts -> :ok — idempotent, skips already-running
- `get_monitor/2`: registry x assembly_id -> {:ok, pid} | {:error, :not_found}
- `list_monitors/1`: registry -> [{assembly_id, pid}]

## Patterns

- Injectable sync_fun: default `&Assemblies.sync_assembly/2`, overridden in tests
- Registry-based monitor lookup: prevents duplicate monitors per assembly
- Composite PubSub event: `{:assembly_monitor, assembly_id, %{changes: [...], assembly: ..., depletion: ...}}`
- Self-termination: 5 consecutive `:not_found` errors -> `:normal` stop
- No named processes: supervisor and monitors use PIDs only; Registry is named but disabled in test env

## Dependencies

- `Sigil.Assemblies` — `sync_assembly/2` as default sync function
- `Sigil.Sui.Types.*` — Assembly struct pattern matching for change detection
- `Phoenix.PubSub` — event broadcasting
- `Registry` — monitor registration and lookup
