# test/sigil/

## Test Files

- `accounts_test.exs` — 14 tests for Sigil.Accounts (R1-R14), async: true
- `assemblies_test.exs` — 19 tests for Sigil.Assemblies (R1-R19), async: true
- `cache_test.exs` — Tests for Sigil.Cache GenServer
- `tribes_test.exs` — 18 tests for Sigil.Tribes (R1-R16 + 2 edge cases), async: true
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
| Assemblies | 19 | R1-R19 | R19 (discover→list→get flow) |
| Tribes | 18 | R1-R16 + 2 edge | R16 (register→discover→list→assemblies) |
| Cache | 11 | R1-R11 | — |
| Application | 5 | R1-R5 | — |
