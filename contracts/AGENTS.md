# contracts/

Sui Move smart contracts for the Sigil package. The current Seal-delivery package has not been published yet; deploy a fresh package ID before pointing runtime config at it.

## Structure

- `sources/` — Move module source files
- `tests/` — Move test files (test_scenario-based)
- `deps/` — External dependencies (symlinked, gitignored)
- `Move.toml` — Package manifest

## Build & Test

```bash
cd contracts && sui move test    # Run all Move tests
cd contracts && sui move build   # Compile only
```

## Deployment Status

- Seal-delivery modules in this directory are not published yet.
- After the next deployment, update runtime configuration with the new package ID before enabling browser Seal flows.
- All tribes share the same package — per-tribe shared objects are the parameterization.
