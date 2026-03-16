#[test_only]
module sigil::frontier_gate_tests;

use std::{bcs, string::utf8};
use sui::{clock, test_scenario as ts};
use sigil::{frontier_gate, standings_table};
use world::{
    access::{AdminACL, OwnerCap, ServerAddressRegistry},
    character::{Self, Character},
    energy::EnergyConfig,
    gate::{Self, Gate, GateConfig, JumpPermit},
    network_node::{Self, NetworkNode},
    object_registry::ObjectRegistry,
    test_helpers::{Self, admin, governor, tenant, user_a}
};

const HOSTILE: u8 = 0;
const UNFRIENDLY: u8 = 1;
const NEUTRAL: u8 = 2;
const FRIENDLY: u8 = 3;
const ALLIED: u8 = 4;

const FRIENDLY_TRIBE: u32 = 42;
const HOSTILE_TRIBE: u32 = 7;
const UNFRIENDLY_TRIBE: u32 = 9;
const NEUTRAL_TRIBE: u32 = 11;
const ALLIED_TRIBE: u32 = 88;
const UNKNOWN_TRIBE: u32 = 999;

const GATE_TYPE_ID: u64 = 8888;
const GATE_ITEM_ID_1: u64 = 7001;
const GATE_ITEM_ID_2: u64 = 7002;

const MS_PER_SECOND: u64 = 1000;
const NETWORK_NODE_TYPE_ID: u64 = 111000;
const NETWORK_NODE_ITEM_ID: u64 = 5000;
const FUEL_MAX_CAPACITY: u64 = 1000;
const FUEL_BURN_RATE_IN_MS: u64 = 3600 * MS_PER_SECOND;
const MAX_PRODUCTION: u64 = 100;
const FUEL_TYPE_ID: u64 = 1;
const FUEL_VOLUME: u64 = 10;

fun setup(ts: &mut ts::Scenario) {
    test_helpers::setup_world(ts);
    test_helpers::configure_fuel(ts);
    test_helpers::configure_assembly_energy(ts);
    test_helpers::register_server_address(ts);

    ts::next_tx(ts, governor());
    gate::init_for_testing(ts.ctx());

    ts::next_tx(ts, admin());
    {
        let admin_acl = ts::take_shared<AdminACL>(ts);
        let mut gate_config = ts::take_shared<GateConfig>(ts);
        gate::set_max_distance(&mut gate_config, &admin_acl, GATE_TYPE_ID, 1_000_000_000, ts.ctx());
        ts::return_shared(gate_config);
        ts::return_shared(admin_acl);
    };

    ts::next_tx(ts, user_a());
    standings_table::create(ts.ctx());
}

fun create_character(ts: &mut ts::Scenario, tribe_id: u32, item_id: u32): ID {
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
            user_a(),
            utf8(b"traveler"),
            ts.ctx(),
        );
        let character_id = object::id(&character);
        character.share_character(&admin_acl, ts.ctx());
        ts::return_shared(registry);
        ts::return_shared(admin_acl);
        character_id
    }
}

fun create_network_node(ts: &mut ts::Scenario, character_id: ID): ID {
    ts::next_tx(ts, admin());
    {
        let mut registry = ts::take_shared<ObjectRegistry>(ts);
        let character = ts::take_shared_by_id<Character>(ts, character_id);
        let admin_acl = ts::take_shared<AdminACL>(ts);
        let network_node = network_node::anchor(
            &mut registry,
            &character,
            &admin_acl,
            NETWORK_NODE_ITEM_ID,
            NETWORK_NODE_TYPE_ID,
            test_helpers::get_verified_location_hash(),
            FUEL_MAX_CAPACITY,
            FUEL_BURN_RATE_IN_MS,
            MAX_PRODUCTION,
            ts.ctx(),
        );
        let network_node_id = object::id(&network_node);
        network_node.share_network_node(&admin_acl, ts.ctx());
        ts::return_shared(character);
        ts::return_shared(registry);
        ts::return_shared(admin_acl);
        network_node_id
    }
}

fun create_gate(ts: &mut ts::Scenario, character_id: ID, network_node_id: ID, item_id: u64): ID {
    ts::next_tx(ts, admin());
    {
        let mut registry = ts::take_shared<ObjectRegistry>(ts);
        let mut network_node = ts::take_shared_by_id<NetworkNode>(ts, network_node_id);
        let character = ts::take_shared_by_id<Character>(ts, character_id);
        let admin_acl = ts::take_shared<AdminACL>(ts);
        let gate_object = gate::anchor(
            &mut registry,
            &mut network_node,
            &character,
            &admin_acl,
            item_id,
            GATE_TYPE_ID,
            test_helpers::get_verified_location_hash(),
            ts.ctx(),
        );
        let gate_id = object::id(&gate_object);
        gate_object.share_gate(&admin_acl, ts.ctx());
        ts::return_shared(character);
        ts::return_shared(network_node);
        ts::return_shared(registry);
        ts::return_shared(admin_acl);
        gate_id
    }
}

fun bring_network_node_online(ts: &mut ts::Scenario, character_id: ID, network_node_id: ID) {
    ts::next_tx(ts, user_a());
    {
        let clock = clock::create_for_testing(ts.ctx());
        let mut network_node = ts::take_shared_by_id<NetworkNode>(ts, network_node_id);
        let mut character = ts::take_shared_by_id<Character>(ts, character_id);
        let owner_cap_id = network_node.owner_cap_id();
        let owner_cap_ticket = ts::receiving_ticket_by_id<OwnerCap<NetworkNode>>(owner_cap_id);
        let (owner_cap, receipt) = character.borrow_owner_cap<NetworkNode>(owner_cap_ticket, ts.ctx());
        network_node.deposit_fuel_test(&owner_cap, FUEL_TYPE_ID, FUEL_VOLUME, 10, &clock);
        network_node.online(&owner_cap, &clock);
        character.return_owner_cap(owner_cap, receipt);
        ts::return_shared(network_node);
        ts::return_shared(character);
        clock.destroy_for_testing();
    };
}

fun link_and_online_gates(
    ts: &mut ts::Scenario,
    character_id: ID,
    network_node_id: ID,
    source_gate_id: ID,
    destination_gate_id: ID,
) {
    ts::next_tx(ts, user_a());
    {
        let mut network_node = ts::take_shared_by_id<NetworkNode>(ts, network_node_id);
        let energy_config = ts::take_shared<EnergyConfig>(ts);
        let gate_config = ts::take_shared<GateConfig>(ts);
        let server_registry = ts::take_shared<ServerAddressRegistry>(ts);
        let admin_acl = ts::take_shared<AdminACL>(ts);
        let mut source_gate = ts::take_shared_by_id<Gate>(ts, source_gate_id);
        let mut destination_gate = ts::take_shared_by_id<Gate>(ts, destination_gate_id);
        let mut character = ts::take_shared_by_id<Character>(ts, character_id);

        let source_owner_cap_id = source_gate.owner_cap_id();
        let destination_owner_cap_id = destination_gate.owner_cap_id();
        let source_owner_cap_ticket = ts::receiving_ticket_by_id<OwnerCap<Gate>>(source_owner_cap_id);
        let destination_owner_cap_ticket = ts::receiving_ticket_by_id<OwnerCap<Gate>>(destination_owner_cap_id);
        let (source_owner_cap, source_receipt) = character.borrow_owner_cap<Gate>(source_owner_cap_ticket, ts.ctx());
        let (destination_owner_cap, destination_receipt) = character.borrow_owner_cap<Gate>(destination_owner_cap_ticket, ts.ctx());

        let proof = test_helpers::construct_location_proof(test_helpers::get_verified_location_hash());
        let proof_bytes = bcs::to_bytes(&proof);
        let clock = clock::create_for_testing(ts.ctx());

        source_gate.link_gates(
            &mut destination_gate,
            &gate_config,
            &server_registry,
            &admin_acl,
            &source_owner_cap,
            &destination_owner_cap,
            proof_bytes,
            &clock,
            ts.ctx(),
        );

        source_gate.online(&mut network_node, &energy_config, &source_owner_cap);
        destination_gate.online(&mut network_node, &energy_config, &destination_owner_cap);

        clock.destroy_for_testing();
        character.return_owner_cap(source_owner_cap, source_receipt);
        character.return_owner_cap(destination_owner_cap, destination_receipt);
        ts::return_shared(character);
        ts::return_shared(source_gate);
        ts::return_shared(destination_gate);
        ts::return_shared(network_node);
        ts::return_shared(energy_config);
        ts::return_shared(gate_config);
        ts::return_shared(server_registry);
        ts::return_shared(admin_acl);
    };
}

fun authorize_frontier_gate_extension(
    ts: &mut ts::Scenario,
    character_id: ID,
    source_gate_id: ID,
    destination_gate_id: ID,
) {
    ts::next_tx(ts, user_a());
    {
        let mut source_gate = ts::take_shared_by_id<Gate>(ts, source_gate_id);
        let mut destination_gate = ts::take_shared_by_id<Gate>(ts, destination_gate_id);
        let mut character = ts::take_shared_by_id<Character>(ts, character_id);

        let source_owner_cap_ticket = ts::receiving_ticket_by_id<OwnerCap<Gate>>(source_gate.owner_cap_id());
        let destination_owner_cap_ticket = ts::receiving_ticket_by_id<OwnerCap<Gate>>(destination_gate.owner_cap_id());
        let (source_owner_cap, source_receipt) = character.borrow_owner_cap<Gate>(source_owner_cap_ticket, ts.ctx());
        let (destination_owner_cap, destination_receipt) = character.borrow_owner_cap<Gate>(destination_owner_cap_ticket, ts.ctx());

        source_gate.authorize_extension<frontier_gate::FrontierGateAuth>(&source_owner_cap);
        destination_gate.authorize_extension<frontier_gate::FrontierGateAuth>(&destination_owner_cap);

        character.return_owner_cap(source_owner_cap, source_receipt);
        character.return_owner_cap(destination_owner_cap, destination_receipt);
        ts::return_shared(character);
        ts::return_shared(source_gate);
        ts::return_shared(destination_gate);
    };
}

fun set_standing(ts: &mut ts::Scenario, tribe_id: u32, standing: u8) {
    ts::next_tx(ts, user_a());
    {
        let mut table = ts::take_shared<standings_table::StandingsTable>(ts);
        standings_table::set_standing(&mut table, tribe_id, standing, ts.ctx());
        ts::return_shared(table);
    };
}

fun set_default_standing(ts: &mut ts::Scenario, standing: u8) {
    ts::next_tx(ts, user_a());
    {
        let mut table = ts::take_shared<standings_table::StandingsTable>(ts);
        standings_table::set_default_standing(&mut table, standing, ts.ctx());
        ts::return_shared(table);
    };
}

fun set_pilot_standing(ts: &mut ts::Scenario, standing: u8) {
    ts::next_tx(ts, user_a());
    {
        let mut table = ts::take_shared<standings_table::StandingsTable>(ts);
        standings_table::set_pilot_standing(&mut table, user_a(), standing, ts.ctx());
        ts::return_shared(table);
    };
}

fun setup_permit_scenario(ts: &mut ts::Scenario, tribe_id: u32, character_item_id: u32): (ID, ID, ID) {
    setup(ts);

    let character_id = create_character(ts, tribe_id, character_item_id);
    let network_node_id = create_network_node(ts, character_id);
    let source_gate_id = create_gate(ts, character_id, network_node_id, GATE_ITEM_ID_1);
    let destination_gate_id = create_gate(ts, character_id, network_node_id, GATE_ITEM_ID_2);

    bring_network_node_online(ts, character_id, network_node_id);
    link_and_online_gates(ts, character_id, network_node_id, source_gate_id, destination_gate_id);
    authorize_frontier_gate_extension(ts, character_id, source_gate_id, destination_gate_id);

    (character_id, source_gate_id, destination_gate_id)
}

fun request_permit(ts: &mut ts::Scenario, character_id: ID, source_gate_id: ID, destination_gate_id: ID) {
    ts::next_tx(ts, user_a());
    {
        let clock = clock::create_for_testing(ts.ctx());
        let table = ts::take_shared<standings_table::StandingsTable>(ts);
        let source_gate = ts::take_shared_by_id<Gate>(ts, source_gate_id);
        let destination_gate = ts::take_shared_by_id<Gate>(ts, destination_gate_id);
        let character = ts::take_shared_by_id<Character>(ts, character_id);

        frontier_gate::request_permit(
            &table,
            &source_gate,
            &destination_gate,
            &character,
            &clock,
            ts.ctx(),
        );

        ts::return_shared(character);
        ts::return_shared(source_gate);
        ts::return_shared(destination_gate);
        ts::return_shared(table);
        clock.destroy_for_testing();
    };
}

fun request_permit_and_consume(
    ts: &mut ts::Scenario,
    character_id: ID,
    source_gate_id: ID,
    destination_gate_id: ID,
) {
    request_permit(ts, character_id, source_gate_id, destination_gate_id);

    ts::next_tx(ts, user_a());
    {
        let clock = clock::create_for_testing(ts.ctx());
        let source_gate = ts::take_shared_by_id<Gate>(ts, source_gate_id);
        let destination_gate = ts::take_shared_by_id<Gate>(ts, destination_gate_id);
        let character = ts::take_shared_by_id<Character>(ts, character_id);
        let permit = ts::take_from_sender<JumpPermit>(ts);

        gate::test_jump_with_permit(&source_gate, &destination_gate, &character, permit, &clock);

        ts::return_shared(character);
        ts::return_shared(source_gate);
        ts::return_shared(destination_gate);
        clock.destroy_for_testing();
    };
}

#[test]
fun test_friendly_gets_permit() {
    let mut ts = ts::begin(governor());
    let (character_id, source_gate_id, destination_gate_id) = setup_permit_scenario(
        &mut ts,
        FRIENDLY_TRIBE,
        101,
    );

    set_standing(&mut ts, FRIENDLY_TRIBE, FRIENDLY);
    request_permit_and_consume(&mut ts, character_id, source_gate_id, destination_gate_id);

    ts::end(ts);
}

#[test, expected_failure(abort_code = frontier_gate::EAccessDenied)]
fun test_hostile_denied() {
    let mut ts = ts::begin(governor());
    let (character_id, source_gate_id, destination_gate_id) = setup_permit_scenario(
        &mut ts,
        HOSTILE_TRIBE,
        102,
    );

    set_standing(&mut ts, HOSTILE_TRIBE, HOSTILE);
    request_permit(&mut ts, character_id, source_gate_id, destination_gate_id);

    ts::end(ts);
}

#[test]
fun test_unfriendly_gets_permit() {
    let mut ts = ts::begin(governor());
    let (character_id, source_gate_id, destination_gate_id) = setup_permit_scenario(
        &mut ts,
        UNFRIENDLY_TRIBE,
        103,
    );

    set_standing(&mut ts, UNFRIENDLY_TRIBE, UNFRIENDLY);
    request_permit_and_consume(&mut ts, character_id, source_gate_id, destination_gate_id);

    ts::end(ts);
}

#[test]
fun test_neutral_gets_permit() {
    let mut ts = ts::begin(governor());
    let (character_id, source_gate_id, destination_gate_id) = setup_permit_scenario(
        &mut ts,
        NEUTRAL_TRIBE,
        104,
    );

    set_standing(&mut ts, NEUTRAL_TRIBE, NEUTRAL);
    request_permit_and_consume(&mut ts, character_id, source_gate_id, destination_gate_id);

    ts::end(ts);
}

#[test]
fun test_allied_gets_permit() {
    let mut ts = ts::begin(governor());
    let (character_id, source_gate_id, destination_gate_id) = setup_permit_scenario(
        &mut ts,
        ALLIED_TRIBE,
        105,
    );

    set_standing(&mut ts, ALLIED_TRIBE, ALLIED);
    request_permit_and_consume(&mut ts, character_id, source_gate_id, destination_gate_id);

    ts::end(ts);
}

#[test]
fun test_pilot_override_allows_hostile_tribe_member() {
    let mut ts = ts::begin(governor());
    let (character_id, source_gate_id, destination_gate_id) = setup_permit_scenario(
        &mut ts,
        HOSTILE_TRIBE,
        106,
    );

    set_standing(&mut ts, HOSTILE_TRIBE, HOSTILE);
    set_pilot_standing(&mut ts, FRIENDLY);
    request_permit_and_consume(&mut ts, character_id, source_gate_id, destination_gate_id);

    ts::end(ts);
}

#[test, expected_failure(abort_code = frontier_gate::EAccessDenied)]
fun test_pilot_override_denies_friendly_tribe_member() {
    let mut ts = ts::begin(governor());
    let (character_id, source_gate_id, destination_gate_id) = setup_permit_scenario(
        &mut ts,
        FRIENDLY_TRIBE,
        107,
    );

    set_standing(&mut ts, FRIENDLY_TRIBE, FRIENDLY);
    set_pilot_standing(&mut ts, HOSTILE);
    request_permit(&mut ts, character_id, source_gate_id, destination_gate_id);

    ts::end(ts);
}

#[test, expected_failure(abort_code = frontier_gate::EAccessDenied)]
fun test_nbsi_denies_unknown() {
    let mut ts = ts::begin(governor());
    let (character_id, source_gate_id, destination_gate_id) = setup_permit_scenario(
        &mut ts,
        UNKNOWN_TRIBE,
        108,
    );

    set_default_standing(&mut ts, HOSTILE);
    request_permit(&mut ts, character_id, source_gate_id, destination_gate_id);

    ts::end(ts);
}

#[test]
fun test_nrds_allows_unknown() {
    let mut ts = ts::begin(governor());
    let (character_id, source_gate_id, destination_gate_id) = setup_permit_scenario(
        &mut ts,
        UNKNOWN_TRIBE,
        109,
    );

    set_default_standing(&mut ts, NEUTRAL);
    request_permit_and_consume(&mut ts, character_id, source_gate_id, destination_gate_id);

    ts::end(ts);
}
