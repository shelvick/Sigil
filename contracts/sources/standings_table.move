module frontier_os::standings_table;

use sui::table::{Self, Table};

/// Caller is not the table owner.
const ENotOwner: u64 = 0;
/// Standing value must be 0 (hostile), 1 (neutral), or 2 (friendly).
const EInvalidStanding: u64 = 1;
/// Batch vectors must have equal length.
const EMismatchedLengths: u64 = 2;

/// On-chain diplomacy table mapping tribe_id -> standing.
/// Standing values: 0 = hostile, 1 = neutral, 2 = friendly.
public struct StandingsTable has key {
    id: UID,
    owner: address,
    standings: Table<u32, u8>,
}

/// Create a new StandingsTable as a shared object. The caller becomes the owner.
public fun create(ctx: &mut TxContext) {
    let table = StandingsTable {
        id: object::new(ctx),
        owner: ctx.sender(),
        standings: table::new(ctx),
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
    assert!(standing <= 2, EInvalidStanding);

    if (table.standings.contains(tribe_id)) {
        *table.standings.borrow_mut(tribe_id) = standing;
    } else {
        table.standings.add(tribe_id, standing);
    };
}

/// Read a tribe's standing. Returns 1 (neutral) if the tribe is not in the table.
public fun get_standing(table: &StandingsTable, tribe_id: u32): u8 {
    if (table.standings.contains(tribe_id)) {
        *table.standings.borrow(tribe_id)
    } else {
        1 // neutral default
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
        assert!(standing <= 2, EInvalidStanding);

        if (table.standings.contains(tribe_id)) {
            *table.standings.borrow_mut(tribe_id) = standing;
        } else {
            table.standings.add(tribe_id, standing);
        };

        i = i + 1;
    };
}
