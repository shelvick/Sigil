# lib/sigil/reputation/

## Modules

- `Sigil.Reputation.Engine` (`engine.ex`) — Singleton GenServer: event handling, timer logic (decay/flush/reconnect), aggressor tracking, score computation dispatch
- `Sigil.Reputation.Engine.Scorer` (`engine/scorer.ex`) — Wraps `DATA_ReputationScoring` with context resolution: loads standings, resolves grid presence from last_gate map, checks aggressor flags
- `Sigil.Reputation.Engine.OracleSubmitter` (`engine/oracle_submitter.ex`) — Builds oracle PTB via TxCustodian, signs with server keypair via Signer, submits via SuiClient
- `Sigil.Reputation.Engine.Persistence` (`engine/persistence.ex`) — `flush_dirty_scores/1` (batch Postgres upsert), `load_scores_from_repo/1` (hydrate ETS on startup)
- `Sigil.Reputation.Engine.ScoreState` (`engine/score_state.ex`) — `fetch_score_record/5`, `normalize_thresholds/2`, `standing_atom/1`, `mark_dirty/3`, `clamp_score/1`
- `Sigil.Reputation.Engine.Tables` (`engine/tables.ex`) — `maybe_resolve/2` (lazy table resolution), `maybe_allow_sandbox_owner/2`
- `Sigil.Reputation.EventParser` (`event_parser.ex`) — Pure functions: parse raw checkpoint events into typed structs with tribe resolution via ETS
- `Sigil.Reputation.Scoring` (`scoring.ex`) — Pure scoring algorithms: kill/jump deltas, time decay, transitive scoring, tier thresholds
- `Sigil.Reputation.ReputationScore` (`reputation_score.ex`) — Ecto schema for per-tribe-pair scores with pin overrides

## Key Functions

### Engine
- `start_link/1`: opts → GenServer.on_start()
- `get_state/1`: server → state (test inspection)
- Handles: `:chain_event`, `:decay_tick`, `:flush_dirty`, `:reconnect`

### EventParser
- `parse_event/3`: (atom, map, keyword) → {:ok, struct} | {:error, reason}
- `parse_checkpoint_events/2`: (list, keyword) → [struct] — skips failures

### Scoring
- `compute_kill_delta/2`, `compute_jump_delta/2`: Pure score deltas
- `apply_time_decay/3`: Exponential decay toward 0
- `evaluate_tier/2`: Score × thresholds → standing atom

## Patterns

- Engine uses injectable funs: `connect_fun`, `event_filter_fun`, `save_cursor_fun`, `load_cursor_fun`
- ETS keys: `{:reputation_score, src, tgt}`, `{:last_gate, character_id}`
- PubSub topics: subscribes to `"chain_events"`, broadcasts on `"reputation"`
- Dirty score tracking via MapSet for batched flush
- Sandbox owner passed through opts for DB access in tests

## Dependencies

- `Sigil.Repo` for score persistence
- `Sigil.Cache` for ETS operations
- `Sigil.Sui.TxCustodian`, `Sigil.Sui.Signer`, `Sigil.Sui.Client` for oracle submission
- `Phoenix.PubSub` for event consumption and broadcasts
