#[test_only]
module sigil::tribe_custodian_tests;

use std::string::utf8;
use sui::test_scenario as ts;
use sigil::tribe_custodian;
use world::{
    access::AdminACL,
    character::{Self, Character},
    object_registry::ObjectRegistry,
    test_helpers::{Self, admin, tenant, user_a, user_b}
};

const OUTSIDER: address = @0xE;

const TRIBE_ALPHA: u32 = 42;
const TRIBE_BETA: u32 = 7;
const TRIBE_GAMMA: u32 = 88;
const UNKNOWN_TRIBE: u32 = 999;

const HOSTILE: u8 = 0;
const UNFRIENDLY: u8 = 1;
const NEUTRAL: u8 = 2;
const FRIENDLY: u8 = 3;
const ALLIED: u8 = 4;

const CHARACTER_A_ITEM_ID: u32 = 7001;
const CHARACTER_B_ITEM_ID: u32 = 7002;
const CHARACTER_C_ITEM_ID: u32 = 7003;

// ── Helpers ──────────────────────────────────────────────────────────

fun setup(ts: &mut ts::Scenario) {
    test_helpers::setup_world(ts);
    ts::next_tx(ts, admin());
    tribe_custodian::init_for_testing(ts.ctx());
    ts::next_tx(ts, admin());
}

fun create_character(
    ts: &mut ts::Scenario,
    owner: address,
    tribe_id: u32,
    item_id: u32,
    name: vector<u8>,
): ID {
    ts::next_tx(ts, admin());
    {
        let admin_acl = ts::take_shared<AdminACL>(ts);
        let mut registry = ts::take_shared<ObjectRegistry>(ts);
        let character = character::create_character(
            &mut registry,
            &admin_acl,
            item_id,
            tenant(),
            tribe_id,
            owner,
            utf8(name),
            ts.ctx(),
        );
        let character_id = object::id(&character);
        character.share_character(&admin_acl, ts.ctx());
        ts::return_shared(registry);
        ts::return_shared(admin_acl);
        character_id
    }
}

fun create_custodian(ts: &mut ts::Scenario, caller: address, character_id: ID) {
    ts::next_tx(ts, caller);
    {
        let mut registry = ts::take_shared<tribe_custodian::TribeCustodianRegistry>(ts);
        let character = ts::take_shared_by_id<Character>(ts, character_id);
        tribe_custodian::create_custodian(&mut registry, &character, ts.ctx());
        ts::return_shared(character);
        ts::return_shared(registry);
    }
}

fun join_custodian(ts: &mut ts::Scenario, caller: address, character_id: ID) {
    ts::next_tx(ts, caller);
    {
        let mut custodian = ts::take_shared<tribe_custodian::Custodian>(ts);
        let character = ts::take_shared_by_id<Character>(ts, character_id);
        tribe_custodian::join(&mut custodian, &character, ts.ctx());
        ts::return_shared(character);
        ts::return_shared(custodian);
    }
}

fun vote_leader(ts: &mut ts::Scenario, caller: address, character_id: ID, candidate: address) {
    ts::next_tx(ts, caller);
    {
        let mut custodian = ts::take_shared<tribe_custodian::Custodian>(ts);
        let character = ts::take_shared_by_id<Character>(ts, character_id);
        tribe_custodian::vote_leader(&mut custodian, &character, candidate, ts.ctx());
        ts::return_shared(character);
        ts::return_shared(custodian);
    }
}

fun claim_leadership(ts: &mut ts::Scenario, caller: address, character_id: ID) {
    ts::next_tx(ts, caller);
    {
        let mut custodian = ts::take_shared<tribe_custodian::Custodian>(ts);
        let character = ts::take_shared_by_id<Character>(ts, character_id);
        tribe_custodian::claim_leadership(&mut custodian, &character, ts.ctx());
        ts::return_shared(character);
        ts::return_shared(custodian);
    }
}

fun add_operator(ts: &mut ts::Scenario, caller: address, character_id: ID, operator: address) {
    ts::next_tx(ts, caller);
    {
        let mut custodian = ts::take_shared<tribe_custodian::Custodian>(ts);
        let character = ts::take_shared_by_id<Character>(ts, character_id);
        tribe_custodian::add_operator(&mut custodian, &character, operator, ts.ctx());
        ts::return_shared(character);
        ts::return_shared(custodian);
    }
}

fun remove_operator(ts: &mut ts::Scenario, caller: address, character_id: ID, operator: address) {
    ts::next_tx(ts, caller);
    {
        let mut custodian = ts::take_shared<tribe_custodian::Custodian>(ts);
        let character = ts::take_shared_by_id<Character>(ts, character_id);
        tribe_custodian::remove_operator(&mut custodian, &character, operator, ts.ctx());
        ts::return_shared(character);
        ts::return_shared(custodian);
    }
}

fun set_standing(ts: &mut ts::Scenario, caller: address, character_id: ID, tribe_id: u32, standing: u8) {
    ts::next_tx(ts, caller);
    {
        let mut custodian = ts::take_shared<tribe_custodian::Custodian>(ts);
        let character = ts::take_shared_by_id<Character>(ts, character_id);
        tribe_custodian::set_standing(&mut custodian, &character, tribe_id, standing, ts.ctx());
        ts::return_shared(character);
        ts::return_shared(custodian);
    }
}

fun set_default_standing(ts: &mut ts::Scenario, caller: address, character_id: ID, standing: u8) {
    ts::next_tx(ts, caller);
    {
        let mut custodian = ts::take_shared<tribe_custodian::Custodian>(ts);
        let character = ts::take_shared_by_id<Character>(ts, character_id);
        tribe_custodian::set_default_standing(&mut custodian, &character, standing, ts.ctx());
        ts::return_shared(character);
        ts::return_shared(custodian);
    }
}

fun set_pilot_standing(
    ts: &mut ts::Scenario, caller: address, character_id: ID, pilot: address, standing: u8,
) {
    ts::next_tx(ts, caller);
    {
        let mut custodian = ts::take_shared<tribe_custodian::Custodian>(ts);
        let character = ts::take_shared_by_id<Character>(ts, character_id);
        tribe_custodian::set_pilot_standing(&mut custodian, &character, pilot, standing, ts.ctx());
        ts::return_shared(character);
        ts::return_shared(custodian);
    }
}

fun batch_set_standings(
    ts: &mut ts::Scenario, caller: address, character_id: ID, tribe_ids: vector<u32>, standings: vector<u8>,
) {
    ts::next_tx(ts, caller);
    {
        let mut custodian = ts::take_shared<tribe_custodian::Custodian>(ts);
        let character = ts::take_shared_by_id<Character>(ts, character_id);
        tribe_custodian::batch_set_standings(&mut custodian, &character, tribe_ids, standings, ts.ctx());
        ts::return_shared(character);
        ts::return_shared(custodian);
    }
}

fun batch_set_pilot_standings(
    ts: &mut ts::Scenario, caller: address, character_id: ID, pilots: vector<address>, standings: vector<u8>,
) {
    ts::next_tx(ts, caller);
    {
        let mut custodian = ts::take_shared<tribe_custodian::Custodian>(ts);
        let character = ts::take_shared_by_id<Character>(ts, character_id);
        tribe_custodian::batch_set_pilot_standings(&mut custodian, &character, pilots, standings, ts.ctx());
        ts::return_shared(character);
        ts::return_shared(custodian);
    }
}

fun assert_pristine_custodian(ts: &mut ts::Scenario, expected_leader: address) {
    ts::next_tx(ts, user_a());
    {
        let c = ts::take_shared<tribe_custodian::Custodian>(ts);
        assert!(tribe_custodian::leader(&c) == expected_leader);
        assert!(!tribe_custodian::is_member(&c, OUTSIDER));
        assert!(!tribe_custodian::is_operator(&c, OUTSIDER));
        assert!(tribe_custodian::get_standing(&c, UNKNOWN_TRIBE) == NEUTRAL);
        ts::return_shared(c);
    }
}


// ── R1: Registry created at init ──

#[test]
fun test_registry_created_at_init() {
    let mut scenario = ts::begin(user_a());
    setup(&mut scenario);
    assert!(ts::has_most_recent_shared<tribe_custodian::TribeCustodianRegistry>());
    let char_id = create_character(&mut scenario, user_a(), TRIBE_ALPHA, CHARACTER_A_ITEM_ID, b"first");
    create_custodian(&mut scenario, user_a(), char_id);
    scenario.end();
}

// ── R2: Create custodian ──

#[test]
fun test_create_custodian() {
    let mut scenario = ts::begin(user_a());
    setup(&mut scenario);
    let char_id = create_character(&mut scenario, user_a(), TRIBE_ALPHA, CHARACTER_A_ITEM_ID, b"leader");
    create_custodian(&mut scenario, user_a(), char_id);
    scenario.next_tx(user_a());
    {
        let c = scenario.take_shared<tribe_custodian::Custodian>();
        assert!(tribe_custodian::tribe_id(&c) == TRIBE_ALPHA);
        assert!(tribe_custodian::leader(&c) == user_a());
        assert!(tribe_custodian::is_member(&c, user_a()));
        assert!(tribe_custodian::get_standing(&c, UNKNOWN_TRIBE) == NEUTRAL); // default_standing=2
        ts::return_shared(c);
    };
    scenario.end();
}

// ── R3: Duplicate tribe rejected ──

#[test, expected_failure(abort_code = tribe_custodian::ETribeAlreadyRegistered)]
fun test_create_custodian_duplicate_tribe_fails() {
    let mut scenario = ts::begin(user_a());
    setup(&mut scenario);
    let char_a = create_character(&mut scenario, user_a(), TRIBE_ALPHA, CHARACTER_A_ITEM_ID, b"a");
    let char_b = create_character(&mut scenario, user_b(), TRIBE_ALPHA, CHARACTER_B_ITEM_ID, b"b");
    create_custodian(&mut scenario, user_a(), char_a);
    create_custodian(&mut scenario, user_b(), char_b);
    scenario.end();
}

// ── R4: Join custodian ──

#[test]
fun test_join_custodian() {
    let mut scenario = ts::begin(user_a());
    setup(&mut scenario);
    let leader_id = create_character(&mut scenario, user_a(), TRIBE_ALPHA, CHARACTER_A_ITEM_ID, b"leader");
    let member_id = create_character(&mut scenario, user_b(), TRIBE_ALPHA, CHARACTER_B_ITEM_ID, b"member");
    create_custodian(&mut scenario, user_a(), leader_id);
    join_custodian(&mut scenario, user_b(), member_id);
    scenario.next_tx(user_a());
    {
        let c = scenario.take_shared<tribe_custodian::Custodian>();
        assert!(tribe_custodian::is_member(&c, user_b()));
        ts::return_shared(c);
    };
    scenario.end();
}

// ── R5: Non-tribe-member join rejected ──

#[test, expected_failure(abort_code = tribe_custodian::ENotTribeMember)]
fun test_join_wrong_tribe_fails() {
    let mut scenario = ts::begin(user_a());
    setup(&mut scenario);
    let leader_id = create_character(&mut scenario, user_a(), TRIBE_ALPHA, CHARACTER_A_ITEM_ID, b"leader");
    let outsider_id = create_character(&mut scenario, OUTSIDER, TRIBE_BETA, CHARACTER_B_ITEM_ID, b"outsider");
    create_custodian(&mut scenario, user_a(), leader_id);
    join_custodian(&mut scenario, OUTSIDER, outsider_id);
    scenario.end();
}

// ── R6: Join is idempotent ──

#[test]
fun test_join_idempotent() {
    let mut scenario = ts::begin(user_a());
    setup(&mut scenario);
    let leader_id = create_character(&mut scenario, user_a(), TRIBE_ALPHA, CHARACTER_A_ITEM_ID, b"leader");
    let member_id = create_character(&mut scenario, user_b(), TRIBE_ALPHA, CHARACTER_B_ITEM_ID, b"member");
    create_custodian(&mut scenario, user_a(), leader_id);
    join_custodian(&mut scenario, user_b(), member_id);
    vote_leader(&mut scenario, user_b(), member_id, user_a());
    join_custodian(&mut scenario, user_b(), member_id);
    scenario.next_tx(user_a());
    {
        let c = scenario.take_shared<tribe_custodian::Custodian>();
        assert!(tribe_custodian::is_member(&c, user_b()));
        assert!(tribe_custodian::leader(&c) == user_a());
        ts::return_shared(c);
    };
    scenario.end();
}

// ── R7: Vote for self (default) ──

#[test]
fun test_default_vote_for_self() {
    let mut scenario = ts::begin(user_a());
    setup(&mut scenario);
    let leader_id = create_character(&mut scenario, user_a(), TRIBE_ALPHA, CHARACTER_A_ITEM_ID, b"leader");
    let member_id = create_character(&mut scenario, user_b(), TRIBE_ALPHA, CHARACTER_B_ITEM_ID, b"member");
    let challenger_id = create_character(&mut scenario, OUTSIDER, TRIBE_ALPHA, CHARACTER_C_ITEM_ID, b"challenger");
    create_custodian(&mut scenario, user_a(), leader_id);
    join_custodian(&mut scenario, user_b(), member_id);
    join_custodian(&mut scenario, OUTSIDER, challenger_id);
    // A=1(self), B=1(self), C=1(self). C votes for B: B gets 2, A has 1. Leadership transfers to B.
    // This only works if B received a default self-vote on join.
    vote_leader(&mut scenario, OUTSIDER, challenger_id, user_b());
    scenario.next_tx(user_a());
    {
        let c = scenario.take_shared<tribe_custodian::Custodian>();
        assert!(tribe_custodian::leader(&c) == user_b());
        ts::return_shared(c);
    };
    scenario.end();
}

// ── R8: Vote for another member ──

#[test]
fun test_vote_for_another_member() {
    let mut scenario = ts::begin(user_a());
    setup(&mut scenario);
    let leader_id = create_character(&mut scenario, user_a(), TRIBE_ALPHA, CHARACTER_A_ITEM_ID, b"leader");
    let member_b_id = create_character(&mut scenario, user_b(), TRIBE_ALPHA, CHARACTER_B_ITEM_ID, b"member");
    let member_c_id = create_character(&mut scenario, OUTSIDER, TRIBE_ALPHA, CHARACTER_C_ITEM_ID, b"c");
    create_custodian(&mut scenario, user_a(), leader_id);
    join_custodian(&mut scenario, user_b(), member_b_id);
    join_custodian(&mut scenario, OUTSIDER, member_c_id);
    // A=1(self), B=1(self), C=1(self). B votes for C, C votes for C: C gets 3 votes.
    // This proves vote_leader moved B's vote from self to C (tally adjusted by 1 each).
    vote_leader(&mut scenario, user_b(), member_b_id, OUTSIDER);
    vote_leader(&mut scenario, OUTSIDER, member_c_id, OUTSIDER);
    scenario.next_tx(user_a());
    {
        let c = scenario.take_shared<tribe_custodian::Custodian>();
        assert!(tribe_custodian::leader(&c) == OUTSIDER);
        ts::return_shared(c);
    };
    scenario.end();
}

// ── R9: Vote auto-joins ──

#[test]
fun test_vote_auto_joins() {
    let mut scenario = ts::begin(user_a());
    setup(&mut scenario);
    let leader_id = create_character(&mut scenario, user_a(), TRIBE_ALPHA, CHARACTER_A_ITEM_ID, b"leader");
    let member_id = create_character(&mut scenario, user_b(), TRIBE_ALPHA, CHARACTER_B_ITEM_ID, b"member");
    create_custodian(&mut scenario, user_a(), leader_id);
    // user_b has NOT joined. vote_leader should auto-join AND record the vote for user_a.
    vote_leader(&mut scenario, user_b(), member_id, user_a());
    scenario.next_tx(user_a());
    {
        let c = scenario.take_shared<tribe_custodian::Custodian>();
        // Proves auto-join: user_b is now a member
        assert!(tribe_custodian::is_member(&c, user_b()));
        // Proves vote recorded: user_a has 2 votes (self + user_b), so user_a stays leader
        assert!(tribe_custodian::leader(&c) == user_a());
        ts::return_shared(c);
    };
    scenario.end();
}

// ── R10: Vote for non-member rejected ──

#[test, expected_failure(abort_code = tribe_custodian::ECandidateNotMember)]
fun test_vote_for_non_member_fails() {
    let mut scenario = ts::begin(user_a());
    setup(&mut scenario);
    let leader_id = create_character(&mut scenario, user_a(), TRIBE_ALPHA, CHARACTER_A_ITEM_ID, b"leader");
    let member_id = create_character(&mut scenario, user_b(), TRIBE_ALPHA, CHARACTER_B_ITEM_ID, b"member");
    create_custodian(&mut scenario, user_a(), leader_id);
    join_custodian(&mut scenario, user_b(), member_id);
    vote_leader(&mut scenario, user_b(), member_id, OUTSIDER); // OUTSIDER not a member
    scenario.end();
}

// ── R11: Change vote updates tallies ──

#[test]
fun test_change_vote_updates_tallies() {
    let mut scenario = ts::begin(user_a());
    setup(&mut scenario);
    let leader_id = create_character(&mut scenario, user_a(), TRIBE_ALPHA, CHARACTER_A_ITEM_ID, b"leader");
    let member_id = create_character(&mut scenario, user_b(), TRIBE_ALPHA, CHARACTER_B_ITEM_ID, b"member");
    let member_c_id = create_character(&mut scenario, OUTSIDER, TRIBE_ALPHA, CHARACTER_C_ITEM_ID, b"third");
    create_custodian(&mut scenario, user_a(), leader_id);
    join_custodian(&mut scenario, user_b(), member_id);
    join_custodian(&mut scenario, OUTSIDER, member_c_id);
    vote_leader(&mut scenario, user_b(), member_id, OUTSIDER);
    vote_leader(&mut scenario, OUTSIDER, member_c_id, OUTSIDER);
    scenario.next_tx(user_a());
    {
        let c = scenario.take_shared<tribe_custodian::Custodian>();
        assert!(tribe_custodian::leader(&c) == OUTSIDER);
        ts::return_shared(c);
    };
    vote_leader(&mut scenario, user_b(), member_id, user_a());
    vote_leader(&mut scenario, OUTSIDER, member_c_id, user_a());
    claim_leadership(&mut scenario, user_a(), leader_id);
    scenario.next_tx(user_a());
    {
        let c = scenario.take_shared<tribe_custodian::Custodian>();
        assert!(tribe_custodian::leader(&c) == user_a());
        ts::return_shared(c);
    };
    scenario.end();
}

// ── R12: Leadership transfers up on vote ──

#[test]
fun test_leadership_transfers_up_on_vote() {
    let mut scenario = ts::begin(user_a());
    setup(&mut scenario);
    let leader_id = create_character(&mut scenario, user_a(), TRIBE_ALPHA, CHARACTER_A_ITEM_ID, b"leader");
    let member_b_id = create_character(&mut scenario, user_b(), TRIBE_ALPHA, CHARACTER_B_ITEM_ID, b"b");
    let member_c_id = create_character(&mut scenario, OUTSIDER, TRIBE_ALPHA, CHARACTER_C_ITEM_ID, b"c");
    create_custodian(&mut scenario, user_a(), leader_id);
    join_custodian(&mut scenario, user_b(), member_b_id);
    join_custodian(&mut scenario, OUTSIDER, member_c_id);
    vote_leader(&mut scenario, user_b(), member_b_id, OUTSIDER);
    vote_leader(&mut scenario, OUTSIDER, member_c_id, OUTSIDER);
    scenario.next_tx(user_a());
    {
        let c = scenario.take_shared<tribe_custodian::Custodian>();
        assert!(tribe_custodian::leader(&c) == OUTSIDER);
        ts::return_shared(c);
    };
    scenario.end();
}

// ── R13: Claim leadership succeeds ──

#[test]
fun test_claim_leadership_succeeds() {
    let mut scenario = ts::begin(user_a());
    setup(&mut scenario);
    let leader_id = create_character(&mut scenario, user_a(), TRIBE_ALPHA, CHARACTER_A_ITEM_ID, b"leader");
    let challenger_id = create_character(&mut scenario, user_b(), TRIBE_ALPHA, CHARACTER_B_ITEM_ID, b"challenger");
    create_custodian(&mut scenario, user_a(), leader_id);
    join_custodian(&mut scenario, user_b(), challenger_id);
    vote_leader(&mut scenario, user_a(), leader_id, user_b());
    claim_leadership(&mut scenario, user_b(), challenger_id);
    scenario.next_tx(user_a());
    {
        let c = scenario.take_shared<tribe_custodian::Custodian>();
        assert!(tribe_custodian::leader(&c) == user_b());
        ts::return_shared(c);
    };
    scenario.end();
}

// ── R14: Claim leadership fails when not ahead ──

#[test, expected_failure(abort_code = tribe_custodian::ENotLeaderCandidate)]
fun test_claim_leadership_insufficient_votes_fails() {
    let mut scenario = ts::begin(user_a());
    setup(&mut scenario);
    let leader_id = create_character(&mut scenario, user_a(), TRIBE_ALPHA, CHARACTER_A_ITEM_ID, b"leader");
    let challenger_id = create_character(&mut scenario, user_b(), TRIBE_ALPHA, CHARACTER_B_ITEM_ID, b"challenger");
    create_custodian(&mut scenario, user_a(), leader_id);
    join_custodian(&mut scenario, user_b(), challenger_id);
    claim_leadership(&mut scenario, user_b(), challenger_id);
    scenario.end();
}

// ── R15: Add operator ──

#[test]
fun test_add_operator() {
    let mut scenario = ts::begin(user_a());
    setup(&mut scenario);
    let leader_id = create_character(&mut scenario, user_a(), TRIBE_ALPHA, CHARACTER_A_ITEM_ID, b"leader");
    let op_id = create_character(&mut scenario, user_b(), TRIBE_ALPHA, CHARACTER_B_ITEM_ID, b"operator");
    create_custodian(&mut scenario, user_a(), leader_id);
    join_custodian(&mut scenario, user_b(), op_id);
    add_operator(&mut scenario, user_a(), leader_id, user_b());
    scenario.next_tx(user_a());
    {
        let c = scenario.take_shared<tribe_custodian::Custodian>();
        assert!(tribe_custodian::is_operator(&c, user_b()));
        ts::return_shared(c);
    };
    scenario.end();
}

// ── R16: Add operator by non-leader rejected ──

#[test, expected_failure(abort_code = tribe_custodian::ENotLeader)]
fun test_add_operator_non_leader_fails() {
    let mut scenario = ts::begin(user_a());
    setup(&mut scenario);
    let leader_id = create_character(&mut scenario, user_a(), TRIBE_ALPHA, CHARACTER_A_ITEM_ID, b"leader");
    let member_id = create_character(&mut scenario, user_b(), TRIBE_ALPHA, CHARACTER_B_ITEM_ID, b"member");
    create_custodian(&mut scenario, user_a(), leader_id);
    join_custodian(&mut scenario, user_b(), member_id);
    add_operator(&mut scenario, user_b(), member_id, user_b());
    scenario.end();
}

// ── R17: Remove operator ──

#[test]
fun test_remove_operator() {
    let mut scenario = ts::begin(user_a());
    setup(&mut scenario);
    let leader_id = create_character(&mut scenario, user_a(), TRIBE_ALPHA, CHARACTER_A_ITEM_ID, b"leader");
    let op_id = create_character(&mut scenario, user_b(), TRIBE_ALPHA, CHARACTER_B_ITEM_ID, b"op");
    create_custodian(&mut scenario, user_a(), leader_id);
    join_custodian(&mut scenario, user_b(), op_id);
    add_operator(&mut scenario, user_a(), leader_id, user_b());
    remove_operator(&mut scenario, user_a(), leader_id, user_b());
    scenario.next_tx(user_a());
    {
        let c = scenario.take_shared<tribe_custodian::Custodian>();
        assert!(!tribe_custodian::is_operator(&c, user_b()));
        ts::return_shared(c);
    };
    scenario.end();
}

// ── R18: Remove operator by non-leader rejected ──

#[test, expected_failure(abort_code = tribe_custodian::ENotLeader)]
fun test_remove_operator_non_leader_fails() {
    let mut scenario = ts::begin(user_a());
    setup(&mut scenario);
    let leader_id = create_character(&mut scenario, user_a(), TRIBE_ALPHA, CHARACTER_A_ITEM_ID, b"leader");
    let op_id = create_character(&mut scenario, user_b(), TRIBE_ALPHA, CHARACTER_B_ITEM_ID, b"op");
    create_custodian(&mut scenario, user_a(), leader_id);
    join_custodian(&mut scenario, user_b(), op_id);
    add_operator(&mut scenario, user_a(), leader_id, user_b());
    remove_operator(&mut scenario, user_b(), op_id, user_b());
    scenario.end();
}

// ── R19: Add non-member as operator rejected ──

#[test, expected_failure(abort_code = tribe_custodian::EOperatorNotMember)]
fun test_add_operator_non_member_fails() {
    let mut scenario = ts::begin(user_a());
    setup(&mut scenario);
    let leader_id = create_character(&mut scenario, user_a(), TRIBE_ALPHA, CHARACTER_A_ITEM_ID, b"leader");
    create_custodian(&mut scenario, user_a(), leader_id);
    add_operator(&mut scenario, user_a(), leader_id, user_b());
    scenario.end();
}

// ── R20: View accessors reflect governance state ──

#[test]
fun test_view_accessors_reflect_governance_state() {
    let mut scenario = ts::begin(user_a());
    setup(&mut scenario);
    let leader_id = create_character(&mut scenario, user_a(), TRIBE_ALPHA, CHARACTER_A_ITEM_ID, b"leader");
    let member_id = create_character(&mut scenario, user_b(), TRIBE_ALPHA, CHARACTER_B_ITEM_ID, b"member");
    create_custodian(&mut scenario, user_a(), leader_id);
    join_custodian(&mut scenario, user_b(), member_id);
    add_operator(&mut scenario, user_a(), leader_id, user_b());
    scenario.next_tx(user_a());
    {
        let c = scenario.take_shared<tribe_custodian::Custodian>();
        assert!(tribe_custodian::tribe_id(&c) == TRIBE_ALPHA);
        assert!(tribe_custodian::leader(&c) == user_a());
        assert!(tribe_custodian::is_member(&c, user_a()));
        assert!(tribe_custodian::is_member(&c, user_b()));
        assert!(!tribe_custodian::is_member(&c, OUTSIDER));
        assert!(tribe_custodian::is_operator(&c, user_b()));
        assert!(!tribe_custodian::is_operator(&c, user_a()));
        assert!(tribe_custodian::is_leader(&c, user_a()));
        assert!(!tribe_custodian::is_leader(&c, user_b()));
        ts::return_shared(c);
    };
    scenario.end();
}

// ── R21: Set standing ──

#[test]
fun test_set_standing() {
    let mut scenario = ts::begin(user_a());
    setup(&mut scenario);
    let leader_id = create_character(&mut scenario, user_a(), TRIBE_ALPHA, CHARACTER_A_ITEM_ID, b"leader");
    create_custodian(&mut scenario, user_a(), leader_id);
    set_standing(&mut scenario, user_a(), leader_id, TRIBE_BETA, ALLIED);
    scenario.next_tx(user_a());
    {
        let c = scenario.take_shared<tribe_custodian::Custodian>();
        assert!(tribe_custodian::get_standing(&c, TRIBE_BETA) == ALLIED);
        ts::return_shared(c);
    };
    scenario.end();
}

// ── R22: All standings writes by non-leader rejected ──
// Split into individual expected_failure tests per write function

#[test, expected_failure(abort_code = tribe_custodian::ENotLeader)]
fun test_set_standing_non_leader_fails() {
    let mut scenario = ts::begin(user_a());
    setup(&mut scenario);
    let leader_id = create_character(&mut scenario, user_a(), TRIBE_ALPHA, CHARACTER_A_ITEM_ID, b"leader");
    let member_id = create_character(&mut scenario, user_b(), TRIBE_ALPHA, CHARACTER_B_ITEM_ID, b"member");
    create_custodian(&mut scenario, user_a(), leader_id);
    join_custodian(&mut scenario, user_b(), member_id);
    set_standing(&mut scenario, user_b(), member_id, TRIBE_BETA, HOSTILE);
    scenario.end();
}

#[test, expected_failure(abort_code = tribe_custodian::ENotLeader)]
fun test_set_default_standing_non_leader_fails() {
    let mut scenario = ts::begin(user_a());
    setup(&mut scenario);
    let leader_id = create_character(&mut scenario, user_a(), TRIBE_ALPHA, CHARACTER_A_ITEM_ID, b"leader");
    let member_id = create_character(&mut scenario, user_b(), TRIBE_ALPHA, CHARACTER_B_ITEM_ID, b"member");
    create_custodian(&mut scenario, user_a(), leader_id);
    join_custodian(&mut scenario, user_b(), member_id);
    set_default_standing(&mut scenario, user_b(), member_id, HOSTILE);
    scenario.end();
}

#[test, expected_failure(abort_code = tribe_custodian::ENotLeader)]
fun test_set_pilot_standing_non_leader_fails() {
    let mut scenario = ts::begin(user_a());
    setup(&mut scenario);
    let leader_id = create_character(&mut scenario, user_a(), TRIBE_ALPHA, CHARACTER_A_ITEM_ID, b"leader");
    let member_id = create_character(&mut scenario, user_b(), TRIBE_ALPHA, CHARACTER_B_ITEM_ID, b"member");
    create_custodian(&mut scenario, user_a(), leader_id);
    join_custodian(&mut scenario, user_b(), member_id);
    set_pilot_standing(&mut scenario, user_b(), member_id, OUTSIDER, HOSTILE);
    scenario.end();
}

#[test, expected_failure(abort_code = tribe_custodian::ENotLeader)]
fun test_batch_set_standings_non_leader_fails() {
    let mut scenario = ts::begin(user_a());
    setup(&mut scenario);
    let leader_id = create_character(&mut scenario, user_a(), TRIBE_ALPHA, CHARACTER_A_ITEM_ID, b"leader");
    let member_id = create_character(&mut scenario, user_b(), TRIBE_ALPHA, CHARACTER_B_ITEM_ID, b"member");
    create_custodian(&mut scenario, user_a(), leader_id);
    join_custodian(&mut scenario, user_b(), member_id);
    batch_set_standings(&mut scenario, user_b(), member_id, vector[TRIBE_BETA], vector[HOSTILE]);
    scenario.end();
}

#[test, expected_failure(abort_code = tribe_custodian::ENotLeader)]
fun test_batch_set_pilot_standings_non_leader_fails() {
    let mut scenario = ts::begin(user_a());
    setup(&mut scenario);
    let leader_id = create_character(&mut scenario, user_a(), TRIBE_ALPHA, CHARACTER_A_ITEM_ID, b"leader");
    let member_id = create_character(&mut scenario, user_b(), TRIBE_ALPHA, CHARACTER_B_ITEM_ID, b"member");
    create_custodian(&mut scenario, user_a(), leader_id);
    join_custodian(&mut scenario, user_b(), member_id);
    batch_set_pilot_standings(&mut scenario, user_b(), member_id, vector[OUTSIDER], vector[HOSTILE]);
    scenario.end();
}

// ── R23: Set default standing ──

#[test]
fun test_set_default_standing() {
    let mut scenario = ts::begin(user_a());
    setup(&mut scenario);
    let leader_id = create_character(&mut scenario, user_a(), TRIBE_ALPHA, CHARACTER_A_ITEM_ID, b"leader");
    create_custodian(&mut scenario, user_a(), leader_id);
    set_default_standing(&mut scenario, user_a(), leader_id, UNFRIENDLY);
    scenario.next_tx(user_a());
    {
        let c = scenario.take_shared<tribe_custodian::Custodian>();
        assert!(tribe_custodian::get_standing(&c, UNKNOWN_TRIBE) == UNFRIENDLY);
        ts::return_shared(c);
    };
    scenario.end();
}

// ── R24: Set pilot standing ──

#[test]
fun test_set_pilot_standing() {
    let mut scenario = ts::begin(user_a());
    setup(&mut scenario);
    let leader_id = create_character(&mut scenario, user_a(), TRIBE_ALPHA, CHARACTER_A_ITEM_ID, b"leader");
    create_custodian(&mut scenario, user_a(), leader_id);
    set_pilot_standing(&mut scenario, user_a(), leader_id, OUTSIDER, FRIENDLY);
    scenario.next_tx(user_a());
    {
        let c = scenario.take_shared<tribe_custodian::Custodian>();
        assert!(tribe_custodian::get_pilot_standing(&c, OUTSIDER) == FRIENDLY);
        ts::return_shared(c);
    };
    scenario.end();
}

// ── R25: Batch set tribe standings ──

#[test]
fun test_batch_set_standings() {
    let mut scenario = ts::begin(user_a());
    setup(&mut scenario);
    let leader_id = create_character(&mut scenario, user_a(), TRIBE_ALPHA, CHARACTER_A_ITEM_ID, b"leader");
    create_custodian(&mut scenario, user_a(), leader_id);
    batch_set_standings(&mut scenario, user_a(), leader_id, vector[TRIBE_BETA, TRIBE_GAMMA], vector[HOSTILE, ALLIED]);
    scenario.next_tx(user_a());
    {
        let c = scenario.take_shared<tribe_custodian::Custodian>();
        assert!(tribe_custodian::get_standing(&c, TRIBE_BETA) == HOSTILE);
        assert!(tribe_custodian::get_standing(&c, TRIBE_GAMMA) == ALLIED);
        ts::return_shared(c);
    };
    scenario.end();
}

// ── R26: Batch set pilot standings ──

#[test]
fun test_batch_set_pilot_standings() {
    let mut scenario = ts::begin(user_a());
    setup(&mut scenario);
    let leader_id = create_character(&mut scenario, user_a(), TRIBE_ALPHA, CHARACTER_A_ITEM_ID, b"leader");
    create_custodian(&mut scenario, user_a(), leader_id);
    batch_set_pilot_standings(&mut scenario, user_a(), leader_id, vector[user_b(), OUTSIDER], vector[FRIENDLY, ALLIED]);
    scenario.next_tx(user_a());
    {
        let c = scenario.take_shared<tribe_custodian::Custodian>();
        assert!(tribe_custodian::get_pilot_standing(&c, user_b()) == FRIENDLY);
        assert!(tribe_custodian::get_pilot_standing(&c, OUTSIDER) == ALLIED);
        ts::return_shared(c);
    };
    scenario.end();
}

// ── R27: Invalid standing rejected (all standing writers) ──

#[test, expected_failure(abort_code = tribe_custodian::EInvalidStanding)]
fun test_invalid_standing_set_standing() {
    let mut scenario = ts::begin(user_a());
    setup(&mut scenario);
    let leader_id = create_character(&mut scenario, user_a(), TRIBE_ALPHA, CHARACTER_A_ITEM_ID, b"leader");
    create_custodian(&mut scenario, user_a(), leader_id);
    set_standing(&mut scenario, user_a(), leader_id, TRIBE_BETA, 5);
    scenario.end();
}

#[test, expected_failure(abort_code = tribe_custodian::EInvalidStanding)]
fun test_invalid_standing_set_default() {
    let mut scenario = ts::begin(user_a());
    setup(&mut scenario);
    let leader_id = create_character(&mut scenario, user_a(), TRIBE_ALPHA, CHARACTER_A_ITEM_ID, b"leader");
    create_custodian(&mut scenario, user_a(), leader_id);
    set_default_standing(&mut scenario, user_a(), leader_id, 5);
    scenario.end();
}

#[test, expected_failure(abort_code = tribe_custodian::EInvalidStanding)]
fun test_invalid_standing_set_pilot() {
    let mut scenario = ts::begin(user_a());
    setup(&mut scenario);
    let leader_id = create_character(&mut scenario, user_a(), TRIBE_ALPHA, CHARACTER_A_ITEM_ID, b"leader");
    create_custodian(&mut scenario, user_a(), leader_id);
    set_pilot_standing(&mut scenario, user_a(), leader_id, OUTSIDER, 5);
    scenario.end();
}

#[test, expected_failure(abort_code = tribe_custodian::EInvalidStanding)]
fun test_invalid_standing_batch_set() {
    let mut scenario = ts::begin(user_a());
    setup(&mut scenario);
    let leader_id = create_character(&mut scenario, user_a(), TRIBE_ALPHA, CHARACTER_A_ITEM_ID, b"leader");
    create_custodian(&mut scenario, user_a(), leader_id);
    batch_set_standings(&mut scenario, user_a(), leader_id, vector[TRIBE_BETA], vector[5]);
    scenario.end();
}

#[test, expected_failure(abort_code = tribe_custodian::EInvalidStanding)]
fun test_invalid_standing_batch_set_pilot() {
    let mut scenario = ts::begin(user_a());
    setup(&mut scenario);
    let leader_id = create_character(&mut scenario, user_a(), TRIBE_ALPHA, CHARACTER_A_ITEM_ID, b"leader");
    create_custodian(&mut scenario, user_a(), leader_id);
    batch_set_pilot_standings(&mut scenario, user_a(), leader_id, vector[OUTSIDER], vector[5]);
    scenario.end();
}

// ── R28: Batch mismatched lengths rejected (both batch APIs) ──

#[test, expected_failure(abort_code = tribe_custodian::EMismatchedLengths)]
fun test_batch_mismatched_lengths_standings() {
    let mut scenario = ts::begin(user_a());
    setup(&mut scenario);
    let leader_id = create_character(&mut scenario, user_a(), TRIBE_ALPHA, CHARACTER_A_ITEM_ID, b"leader");
    create_custodian(&mut scenario, user_a(), leader_id);
    batch_set_standings(&mut scenario, user_a(), leader_id, vector[TRIBE_ALPHA, TRIBE_BETA], vector[HOSTILE]);
    scenario.end();
}

#[test, expected_failure(abort_code = tribe_custodian::EMismatchedLengths)]
fun test_batch_mismatched_lengths_pilot_standings() {
    let mut scenario = ts::begin(user_a());
    setup(&mut scenario);
    let leader_id = create_character(&mut scenario, user_a(), TRIBE_ALPHA, CHARACTER_A_ITEM_ID, b"leader");
    create_custodian(&mut scenario, user_a(), leader_id);
    batch_set_pilot_standings(&mut scenario, user_a(), leader_id, vector[user_a(), user_b()], vector[HOSTILE]);
    scenario.end();
}

// ── R29: Get standing returns stored value ──

#[test]
fun test_get_standing_stored() {
    let mut scenario = ts::begin(user_a());
    setup(&mut scenario);
    let leader_id = create_character(&mut scenario, user_a(), TRIBE_ALPHA, CHARACTER_A_ITEM_ID, b"leader");
    create_custodian(&mut scenario, user_a(), leader_id);
    set_standing(&mut scenario, user_a(), leader_id, TRIBE_BETA, ALLIED);
    scenario.next_tx(user_a());
    {
        let c = scenario.take_shared<tribe_custodian::Custodian>();
        assert!(tribe_custodian::get_standing(&c, TRIBE_BETA) == ALLIED);
        ts::return_shared(c);
    };
    scenario.end();
}

// ── R30: Get standing returns default for unknown ──

#[test]
fun test_get_standing_default() {
    let mut scenario = ts::begin(user_a());
    setup(&mut scenario);
    let leader_id = create_character(&mut scenario, user_a(), TRIBE_ALPHA, CHARACTER_A_ITEM_ID, b"leader");
    create_custodian(&mut scenario, user_a(), leader_id);
    scenario.next_tx(user_a());
    {
        let c = scenario.take_shared<tribe_custodian::Custodian>();
        assert!(tribe_custodian::get_standing(&c, UNKNOWN_TRIBE) == NEUTRAL);
        ts::return_shared(c);
    };
    scenario.end();
}

// ── R31: Get pilot standing returns stored value ──

#[test]
fun test_get_pilot_standing_stored() {
    let mut scenario = ts::begin(user_a());
    setup(&mut scenario);
    let leader_id = create_character(&mut scenario, user_a(), TRIBE_ALPHA, CHARACTER_A_ITEM_ID, b"leader");
    create_custodian(&mut scenario, user_a(), leader_id);
    set_pilot_standing(&mut scenario, user_a(), leader_id, OUTSIDER, ALLIED);
    scenario.next_tx(user_a());
    {
        let c = scenario.take_shared<tribe_custodian::Custodian>();
        assert!(tribe_custodian::get_pilot_standing(&c, OUTSIDER) == ALLIED);
        ts::return_shared(c);
    };
    scenario.end();
}

// ── R32: Get pilot standing returns default for unknown ──

#[test]
fun test_get_pilot_standing_default() {
    let mut scenario = ts::begin(user_a());
    setup(&mut scenario);
    let leader_id = create_character(&mut scenario, user_a(), TRIBE_ALPHA, CHARACTER_A_ITEM_ID, b"leader");
    create_custodian(&mut scenario, user_a(), leader_id);
    scenario.next_tx(user_a());
    {
        let c = scenario.take_shared<tribe_custodian::Custodian>();
        assert!(tribe_custodian::get_pilot_standing(&c, OUTSIDER) == NEUTRAL);
        ts::return_shared(c);
    };
    scenario.end();
}

// ── R33: Effective standing — pilot override ──

#[test]
fun test_effective_standing_pilot_override() {
    let mut scenario = ts::begin(user_a());
    setup(&mut scenario);
    let leader_id = create_character(&mut scenario, user_a(), TRIBE_ALPHA, CHARACTER_A_ITEM_ID, b"leader");
    create_custodian(&mut scenario, user_a(), leader_id);
    set_standing(&mut scenario, user_a(), leader_id, TRIBE_BETA, HOSTILE);
    set_pilot_standing(&mut scenario, user_a(), leader_id, OUTSIDER, ALLIED);
    scenario.next_tx(user_a());
    {
        let c = scenario.take_shared<tribe_custodian::Custodian>();
        assert!(tribe_custodian::get_effective_standing(&c, TRIBE_BETA, OUTSIDER) == ALLIED);
        ts::return_shared(c);
    };
    scenario.end();
}

// ── R34: Effective standing — tribe fallback ──

#[test]
fun test_effective_standing_tribe_fallback() {
    let mut scenario = ts::begin(user_a());
    setup(&mut scenario);
    let leader_id = create_character(&mut scenario, user_a(), TRIBE_ALPHA, CHARACTER_A_ITEM_ID, b"leader");
    create_custodian(&mut scenario, user_a(), leader_id);
    set_default_standing(&mut scenario, user_a(), leader_id, HOSTILE);
    set_standing(&mut scenario, user_a(), leader_id, TRIBE_BETA, FRIENDLY);
    scenario.next_tx(user_a());
    {
        let c = scenario.take_shared<tribe_custodian::Custodian>();
        assert!(tribe_custodian::get_effective_standing(&c, TRIBE_BETA, OUTSIDER) == FRIENDLY);
        ts::return_shared(c);
    };
    scenario.end();
}

// ── R35: Effective standing — default fallback ──

#[test]
fun test_effective_standing_default_fallback() {
    let mut scenario = ts::begin(user_a());
    setup(&mut scenario);
    let leader_id = create_character(&mut scenario, user_a(), TRIBE_ALPHA, CHARACTER_A_ITEM_ID, b"leader");
    create_custodian(&mut scenario, user_a(), leader_id);
    set_default_standing(&mut scenario, user_a(), leader_id, UNFRIENDLY);
    scenario.next_tx(user_a());
    {
        let c = scenario.take_shared<tribe_custodian::Custodian>();
        assert!(tribe_custodian::get_effective_standing(&c, UNKNOWN_TRIBE, OUTSIDER) == UNFRIENDLY);
        ts::return_shared(c);
    };
    scenario.end();
}

// ── R36: Operator standings write rejected ──

#[test, expected_failure(abort_code = tribe_custodian::ENotLeader)]
fun test_operator_cannot_write_standings() {
    let mut scenario = ts::begin(user_a());
    setup(&mut scenario);
    let leader_id = create_character(&mut scenario, user_a(), TRIBE_ALPHA, CHARACTER_A_ITEM_ID, b"leader");
    let op_id = create_character(&mut scenario, user_b(), TRIBE_ALPHA, CHARACTER_B_ITEM_ID, b"op");
    create_custodian(&mut scenario, user_a(), leader_id);
    join_custodian(&mut scenario, user_b(), op_id);
    add_operator(&mut scenario, user_a(), leader_id, user_b());
    set_standing(&mut scenario, user_b(), op_id, TRIBE_BETA, HOSTILE);
    scenario.end();
}

// ── R37: Leadership change preserves operators ──

#[test]
fun test_leadership_change_preserves_operators() {
    let mut scenario = ts::begin(user_a());
    setup(&mut scenario);
    let leader_id = create_character(&mut scenario, user_a(), TRIBE_ALPHA, CHARACTER_A_ITEM_ID, b"leader");
    let op_id = create_character(&mut scenario, user_b(), TRIBE_ALPHA, CHARACTER_B_ITEM_ID, b"op");
    let challenger_id = create_character(&mut scenario, OUTSIDER, TRIBE_ALPHA, CHARACTER_C_ITEM_ID, b"challenger");
    create_custodian(&mut scenario, user_a(), leader_id);
    join_custodian(&mut scenario, user_b(), op_id);
    join_custodian(&mut scenario, OUTSIDER, challenger_id);
    add_operator(&mut scenario, user_a(), leader_id, user_b());
    // Transfer leadership to OUTSIDER
    vote_leader(&mut scenario, user_a(), leader_id, OUTSIDER);
    vote_leader(&mut scenario, user_b(), op_id, OUTSIDER);
    claim_leadership(&mut scenario, OUTSIDER, challenger_id);
    scenario.next_tx(user_a());
    {
        let c = scenario.take_shared<tribe_custodian::Custodian>();
        assert!(tribe_custodian::leader(&c) == OUTSIDER);
        assert!(tribe_custodian::is_operator(&c, user_b())); // operator preserved
        ts::return_shared(c);
    };
    scenario.end();
}

// ── R38: Creator is initial leader ──

#[test]
fun test_creator_is_initial_leader() {
    let mut scenario = ts::begin(user_a());
    setup(&mut scenario);
    let leader_id = create_character(&mut scenario, user_a(), TRIBE_ALPHA, CHARACTER_A_ITEM_ID, b"leader");
    create_custodian(&mut scenario, user_a(), leader_id);
    scenario.next_tx(user_a());
    {
        let c = scenario.take_shared<tribe_custodian::Custodian>();
        assert!(tribe_custodian::leader(&c) == user_a());
        assert!(tribe_custodian::is_leader(&c, user_a()));
        assert!(tribe_custodian::is_member(&c, user_a()));
        ts::return_shared(c);
    };
    scenario.end();
}

// ── R39: Full governance cycle ──

#[test]
fun test_full_governance_cycle() {
    let mut scenario = ts::begin(user_a());
    setup(&mut scenario);
    let leader_id = create_character(&mut scenario, user_a(), TRIBE_ALPHA, CHARACTER_A_ITEM_ID, b"leader");
    let member_b_id = create_character(&mut scenario, user_b(), TRIBE_ALPHA, CHARACTER_B_ITEM_ID, b"b");
    let member_c_id = create_character(&mut scenario, OUTSIDER, TRIBE_ALPHA, CHARACTER_C_ITEM_ID, b"c");
    create_custodian(&mut scenario, user_a(), leader_id);
    join_custodian(&mut scenario, user_b(), member_b_id);
    join_custodian(&mut scenario, OUTSIDER, member_c_id);
    vote_leader(&mut scenario, user_a(), leader_id, user_b());
    vote_leader(&mut scenario, OUTSIDER, member_c_id, user_b());
    claim_leadership(&mut scenario, user_b(), member_b_id);
    set_standing(&mut scenario, user_b(), member_b_id, TRIBE_BETA, ALLIED);
    scenario.next_tx(user_a());
    {
        let c = scenario.take_shared<tribe_custodian::Custodian>();
        assert!(tribe_custodian::leader(&c) == user_b());
        assert!(tribe_custodian::get_standing(&c, TRIBE_BETA) == ALLIED);
        ts::return_shared(c);
    };
    scenario.end();
}

#[test, expected_failure(abort_code = tribe_custodian::ENotLeader)]
fun test_full_governance_cycle_old_leader_rejected() {
    let mut scenario = ts::begin(user_a());
    setup(&mut scenario);
    let leader_id = create_character(&mut scenario, user_a(), TRIBE_ALPHA, CHARACTER_A_ITEM_ID, b"leader");
    let member_b_id = create_character(&mut scenario, user_b(), TRIBE_ALPHA, CHARACTER_B_ITEM_ID, b"b");
    let member_c_id = create_character(&mut scenario, OUTSIDER, TRIBE_ALPHA, CHARACTER_C_ITEM_ID, b"c");
    create_custodian(&mut scenario, user_a(), leader_id);
    join_custodian(&mut scenario, user_b(), member_b_id);
    join_custodian(&mut scenario, OUTSIDER, member_c_id);
    vote_leader(&mut scenario, user_a(), leader_id, user_b());
    vote_leader(&mut scenario, OUTSIDER, member_c_id, user_b());
    claim_leadership(&mut scenario, user_b(), member_b_id);
    set_standing(&mut scenario, user_a(), leader_id, TRIBE_GAMMA, HOSTILE);
    scenario.end();
}

// ── R40: Standings survive leadership change ──

#[test]
fun test_standings_survive_leadership_change() {
    let mut scenario = ts::begin(user_a());
    setup(&mut scenario);
    let leader_id = create_character(&mut scenario, user_a(), TRIBE_ALPHA, CHARACTER_A_ITEM_ID, b"leader");
    let member_b_id = create_character(&mut scenario, user_b(), TRIBE_ALPHA, CHARACTER_B_ITEM_ID, b"b");
    let member_c_id = create_character(&mut scenario, OUTSIDER, TRIBE_ALPHA, CHARACTER_C_ITEM_ID, b"c");
    create_custodian(&mut scenario, user_a(), leader_id);
    join_custodian(&mut scenario, user_b(), member_b_id);
    join_custodian(&mut scenario, OUTSIDER, member_c_id);
    set_standing(&mut scenario, user_a(), leader_id, TRIBE_BETA, FRIENDLY);
    vote_leader(&mut scenario, user_a(), leader_id, user_b());
    vote_leader(&mut scenario, OUTSIDER, member_c_id, user_b());
    claim_leadership(&mut scenario, user_b(), member_b_id);
    set_standing(&mut scenario, user_b(), member_b_id, TRIBE_GAMMA, HOSTILE);
    scenario.next_tx(user_a());
    {
        let c = scenario.take_shared<tribe_custodian::Custodian>();
        assert!(tribe_custodian::get_standing(&c, TRIBE_BETA) == FRIENDLY);
        assert!(tribe_custodian::get_standing(&c, TRIBE_GAMMA) == HOSTILE);
        assert!(tribe_custodian::leader(&c) == user_b());
        ts::return_shared(c);
    };
    scenario.end();
}

// ── R41: Non-tribe-member blocked from all mutation paths ──
// Move VM guarantee: when a function aborts, the entire transaction is rolled back
// atomically. No partial state changes persist. The expected_failure annotation proves
// the abort, and the assert_pristine_custodian call before each mutation proves the
// pre-state. Post-abort state is identical to pre-state by VM semantics.

#[test, expected_failure(abort_code = tribe_custodian::ENotTribeMember)]
fun test_non_tribe_member_blocked_join() {
    let mut scenario = ts::begin(user_a());
    setup(&mut scenario);
    let leader_id = create_character(&mut scenario, user_a(), TRIBE_ALPHA, CHARACTER_A_ITEM_ID, b"leader");
    let outsider_id = create_character(&mut scenario, OUTSIDER, TRIBE_BETA, CHARACTER_B_ITEM_ID, b"outsider");
    create_custodian(&mut scenario, user_a(), leader_id);
    assert_pristine_custodian(&mut scenario, user_a());
    join_custodian(&mut scenario, OUTSIDER, outsider_id);
    scenario.end();
}

#[test, expected_failure(abort_code = tribe_custodian::ENotTribeMember)]
fun test_non_tribe_member_blocked_vote() {
    let mut scenario = ts::begin(user_a());
    setup(&mut scenario);
    let leader_id = create_character(&mut scenario, user_a(), TRIBE_ALPHA, CHARACTER_A_ITEM_ID, b"leader");
    let outsider_id = create_character(&mut scenario, OUTSIDER, TRIBE_BETA, CHARACTER_B_ITEM_ID, b"outsider");
    create_custodian(&mut scenario, user_a(), leader_id);
    assert_pristine_custodian(&mut scenario, user_a());
    vote_leader(&mut scenario, OUTSIDER, outsider_id, user_a());
    scenario.end();
}

#[test, expected_failure(abort_code = tribe_custodian::ENotTribeMember)]
fun test_non_tribe_member_blocked_claim() {
    let mut scenario = ts::begin(user_a());
    setup(&mut scenario);
    let leader_id = create_character(&mut scenario, user_a(), TRIBE_ALPHA, CHARACTER_A_ITEM_ID, b"leader");
    let outsider_id = create_character(&mut scenario, OUTSIDER, TRIBE_BETA, CHARACTER_B_ITEM_ID, b"outsider");
    create_custodian(&mut scenario, user_a(), leader_id);
    assert_pristine_custodian(&mut scenario, user_a());
    claim_leadership(&mut scenario, OUTSIDER, outsider_id);
    scenario.end();
}

#[test, expected_failure(abort_code = tribe_custodian::ENotTribeMember)]
fun test_non_tribe_member_blocked_add_operator() {
    let mut scenario = ts::begin(user_a());
    setup(&mut scenario);
    let leader_id = create_character(&mut scenario, user_a(), TRIBE_ALPHA, CHARACTER_A_ITEM_ID, b"leader");
    let outsider_id = create_character(&mut scenario, OUTSIDER, TRIBE_BETA, CHARACTER_B_ITEM_ID, b"outsider");
    create_custodian(&mut scenario, user_a(), leader_id);
    assert_pristine_custodian(&mut scenario, user_a());
    add_operator(&mut scenario, OUTSIDER, outsider_id, OUTSIDER);
    scenario.end();
}

#[test, expected_failure(abort_code = tribe_custodian::ENotTribeMember)]
fun test_non_tribe_member_blocked_set_standing() {
    let mut scenario = ts::begin(user_a());
    setup(&mut scenario);
    let leader_id = create_character(&mut scenario, user_a(), TRIBE_ALPHA, CHARACTER_A_ITEM_ID, b"leader");
    let outsider_id = create_character(&mut scenario, OUTSIDER, TRIBE_BETA, CHARACTER_B_ITEM_ID, b"outsider");
    create_custodian(&mut scenario, user_a(), leader_id);
    assert_pristine_custodian(&mut scenario, user_a());
    set_standing(&mut scenario, OUTSIDER, outsider_id, TRIBE_ALPHA, HOSTILE);
    scenario.end();
}

#[test, expected_failure(abort_code = tribe_custodian::ENotTribeMember)]
fun test_non_tribe_member_blocked_remove_operator() {
    let mut scenario = ts::begin(user_a());
    setup(&mut scenario);
    let leader_id = create_character(&mut scenario, user_a(), TRIBE_ALPHA, CHARACTER_A_ITEM_ID, b"leader");
    let outsider_id = create_character(&mut scenario, OUTSIDER, TRIBE_BETA, CHARACTER_B_ITEM_ID, b"outsider");
    create_custodian(&mut scenario, user_a(), leader_id);
    assert_pristine_custodian(&mut scenario, user_a());
    remove_operator(&mut scenario, OUTSIDER, outsider_id, user_a());
    scenario.end();
}

#[test, expected_failure(abort_code = tribe_custodian::ENotTribeMember)]
fun test_non_tribe_member_blocked_set_default_standing() {
    let mut scenario = ts::begin(user_a());
    setup(&mut scenario);
    let leader_id = create_character(&mut scenario, user_a(), TRIBE_ALPHA, CHARACTER_A_ITEM_ID, b"leader");
    let outsider_id = create_character(&mut scenario, OUTSIDER, TRIBE_BETA, CHARACTER_B_ITEM_ID, b"outsider");
    create_custodian(&mut scenario, user_a(), leader_id);
    assert_pristine_custodian(&mut scenario, user_a());
    set_default_standing(&mut scenario, OUTSIDER, outsider_id, HOSTILE);
    scenario.end();
}

#[test, expected_failure(abort_code = tribe_custodian::ENotTribeMember)]
fun test_non_tribe_member_blocked_set_pilot_standing() {
    let mut scenario = ts::begin(user_a());
    setup(&mut scenario);
    let leader_id = create_character(&mut scenario, user_a(), TRIBE_ALPHA, CHARACTER_A_ITEM_ID, b"leader");
    let outsider_id = create_character(&mut scenario, OUTSIDER, TRIBE_BETA, CHARACTER_B_ITEM_ID, b"outsider");
    create_custodian(&mut scenario, user_a(), leader_id);
    assert_pristine_custodian(&mut scenario, user_a());
    set_pilot_standing(&mut scenario, OUTSIDER, outsider_id, user_a(), HOSTILE);
    scenario.end();
}

#[test, expected_failure(abort_code = tribe_custodian::ENotTribeMember)]
fun test_non_tribe_member_blocked_batch_set_standings() {
    let mut scenario = ts::begin(user_a());
    setup(&mut scenario);
    let leader_id = create_character(&mut scenario, user_a(), TRIBE_ALPHA, CHARACTER_A_ITEM_ID, b"leader");
    let outsider_id = create_character(&mut scenario, OUTSIDER, TRIBE_BETA, CHARACTER_B_ITEM_ID, b"outsider");
    create_custodian(&mut scenario, user_a(), leader_id);
    assert_pristine_custodian(&mut scenario, user_a());
    batch_set_standings(&mut scenario, OUTSIDER, outsider_id, vector[TRIBE_ALPHA], vector[HOSTILE]);
    scenario.end();
}

#[test, expected_failure(abort_code = tribe_custodian::ENotTribeMember)]
fun test_non_tribe_member_blocked_batch_set_pilot_standings() {
    let mut scenario = ts::begin(user_a());
    setup(&mut scenario);
    let leader_id = create_character(&mut scenario, user_a(), TRIBE_ALPHA, CHARACTER_A_ITEM_ID, b"leader");
    let outsider_id = create_character(&mut scenario, OUTSIDER, TRIBE_BETA, CHARACTER_B_ITEM_ID, b"outsider");
    create_custodian(&mut scenario, user_a(), leader_id);
    assert_pristine_custodian(&mut scenario, user_a());
    batch_set_pilot_standings(&mut scenario, OUTSIDER, outsider_id, vector[user_a()], vector[HOSTILE]);
    scenario.end();
}

// ── R42: NBSI/NRDS via default_standing ──

#[test]
fun test_nbsi_nrds_via_default_standing() {
    let mut scenario = ts::begin(user_a());
    setup(&mut scenario);
    let leader_id = create_character(&mut scenario, user_a(), TRIBE_ALPHA, CHARACTER_A_ITEM_ID, b"leader");
    create_custodian(&mut scenario, user_a(), leader_id);
    // NBSI: default=HOSTILE — unknown entities get Hostile
    set_default_standing(&mut scenario, user_a(), leader_id, HOSTILE);
    scenario.next_tx(user_a());
    {
        let c = scenario.take_shared<tribe_custodian::Custodian>();
        assert!(tribe_custodian::get_standing(&c, UNKNOWN_TRIBE) == HOSTILE);
        ts::return_shared(c);
    };
    // NRDS: default=NEUTRAL — unknown entities get Neutral
    set_default_standing(&mut scenario, user_a(), leader_id, NEUTRAL);
    scenario.next_tx(user_a());
    {
        let c = scenario.take_shared<tribe_custodian::Custodian>();
        assert!(tribe_custodian::get_standing(&c, UNKNOWN_TRIBE) == NEUTRAL);
        ts::return_shared(c);
    };
    scenario.end();
}
