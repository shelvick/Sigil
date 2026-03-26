#[test_only]
module sigil::seal_policy_tests;

use sui::{coin, test_scenario as ts};
use sui::sui::SUI;
use sigil::{intel_market, seal_policy};
use world::test_helpers::{Self, admin, user_a, user_b};

const OUTSIDER: address = @0xE;

const LISTING_PRICE: u64 = 25_000_000;
const CLIENT_NONCE: u64 = 77;
const SOLAR_SYSTEM_ID: u32 = 30_000_142;

const STATUS_ACTIVE: u8 = 0;
const STATUS_SOLD: u8 = 1;
const STATUS_CANCELLED: u8 = 2;

fun setup(ts: &mut ts::Scenario) {
    test_helpers::setup_world(ts);

    ts::next_tx(ts, admin());
    intel_market::init_for_testing(ts.ctx());

    ts::next_tx(ts, admin());
}

fun seal_id(): vector<u8> {
    x"00112233445566778899aabbccddeeff102132435465768798a9bacbdcedfe0f"
}

fun mismatched_seal_id(): vector<u8> {
    x"f0e1d2c3b4a5968778695a4b3c2d1e0ffeedccbbaa998877665544332211000f"
}

fun encrypted_blob_id(): vector<u8> {
    b"walrus://sealed/listing-1"
}

fun listing_description(): vector<u8> {
    b"Jita gate fuel window"
}

fun create_listing_with_seal_delivery(ts: &mut ts::Scenario, caller: address): ID {
    ts::next_tx(ts, caller);
    {
        intel_market::create_listing(
            seal_id(),
            encrypted_blob_id(),
            CLIENT_NONCE,
            LISTING_PRICE,
            1,
            SOLAR_SYSTEM_ID,
            listing_description(),
            ts.ctx(),
        );
    };

    ts::next_tx(ts, caller);
    {
        let listing = ts::take_shared<intel_market::IntelListing>(ts);
        let listing_id = object::id(&listing);
        ts::return_shared(listing);
        listing_id
    }
}

fun mint_payment(ts: &mut ts::Scenario, amount: u64): coin::Coin<SUI> {
    let mut treasury = coin::create_treasury_cap_for_testing<SUI>(ts.ctx());
    let payment = coin::mint(&mut treasury, amount, ts.ctx());
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

fun cancel_listing(ts: &mut ts::Scenario, caller: address, listing_id: ID) {
    ts::next_tx(ts, caller);
    {
        let mut listing = ts::take_shared_by_id<intel_market::IntelListing>(ts, listing_id);
        intel_market::cancel_listing(&mut listing, ts.ctx());
        ts::return_shared(listing);
    };
}

#[test]
fun test_seal_approve_buyer_of_sold_listing() {
    let mut scenario = ts::begin(admin());
    setup(&mut scenario);

    let listing_id = create_listing_with_seal_delivery(&mut scenario, user_a());
    purchase_listing(&mut scenario, user_b(), listing_id);

    scenario.next_tx(user_b());
    {
        let listing = scenario.take_shared_by_id<intel_market::IntelListing>(listing_id);
        assert!(intel_market::status(&listing) == STATUS_SOLD);
        assert!(option::destroy_some(intel_market::buyer(&listing)) == user_b());
        assert!(intel_market::seller(&listing) == user_a());
        seal_policy::seal_approve_for_testing(seal_id(), &listing, scenario.ctx());
        ts::return_shared(listing);
    };
    scenario.end();
}

#[test]
fun test_seal_approve_seller_always_allowed() {
    let mut scenario = ts::begin(admin());
    setup(&mut scenario);

    let sold_listing_id = create_listing_with_seal_delivery(&mut scenario, user_a());
    purchase_listing(&mut scenario, user_b(), sold_listing_id);
    let cancelled_listing_id = create_listing_with_seal_delivery(&mut scenario, user_a());
    cancel_listing(&mut scenario, user_a(), cancelled_listing_id);

    scenario.next_tx(user_a());
    {
        let sold_listing = scenario.take_shared_by_id<intel_market::IntelListing>(sold_listing_id);
        assert!(intel_market::seller(&sold_listing) == user_a());
        assert!(intel_market::status(&sold_listing) == STATUS_SOLD);
        assert!(option::destroy_some(intel_market::buyer(&sold_listing)) == user_b());
        seal_policy::seal_approve_for_testing(seal_id(), &sold_listing, scenario.ctx());
        ts::return_shared(sold_listing);
    };

    scenario.next_tx(user_a());
    {
        let cancelled_listing = scenario.take_shared_by_id<intel_market::IntelListing>(cancelled_listing_id);
        assert!(intel_market::seller(&cancelled_listing) == user_a());
        assert!(intel_market::status(&cancelled_listing) == STATUS_CANCELLED);
        assert!(option::is_none(&intel_market::buyer(&cancelled_listing)));
        seal_policy::seal_approve_for_testing(seal_id(), &cancelled_listing, scenario.ctx());
        ts::return_shared(cancelled_listing);
    };
    scenario.end();
}

#[test, expected_failure(abort_code = seal_policy::ENoAccess)]
fun test_seal_approve_rejects_unauthorized() {
    let mut scenario = ts::begin(admin());
    setup(&mut scenario);

    let listing_id = create_listing_with_seal_delivery(&mut scenario, user_a());
    purchase_listing(&mut scenario, user_b(), listing_id);

    scenario.next_tx(OUTSIDER);
    {
        let listing = scenario.take_shared_by_id<intel_market::IntelListing>(listing_id);
        assert!(intel_market::status(&listing) == STATUS_SOLD);
        assert!(intel_market::seller(&listing) == user_a());
        assert!(option::destroy_some(intel_market::buyer(&listing)) == user_b());
        assert!(OUTSIDER != user_a());
        assert!(OUTSIDER != user_b());
        seal_policy::seal_approve_for_testing(seal_id(), &listing, scenario.ctx());
        ts::return_shared(listing);
    };
    scenario.end();
}

#[test, expected_failure(abort_code = seal_policy::ESealIdMismatch)]
fun test_seal_approve_rejects_mismatched_seal_id() {
    let mut scenario = ts::begin(admin());
    setup(&mut scenario);

    let listing_id = create_listing_with_seal_delivery(&mut scenario, user_a());
    purchase_listing(&mut scenario, user_b(), listing_id);

    scenario.next_tx(user_b());
    {
        let listing = scenario.take_shared_by_id<intel_market::IntelListing>(listing_id);
        assert!(intel_market::status(&listing) == STATUS_SOLD);
        assert!(mismatched_seal_id() != seal_id());
        assert!(option::destroy_some(intel_market::buyer(&listing)) == user_b());
        seal_policy::seal_approve_for_testing(mismatched_seal_id(), &listing, scenario.ctx());
        ts::return_shared(listing);
    };
    scenario.end();
}

#[test, expected_failure(abort_code = seal_policy::ENoAccess)]
fun test_seal_approve_rejects_non_seller_on_active_listing() {
    let mut scenario = ts::begin(admin());
    setup(&mut scenario);

    let listing_id = create_listing_with_seal_delivery(&mut scenario, user_a());

    scenario.next_tx(user_b());
    {
        let listing = scenario.take_shared_by_id<intel_market::IntelListing>(listing_id);
        assert!(intel_market::status(&listing) == STATUS_ACTIVE);
        assert!(option::is_none(&intel_market::buyer(&listing)));
        assert!(intel_market::seller(&listing) == user_a());
        seal_policy::seal_approve_for_testing(seal_id(), &listing, scenario.ctx());
        ts::return_shared(listing);
    };
    scenario.end();
}

#[test]
fun test_seal_approve_seller_of_cancelled_listing() {
    let mut scenario = ts::begin(admin());
    setup(&mut scenario);

    let listing_id = create_listing_with_seal_delivery(&mut scenario, user_a());
    cancel_listing(&mut scenario, user_a(), listing_id);

    scenario.next_tx(user_a());
    {
        let listing = scenario.take_shared_by_id<intel_market::IntelListing>(listing_id);
        assert!(intel_market::seller(&listing) == user_a());
        assert!(intel_market::status(&listing) == STATUS_CANCELLED);
        assert!(option::is_none(&intel_market::buyer(&listing)));
        seal_policy::seal_approve_for_testing(seal_id(), &listing, scenario.ctx());
        ts::return_shared(listing);
    };
    scenario.end();
}
