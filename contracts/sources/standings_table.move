module sigil::standings_table;

use sui::table::{Self, Table};

/// Caller is not the table owner.
const ENotOwner: u64 = 0;
/// Standing value must be 0..4 (hostile/unfriendly/neutral/friendly/allied).
const EInvalidStanding: u64 = 1;
/// Batch vectors must have equal length.
const EMismatchedLengths: u64 = 2;

/// On-chain diplomacy table mapping tribe_id -> standing and pilot -> standing.
/// Standing values: 0 = hostile, 1 = unfriendly, 2 = neutral, 3 = friendly, 4 = allied.
public struct StandingsTable has key {
    id: UID,
    owner: address,
    standings: Table<u32, u8>,
    default_standing: u8,
    pilot_standings: Table<address, u8>,
}

/// Create a new StandingsTable as a shared object. The caller becomes the owner.
public fun create(ctx: &mut TxContext) {
    let table = StandingsTable {
        id: object::new(ctx),
        owner: ctx.sender(),
        standings: table::new(ctx),
        default_standing: 2, // neutral
        pilot_standings: table::new(ctx),
    };
    transfer::share_object(table);
}

/// Set a single tribe's standing. Only the owner may call this.
public fun set_standing(
    table: &mut StandingsTable,
    tribe_id: u32,
    standing: u8,
    ctx: &TxContext,
) {
    assert!(ctx.sender() == table.owner, ENotOwner);
    assert!(standing <= 4, EInvalidStanding);

    if (table.standings.contains(tribe_id)) {
        *table.standings.borrow_mut(tribe_id) = standing;
    } else {
        table.standings.add(tribe_id, standing);
    };
}

/// Read a tribe's standing. Returns default_standing if the tribe is not in the table.
public fun get_standing(table: &StandingsTable, tribe_id: u32): u8 {
    if (table.standings.contains(tribe_id)) {
        *table.standings.borrow(tribe_id)
    } else {
        table.default_standing
    }
}

/// Set the default standing for unknown tribes. Only the owner may call this.
public fun set_default_standing(
    table: &mut StandingsTable,
    standing: u8,
    ctx: &TxContext,
) {
    assert!(ctx.sender() == table.owner, ENotOwner);
    assert!(standing <= 4, EInvalidStanding);
    table.default_standing = standing;
}

/// Set a single pilot's standing. Only the owner may call this.
public fun set_pilot_standing(
    table: &mut StandingsTable,
    pilot: address,
    standing: u8,
    ctx: &TxContext,
) {
    assert!(ctx.sender() == table.owner, ENotOwner);
    assert!(standing <= 4, EInvalidStanding);

    if (table.pilot_standings.contains(pilot)) {
        *table.pilot_standings.borrow_mut(pilot) = standing;
    } else {
        table.pilot_standings.add(pilot, standing);
    };
}

/// Read a pilot's standing. Returns default_standing if the pilot is not in the table.
public fun get_pilot_standing(table: &StandingsTable, pilot: address): u8 {
    if (table.pilot_standings.contains(pilot)) {
        *table.pilot_standings.borrow(pilot)
    } else {
        table.default_standing
    }
}

/// Get effective standing for a pilot: pilot -> tribe -> default_standing.
public fun get_effective_standing(table: &StandingsTable, tribe_id: u32, pilot: address): u8 {
    if (table.pilot_standings.contains(pilot)) {
        *table.pilot_standings.borrow(pilot)
    } else if (table.standings.contains(tribe_id)) {
        *table.standings.borrow(tribe_id)
    } else {
        table.default_standing
    }
}

/// Set standings for multiple tribes in one call. Only the owner may call this.
/// Aborts if `tribe_ids` and `standings` have different lengths.
public fun batch_set_standings(
    table: &mut StandingsTable,
    tribe_ids: vector<u32>,
    standings: vector<u8>,
    ctx: &TxContext,
) {
    assert!(ctx.sender() == table.owner, ENotOwner);
    assert!(tribe_ids.length() == standings.length(), EMismatchedLengths);

    let mut i = 0;
    while (i < tribe_ids.length()) {
        let tribe_id = tribe_ids[i];
        let standing = standings[i];
        assert!(standing <= 4, EInvalidStanding);

        if (table.standings.contains(tribe_id)) {
            *table.standings.borrow_mut(tribe_id) = standing;
        } else {
            table.standings.add(tribe_id, standing);
        };

        i = i + 1;
    };
}

/// Set standings for multiple pilots in one call. Only the owner may call this.
/// Aborts if `pilots` and `standings` have different lengths.
public fun batch_set_pilot_standings(
    table: &mut StandingsTable,
    pilots: vector<address>,
    standings: vector<u8>,
    ctx: &TxContext,
) {
    assert!(ctx.sender() == table.owner, ENotOwner);
    assert!(pilots.length() == standings.length(), EMismatchedLengths);

    let mut i = 0;
    while (i < pilots.length()) {
        let pilot = pilots[i];
        let standing = standings[i];
        assert!(standing <= 4, EInvalidStanding);

        if (table.pilot_standings.contains(pilot)) {
            *table.pilot_standings.borrow_mut(pilot) = standing;
        } else {
            table.pilot_standings.add(pilot, standing);
        };

        i = i + 1;
    };
}
