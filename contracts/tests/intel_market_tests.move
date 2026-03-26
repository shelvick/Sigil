#[test_only]
module sigil::intel_market_tests;

use std::string::utf8;
use sui::{coin, test_scenario as ts};
use sui::sui::SUI;
use sigil::{intel_market, tribe_custodian};
use world::{
    access::AdminACL,
    character::{Self, Character},
    object_registry::ObjectRegistry,
    test_helpers::{Self, admin, tenant, user_a, user_b}
};

const OUTSIDER: address = @0xE;

const SELLER_TRIBE: u32 = 42;
const WRONG_TRIBE: u32 = 88;

const SELLER_ITEM_ID: u32 = 7001;
const BUYER_ITEM_ID: u32 = 7002;
const WRONG_TRIBE_ITEM_ID: u32 = 7003;

const LISTING_PRICE: u64 = 25_000_000;
const WRONG_PRICE: u64 = 24_999_999;
const CLIENT_NONCE: u64 = 77;
const SECOND_CLIENT_NONCE: u64 = 78;
const REPORT_LOCATION: u8 = 1;
const REPORT_SCOUTING: u8 = 2;
const SOLAR_SYSTEM_ID: u32 = 30_000_142;

const STATUS_ACTIVE: u8 = 0;
const STATUS_SOLD: u8 = 1;
const STATUS_CANCELLED: u8 = 2;

fun setup(ts: &mut ts::Scenario) {
    test_helpers::setup_world(ts);

    ts::next_tx(ts, admin());
    tribe_custodian::init_for_testing(ts.ctx());

    ts::next_tx(ts, admin());
    intel_market::init_for_testing(ts.ctx());

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

fun create_custodian(ts: &mut ts::Scenario, caller: address, character_id: ID): ID {
    ts::next_tx(ts, caller);
    {
        let mut registry = ts::take_shared<tribe_custodian::TribeCustodianRegistry>(ts);
        let character = ts::take_shared_by_id<Character>(ts, character_id);
        tribe_custodian::create_custodian(&mut registry, &character, ts.ctx());
        ts::return_shared(character);
        ts::return_shared(registry);
    };

    ts::next_tx(ts, caller);
    {
        let custodian = ts::take_shared<tribe_custodian::Custodian>(ts);
        let custodian_id = object::id(&custodian);
        ts::return_shared(custodian);
        custodian_id
    }
}

fun join_custodian(ts: &mut ts::Scenario, caller: address, custodian_id: ID, character_id: ID) {
    ts::next_tx(ts, caller);
    {
        let mut custodian = ts::take_shared_by_id<tribe_custodian::Custodian>(ts, custodian_id);
        let character = ts::take_shared_by_id<Character>(ts, character_id);
        tribe_custodian::join(&mut custodian, &character, ts.ctx());
        ts::return_shared(character);
        ts::return_shared(custodian);
    };
}

fun seal_id(): vector<u8> {
    x"00112233445566778899aabbccddeeff102132435465768798a9bacbdcedfe0f"
}

fun second_seal_id(): vector<u8> {
    x"f0e1d2c3b4a5968778695a4b3c2d1e0ffeedccbbaa998877665544332211000f"
}

fun encrypted_blob_id(): vector<u8> {
    b"walrus://sealed/listing-1"
}

fun second_encrypted_blob_id(): vector<u8> {
    b"walrus://sealed/listing-2"
}

fun listing_description(): vector<u8> {
    b"Jita gate fuel window"
}

fun scout_description(): vector<u8> {
    b"Scout ping from black rise"
}

fun create_listing_with_seal_delivery(
    ts: &mut ts::Scenario,
    caller: address,
    seal_id_bytes: vector<u8>,
    encrypted_blob_bytes: vector<u8>,
    client_nonce: u64,
    report_type: u8,
    description: vector<u8>,
): ID {
    ts::next_tx(ts, caller);
    {
        intel_market::create_listing(
            seal_id_bytes,
            encrypted_blob_bytes,
            client_nonce,
            LISTING_PRICE,
            report_type,
            SOLAR_SYSTEM_ID,
            description,
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

fun create_restricted_listing_with_seal_delivery(
    ts: &mut ts::Scenario,
    caller: address,
    custodian_id: ID,
    seal_id_bytes: vector<u8>,
    encrypted_blob_bytes: vector<u8>,
    client_nonce: u64,
    description: vector<u8>,
): ID {
    ts::next_tx(ts, caller);
    {
        let custodian = ts::take_shared_by_id<tribe_custodian::Custodian>(ts, custodian_id);
        intel_market::create_restricted_listing(
            &custodian,
            seal_id_bytes,
            encrypted_blob_bytes,
            client_nonce,
            LISTING_PRICE,
            REPORT_LOCATION,
            SOLAR_SYSTEM_ID,
            description,
            ts.ctx(),
        );
        ts::return_shared(custodian);
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

fun purchase_listing(ts: &mut ts::Scenario, buyer: address, listing_id: ID, amount: u64) {
    ts::next_tx(ts, buyer);
    {
        let mut listing = ts::take_shared_by_id<intel_market::IntelListing>(ts, listing_id);
        let payment = mint_payment(ts, amount);
        intel_market::purchase(&mut listing, payment, ts.ctx());
        ts::return_shared(listing);
    };
}

fun purchase_restricted_listing(
    ts: &mut ts::Scenario,
    buyer: address,
    listing_id: ID,
    custodian_id: ID,
    amount: u64,
) {
    ts::next_tx(ts, buyer);
    {
        let mut listing = ts::take_shared_by_id<intel_market::IntelListing>(ts, listing_id);
        let custodian = ts::take_shared_by_id<tribe_custodian::Custodian>(ts, custodian_id);
        let payment = mint_payment(ts, amount);
        intel_market::purchase_restricted(&mut listing, &custodian, payment, ts.ctx());
        ts::return_shared(custodian);
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
fun test_create_listing_stores_fields() {
    let mut scenario = ts::begin(admin());
    setup(&mut scenario);

    let listing_id = create_listing_with_seal_delivery(
        &mut scenario,
        user_a(),
        seal_id(),
        encrypted_blob_id(),
        CLIENT_NONCE,
        REPORT_LOCATION,
        listing_description(),
    );

    scenario.next_tx(user_a());
    {
        let listing = scenario.take_shared_by_id<intel_market::IntelListing>(listing_id);
        assert!(intel_market::seller(&listing) == user_a());
        assert!(intel_market::client_nonce(&listing) == CLIENT_NONCE);
        assert!(intel_market::price(&listing) == LISTING_PRICE);
        assert!(intel_market::report_type(&listing) == REPORT_LOCATION);
        assert!(intel_market::solar_system_id(&listing) == SOLAR_SYSTEM_ID);
        assert!(intel_market::description(&listing) == listing_description());
        assert!(intel_market::status(&listing) == STATUS_ACTIVE);
        assert!(option::is_none(&intel_market::buyer(&listing)));
        assert!(option::is_none(&intel_market::restricted_to_tribe_id(&listing)));
        ts::return_shared(listing);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = intel_market::ENotTribeMember)]
fun test_create_restricted_listing_requires_membership() {
    let mut scenario = ts::begin(admin());
    setup(&mut scenario);

    let seller_character = create_character(&mut scenario, user_a(), SELLER_TRIBE, SELLER_ITEM_ID, b"seller");
    let _outsider_character = create_character(
        &mut scenario,
        OUTSIDER,
        WRONG_TRIBE,
        WRONG_TRIBE_ITEM_ID,
        b"outsider",
    );
    let custodian_id = create_custodian(&mut scenario, user_a(), seller_character);

    create_restricted_listing_with_seal_delivery(
        &mut scenario,
        OUTSIDER,
        custodian_id,
        seal_id(),
        encrypted_blob_id(),
        CLIENT_NONCE,
        listing_description(),
    );

    scenario.end();
}

#[test]
fun test_purchase_transfers_sui_to_seller() {
    let mut scenario = ts::begin(admin());
    setup(&mut scenario);

    let listing_id = create_listing_with_seal_delivery(
        &mut scenario,
        user_a(),
        seal_id(),
        encrypted_blob_id(),
        CLIENT_NONCE,
        REPORT_LOCATION,
        listing_description(),
    );
    purchase_listing(&mut scenario, user_b(), listing_id, LISTING_PRICE);

    scenario.next_tx(user_b());
    {
        let listing = scenario.take_shared_by_id<intel_market::IntelListing>(listing_id);
        assert!(intel_market::status(&listing) == STATUS_SOLD);
        assert!(option::destroy_some(intel_market::buyer(&listing)) == user_b());
        ts::return_shared(listing);
    };

    scenario.next_tx(user_a());
    {
        let payment = scenario.take_from_sender<coin::Coin<SUI>>();
        assert!(coin::value(&payment) == LISTING_PRICE);
        scenario.return_to_sender(payment);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = intel_market::EWrongPayment)]
fun test_purchase_wrong_amount_aborts() {
    let mut scenario = ts::begin(admin());
    setup(&mut scenario);

    let listing_id = create_listing_with_seal_delivery(
        &mut scenario,
        user_a(),
        seal_id(),
        encrypted_blob_id(),
        CLIENT_NONCE,
        REPORT_LOCATION,
        listing_description(),
    );
    purchase_listing(&mut scenario, user_b(), listing_id, WRONG_PRICE);

    scenario.end();
}

#[test, expected_failure(abort_code = intel_market::EListingNotActive)]
fun test_purchase_sold_listing_aborts() {
    let mut scenario = ts::begin(admin());
    setup(&mut scenario);

    let listing_id = create_listing_with_seal_delivery(
        &mut scenario,
        user_a(),
        seal_id(),
        encrypted_blob_id(),
        CLIENT_NONCE,
        REPORT_LOCATION,
        listing_description(),
    );
    purchase_listing(&mut scenario, user_b(), listing_id, LISTING_PRICE);
    purchase_listing(&mut scenario, OUTSIDER, listing_id, LISTING_PRICE);

    scenario.end();
}

#[test]
fun test_cancel_listing_by_seller() {
    let mut scenario = ts::begin(admin());
    setup(&mut scenario);

    let listing_id = create_listing_with_seal_delivery(
        &mut scenario,
        user_a(),
        seal_id(),
        encrypted_blob_id(),
        CLIENT_NONCE,
        REPORT_LOCATION,
        listing_description(),
    );
    cancel_listing(&mut scenario, user_a(), listing_id);

    scenario.next_tx(user_a());
    {
        let listing = scenario.take_shared_by_id<intel_market::IntelListing>(listing_id);
        assert!(intel_market::status(&listing) == STATUS_CANCELLED);
        ts::return_shared(listing);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = intel_market::ENotSeller)]
fun test_cancel_listing_non_seller_aborts() {
    let mut scenario = ts::begin(admin());
    setup(&mut scenario);

    let listing_id = create_listing_with_seal_delivery(
        &mut scenario,
        user_a(),
        seal_id(),
        encrypted_blob_id(),
        CLIENT_NONCE,
        REPORT_LOCATION,
        listing_description(),
    );
    cancel_listing(&mut scenario, user_b(), listing_id);

    scenario.end();
}

#[test, expected_failure(abort_code = intel_market::ENotTribeMember)]
fun test_purchase_restricted_checks_buyer_membership() {
    let mut scenario = ts::begin(admin());
    setup(&mut scenario);

    let seller_character = create_character(&mut scenario, user_a(), SELLER_TRIBE, SELLER_ITEM_ID, b"seller");
    let custodian_id = create_custodian(&mut scenario, user_a(), seller_character);
    let listing_id = create_restricted_listing_with_seal_delivery(
        &mut scenario,
        user_a(),
        custodian_id,
        seal_id(),
        encrypted_blob_id(),
        CLIENT_NONCE,
        listing_description(),
    );

    purchase_restricted_listing(&mut scenario, user_b(), listing_id, custodian_id, LISTING_PRICE);

    scenario.end();
}

#[test, expected_failure(abort_code = intel_market::EListingNotRestricted)]
fun test_purchase_restricted_rejects_global_listing() {
    let mut scenario = ts::begin(admin());
    setup(&mut scenario);

    let seller_character = create_character(&mut scenario, user_a(), SELLER_TRIBE, SELLER_ITEM_ID, b"seller");
    let buyer_character = create_character(&mut scenario, user_b(), SELLER_TRIBE, BUYER_ITEM_ID, b"buyer");
    let custodian_id = create_custodian(&mut scenario, user_a(), seller_character);
    join_custodian(&mut scenario, user_b(), custodian_id, buyer_character);

    let listing_id = create_listing_with_seal_delivery(
        &mut scenario,
        user_a(),
        seal_id(),
        encrypted_blob_id(),
        CLIENT_NONCE,
        REPORT_LOCATION,
        listing_description(),
    );
    purchase_restricted_listing(&mut scenario, user_b(), listing_id, custodian_id, LISTING_PRICE);

    scenario.end();
}

#[test, expected_failure(abort_code = intel_market::EWrongTribe)]
fun test_purchase_restricted_rejects_wrong_custodian() {
    let mut scenario = ts::begin(admin());
    setup(&mut scenario);

    let seller_character = create_character(&mut scenario, user_a(), SELLER_TRIBE, SELLER_ITEM_ID, b"seller");
    let buyer_character = create_character(&mut scenario, user_b(), SELLER_TRIBE, BUYER_ITEM_ID, b"buyer");
    let wrong_character = create_character(&mut scenario, OUTSIDER, WRONG_TRIBE, WRONG_TRIBE_ITEM_ID, b"wrong");

    let custodian_id = create_custodian(&mut scenario, user_a(), seller_character);
    let wrong_custodian_id = create_custodian(&mut scenario, OUTSIDER, wrong_character);
    join_custodian(&mut scenario, user_b(), custodian_id, buyer_character);

    let listing_id = create_restricted_listing_with_seal_delivery(
        &mut scenario,
        user_a(),
        custodian_id,
        seal_id(),
        encrypted_blob_id(),
        CLIENT_NONCE,
        listing_description(),
    );
    purchase_restricted_listing(&mut scenario, user_b(), listing_id, wrong_custodian_id, LISTING_PRICE);

    scenario.end();
}

#[test, expected_failure(abort_code = intel_market::ESelfPurchase)]
fun test_purchase_rejects_self_purchase() {
    let mut scenario = ts::begin(admin());
    setup(&mut scenario);

    let listing_id = create_listing_with_seal_delivery(
        &mut scenario,
        user_a(),
        seal_id(),
        encrypted_blob_id(),
        CLIENT_NONCE,
        REPORT_LOCATION,
        listing_description(),
    );
    purchase_listing(&mut scenario, user_a(), listing_id, LISTING_PRICE);

    scenario.end();
}

#[test, expected_failure(abort_code = intel_market::ESelfPurchase)]
fun test_purchase_restricted_rejects_self_purchase() {
    let mut scenario = ts::begin(admin());
    setup(&mut scenario);

    let seller_character = create_character(&mut scenario, user_a(), SELLER_TRIBE, SELLER_ITEM_ID, b"seller");
    let custodian_id = create_custodian(&mut scenario, user_a(), seller_character);
    let listing_id = create_restricted_listing_with_seal_delivery(
        &mut scenario,
        user_a(),
        custodian_id,
        seal_id(),
        encrypted_blob_id(),
        CLIENT_NONCE,
        listing_description(),
    );

    purchase_restricted_listing(&mut scenario, user_a(), listing_id, custodian_id, LISTING_PRICE);

    scenario.end();
}

#[test]
fun test_seal_id_accessor() {
    let mut scenario = ts::begin(admin());
    setup(&mut scenario);

    let first_listing_id = create_listing_with_seal_delivery(
        &mut scenario,
        user_a(),
        seal_id(),
        encrypted_blob_id(),
        CLIENT_NONCE,
        REPORT_LOCATION,
        listing_description(),
    );
    let second_listing_id = create_listing_with_seal_delivery(
        &mut scenario,
        user_a(),
        second_seal_id(),
        encrypted_blob_id(),
        SECOND_CLIENT_NONCE,
        REPORT_LOCATION,
        listing_description(),
    );

    scenario.next_tx(user_a());
    {
        let first_listing = scenario.take_shared_by_id<intel_market::IntelListing>(first_listing_id);
        let second_listing = scenario.take_shared_by_id<intel_market::IntelListing>(second_listing_id);
        assert!(object::id(&first_listing) != object::id(&second_listing));
        assert!(intel_market::client_nonce(&first_listing) == CLIENT_NONCE);
        assert!(intel_market::client_nonce(&second_listing) == SECOND_CLIENT_NONCE);
        assert!(intel_market::seal_id(&first_listing) == seal_id());
        assert!(intel_market::seal_id(&second_listing) == second_seal_id());
        ts::return_shared(second_listing);
        ts::return_shared(first_listing);
    };
    scenario.end();
}

#[test]
fun test_encrypted_blob_id_accessor() {
    let mut scenario = ts::begin(admin());
    setup(&mut scenario);

    let first_listing_id = create_listing_with_seal_delivery(
        &mut scenario,
        user_a(),
        seal_id(),
        encrypted_blob_id(),
        CLIENT_NONCE,
        REPORT_LOCATION,
        listing_description(),
    );
    let second_listing_id = create_listing_with_seal_delivery(
        &mut scenario,
        user_a(),
        seal_id(),
        second_encrypted_blob_id(),
        SECOND_CLIENT_NONCE,
        REPORT_SCOUTING,
        scout_description(),
    );

    scenario.next_tx(user_a());
    {
        let first_listing = scenario.take_shared_by_id<intel_market::IntelListing>(first_listing_id);
        let second_listing = scenario.take_shared_by_id<intel_market::IntelListing>(second_listing_id);
        assert!(object::id(&first_listing) != object::id(&second_listing));
        assert!(intel_market::report_type(&first_listing) == REPORT_LOCATION);
        assert!(intel_market::report_type(&second_listing) == REPORT_SCOUTING);
        assert!(intel_market::encrypted_blob_id(&first_listing) == encrypted_blob_id());
        assert!(intel_market::encrypted_blob_id(&second_listing) == second_encrypted_blob_id());
        ts::return_shared(second_listing);
        ts::return_shared(first_listing);
    };
    scenario.end();
}

#[test]
fun test_create_listing_stores_client_nonce() {
    let mut scenario = ts::begin(admin());
    setup(&mut scenario);

    let first_listing_id = create_listing_with_seal_delivery(
        &mut scenario,
        user_a(),
        seal_id(),
        encrypted_blob_id(),
        CLIENT_NONCE,
        REPORT_LOCATION,
        listing_description(),
    );
    let second_listing_id = create_listing_with_seal_delivery(
        &mut scenario,
        user_a(),
        second_seal_id(),
        second_encrypted_blob_id(),
        SECOND_CLIENT_NONCE,
        REPORT_SCOUTING,
        scout_description(),
    );

    scenario.next_tx(user_a());
    {
        let first_listing = scenario.take_shared_by_id<intel_market::IntelListing>(first_listing_id);
        assert!(intel_market::client_nonce(&first_listing) == CLIENT_NONCE);
        assert!(intel_market::description(&first_listing) == listing_description());
        ts::return_shared(first_listing);
    };

    scenario.next_tx(user_a());
    {
        let second_listing = scenario.take_shared_by_id<intel_market::IntelListing>(second_listing_id);
        assert!(intel_market::client_nonce(&second_listing) == SECOND_CLIENT_NONCE);
        assert!(intel_market::description(&second_listing) == scout_description());
        ts::return_shared(second_listing);
    };

    scenario.end();
}
