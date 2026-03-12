# lib/frontier_os/sui/

## Modules

- `FrontierOS.Sui.BCS` — Pure BCS encoder/decoder for Sui transaction serialization
- `FrontierOS.Sui.Signer` — Ed25519 signing, verification, Sui address derivation
- `FrontierOS.Sui.Client` — Behaviour contract for Sui GraphQL access (3 callbacks)
- `FrontierOS.Sui.Types` — Namespace for Sui type structs
- `FrontierOS.Sui.Types.Parser` — Shared scalar parsers (integer!, bytes!, uid!, status!, optional)
- `FrontierOS.Sui.Types.TenantItemId` — Tenant-scoped item identifier
- `FrontierOS.Sui.Types.AssemblyStatus` — Status enum (:null, :offline, :online)
- `FrontierOS.Sui.Types.Location` — Hashed location (32-byte location_hash)
- `FrontierOS.Sui.Types.Metadata` — Common metadata (assembly_id, name, description, url)
- `FrontierOS.Sui.Types.Fuel` — Network node fuel state (9 fields)
- `FrontierOS.Sui.Types.EnergySource` — Energy production values (3 fields)
- `FrontierOS.Sui.Types.Gate` — Jump gate object
- `FrontierOS.Sui.Types.Assembly` — Assembly object
- `FrontierOS.Sui.Types.NetworkNode` — Network node with nested Fuel + EnergySource
- `FrontierOS.Sui.Types.Character` — Character object
- `FrontierOS.Sui.Types.Turret` — Turret object
- `FrontierOS.Sui.Types.StorageUnit` — Storage unit with inventory_keys

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

### Types (types/*.ex)
- Each struct: `from_json/1` parses Sui GraphQL JSON into typed Elixir struct
- Parser: `integer!/1` (rejects negatives), `bytes!/1`, `uid!/1`, `status!/1`, `optional/2`

## Patterns

- All modules are pure functions (no state, no side effects)
- Error handling via FunctionClauseError (guards/pattern matching) and ArgumentError (validation)
- Client uses behaviour + Hammox mock for DI (`config :frontier_os, :sui_client`)
- Types split across files when combined size exceeds 500 lines

## Dependencies

- Erlang `:crypto` — Ed25519 operations (Signer)
- `Blake2` — Blake2b-256 hashing (Signer address derivation)
- `Hammox` — Behaviour mock for Client (test only)

## Specs

- SVC_BCS: `noderr/specs/SVC_BCS.md`
- SVC_Signer: `noderr/specs/SVC_Signer.md`
- SVC_SuiClient: `noderr/specs/SVC_SuiClient.md`
- UTIL_SuiTypes: `noderr/specs/UTIL_SuiTypes.md`
