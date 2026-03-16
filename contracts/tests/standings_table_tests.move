#[test_only]
module sigil::standings_table_tests;

use sui::test_scenario;
use sigil::standings_table;

const OWNER: address = @0xA;
const STRANGER: address = @0xB;
const PILOT_A: address = @0xC;
const PILOT_B: address = @0xD;
const UNKNOWN_TRIBE: u32 = 999;
const HOSTILE: u8 = 0;
const UNFRIENDLY: u8 = 1;
const NEUTRAL: u8 = 2;
const FRIENDLY: u8 = 3;
const ALLIED: u8 = 4;

#[test]
fun test_create_standings_table() {
    let mut scenario = test_scenario::begin(OWNER);

    standings_table::create(scenario.ctx());
    scenario.next_tx(OWNER);

    assert!(test_scenario::has_most_recent_shared<standings_table::StandingsTable>());

    scenario.end();
}

#[test]
fun test_set_standing() {
    let mut scenario = test_scenario::begin(OWNER);

    standings_table::create(scenario.ctx());
    scenario.next_tx(OWNER);

    {
        let mut table = scenario.take_shared<standings_table::StandingsTable>();
        standings_table::set_standing(&mut table, 42u32, ALLIED, scenario.ctx());
        assert!(standings_table::get_standing(&table, 42u32) == ALLIED);
        test_scenario::return_shared(table);
    };

    scenario.next_tx(OWNER);

    {
        let table = scenario.take_shared<standings_table::StandingsTable>();
        assert!(standings_table::get_standing(&table, 42u32) == ALLIED);
        test_scenario::return_shared(table);
    };

    scenario.end();
}

#[test]
fun test_set_default_standing() {
    let mut scenario = test_scenario::begin(OWNER);

    standings_table::create(scenario.ctx());
    scenario.next_tx(OWNER);

    {
        let mut table = scenario.take_shared<standings_table::StandingsTable>();
        standings_table::set_default_standing(&mut table, UNFRIENDLY, scenario.ctx());
        assert!(standings_table::get_standing(&table, UNKNOWN_TRIBE) == UNFRIENDLY);
        test_scenario::return_shared(table);
    };

    scenario.end();
}

#[test]
fun test_default_standing_used_for_unknown() {
    let mut scenario = test_scenario::begin(OWNER);

    standings_table::create(scenario.ctx());
    scenario.next_tx(OWNER);

    {
        let mut table = scenario.take_shared<standings_table::StandingsTable>();
        standings_table::set_default_standing(&mut table, FRIENDLY, scenario.ctx());
        assert!(standings_table::get_standing(&table, UNKNOWN_TRIBE) == FRIENDLY);
        test_scenario::return_shared(table);
    };

    scenario.end();
}

#[test]
fun test_set_pilot_standing() {
    let mut scenario = test_scenario::begin(OWNER);

    standings_table::create(scenario.ctx());
    scenario.next_tx(OWNER);

    {
        let mut table = scenario.take_shared<standings_table::StandingsTable>();
        standings_table::set_pilot_standing(&mut table, PILOT_A, ALLIED, scenario.ctx());
        assert!(standings_table::get_pilot_standing(&table, PILOT_A) == ALLIED);
        test_scenario::return_shared(table);
    };

    scenario.end();
}

#[test]
fun test_get_pilot_standing_default() {
    let mut scenario = test_scenario::begin(OWNER);

    standings_table::create(scenario.ctx());
    scenario.next_tx(OWNER);

    {
        let mut table = scenario.take_shared<standings_table::StandingsTable>();
        standings_table::set_default_standing(&mut table, UNFRIENDLY, scenario.ctx());
        assert!(standings_table::get_pilot_standing(&table, PILOT_A) == UNFRIENDLY);
        test_scenario::return_shared(table);
    };

    scenario.end();
}

#[test, expected_failure]
fun test_non_owner_fails() {
    let mut scenario = test_scenario::begin(OWNER);

    standings_table::create(scenario.ctx());
    scenario.next_tx(STRANGER);

    {
        let mut table = scenario.take_shared<standings_table::StandingsTable>();
        standings_table::set_standing(&mut table, 7u32, HOSTILE, scenario.ctx());
        test_scenario::return_shared(table);
    };

    scenario.end();
}

#[test]
fun test_batch_set_standings() {
    let mut scenario = test_scenario::begin(OWNER);

    standings_table::create(scenario.ctx());
    scenario.next_tx(OWNER);

    {
        let mut table = scenario.take_shared<standings_table::StandingsTable>();
        let tribe_ids: vector<u32> = vector[7u32, 11u32, 42u32];
        let standings: vector<u8> = vector[HOSTILE, NEUTRAL, ALLIED];

        standings_table::batch_set_standings(&mut table, tribe_ids, standings, scenario.ctx());

        assert!(standings_table::get_standing(&table, 7u32) == HOSTILE);
        assert!(standings_table::get_standing(&table, 11u32) == NEUTRAL);
        assert!(standings_table::get_standing(&table, 42u32) == ALLIED);
        test_scenario::return_shared(table);
    };

    scenario.next_tx(OWNER);

    {
        let table = scenario.take_shared<standings_table::StandingsTable>();
        assert!(standings_table::get_standing(&table, 7u32) == HOSTILE);
        assert!(standings_table::get_standing(&table, 11u32) == NEUTRAL);
        assert!(standings_table::get_standing(&table, 42u32) == ALLIED);
        test_scenario::return_shared(table);
    };

    scenario.end();
}

#[test]
fun test_batch_set_pilot_standings() {
    let mut scenario = test_scenario::begin(OWNER);

    standings_table::create(scenario.ctx());
    scenario.next_tx(OWNER);

    {
        let mut table = scenario.take_shared<standings_table::StandingsTable>();
        let pilots: vector<address> = vector[PILOT_A, PILOT_B];
        let standings: vector<u8> = vector[UNFRIENDLY, ALLIED];

        standings_table::batch_set_pilot_standings(&mut table, pilots, standings, scenario.ctx());

        assert!(standings_table::get_pilot_standing(&table, PILOT_A) == UNFRIENDLY);
        assert!(standings_table::get_pilot_standing(&table, PILOT_B) == ALLIED);
        test_scenario::return_shared(table);
    };

    scenario.end();
}

#[test]
fun test_effective_standing_pilot_override() {
    let mut scenario = test_scenario::begin(OWNER);

    standings_table::create(scenario.ctx());
    scenario.next_tx(OWNER);

    {
        let mut table = scenario.take_shared<standings_table::StandingsTable>();
        standings_table::set_standing(&mut table, 42u32, HOSTILE, scenario.ctx());
        standings_table::set_pilot_standing(&mut table, PILOT_A, ALLIED, scenario.ctx());
        assert!(standings_table::get_effective_standing(&table, 42u32, PILOT_A) == ALLIED);
        test_scenario::return_shared(table);
    };

    scenario.end();
}

#[test]
fun test_effective_standing_tribe_fallback() {
    let mut scenario = test_scenario::begin(OWNER);

    standings_table::create(scenario.ctx());
    scenario.next_tx(OWNER);

    {
        let mut table = scenario.take_shared<standings_table::StandingsTable>();
        standings_table::set_default_standing(&mut table, HOSTILE, scenario.ctx());
        standings_table::set_standing(&mut table, 42u32, FRIENDLY, scenario.ctx());
        assert!(standings_table::get_effective_standing(&table, 42u32, PILOT_A) == FRIENDLY);
        test_scenario::return_shared(table);
    };

    scenario.end();
}

#[test]
fun test_effective_standing_default_fallback() {
    let mut scenario = test_scenario::begin(OWNER);

    standings_table::create(scenario.ctx());
    scenario.next_tx(OWNER);

    {
        let mut table = scenario.take_shared<standings_table::StandingsTable>();
        standings_table::set_default_standing(&mut table, UNFRIENDLY, scenario.ctx());
        assert!(standings_table::get_effective_standing(&table, UNKNOWN_TRIBE, PILOT_A) == UNFRIENDLY);
        test_scenario::return_shared(table);
    };

    scenario.end();
}

#[test, expected_failure]
fun test_invalid_standing_5tier() {
    let mut scenario = test_scenario::begin(OWNER);

    standings_table::create(scenario.ctx());
    scenario.next_tx(OWNER);

    {
        let mut table = scenario.take_shared<standings_table::StandingsTable>();
        standings_table::set_default_standing(&mut table, 5, scenario.ctx());
        test_scenario::return_shared(table);
    };

    scenario.end();
}
