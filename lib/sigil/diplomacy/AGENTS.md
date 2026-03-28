# lib/sigil/diplomacy/

## Modules

- `Sigil.Diplomacy.Governance` (`governance.ex`) — all transaction builders (standings CRUD and governance vote/claim/join) plus governance data loading via paginated dynamic field queries and membership checks. Delegated from parent `Sigil.Diplomacy` via `defdelegate`.
- `Sigil.Diplomacy.ObjectCodec` (`object_codec.ex`) — chain JSON/object ref/standing conversion helpers.
- `Sigil.Diplomacy.PendingOps` (`pending_ops.ex`) — applies cached pending operations after successful signed transaction submission.
- `Sigil.Diplomacy.LocalSigner` (`local_signer.ex`) — localnet-only sign-and-submit fallback for development.

## Key Functions

### Governance (governance.ex)
- `build_set_standing_tx/3`: Builds unsigned PTB for setting a tribe standing
- `build_create_custodian_tx/1`: Builds unsigned PTB for creating a custodian
- `build_batch_set_standings_tx/2`: Builds unsigned PTB for batch standings updates
- `build_set_pilot_standing_tx/3`: Builds unsigned PTB for setting a pilot standing
- `build_set_default_standing_tx/2`: Builds unsigned PTB for setting default standing
- `build_batch_set_pilot_standings_tx/2`: Builds unsigned PTB for batch pilot standings
- `build_vote_leader_tx/2`: Builds unsigned PTB for voting for a leader candidate
- `build_claim_leadership_tx/1`: Builds unsigned PTB for claiming leadership
- `load_governance_data/1`: Loads and caches votes + tallies via paginated dynamic field queries
- `member?/1`: Checks if sender is in cached custodian members list

## Patterns

- All tx builders follow the same pattern: require_active_custodian -> require_character_ref -> ObjectCodec.to_custodian_ref -> TxCustodian.build_* -> TransactionBuilder.build_kind! -> Base.encode64 -> store_pending_tx
- Governance tx builders additionally call `mark_governance_refresh/2` to flag the tx for post-submission governance reload
- Dynamic field loading paginates until `has_next_page` is false, merging pages into complete vote and tally maps
- `@sui_client Application.compile_env!(:sigil, :sui_client)` for Sui client DI

## Dependencies

- `Sigil.Diplomacy` — parent module (shared helpers: require_active_custodian, require_character_ref, store_pending_tx, etc.)
- `Sigil.Sui.TxCustodian` — PTB construction for Custodian operations
- `Sigil.Sui.TransactionBuilder` — BCS encoding (`build_kind!/1`)
- `Sigil.Cache` — ETS cache reads/writes
