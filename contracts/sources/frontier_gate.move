/// Gate extension that reads a StandingsTable to issue or deny JumpPermits.
/// Friendly and neutral tribes receive permits; hostile tribes are denied.
///
/// Uses the typed-witness extension pattern: gate owners call
/// `gate::authorize_extension<FrontierGateAuth>()` to register this extension,
/// then travelers call `request_permit()` to obtain a JumpPermit.
module frontier_os::frontier_gate;

use sui::clock::Clock;
use frontier_os::standings_table::{Self, StandingsTable};
use world::{character::Character, gate::{Self, Gate}};

// === Errors ===

/// Traveler's tribe has hostile standing — access denied.
const EAccessDenied: u64 = 0;

// === Constants ===

/// Standing value for hostile tribes.
const HOSTILE: u8 = 0;

/// Default permit duration: 5 minutes in milliseconds.
const DEFAULT_EXPIRY_MS: u64 = 300_000;

// === Structs ===

/// Zero-sized witness struct proving this is the registered gate extension.
public struct FrontierGateAuth has drop {}

// === Public Functions ===

/// Request a jump permit for the given gate pair.
///
/// Reads the traveler's tribe_id from their Character, looks up the standing
/// in the StandingsTable, and either issues a JumpPermit (friendly/neutral)
/// or aborts (hostile).
public fun request_permit(
    table: &StandingsTable,
    source_gate: &Gate,
    destination_gate: &Gate,
    character: &Character,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let tribe_id = character.tribe();
    let standing = standings_table::get_standing(table, tribe_id);

    assert!(standing != HOSTILE, EAccessDenied);

    let expires_at_timestamp_ms = clock.timestamp_ms() + DEFAULT_EXPIRY_MS;

    gate::issue_jump_permit<FrontierGateAuth>(
        source_gate,
        destination_gate,
        character,
        FrontierGateAuth {},
        expires_at_timestamp_ms,
        ctx,
    );
}
