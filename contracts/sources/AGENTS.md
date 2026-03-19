# contracts/sources/

## Modules

- `sigil::standings_table` (`standings_table.move`) — Standalone 5-tier standings table (OBSOLETE, pending migration to Custodian)
- `sigil::tribe_custodian` (`tribe_custodian.move`) — Per-tribe governance + inline standings. TribeCustodianRegistry singleton, one-person-one-vote leader election, operator management, leader-gated standings upsert/read
- `sigil::frontier_gate` (`frontier_gate.move`) — Gate access extension using typed-witness pattern, denies HOSTILE tier via get_effective_standing

## Key Types

### tribe_custodian
- `TribeCustodianRegistry` (key) — singleton, `tribes: Table<u32, ID>`
- `Custodian` (key) — per-tribe shared object: governance (members, votes, tallies, leader, operators) + standings (tribe, pilot, default)

### standings_table
- `StandingsTable` (key, store) — standalone standings with owner-gated writes

### frontier_gate
- Uses world::access typed-witness extension pattern

## Error Constants (tribe_custodian)

| Code | Name | Condition |
|------|------|-----------|
| 0 | ENotTribeMember | character.tribe() != custodian.tribe_id |
| 1 | ETribeAlreadyRegistered | duplicate tribe_id in registry |
| 2 | ENotLeader | caller is not current_leader |
| 3 | EInvalidStanding | standing > 4 |
| 4 | EMismatchedLengths | batch vectors differ in length |
| 5 | ECandidateNotMember | vote candidate not in members |
| 6 | EOperatorNotMember | operator not in members |
| 7 | ENotLeaderCandidate | challenger votes <= leader votes |

## Standing Tiers

0=Hostile, 1=Unfriendly, 2=Neutral, 3=Friendly, 4=Allied

## Dependencies

- `sui::table`, `sui::vec_set`, `sui::transfer`, `sui::object`, `sui::tx_context`
- `world::character` — tribe_id verification via `character.tribe()`
- `world::access` — typed-witness extension pattern (frontier_gate)
