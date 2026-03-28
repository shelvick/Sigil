# test/sigil/sui/

## Test Files

| File | Module | Tests | Covers |
|------|--------|-------|--------|
| `bcs_test.exs` | `Sigil.Sui.BCSTest` | 12 | All encode/decode, roundtrips, reference vectors, errors |
| `signer_test.exs` | `Sigil.Sui.SignerTest` | 9 | Keypair gen/derive, intent signing, verify, address, errors |
| `client_test.exs` | `Sigil.Sui.ClientTest` | 6 | Behaviour callbacks, mock, Hammox type enforcement, config, objects_page type validation |
| `client_http_test.exs` | `Sigil.Sui.ClientHTTPTest` | 21 | get_object, get_object_with_ref, get_objects, execute_transaction, URL/retry/behaviour (Req.Test stubs) |
| `types_test.exs` | `Sigil.Sui.TypesTest` | 13 | All struct from_json, optionals, vectors, scalars, validation |
| `transaction_builder_ptb_test.exs` | `PTBTest` | 20 | All PTB BCS encoders (argument, call_arg, object_ref, gas_data, expiration, type_tag, struct_tag, move_call, command, programmable_transaction, transaction_data) |
| `transaction_builder_test.exs` | `TransactionBuilderTest` | 14 | build!/1, build/1, digest/1, execute/3, reference vector |
| `tx_diplomacy_test.exs` | `Sigil.Sui.TxDiplomacyTest` | 11 | All builder functions, package ID, shared refs, validation, TransactionBuilder integration |
| `tx_custodian_test.exs` | `Sigil.Sui.TxCustodianTest` | 19 | All 11 builders, package ID, mutable/immutable refs, standing/address/batch validation, TransactionBuilder integration |
| `gas_relay_test.exs` | `Sigil.Sui.GasRelayTest` | 13 | prepare_sponsored (coin selection, gas budget, relay signing), submit_sponsored (dual-sig, error handling), relay_address, keypair file lifecycle (load/generate/persist), insufficient gas, no coins |
| `tx_intel_reputation_test.exs` | `Sigil.Sui.TxIntelReputationTest` | 5 | build_confirm_quality/build_report_bad_quality PTB structure, shared-ref mutability (registry mutable, listing immutable), TransactionBuilder integration |

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
