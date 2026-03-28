#[test_only]
module sigil::intel_reputation_tests;

use sui::test_scenario as ts;
use sigil::{intel_market, intel_reputation};
use world::test_helpers::{admin, user_a, user_b};

const USER_C: address = @0xC;
const OUTSIDER: address = @0xF;

const LISTING_PRICE: u64 = 25_000_000;
const CLIENT_NONCE: u64 = 77;
const SECOND_CLIENT_NONCE: u64 = 78;
const THIRD_CLIENT_NONCE: u64 = 79;
const REPORT_LOCATION: u8 = 1;
const SOLAR_SYSTEM_ID: u32 = 30_000_142;

fun setup(ts: &mut ts::Scenario) {
    ts::next_tx(ts, admin());
    intel_market::init_for_testing(ts.ctx());

    ts::next_tx(ts, admin());
    intel_reputation::init_for_testing(ts.ctx());
}

fun seal_id(byte: u8): vector<u8> {
    vector[byte, byte, byte, byte]
}

fun encrypted_blob_id(byte: u8): vector<u8> {
    vector[byte + 10, byte + 11, byte + 12]
}

fun listing_description(byte: u8): vector<u8> {
    vector[byte + 20, byte + 21, byte + 22]
}

fun create_listing(ts: &mut ts::Scenario, seller: address, nonce: u64, seed: u8): ID {
    ts::next_tx(ts, seller);
    {
        intel_market::create_listing(
            seal_id(seed),
            encrypted_blob_id(seed),
            nonce,
            LISTING_PRICE,
            REPORT_LOCATION,
            SOLAR_SYSTEM_ID,
            listing_description(seed),
            ts.ctx(),
        );
    };

    ts::next_tx(ts, seller);
    {
        let listing = ts::take_shared<intel_market::IntelListing>(ts);
        let listing_id = object::id(&listing);
        ts::return_shared(listing);
        listing_id
    }
}

fun mint_payment(ts: &mut ts::Scenario, amount: u64): sui::coin::Coin<sui::sui::SUI> {
    let mut treasury = sui::coin::create_treasury_cap_for_testing<sui::sui::SUI>(ts.ctx());
    let payment = sui::coin::mint(&mut treasury, amount, ts.ctx());
    transfer::public_transfer(treasury, ts.ctx().sender());
    payment
}

fun purchase_listing(ts: &mut ts::Scenario, buyer: address, listing_id: ID) {
    ts::next_tx(ts, buyer);
    {
        let mut listing = ts::take_shared_by_id<intel_market::IntelListing>(ts, listing_id);
        let payment = mint_payment(ts, LISTING_PRICE);
        intel_market::purchase(&mut listing, payment, ts.ctx());
        ts::return_shared(listing);
    };
}

fun confirm_quality(ts: &mut ts::Scenario, reviewer: address, listing_id: ID) {
    ts::next_tx(ts, reviewer);
    {
        let mut registry = ts::take_shared<intel_reputation::ReputationRegistry>(ts);
        let listing = ts::take_shared_by_id<intel_market::IntelListing>(ts, listing_id);
        intel_reputation::confirm_quality(&mut registry, &listing, ts.ctx());
        ts::return_shared(listing);
        ts::return_shared(registry);
    };
}

fun report_bad_quality(ts: &mut ts::Scenario, reviewer: address, listing_id: ID) {
    ts::next_tx(ts, reviewer);
    {
        let mut registry = ts::take_shared<intel_reputation::ReputationRegistry>(ts);
        let listing = ts::take_shared_by_id<intel_market::IntelListing>(ts, listing_id);
        intel_reputation::report_bad_quality(&mut registry, &listing, ts.ctx());
        ts::return_shared(listing);
        ts::return_shared(registry);
    };
}

#[test]
fun test_buyer_feedback_updates_seller_score() {
    let mut scenario = ts::begin(admin());
    setup(&mut scenario);

    let listing_id = create_listing(&mut scenario, user_a(), CLIENT_NONCE, 1);
    purchase_listing(&mut scenario, user_b(), listing_id);
    confirm_quality(&mut scenario, user_b(), listing_id);

    scenario.next_tx(user_b());
    {
        let registry = scenario.take_shared<intel_reputation::ReputationRegistry>();
        let (positive, negative) = intel_reputation::get_reputation(&registry, user_a());
        assert!(positive == 1);
        assert!(negative == 0);
        ts::return_shared(registry);
    };

    scenario.end();
}

#[test]
fun test_buyer_can_confirm_quality_and_positive_count_increments() {
    let mut scenario = ts::begin(admin());
    setup(&mut scenario);

    let listing_id = create_listing(&mut scenario, user_a(), CLIENT_NONCE, 1);
    purchase_listing(&mut scenario, user_b(), listing_id);
    confirm_quality(&mut scenario, user_b(), listing_id);

    scenario.next_tx(user_b());
    {
        let registry = scenario.take_shared<intel_reputation::ReputationRegistry>();
        let (positive, negative) = intel_reputation::get_reputation(&registry, user_a());
        assert!(positive == 1);
        assert!(negative == 0);
        ts::return_shared(registry);
    };

    scenario.end();
}

#[test]
fun test_buyer_can_report_bad_quality_and_negative_count_increments() {
    let mut scenario = ts::begin(admin());
    setup(&mut scenario);

    let listing_id = create_listing(&mut scenario, user_a(), CLIENT_NONCE, 1);
    purchase_listing(&mut scenario, user_b(), listing_id);
    report_bad_quality(&mut scenario, user_b(), listing_id);

    scenario.next_tx(user_b());
    {
        let registry = scenario.take_shared<intel_reputation::ReputationRegistry>();
        let (positive, negative) = intel_reputation::get_reputation(&registry, user_a());
        assert!(positive == 0);
        assert!(negative == 1);
        ts::return_shared(registry);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = intel_reputation::ENotBuyer)]
fun test_non_buyer_cannot_leave_feedback() {
    let mut scenario = ts::begin(admin());
    setup(&mut scenario);

    let listing_id = create_listing(&mut scenario, user_a(), CLIENT_NONCE, 1);
    purchase_listing(&mut scenario, user_b(), listing_id);
    confirm_quality(&mut scenario, OUTSIDER, listing_id);

    scenario.end();
}

#[test, expected_failure(abort_code = intel_reputation::EAlreadyReviewed)]
fun test_buyer_cannot_leave_a_second_review_on_the_same_listing() {
    let mut scenario = ts::begin(admin());
    setup(&mut scenario);

    let listing_id = create_listing(&mut scenario, user_a(), CLIENT_NONCE, 1);
    purchase_listing(&mut scenario, user_b(), listing_id);
    confirm_quality(&mut scenario, user_b(), listing_id);
    report_bad_quality(&mut scenario, user_b(), listing_id);

    scenario.end();
}

#[test, expected_failure(abort_code = intel_reputation::ESelfReview)]
fun test_seller_cannot_review_own_listing() {
    let mut scenario = ts::begin(admin());
    setup(&mut scenario);

    let listing_id = create_listing(&mut scenario, user_a(), CLIENT_NONCE, 9);
    confirm_quality(&mut scenario, user_a(), listing_id);

    scenario.end();
}

#[test, expected_failure(abort_code = intel_reputation::ENotSold)]
fun test_feedback_rejected_on_active_listing() {
    let mut scenario = ts::begin(admin());
    setup(&mut scenario);

    let listing_id = create_listing(&mut scenario, user_a(), CLIENT_NONCE, 1);
    confirm_quality(&mut scenario, user_b(), listing_id);

    scenario.end();
}

#[test]
fun test_get_reputation_returns_zero_for_unknown_seller() {
    let mut scenario = ts::begin(admin());
    setup(&mut scenario);

    scenario.next_tx(user_b());
    {
        let registry = scenario.take_shared<intel_reputation::ReputationRegistry>();
        let (positive, negative) = intel_reputation::get_reputation(&registry, OUTSIDER);
        assert!(positive == 0);
        assert!(negative == 0);
        ts::return_shared(registry);
    };

    scenario.end();
}

#[test]
fun test_reputation_accumulates_across_multiple_listings() {
    let mut scenario = ts::begin(admin());
    setup(&mut scenario);

    let first_listing_id = create_listing(&mut scenario, user_a(), CLIENT_NONCE, 1);
    let second_listing_id = create_listing(&mut scenario, user_a(), SECOND_CLIENT_NONCE, 2);

    purchase_listing(&mut scenario, user_b(), first_listing_id);
    purchase_listing(&mut scenario, user_b(), second_listing_id);
    confirm_quality(&mut scenario, user_b(), first_listing_id);
    confirm_quality(&mut scenario, user_b(), second_listing_id);

    scenario.next_tx(user_b());
    {
        let registry = scenario.take_shared<intel_reputation::ReputationRegistry>();
        let (positive, negative) = intel_reputation::get_reputation(&registry, user_a());
        assert!(positive == 2);
        assert!(negative == 0);
        ts::return_shared(registry);
    };

    scenario.end();
}

#[test]
fun test_positive_and_negative_feedback_from_different_buyers_accumulate_independently() {
    let mut scenario = ts::begin(admin());
    setup(&mut scenario);

    let first_listing_id = create_listing(&mut scenario, user_a(), CLIENT_NONCE, 1);
    let second_listing_id = create_listing(&mut scenario, user_a(), SECOND_CLIENT_NONCE, 2);

    purchase_listing(&mut scenario, user_b(), first_listing_id);
    purchase_listing(&mut scenario, USER_C, second_listing_id);
    confirm_quality(&mut scenario, user_b(), first_listing_id);
    report_bad_quality(&mut scenario, USER_C, second_listing_id);

    scenario.next_tx(user_b());
    {
        let registry = scenario.take_shared<intel_reputation::ReputationRegistry>();
        let (positive, negative) = intel_reputation::get_reputation(&registry, user_a());
        assert!(positive == 1);
        assert!(negative == 1);
        ts::return_shared(registry);
    };

    scenario.end();
}

#[test]
fun test_has_reviewed_returns_correct_status() {
    let mut scenario = ts::begin(admin());
    setup(&mut scenario);

    let reviewed_listing_id = create_listing(&mut scenario, user_a(), CLIENT_NONCE, 1);
    let untouched_listing_id = create_listing(&mut scenario, user_a(), THIRD_CLIENT_NONCE, 3);

    purchase_listing(&mut scenario, user_b(), reviewed_listing_id);
    confirm_quality(&mut scenario, user_b(), reviewed_listing_id);

    scenario.next_tx(user_b());
    {
        let registry = scenario.take_shared<intel_reputation::ReputationRegistry>();
        assert!(intel_reputation::has_reviewed(&registry, user_a(), reviewed_listing_id));
        assert!(!intel_reputation::has_reviewed(&registry, user_a(), untouched_listing_id));
        ts::return_shared(registry);
    };

    scenario.end();
}
