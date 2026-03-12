# test/frontier_os/sui/

## Test Files

| File | Module | Tests | Covers |
|------|--------|-------|--------|
| `bcs_test.exs` | `FrontierOS.Sui.BCSTest` | 12 | All encode/decode, roundtrips, reference vectors, errors |
| `signer_test.exs` | `FrontierOS.Sui.SignerTest` | 9 | Keypair gen/derive, intent signing, verify, address, errors |
| `client_test.exs` | `FrontierOS.Sui.ClientTest` | 4 | Behaviour callbacks, mock, Hammox type enforcement, config |
| `types_test.exs` | `FrontierOS.Sui.TypesTest` | 13 | All struct from_json, optionals, vectors, scalars, validation |

## Patterns

- All files: `async: true`
- client_test: `import Hammox` + `setup :verify_on_exit!`
- types_test: Private fixture helpers (`gate_json/1`, `uid/1`, etc.) simulate GraphQL responses
- bcs_test: Reference vectors loaded from `test/fixtures/sui/bcs_reference_vectors.json`
- No mocks except ClientMock (which IS the deliverable for SVC_SuiClient)

## Fixtures

- `test/fixtures/sui/bcs_reference_vectors.json` — 5 MystenLabs BCS test vectors
