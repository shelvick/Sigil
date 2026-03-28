#[allow(unused_const)]
module sigil::tribe_custodian;

use sui::table::{Self, Table};
use sui::vec_set::{Self, VecSet};
use world::character::{Self, Character};

const ENotTribeMember: u64 = 0;
const ETribeAlreadyRegistered: u64 = 1;
const ENotLeader: u64 = 2;
const EInvalidStanding: u64 = 3;
const EMismatchedLengths: u64 = 4;
const ECandidateNotMember: u64 = 5;
const EOperatorNotMember: u64 = 6;
const ENotLeaderCandidate: u64 = 7;
const ENotOracle: u64 = 8;
const EOracleNotSet: u64 = 9;

public struct TribeCustodianRegistry has key {
    id: UID,
    tribes: Table<u32, ID>,
}

public struct Custodian has key {
    id: UID,
    tribe_id: u32,
    standings: Table<u32, u8>,
    pilot_standings: Table<address, u8>,
    default_standing: u8,
    current_leader: address,
    current_leader_votes: u64,
    members: VecSet<address>,
    operators: VecSet<address>,
    votes: Table<address, address>,
    vote_tallies: Table<address, u64>,
    oracle: Option<address>,
}

/// Module initializer: creates the TribeCustodianRegistry singleton as a shared object.
fun init(ctx: &mut TxContext) {
    share_registry(ctx);
}

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    share_registry(ctx);
}

/// Create a new Custodian for the caller's tribe. The caller becomes the initial leader
/// with one self-vote. Aborts if a Custodian already exists for this tribe_id.
public fun create_custodian(
    registry: &mut TribeCustodianRegistry,
    character: &Character,
    ctx: &mut TxContext,
) {
    assert_sender_controls_character(character, ctx);
    let tribe_id = character.tribe();
    assert!(!table::contains(&registry.tribes, tribe_id), ETribeAlreadyRegistered);

    let sender = ctx.sender();
    let mut members = vec_set::empty<address>();
    vec_set::insert(&mut members, sender);

    let mut votes = table::new<address, address>(ctx);
    table::add(&mut votes, sender, sender);

    let mut vote_tallies = table::new<address, u64>(ctx);
    table::add(&mut vote_tallies, sender, 1);

    let custodian = Custodian {
        id: object::new(ctx),
        tribe_id,
        standings: table::new(ctx),
        pilot_standings: table::new(ctx),
        default_standing: 2,
        current_leader: sender,
        current_leader_votes: 1,
        members,
        operators: vec_set::empty(),
        votes,
        vote_tallies,
        oracle: option::none(),
    };

    table::add(&mut registry.tribes, tribe_id, object::id(&custodian));
    transfer::share_object(custodian);
}

/// Register the caller as a member with a default self-vote. Idempotent — no-op if already a member.
public fun join(custodian: &mut Custodian, character: &Character, ctx: &mut TxContext) {
    assert_authorized_member(custodian, character, ctx);
    ensure_member(custodian, ctx.sender());
}

/// Change the caller's vote to `candidate`. Auto-joins if not already a member.
/// Transfers leadership automatically if candidate's tally exceeds the current leader's.
public fun vote_leader(
    custodian: &mut Custodian,
    character: &Character,
    candidate: address,
    ctx: &mut TxContext,
) {
    assert_authorized_member(custodian, character, ctx);

    let voter = ctx.sender();
    ensure_member(custodian, voter);
    assert!(vec_set::contains(&custodian.members, &candidate), ECandidateNotMember);

    let old_candidate = *table::borrow(&custodian.votes, voter);
    if (old_candidate == candidate) {
        return
    };

    decrement_tally(custodian, old_candidate);
    let candidate_votes = increment_tally(custodian, candidate);
    *table::borrow_mut(&mut custodian.votes, voter) = candidate;

    custodian.current_leader_votes = get_tally(custodian, custodian.current_leader);
    if (candidate_votes > custodian.current_leader_votes) {
        custodian.current_leader = candidate;
        custodian.current_leader_votes = candidate_votes;
    };
}

/// Claim leadership if the caller's vote tally exceeds the current leader's.
/// For lazy downward leadership transfer when votes shift outside of `vote_leader`.
public fun claim_leadership(
    custodian: &mut Custodian,
    character: &Character,
    ctx: &mut TxContext,
) {
    assert_authorized_member(custodian, character, ctx);

    let candidate = ctx.sender();
    let candidate_votes = get_tally(custodian, candidate);
    if (candidate == custodian.current_leader) {
        custodian.current_leader_votes = candidate_votes;
        return
    };

    let leader_votes = get_tally(custodian, custodian.current_leader);
    assert!(candidate_votes > leader_votes, ENotLeaderCandidate);
    custodian.current_leader = candidate;
    custodian.current_leader_votes = candidate_votes;
}

/// Add a member to the operators set. Leader only. Idempotent.
public fun add_operator(
    custodian: &mut Custodian,
    character: &Character,
    operator: address,
    ctx: &mut TxContext,
) {
    assert_authorized_member(custodian, character, ctx);
    assert_leader(custodian, ctx.sender());
    assert!(vec_set::contains(&custodian.members, &operator), EOperatorNotMember);

    if (!vec_set::contains(&custodian.operators, &operator)) {
        vec_set::insert(&mut custodian.operators, operator);
    };
}

/// Remove an address from the operators set. Leader only. No-op if not an operator.
public fun remove_operator(
    custodian: &mut Custodian,
    character: &Character,
    operator: address,
    ctx: &mut TxContext,
) {
    assert_authorized_member(custodian, character, ctx);
    assert_leader(custodian, ctx.sender());

    if (vec_set::contains(&custodian.operators, &operator)) {
        vec_set::remove(&mut custodian.operators, &operator);
    };
}

/// Set a tribe's standing tier (0-4). Leader only. Upserts — creates or updates.
public fun set_standing(
    custodian: &mut Custodian,
    character: &Character,
    tribe_id: u32,
    standing: u8,
    ctx: &mut TxContext,
) {
    assert_authorized_member(custodian, character, ctx);
    assert_leader(custodian, ctx.sender());
    assert_valid_standing(standing);
    upsert_standing(&mut custodian.standings, tribe_id, standing);
}

/// Set the default standing for unknown entities. Leader only. Controls NBSI/NRDS policy.
public fun set_default_standing(
    custodian: &mut Custodian,
    character: &Character,
    standing: u8,
    ctx: &mut TxContext,
) {
    assert_authorized_member(custodian, character, ctx);
    assert_leader(custodian, ctx.sender());
    assert_valid_standing(standing);
    custodian.default_standing = standing;
}

/// Set an individual pilot's standing override. Leader only. Upserts — creates or updates.
public fun set_pilot_standing(
    custodian: &mut Custodian,
    character: &Character,
    pilot: address,
    standing: u8,
    ctx: &mut TxContext,
) {
    assert_authorized_member(custodian, character, ctx);
    assert_leader(custodian, ctx.sender());
    assert_valid_standing(standing);
    upsert_pilot_standing(&mut custodian.pilot_standings, pilot, standing);
}

/// Set standings for multiple tribes in one call. Leader only.
/// Aborts if `tribe_ids` and `standings` have different lengths.
public fun batch_set_standings(
    custodian: &mut Custodian,
    character: &Character,
    tribe_ids: vector<u32>,
    standings: vector<u8>,
    ctx: &mut TxContext,
) {
    assert_authorized_member(custodian, character, ctx);
    assert_leader(custodian, ctx.sender());
    assert!(tribe_ids.length() == standings.length(), EMismatchedLengths);

    let mut i = 0;
    while (i < tribe_ids.length()) {
        let tribe_id = tribe_ids[i];
        let standing = standings[i];
        assert_valid_standing(standing);
        upsert_standing(&mut custodian.standings, tribe_id, standing);
        i = i + 1;
    };
}

/// Set standings for multiple pilots in one call. Leader only.
/// Aborts if `pilots` and `standings` have different lengths.
public fun batch_set_pilot_standings(
    custodian: &mut Custodian,
    character: &Character,
    pilots: vector<address>,
    standings: vector<u8>,
    ctx: &mut TxContext,
) {
    assert_authorized_member(custodian, character, ctx);
    assert_leader(custodian, ctx.sender());
    assert!(pilots.length() == standings.length(), EMismatchedLengths);

    let mut i = 0;
    while (i < pilots.length()) {
        let pilot = pilots[i];
        let standing = standings[i];
        assert_valid_standing(standing);
        upsert_pilot_standing(&mut custodian.pilot_standings, pilot, standing);
        i = i + 1;
    };
}

/// Read a tribe's standing. Returns default_standing if the tribe has no explicit entry.
public fun get_standing(custodian: &Custodian, tribe_id: u32): u8 {
    if (table::contains(&custodian.standings, tribe_id)) {
        *table::borrow(&custodian.standings, tribe_id)
    } else {
        custodian.default_standing
    }
}

/// Read a pilot's standing. Returns default_standing if the pilot has no explicit entry.
public fun get_pilot_standing(custodian: &Custodian, pilot: address): u8 {
    if (table::contains(&custodian.pilot_standings, pilot)) {
        *table::borrow(&custodian.pilot_standings, pilot)
    } else {
        custodian.default_standing
    }
}

/// Get effective standing for a pilot: pilot override -> tribe standing -> default_standing.
/// API-compatible with `standings_table::get_effective_standing`.
public fun get_effective_standing(
    custodian: &Custodian,
    tribe_id: u32,
    pilot: address,
): u8 {
    if (table::contains(&custodian.pilot_standings, pilot)) {
        *table::borrow(&custodian.pilot_standings, pilot)
    } else if (table::contains(&custodian.standings, tribe_id)) {
        *table::borrow(&custodian.standings, tribe_id)
    } else {
        custodian.default_standing
    }
}

/// Returns the tribe_id this Custodian manages.
public fun tribe_id(custodian: &Custodian): u32 {
    custodian.tribe_id
}

/// Returns the current leader's address.
public fun leader(custodian: &Custodian): address {
    custodian.current_leader
}

/// Returns whether `addr` is in the members set.
public fun is_member(custodian: &Custodian, addr: address): bool {
    vec_set::contains(&custodian.members, &addr)
}

/// Returns whether `addr` is in the operators set.
public fun is_operator(custodian: &Custodian, addr: address): bool {
    vec_set::contains(&custodian.operators, &addr)
}

/// Returns whether `addr` is the current leader.
public fun is_leader(custodian: &Custodian, addr: address): bool {
    custodian.current_leader == addr
}

/// Set the oracle address. Leader only.
public fun set_oracle(
    custodian: &mut Custodian,
    character: &Character,
    oracle_address: address,
    ctx: &mut TxContext,
) {
    assert_authorized_member(custodian, character, ctx);
    assert_leader(custodian, ctx.sender());
    custodian.oracle = option::some(oracle_address);
}

/// Remove the oracle address. Leader only.
public fun remove_oracle(
    custodian: &mut Custodian,
    character: &Character,
    ctx: &mut TxContext,
) {
    assert_authorized_member(custodian, character, ctx);
    assert_leader(custodian, ctx.sender());
    custodian.oracle = option::none();
}

/// Set a tribe standing via the configured oracle.
public fun oracle_set_standing(
    custodian: &mut Custodian,
    tribe_id: u32,
    standing: u8,
    ctx: &mut TxContext,
) {
    assert_oracle(custodian, ctx);
    assert_valid_standing(standing);
    upsert_standing(&mut custodian.standings, tribe_id, standing);
}

/// Batch set tribe standings via the configured oracle.
public fun oracle_batch_set_standings(
    custodian: &mut Custodian,
    tribe_ids: vector<u32>,
    standings: vector<u8>,
    ctx: &mut TxContext,
) {
    assert_oracle(custodian, ctx);
    assert!(tribe_ids.length() == standings.length(), EMismatchedLengths);

    let mut i = 0;
    while (i < tribe_ids.length()) {
        let tribe_id = tribe_ids[i];
        let standing = standings[i];
        assert_valid_standing(standing);
        upsert_standing(&mut custodian.standings, tribe_id, standing);
        i = i + 1;
    };
}

/// Returns whether the custodian has an oracle configured.
public fun has_oracle(custodian: &Custodian): bool {
    option::is_some(&custodian.oracle)
}

/// Returns the oracle address.
public fun get_oracle(custodian: &Custodian): address {
    assert!(option::is_some(&custodian.oracle), EOracleNotSet);
    *option::borrow(&custodian.oracle)
}

fun share_registry(ctx: &mut TxContext) {
    let registry = TribeCustodianRegistry {
        id: object::new(ctx),
        tribes: table::new(ctx),
    };
    transfer::share_object(registry);
}

fun assert_authorized_member(custodian: &Custodian, character: &Character, ctx: &TxContext) {
    assert_sender_controls_character(character, ctx);
    assert!(character.tribe() == custodian.tribe_id, ENotTribeMember);
}

fun assert_sender_controls_character(character: &Character, ctx: &TxContext) {
    assert!(character::character_address(character) == ctx.sender(), ENotTribeMember);
}

fun assert_leader(custodian: &Custodian, sender: address) {
    assert!(custodian.current_leader == sender, ENotLeader);
}

fun assert_oracle(custodian: &Custodian, ctx: &TxContext) {
    assert!(option::is_some(&custodian.oracle), EOracleNotSet);
    assert!(*option::borrow(&custodian.oracle) == ctx.sender(), ENotOracle);
}

fun assert_valid_standing(standing: u8) {
    assert!(standing <= 4, EInvalidStanding);
}

fun ensure_member(custodian: &mut Custodian, member: address) {
    if (!vec_set::contains(&custodian.members, &member)) {
        vec_set::insert(&mut custodian.members, member);
        table::add(&mut custodian.votes, member, member);
        increment_tally(custodian, member);
    };
}

fun increment_tally(custodian: &mut Custodian, candidate: address): u64 {
    if (table::contains(&custodian.vote_tallies, candidate)) {
        let tally = table::borrow_mut(&mut custodian.vote_tallies, candidate);
        *tally = *tally + 1;
        *tally
    } else {
        table::add(&mut custodian.vote_tallies, candidate, 1);
        1
    }
}

fun decrement_tally(custodian: &mut Custodian, candidate: address): u64 {
    let tally = table::borrow_mut(&mut custodian.vote_tallies, candidate);
    *tally = *tally - 1;
    *tally
}

fun get_tally(custodian: &Custodian, candidate: address): u64 {
    if (table::contains(&custodian.vote_tallies, candidate)) {
        *table::borrow(&custodian.vote_tallies, candidate)
    } else {
        0
    }
}

fun upsert_standing(standings: &mut Table<u32, u8>, tribe_id: u32, standing: u8) {
    if (table::contains(standings, tribe_id)) {
        *table::borrow_mut(standings, tribe_id) = standing;
    } else {
        table::add(standings, tribe_id, standing);
    };
}

fun upsert_pilot_standing(standings: &mut Table<address, u8>, pilot: address, standing: u8) {
    if (table::contains(standings, pilot)) {
        *table::borrow_mut(standings, pilot) = standing;
    } else {
        table::add(standings, pilot, standing);
    };
}
