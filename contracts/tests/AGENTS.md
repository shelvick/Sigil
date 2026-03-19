# contracts/tests/

## Test Files

| File | Tests | Covers |
|------|-------|--------|
| `tribe_custodian_tests.move` | 42 | Registry init, custodian lifecycle, membership, voting, leadership, operators, standings CRUD, read API, permission edge cases, integration scenarios (R1-R42) |
| `frontier_gate_tests.move` | 9 | Gate extension: create, allow/deny by standing tier, pilot override, NBSI/NRDS, multi-tribe |
| `standings_table_tests.move` | 22 | Standalone standings: create, set, batch, pilot, default, effective standing, owner-only writes |

## Patterns

- `test_scenario` with `ts::begin(addr)`, `scenario.next_tx(addr)`, `scenario.end()`
- Shared objects: `ts::take_shared<T>(&scenario)` / `ts::return_shared(obj)`
- Characters via `world::test_helpers::create_test_character`
- Error tests: `#[test, expected_failure(abort_code = sigil::module::ERROR_CONST)]`
- Helper functions for setup, object creation, and assertions (e.g., `assert_pristine_custodian`)
- Test addresses: `const USER_A: address = @0xA;` etc.
