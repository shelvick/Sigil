module sigil::intel_reputation;

use sui::vec_map::{Self, VecMap};
use sigil::intel_market::{Self, IntelListing};

const STATUS_SOLD: u8 = 1;

const ENotBuyer: u64 = 0;
const ENotSold: u64 = 1;
const EAlreadyReviewed: u64 = 2;
const ESelfReview: u64 = 3;

public struct ReputationRegistry has key {
    id: UID,
    scores: VecMap<address, ReputationScore>,
}

public struct ReputationScore has store, copy, drop {
    positive: u64,
    negative: u64,
    reviewed_listings: vector<ID>,
}

fun init(ctx: &mut TxContext) {
    share_registry(ctx);
}

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    share_registry(ctx);
}

public fun confirm_quality(registry: &mut ReputationRegistry, listing: &IntelListing, ctx: &TxContext) {
    leave_feedback(registry, listing, ctx, true);
}

public fun report_bad_quality(registry: &mut ReputationRegistry, listing: &IntelListing, ctx: &TxContext) {
    leave_feedback(registry, listing, ctx, false);
}

public fun get_reputation(registry: &ReputationRegistry, seller: address): (u64, u64) {
    if (vec_map::contains(&registry.scores, &seller)) {
        let score = vec_map::get(&registry.scores, &seller);
        (score.positive, score.negative)
    } else {
        (0, 0)
    }
}

public fun has_reviewed(registry: &ReputationRegistry, seller: address, listing_id: ID): bool {
    if (vec_map::contains(&registry.scores, &seller)) {
        let score = vec_map::get(&registry.scores, &seller);
        contains_listing(&score.reviewed_listings, listing_id)
    } else {
        false
    }
}

fun share_registry(ctx: &mut TxContext) {
    transfer::share_object(ReputationRegistry {
        id: object::new(ctx),
        scores: vec_map::empty<address, ReputationScore>(),
    });
}

fun leave_feedback(
    registry: &mut ReputationRegistry,
    listing: &IntelListing,
    ctx: &TxContext,
    is_positive: bool,
) {
    let reviewer = ctx.sender();
    let seller = intel_market::seller(listing);
    assert!(reviewer != seller, ESelfReview);
    assert!(intel_market::status(listing) == STATUS_SOLD, ENotSold);

    let buyer = intel_market::buyer(listing);
    assert!(option::is_some(&buyer), ENotBuyer);
    assert!(*option::borrow(&buyer) == reviewer, ENotBuyer);

    let listing_id = object::id(listing);
    let score = upsert_score(registry, seller);
    assert!(!contains_listing(&score.reviewed_listings, listing_id), EAlreadyReviewed);

    if (is_positive) {
        score.positive = score.positive + 1;
    } else {
        score.negative = score.negative + 1;
    };

    vector::push_back(&mut score.reviewed_listings, listing_id);
}

fun upsert_score(registry: &mut ReputationRegistry, seller: address): &mut ReputationScore {
    if (!vec_map::contains(&registry.scores, &seller)) {
        vec_map::insert(&mut registry.scores, seller, ReputationScore {
            positive: 0,
            negative: 0,
            reviewed_listings: vector[],
        });
    };

    vec_map::get_mut(&mut registry.scores, &seller)
}

fun contains_listing(reviewed_listings: &vector<ID>, listing_id: ID): bool {
    let mut i = 0;

    while (i < reviewed_listings.length()) {
        if (*vector::borrow(reviewed_listings, i) == listing_id) {
            return true
        };

        i = i + 1;
    };

    false
}
