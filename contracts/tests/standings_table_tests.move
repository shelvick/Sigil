#[test_only]
module frontier_os::standings_table_tests;

use sui::test_scenario;
use frontier_os::standings_table;

const OWNER: address = @0xA;
const STRANGER: address = @0xB;
const HOSTILE: u8 = 0;
const NEUTRAL: u8 = 1;
const FRIENDLY: u8 = 2;

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
        standings_table::set_standing(&mut table, 42u32, FRIENDLY, scenario.ctx());
        assert!(standings_table::get_standing(&table, 42u32) == FRIENDLY);
        test_scenario::return_shared(table);
    };

    scenario.next_tx(OWNER);

    {
        let table = scenario.take_shared<standings_table::StandingsTable>();
        assert!(standings_table::get_standing(&table, 42u32) == FRIENDLY);
        test_scenario::return_shared(table);
    };

    scenario.end();
}

#[test]
fun test_default_neutral() {
    let mut scenario = test_scenario::begin(OWNER);

    standings_table::create(scenario.ctx());
    scenario.next_tx(OWNER);

    {
        let table = scenario.take_shared<standings_table::StandingsTable>();
        assert!(standings_table::get_standing(&table, 999u32) == NEUTRAL);
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
        let standings: vector<u8> = vector[HOSTILE, NEUTRAL, FRIENDLY];

        standings_table::batch_set_standings(&mut table, tribe_ids, standings, scenario.ctx());

        assert!(standings_table::get_standing(&table, 7u32) == HOSTILE);
        assert!(standings_table::get_standing(&table, 11u32) == NEUTRAL);
        assert!(standings_table::get_standing(&table, 42u32) == FRIENDLY);
        test_scenario::return_shared(table);
    };

    scenario.next_tx(OWNER);

    {
        let table = scenario.take_shared<standings_table::StandingsTable>();
        assert!(standings_table::get_standing(&table, 7u32) == HOSTILE);
        assert!(standings_table::get_standing(&table, 11u32) == NEUTRAL);
        assert!(standings_table::get_standing(&table, 42u32) == FRIENDLY);
        test_scenario::return_shared(table);
    };

    scenario.end();
}
