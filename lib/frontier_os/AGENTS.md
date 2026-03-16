# lib/frontier_os/

## Modules

- `FrontierOS.Application` (`application.ex`) — OTP app: Telemetry, Repo, PubSub, Cache(5 tables), StaticData, Endpoint
- `FrontierOS.Repo` (`repo.ex`) — Ecto Postgres adapter (deferred to Slice 3 alerts)
- `FrontierOS.Cache` (`cache.ex`) — Process-owned ETS GenServer: start_link/1, tables/1, put/3, get/2, delete/2, all/1, match/2
- `FrontierOS.Accounts` (`accounts.ex`) — Wallet session + character lookup over ETS
- `FrontierOS.Accounts.Account` (inline in `accounts.ex`) — Struct: address, characters, tribe_id
- `FrontierOS.Assemblies` (`assemblies.ex`) — Assembly discovery + cached query over ETS
- `FrontierOS.Tribes` (`tribes.ex`) — Tribe member discovery + aggregation over ETS
- `FrontierOS.Tribes.Tribe` (inline in `tribes.ex`) — Struct: tribe_id, members, discovered_at
- `FrontierOS.Tribes.TribeMember` (inline in `tribes.ex`) — Struct: character_id, character_name, character_address, tribe_id, connected, wallet_address
- `FrontierOS.StaticData` (`static_data.ex`) — DETS-backed GenServer for World API reference data
- `FrontierOS.GameState.Poller` (`game_state/poller.ex`) — Linked GenServer: periodic assembly sync via injectable sync_fun, Process.send_after scheduling, update_assembly_ids/2

## Key Functions

### Accounts (accounts.ex)
- `register_wallet/2`: address × opts → {:ok, Account.t()} | {:error, reason} — validates, queries chain, caches, broadcasts
- `get_account/2`: address × opts → {:ok, Account.t()} | {:error, :not_found} — ETS read
- `sync_from_chain/2`: address × opts → {:ok, Account.t()} | {:error, reason} — refresh registered account

### Assemblies (assemblies.ex)
- `discover_for_owner/2`: owner × opts → {:ok, [assembly()]} | {:error, reason} — OwnerCap query → resolve → cache → broadcast
- `list_for_owner/2`: owner × opts → [assembly()] — ETS match by owner
- `get_assembly/2`: id × opts → {:ok, assembly()} | {:error, :not_found} — ETS read
- `sync_assembly/2`: id × opts → {:ok, assembly()} | {:error, reason} — refresh cached assembly

### Tribes (tribes.ex)
- `discover_members/2`: tribe_id × opts → {:ok, Tribe.t()} | {:error, reason} — paginate chain Characters, filter by tribe_id, cross-ref accounts, cache, broadcast
- `list_members/2`: tribe_id × opts → [TribeMember.t()] — ETS read, [] if undiscovered
- `get_tribe/2`: tribe_id × opts → Tribe.t() | nil — ETS read
- `list_tribe_assemblies/2`: tribe_id × opts → [{TribeMember.t(), [assembly()]}] — cross-ref assemblies ETS for connected members

### Cache (cache.ex)
- `start_link/1`: opts with tables keyword → {:ok, pid}
- `tables/1`: pid → %{table_name => tid}
- `put/3`, `get/2`, `delete/2`, `all/1`, `match/2`: direct ETS operations

## Patterns

- Domain contexts are pure function modules (not GenServers) operating over injected ETS tables
- DI via `@sui_client Application.compile_env!(:frontier_os, :sui_client)`
- Options keyword list: `tables:` (required), `pubsub:` (optional), `req_options:` (optional)
- PubSub topics: `"accounts"`, `"assemblies:#{owner}"`, `"assembly:#{id}"`, `"tribes"`
- Type dispatch in Assemblies via multi-clause `parse_assembly/1` with field-presence pattern matching
- Cache values: accounts `{address, Account.t()}`, assemblies `{id, {owner, assembly()}}`, tribes `{tribe_id, Tribe.t()}`

## Dependencies

- `FrontierOS.Sui.Client` behaviour (via compile_env mock)
- `FrontierOS.Sui.Types.*` structs (Character, Gate, Turret, NetworkNode, StorageUnit, Assembly)
- `FrontierOS.Cache` for ETS operations
- `Phoenix.PubSub` for event broadcasting
