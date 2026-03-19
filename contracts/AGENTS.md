# contracts/

Sui Move smart contracts for the Sigil package. Published as a single universal package on Sui testnet.

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

## Published Package

- Testnet deployment: `0x06ce9d6bed77615383575cc7eba4883d32769b30cd5df00561e38434a59611a1`
- All tribes share the same package — per-tribe shared objects are the parameterization
