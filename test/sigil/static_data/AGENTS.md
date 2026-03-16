# test/sigil/static_data/

## Test Files

| File | Module | Tests | Covers |
|------|--------|-------|--------|
| `world_api_types_test.exs` | `WorldApiTypesTest` | 14 | Struct parsing (SolarSystem, ItemType, Constellation), WorldClient.HTTP pagination/errors, mock compliance |
| `static_data_test.exs` | `StaticDataTest` | 18 | Read API, DETS loading, auto-fetch, test isolation, pending_callers, tables lifecycle |

## Patterns

- All files: `async: true`
- `import Hammox` + `setup :verify_on_exit!` for WorldClient mock tests
- StaticData tests: `test_data:` option for UNIT tests (no DETS), temp dirs for INTEGRATION tests
- DETS tests: unique temp dirs via `StaticDataTestFixtures.ensure_tmp_dir!/1`, cleanup via `on_exit`
- WorldClient.HTTP tests: `Req.Test` adapter stubs (no real HTTP)
- DetsFile operations: `DetsFile.open_file/1` + manual `:dets.close/1` for reading test results

## Support Files

- `test/support/static_data_fixtures.ex` — Shared fixture helpers (sample data, JSON builders, DETS path/write, mix run args, config writers)
- `test/support/mocks.ex` — `WorldClientMock` via Hammox
- `test/support/env_world_client.ex` — Stub WorldClient for application probe subprocess tests
