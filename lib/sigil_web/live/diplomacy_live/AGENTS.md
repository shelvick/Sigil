# lib/sigil_web/live/diplomacy_live/

## Modules

- `SigilWeb.DiplomacyLive.Governance` (`governance.ex`) — governance state management and transaction building helpers extracted from `SigilWeb.DiplomacyLive`. Handles governance data loading, custodian discovery, standings loading, transaction construction, wallet signing flow, and post-submission refresh.
- `SigilWeb.DiplomacyLive.GovernanceComponents` (`governance_components.ex`) — governance section HEEx components: collapsible voting section with current leader card, member list with vote indicators, vote/claim actions, and non-member guidance.

## Key Functions

### Governance (governance.ex)
- `load_governance_state/2`: Loads governance members, votes, and tallies into socket assigns
- `build_transaction/3`: Resolves character ref and enters signing flow for a given tx builder
- `enter_signing/2`: Pushes wallet signing event or signs locally on localnet
- `maybe_refresh_after_submission/1`: Refreshes standings (and custodian on :no_custodian return state) after successful submission
- `governance_tx?/2`: Checks whether a pending tx is a vote/claim governance operation
- `discover_custodian_state/1`: Discovers and applies custodian state for the socket's tribe
- `apply_discovered_custodian/2`: Maps discovery result to :no_custodian, :active, or :active_readonly
- `apply_cached_custodian_state/1`: Re-applies cached custodian state from ETS
- `load_standings/1`: Loads all standings, world tribes, character ref, and governance into the socket
- `diplomacy_opts/1`: Builds the diplomacy opts keyword list from socket assigns

### GovernanceComponents (governance_components.ex)
- `governance_section/1`: Collapsible governance section with current leader summary, expanded member list, vote buttons, and claim leadership action

## Patterns

- `viewer_address` assign is passed to governance components (not `current_account.address`) for claim visibility decoupling
- `ignore_governance_update` flag suppresses self-triggered PubSub refresh after governance tx submission
- Governance data loading wraps `Diplomacy.load_governance_data/1` in try/rescue for resilience
- Module size kept under 500 lines per module via this extraction

## Dependencies

- `Sigil.Diplomacy` — context module for all diplomacy operations
- `Sigil.Tribes` — member label lookup for governance display
- `Sigil.Cache` — ETS cache for governance data and pending tx checks
- `SigilWeb.TransactionHelpers` — localnet detection and signer address
