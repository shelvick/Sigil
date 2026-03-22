/// Gate extension that reads a Custodian to issue or deny JumpPermits.
/// Non-hostile pilots receive permits; hostile pilots are denied.
///
/// Uses the typed-witness extension pattern: gate owners call
/// `gate::authorize_extension<FrontierGateAuth>()` to register this extension,
/// then travelers call `request_permit()` to obtain a JumpPermit.
module sigil::frontier_gate;

use sui::clock::Clock;
use sigil::tribe_custodian::{Self, Custodian};
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
/// Reads the traveler's tribe_id from their Character, looks up the effective
/// standing (pilot -> tribe -> default) in the Custodian, and either
/// issues a JumpPermit (non-hostile) or aborts (hostile).
public fun request_permit(
    custodian: &Custodian,
    source_gate: &Gate,
    destination_gate: &Gate,
    character: &Character,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let tribe_id = character.tribe();
    let standing = tribe_custodian::get_effective_standing(custodian, tribe_id, ctx.sender());

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
