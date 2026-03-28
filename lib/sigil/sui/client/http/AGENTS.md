# lib/sigil/sui/client/http/

## Modules

- `Sigil.Sui.Client.HTTP.DynamicFields` (`dynamic_fields.ex`) — GraphQL query and response parsing helpers for Sui dynamic field operations. Extracted from `Sigil.Sui.Client.HTTP` to keep the main client module focused on core object and transaction operations.

## Key Functions

### DynamicFields (dynamic_fields.ex)
- `query/0`: Returns the `GetDynamicFields` GraphQL query string
- `build_page/1`: Parses GraphQL response data into `dynamic_fields_page()`. Normalizes the `value` union type: `MoveValue` (inline `type`/`json`) and `MoveObject` (nested `contents.type`/`contents.json`) are both normalized to `%{type: String.t(), json: term()}`

## Patterns

- Called from `Sigil.Sui.Client.HTTP.get_dynamic_fields/2` which handles variable construction and request dispatch
- GraphQL query stored as module attribute `@get_dynamic_fields_query`
- Pagination via `pageInfo.hasNextPage` and `pageInfo.endCursor`
- Parent object not found (`data["object"]` is nil) returns `{:error, :not_found}`
- All `@spec` annotations reference `Sigil.Sui.Client` types

## Dependencies

- `Sigil.Sui.Client` — type definitions (dynamic_fields_page, dynamic_field_entry, etc.)
