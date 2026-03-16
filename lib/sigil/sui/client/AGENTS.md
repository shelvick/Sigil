# lib/sigil/sui/client/

## Modules

- `Sigil.Sui.Client.HTTP` — Req-backed HTTP implementation of the `Sui.Client` behaviour

## Key Functions

### Client.HTTP (http.ex)
- `get_object/2`: Sends `GetObject` GraphQL query, extracts `asMoveObject.contents.json`
- `get_object_with_ref/2`: Same query, returns `%{json: map, ref: {id_bytes, version, digest_bytes}}` (non-behaviour)
- `get_objects/2`: Sends `GetObjects` query with filter/cursor/limit, returns `objects_page()`
- `execute_transaction/3`: Sends `ExecuteTransaction` mutation, returns effects map

### Private Helpers
- `graphql_request/3`: Shared request pipeline (URL resolve → Req.post → response mapping)
- `request_options/3`: Merges caller opts with defaults (URL, retry, timeout)
- `map_graphql_response/1`: Pattern-matched response → `{:ok, data}` or `{:error, reason}`
- `object_variables/1`: Keyword filter list → GraphQL variables map
- `build_objects_page/1`: GraphQL nodes → `%{data: [...], has_next_page: bool, end_cursor: str}`
- `decode_sui_address/1`: 0x-prefixed hex → 32-byte binary
- `base58_decode/1`: Base58 string → binary (inline decoder, no external dep)
- `retry?/2`: Custom retry predicate — retries 408/5xx, transport errors, HTTP/2 unprocessed; excludes 429

## Patterns

- `@behaviour Sigil.Sui.Client` — implements 3 callbacks
- GraphQL queries as module attributes (`@get_object_query`, `@get_objects_query`, `@execute_transaction_mutation`)
- Req.Test plug injection via `opts[:req_options]` for test isolation
- Custom `retry?/2` instead of `:transient` — excludes 429 rate limits
- Configurable retry: `Application.get_env(:sigil, :sui_client_retry_delay, 1_000)`
- `receive_timeout: 30_000` — matches WorldClient.HTTP
- Nodes without `asMoveObject` silently filtered in `get_objects` (package objects)

## Dependencies

- `Req` — HTTP client
- `Sigil.Sui.Client` — behaviour contract (types, callbacks)
