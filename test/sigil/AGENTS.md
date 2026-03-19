# test/sigil/

## Test Files

- `accounts_test.exs` — 14 tests for Sigil.Accounts (R1-R14), async: true
- `assemblies_test.exs` — 39 tests for Sigil.Assemblies (R1-R36 + edge cases), async: true
- `cache_test.exs` — Tests for Sigil.Cache GenServer
- `tribes_test.exs` — 18 tests for Sigil.Tribes (R1-R16 + 2 edge cases), async: true
- `diplomacy_test.exs` — 28 tests for Sigil.Diplomacy (R1-R22 + acceptance), async: true
- `application_test.exs` — Tests for OTP supervision tree

## Test Patterns

- Isolated Cache per test: `start_supervised!({Cache, tables: [...]})`
- Isolated PubSub per test: `start_supervised!({Phoenix.PubSub, name: unique_name})`
- Hammox mocks: `expect(ClientMock, :get_objects, fn ...)` with `verify_on_exit!`
- JSON fixtures via private helper functions with map merge overrides
- Acceptance tests tagged `@tag :acceptance` — test full flows without pre-populated state

## Coverage

| Module | Tests | Spec Reqs | Acceptance |
|--------|-------|-----------|------------|
| Accounts | 14 | R1-R14 | R14 (register→get flow) |
| Assemblies | 39 | R1-R36 + edge | R21 (discover→list→get flow), R36 (build→submit→verify) |
| Tribes | 18 | R1-R16 + 2 edge | R16 (register→discover→list→assemblies) |
| Diplomacy | 28 | R1-R22 + acceptance | R22 (discover→build→submit→verify) |
| TxDiplomacy | 11 | R1-R11 | R11 (build→TransactionBuilder integration) |
| TxGateExtension | 10 | R1-R10 | R8 (PTB→BCS integration) |
| Cache | 11 | R1-R11 | — |
| Application | 5 | R1-R5 | — |
