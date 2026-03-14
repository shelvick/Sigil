# test/frontier_os/sui/

## Test Files

| File | Module | Tests | Covers |
|------|--------|-------|--------|
| `bcs_test.exs` | `FrontierOS.Sui.BCSTest` | 12 | All encode/decode, roundtrips, reference vectors, errors |
| `signer_test.exs` | `FrontierOS.Sui.SignerTest` | 9 | Keypair gen/derive, intent signing, verify, address, errors |
| `client_test.exs` | `FrontierOS.Sui.ClientTest` | 6 | Behaviour callbacks, mock, Hammox type enforcement, config, objects_page type validation |
| `client_http_test.exs` | `FrontierOS.Sui.ClientHTTPTest` | 21 | get_object, get_object_with_ref, get_objects, execute_transaction, URL/retry/behaviour (Req.Test stubs) |
| `types_test.exs` | `FrontierOS.Sui.TypesTest` | 13 | All struct from_json, optionals, vectors, scalars, validation |
| `transaction_builder_ptb_test.exs` | `PTBTest` | 20 | All PTB BCS encoders (argument, call_arg, object_ref, gas_data, expiration, type_tag, struct_tag, move_call, command, programmable_transaction, transaction_data) |
| `transaction_builder_test.exs` | `TransactionBuilderTest` | 14 | build!/1, build/1, digest/1, execute/3, reference vector |

## Patterns

- All files: `async: true`
- client_test, transaction_builder_test: `import Hammox` + `setup :verify_on_exit!`
- types_test: Private fixture helpers (`gate_json/1`, `uid/1`, etc.) simulate GraphQL responses
- bcs_test: Reference vectors loaded from `test/fixtures/sui/bcs_reference_vectors.json`
- transaction_builder_test: `@reference_tx_hex` inline hex fixture for reference vector
- transaction_builder_ptb_test: Independent expected_* helpers mirror each encoder for byte-level verification
- client_http_test: `Req.Test.expect/2` with unique stub names via `System.unique_integer` for test isolation
- No mocks except ClientMock (used by Client behaviour tests and TransactionBuilder execute/3)

## Fixtures

- `test/fixtures/sui/bcs_reference_vectors.json` — 5 MystenLabs BCS test vectors
