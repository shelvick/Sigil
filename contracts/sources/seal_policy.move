module sigil::seal_policy;

use sigil::intel_market::{Self, IntelListing};

const ENoAccess: u64 = 0;
const ESealIdMismatch: u64 = 1;

const STATUS_SOLD: u8 = 1;

entry fun seal_approve(id: vector<u8>, listing: &IntelListing, ctx: &TxContext) {
    approve(id, listing, ctx);
}

#[test_only]
public fun seal_approve_for_testing(id: vector<u8>, listing: &IntelListing, ctx: &TxContext) {
    approve(id, listing, ctx);
}

fun approve(id: vector<u8>, listing: &IntelListing, ctx: &TxContext) {
    assert!(id == intel_market::seal_id(listing), ESealIdMismatch);

    let sender = ctx.sender();
    if (sender == intel_market::seller(listing)) {
        return
    };

    let buyer = intel_market::buyer(listing);
    if (intel_market::status(listing) == STATUS_SOLD && option::is_some(&buyer)) {
        if (*option::borrow(&buyer) == sender) {
            return
        };
    };

    abort ENoAccess
}
