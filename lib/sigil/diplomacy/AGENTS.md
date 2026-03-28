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
- `Sigil.Diplomacy` (`../diplomacy.ex`) — Thin facade: types, public API delegation to submodules. Owns `standings_table/1`, `source_tribe_id/1`, `active_tribe_id/2`, `get/set_active_custodian`, `leader?/1`
- `Sigil.Diplomacy.Discovery` (`discovery.ex`) — Custodian discovery via chain query, character/registry ref resolution (opts → cache → chain), tribe name caching from World API
- `Sigil.Diplomacy.TransactionOps` (`transaction_ops.ex`) — All `build_*_tx` functions, `submit_signed_transaction/3`, `sign_and_submit_locally/2`, `set_oracle_address/3`, `remove_oracle_address/2`. Stores pending ops in ETS
- `Sigil.Diplomacy.ReputationOps` (`reputation_ops.ex`) — `pin_standing/3`, `unpin_standing/2`, `pinned?/2`, `get_reputation_score/2`, `list_reputation_scores/1`. DB upsert for pin state, ETS cache, PubSub broadcast
- `Sigil.Diplomacy.ObjectCodec` (`object_codec.ex`) — Chain JSON → custodian_info, shared-object ref builders, hex/bytes conversion, standing atom/value mapping
- `Sigil.Diplomacy.PendingOps` (`pending_ops.ex`) — Applies cached pending ops (standings/pilot/default/batch) after successful tx submission
- `Sigil.Diplomacy.LocalSigner` (`local_signer.ex`) — Localnet signing fallback for development

## Key Functions

### Facade (../diplomacy.ex)
- `discover_custodian/2`, `resolve_character_ref/2`, `resolve_registry_ref/1` → Discovery
- `build_set_standing_tx/3`, `build_create_custodian_tx/1`, `build_batch_set_standings_tx/2` → TransactionOps
- `pin_standing/3`, `unpin_standing/2`, `get_reputation_score/2` → ReputationOps
- `get_standing/2`, `list_standings/1`, `get_pilot_standing/2`, `get_default_standing/1` — direct ETS reads
- `oracle_enabled?/1` — checks active custodian for oracle_address

### TransactionOps
- `build_set_standing_tx/3`, `build_create_custodian_tx/1`, `build_batch_set_standings_tx/2`
- `build_set_pilot_standing_tx/3`, `build_set_default_standing_tx/2`, `build_batch_set_pilot_standings_tx/2`
- `submit_signed_transaction/3`, `sign_and_submit_locally/2`
- `set_oracle_address/3`, `remove_oracle_address/2` — leader-gated oracle management

### ReputationOps
- `pin_standing/3`: Leader-gated, DB upsert + ETS cache + PubSub `{:reputation_pinned, _}`
- `unpin_standing/2`: Leader-gated, DB upsert + ETS cache + PubSub `{:reputation_unpinned, _}`
- `get_reputation_score/2`, `list_reputation_scores/1`: ETS reads with normalization

## Patterns

- Facade delegates to submodules; no business logic in diplomacy.ex itself
- All functions accept `opts` keyword list with `:tables`, `:tribe_id`, `:client`, `:pubsub`, etc.
- `@sui_client Application.compile_env!(:sigil, :sui_client)` in TransactionOps for chain queries
- ETS keys: `{:tribe_standing, src, tgt}`, `{:pilot_standing, src, pilot}`, `{:default_standing, src}`, `{:active_custodian, tribe_id}`, `{:pending_tx, bytes}`, `{:reputation_score, src, tgt}`
- PubSub topics: `"diplomacy"`, `"reputation"`

## Dependencies

- `Sigil.Cache` for ETS operations
- `Sigil.Repo` for reputation pin state persistence (ReputationOps)
- `Sigil.Sui.TransactionBuilder` and `Sigil.Sui.TxCustodian` for tx building
- `Phoenix.PubSub` for broadcasts
