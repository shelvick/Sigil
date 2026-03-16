# lib/mix/tasks/sigil/

## Modules

- `Mix.Tasks.Sigil.PopulateStaticData` — Fetches World API data → DETS files

## Key Functions

- `run/1`: Parse args → start Req → fetch each type → write DETS → print summary
- `parse_args!/1`: OptionParser for `--only` flag, validates against known type names
- `populate_table/3`: Single type fetch+write with progress output
- `fetch_rows/2`: WorldClient callback via `@table_metadata` → parsed `{id, struct}` tuples

## Patterns

- `use Mix.Task` with `@shortdoc`
- Data-driven dispatch via `@table_metadata` (shared pattern with StaticData)
- `@cli_names` maps internal atoms to CLI-friendly strings
- `DetsFile.write_rows!/2` delegation for DETS operations
- Partial failure: continues with remaining types, prints retry hint
- `Application.ensure_all_started(:req)` (not full app start)
