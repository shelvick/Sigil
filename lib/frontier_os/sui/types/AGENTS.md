# lib/frontier_os/sui/types/

## Modules

- `Parser` (`parser.ex`) — Shared scalar parsers: `integer!/1`, `bytes!/1`, `uid!/1`, `status!/1`, `optional/2`
- `TenantItemId` (`primitives.ex`) — `{item_id, tenant}` from GraphQL JSON
- `AssemblyStatus` (`primitives.ex`) — Status enum: NULL→:null, OFFLINE→:offline, ONLINE→:online
- `Location` (`primitives.ex`) — 32-byte location_hash from byte vector, validates size
- `Metadata` (`primitives.ex`) — Common metadata: assembly_id, name, description, url
- `Fuel` (`primitives.ex`) — Network node fuel state (9 integer/boolean fields)
- `EnergySource` (`primitives.ex`) — Energy production values (3 integer fields)
- `Gate` (`objects.ex`) — Jump gate with nested Location, Metadata, optional extension
- `Assembly` (`objects.ex`) — Assembly object
- `NetworkNode` (`objects.ex`) — Node with nested Fuel + EnergySource
- `Character` (`objects.ex`) — Character with tribe_id, character_address
- `Turret` (`objects.ex`) — Turret with optional extension
- `StorageUnit` (`objects.ex`) — Storage unit with inventory_keys list

## Patterns

- Every struct: `@enforce_keys`, `defstruct`, `@type t()`, `@spec from_json(map()) :: t()`
- Required fields: `Map.fetch!/2` — crashes on missing data (let it crash)
- Optional fields: `Map.get/2` + `Parser.optional/2`
- Integer fields: JSON strings → `Parser.integer!/1` (validates non-negative)
- UID fields: `%{"id" => "0x..."}` → `Parser.uid!/1` (unwraps or passes string)
