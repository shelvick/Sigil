# lib/sigil/sui/client/

## Modules

- `Sigil.Sui.Client.HTTP` — Req-backed HTTP implementation of the `Sui.Client` behaviour
- `Sigil.Sui.Client.HTTP.DynamicFields` (`http/dynamic_fields.ex`) — extracted GraphQL query and response parsing for dynamic field operations (MoveValue/MoveObject normalization)
- `Sigil.Sui.Client.HTTP` (`http.ex`) — Public API + behaviour callbacks, delegates internals to submodules
- `Sigil.Sui.Client.HTTP.Codec` (`http/codec.ex`) — GraphQL response parsing, BCS decoding, object normalization
- `Sigil.Sui.Client.HTTP.Paging` (`http/paging.ex`) — Paginated object fetching with cursor-based iteration
- `Sigil.Sui.Client.HTTP.Request` (`http/request.ex`) — GraphQL query construction, Req.post wrapper, error handling

## Key Functions

### Client.HTTP (http.ex)
- `get_object/2`: Sends `GetObject` GraphQL query, extracts `asMoveObject.contents.json`
- `get_object_with_ref/2`: Same query, returns `%{json: map, ref: {id_bytes, version, digest_bytes}}` (non-behaviour)
- `get_objects/2`: Sends `GetObjects` query with filter/cursor/limit, returns `objects_page()`
- `execute_transaction/3`: Sends `ExecuteTransaction` mutation, returns effects map
- `get_dynamic_fields/2`: Constructs variables and delegates to `DynamicFields.build_page/1`
- `verify_zklogin_signature/5`: Sends `VerifyZkLoginSignature` query, returns raw result

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

- `@behaviour Sigil.Sui.Client` — implements 6 callbacks (get_object, get_object_with_ref, get_objects, get_dynamic_fields, execute_transaction, verify_zklogin_signature)
- `@behaviour Sigil.Sui.Client` — implements 6 callbacks
- GraphQL queries as module attributes (`@get_object_query`, `@get_objects_query`, `@execute_transaction_mutation`)
- Req.Test plug injection via `opts[:req_options]` for test isolation
- Custom `retry?/2` instead of `:transient` — excludes 429 rate limits
- Configurable retry: `Application.get_env(:sigil, :sui_client_retry_delay, 1_000)`
- `receive_timeout: 30_000` — matches WorldClient.HTTP
- Nodes without `asMoveObject` silently filtered in `get_objects` (package objects)

## Dependencies

- `Req` — HTTP client
- `Sigil.Sui.Client` — behaviour contract (types, callbacks)
