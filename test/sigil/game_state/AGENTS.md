# test/sigil/game_state/

## Test Files

| File | Module | Tests | Covers |
|------|--------|-------|--------|
| `fuel_analytics_test.exs` | `FuelAnalyticsTest` | 10 | R1-R10: compute_depletion, ring_buffer_push, edge cases |
| `assembly_event_parser_test.exs` | `AssemblyEventParserTest` | 10 | R1-R10: assembly_event?, extract_assembly_id, assembly_event_types, pure function guarantee |
| `assembly_event_router_test.exs` | `AssemblyEventRouterTest` | 11 | R1-R11: event routing (3 types), ignore/drop, malformed, subscribe, no named process, injectable parser, multi-monitor dispatch + acceptance tests |
| `assembly_monitor_test.exs` | `AssemblyMonitorTest` | 20 | R1-R25: poll sync, change detection (status/fuel/extension), depletion, not_found termination, ring buffer, Registry, event-driven sync, debounce, heartbeat independence, broadcast shape |
| `monitor_supervisor_test.exs` | `MonitorSupervisorTest` | 13 | R1-R11: start/stop/ensure/get/list monitors, crash restart, unnamed PID, round-trip |

## Patterns

- All files: `async: true`
- Isolated PubSub + Registry + Cache per test via `start_supervised!`
- Injectable `sync_fun` for controlling monitor sync responses (including `sequence_sync_fun` helper)
- ProbeMonitor test double for router dispatch verification
- `on_exit` cleanup for all spawned GenServers (3-step pattern)
- No Process.sleep — synchronization via GenServer.call, assert_receive, render(view)
