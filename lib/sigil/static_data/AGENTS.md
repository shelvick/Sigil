# lib/sigil/static_data/

## Modules

- `Sigil.StaticData` — DETS-backed GenServer loading static data into process-owned ETS tables (`static_data.ex` in parent dir)
- `Sigil.StaticData.DetsFile` — Bounded atom pool DETS file operations (open, write, path resolution)
- `Sigil.StaticData.SolarSystem` — Struct + `from_json/1` for World API solar systems
- `Sigil.StaticData.ItemType` — Struct + `from_json/1` for World API item types
- `Sigil.StaticData.Constellation` — Struct + `from_json/1` for World API constellations
- `Sigil.StaticData.WorldClient` — Behaviour contract (3 callbacks: fetch_types, fetch_solar_systems, fetch_constellations)
- `Sigil.StaticData.WorldClient.HTTP` — Req-backed paginated HTTP implementation with retry

## Key Functions

### StaticData (static_data.ex)
- `start_link/1`: Accepts dets_dir, world_client, test_data, mox_owner options
- `tables/1`: Returns `%{table_name => tid}` (blocks via pending_callers until ready)
- `get_solar_system/2`, `get_item_type/2`, `get_constellation/2`: Lookup by id, returns struct or nil
- `list_solar_systems/1`, `list_item_types/1`, `list_constellations/1`: All records

### DetsFile (dets_file.ex)
- `open_file/1`: Path → `{:ok, atom()}` via 128-slot bounded pool
- `dets_path/2`: Dir + table_name → file path (e.g., `"item_types.dets"`)
- `write_rows!/1`: Open → delete_all → insert → sync → close

### WorldClient.HTTP (world_client/http.ex)
- `fetch_types/1`, `fetch_solar_systems/1`, `fetch_constellations/1`: Paginated fetch (limit=1000)
- `receive_timeout: 30_000`, `retry: :transient`, configurable retry_delay/max_retries

## Patterns

- GenServer with `handle_continue(:load_tables)` for async init + `pending_callers` queue
- `@table_metadata` map for data-driven fetch/parse dispatch (no multi-clause switching)
- `DetsFile` bounded atom pool avoids unbounded atom creation from runtime paths
- WorldClient behaviour + Hammox mock for DI (`config :sigil, :world_client`)
- `mox_owner` auto-set via `normalize_start_opts/1` for Mox.allow delegation
- `test_data:` option bypasses DETS entirely for test isolation

## Dependencies

- `Req` — HTTP client (WorldClient.HTTP)
- `Hammox` — Behaviour mock for WorldClient (test only)
- Erlang `:dets` — Disk-based term storage
