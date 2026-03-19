# lib/sigil/sui/

## Modules

- `Sigil.Sui.BCS` — Pure BCS encoder/decoder for Sui transaction serialization
- `Sigil.Sui.Signer` — Ed25519 signing, verification, Sui address derivation
- `Sigil.Sui.Client` — Behaviour contract for Sui GraphQL access (4 callbacks: get_object, get_objects, execute_transaction, verify_zklogin_signature)
- `Sigil.Sui.Client.HTTP` — Req-backed HTTP implementation of Client behaviour (see `client/AGENTS.md`)
- `Sigil.Sui.ZkLoginVerifier` — Challenge nonce lifecycle + zkLogin signature verification. Pure function module over injected ETS + Sui client
- `Sigil.Sui.TransactionBuilder` — PTB construction, digest, sign+submit (public API)
- `Sigil.Sui.TransactionBuilder.PTB` — BCS encoding for all PTB struct types
- `Sigil.Sui.TxDiplomacy` — PTB construction for StandingsTable operations (create, set_standing, batch, pilot, default)
- `Sigil.Sui.TxGateExtension` — PTB construction for gate extension authorization (3-command borrow/authorize/return pattern)
- `Sigil.Sui.Base58` — Pure Base58 encoder/decoder for Sui digest strings
- `Sigil.Sui.Types` — Namespace for Sui type structs
- `Sigil.Sui.Types.Parser` — Shared scalar parsers (integer!, bytes!, uid!, status!, optional)
- `Sigil.Sui.Types.TenantItemId` — Tenant-scoped item identifier
- `Sigil.Sui.Types.AssemblyStatus` — Status enum (:null, :offline, :online)
- `Sigil.Sui.Types.Location` — Hashed location (32-byte location_hash)
- `Sigil.Sui.Types.Metadata` — Common metadata (assembly_id, name, description, url)
- `Sigil.Sui.Types.Fuel` — Network node fuel state (9 fields)
- `Sigil.Sui.Types.EnergySource` — Energy production values (3 fields)
- `Sigil.Sui.Types.Gate` — Jump gate object
- `Sigil.Sui.Types.Assembly` — Assembly object
- `Sigil.Sui.Types.NetworkNode` — Network node with nested Fuel + EnergySource
- `Sigil.Sui.Types.Character` — Character object
- `Sigil.Sui.Types.Turret` — Turret object
- `Sigil.Sui.Types.StorageUnit` — Storage unit with inventory_keys

## Key Functions

### BCS (bcs.ex)
- `encode_u8/1` .. `encode_u256/1`: Fixed-width little-endian integer encoding
- `encode_uleb128/1`: Variable-length unsigned integer encoding
- `encode_bool/1`, `encode_string/1`, `encode_vector/2`, `encode_option/2`, `encode_address/1`
- `decode_*` mirrors for all encode functions, returns `{value, remaining_bytes}`

### Signer (signer.ex)
- `generate_keypair/0`: Ed25519 keypair via :crypto
- `keypair_from_private_key/1`: Derive pubkey from 32-byte privkey
- `sign/2`: Intent-prefixed (<<0,0,0>>) Ed25519 signing
- `encode_signature/2`: 97-byte scheme-byte format (<<0x00>> + sig + pubkey)
- `verify/3`: Intent-prefixed signature verification
- `address_from_public_key/1`: Blake2b-256 of <<0x00>> ++ pubkey
- `to_sui_address/1`: 0x-prefixed lowercase hex string

### Client (client.ex)
- `get_object/2`: Fetch single object by id
- `get_objects/2`: Fetch objects by filter (type, owner, cursor, limit)
- `execute_transaction/3`: Submit signed tx (tx_bytes + signatures)
- `verify_zklogin_signature/5`: Verify zkLogin signature via Sui GraphQL (bytes, sig, scope, author, opts)

### ZkLoginVerifier (zklogin_verifier.ex)
- `generate_nonce/2`: address × opts → {:ok, %{nonce, message}} — stores nonce+expected_message in ETS
- `verify_and_consume/2`: params × opts → {:ok, %{address, item_id, tenant}} — atomic take, bytes validation, Sui verification

### TransactionBuilder (transaction_builder.ex)
- `build!/1`: Keyword opts → BCS-serialized TransactionData binary (raises on invalid)
- `build/1`: Same as build! but returns `{:ok, binary} | {:error, String.t()}`
- `digest/1`: BCS bytes → Blake2b-256(<<0,0,0>> <> bytes), 32-byte digest
- `execute/3`: build + sign + submit via injected client, returns `{:ok, effects} | {:error, reason}`

### TransactionBuilder.PTB (transaction_builder/ptb.ex)
- `encode_argument/1`: Argument enum (GasCoin/Input/Result/NestedResult)
- `encode_call_arg/1`: CallArg enum (Pure/Object with ImmOrOwned/Shared/Receiving)
- `encode_object_ref/1`: 72-byte fixed tuple (id+version+digest)
- `encode_gas_data/1`: Payment refs + owner + price + budget
- `encode_transaction_expiration/1`: None/Epoch enum
- `encode_type_tag/1`: TypeTag enum (9 primitives via map lookup + Vector + Struct)
- `encode_struct_tag/1`: StructTag (address+module+name+type_params)
- `encode_move_call/1`: ProgrammableMoveCall struct
- `encode_command/1`: Command enum (MoveCall = variant 0)
- `encode_programmable_transaction/1`: Inputs vector + commands vector
- `encode_transaction_data_v1/1`: Kind + sender + gas_data + expiration
- `encode_transaction_data/1`: Outer enum wrapper (V1 = variant 0)

### TxDiplomacy (tx_diplomacy.ex)
- `build_create_table/1`: tx_opts → build_opts (standings_table::create)
- `build_set_standing/4`: table_ref × tribe_id × standing × tx_opts → build_opts
- `build_set_default_standing/3`: table_ref × standing × tx_opts → build_opts
- `build_set_pilot_standing/4`: table_ref × pilot_bytes × standing × tx_opts → build_opts
- `build_batch_set_standings/3`: table_ref × [{tribe_id, standing}] × tx_opts → build_opts
- `build_batch_set_pilot_standings/3`: table_ref × [{pilot_bytes, standing}] × tx_opts → build_opts

### TxGateExtension (tx_gate_extension.ex)
- `build_authorize_extension/3`: gate_ref × owner_cap_ref × character_ref → kind_opts (3-command PTB: borrow_owner_cap, authorize_extension, return_owner_cap)

### Base58 (base58.ex)
- `decode!/1`: Base58 string → binary (raises on invalid)
- `decode/1`: Base58 string → {:ok, binary} | {:error, :invalid_base58}

### Types (types/*.ex)
- Each struct: `from_json/1` parses Sui GraphQL JSON into typed Elixir struct
- Parser: `integer!/1` (rejects negatives), `bytes!/1`, `uid!/1`, `status!/1`, `optional/2`

## Patterns

- All modules are pure functions (no state, no side effects)
- Error handling via FunctionClauseError (guards/pattern matching) and ArgumentError (validation)
- Client uses behaviour + Hammox mock for DI (`config :sigil, :sui_client`)
- TransactionBuilder uses `@sui_client Application.compile_env!` for client DI (compile-time module attribute)
- PTB uses `@type_tag_indices` map for TypeTag primitive BCS variant lookups (non-sequential indices)
- Multi-clause public functions use `@doc false` on subsequent clauses (Credo compliance)
- Types split across files when combined size exceeds 500 lines

## Dependencies

- Erlang `:crypto` — Ed25519 operations (Signer)
- `Blake2` — Blake2b-256 hashing (Signer address derivation, TransactionBuilder digest)
- `Hammox` — Behaviour mock for Client (test only)

