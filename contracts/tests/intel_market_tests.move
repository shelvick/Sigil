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
const OTHER_TRIBE: u32 = 7;
const WRONG_TRIBE: u32 = 88;

const SELLER_ITEM_ID: u32 = 7001;
const BUYER_ITEM_ID: u32 = 7002;
const OUTSIDER_ITEM_ID: u32 = 7003;
const WRONG_TRIBE_ITEM_ID: u32 = 7004;

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

const EXPECTED_COMMITMENT: u256 = 15539519021302514881265614457483181390288297695578326223934756601408766449787;

fun setup(ts: &mut ts::Scenario) {
    test_helpers::setup_world(ts);

    ts::next_tx(ts, admin());
    tribe_custodian::init_for_testing(ts.ctx());

    ts::next_tx(ts, admin());
    intel_market::init_for_testing(ts.ctx());

    // Shared objects become visible to `take_shared`/`has_most_recent_shared` on the next tx boundary.
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

fun raw_verification_key_bytes(): vector<u8> {
    x"02c26f31610b8b42bdbe0bcf2c820618eaddc49129135184331e0391115fd018bf1dcb6e55eac0e84827a6f0f3af5d672b10955f7d7db3d9c91a417a906508161f2f2f1c813babc1dc1a59b5e8ad396dc9da65dae9ef271bd0b42572dbde7b86edf692d95cbdde46ddda5ef7d422436779445c5e66006a42761e1f12efde0018c212f3aeb785e49712e7a9353349aaf1255dfb31b7bf60723a480d9293938e197d78a281e6154bd460e2b2d47ef8c4efdd92bbb7033f91625587e9423001b1119971804fe0711c73a2e4b10a93a143fa2db69ebf8efa3be92bdf7993b9ba5d250200000000000000a4f60fe9ca96add34171fd2a68a577e8dc17bd760557db64aa94f1b443ca578d00cc70e88de2168f8b1152f28f1188adbc840a9c7ecbbc27fea43910f994340f"
}

fun test_vector_proof_points_bytes(): vector<u8> {
    x"8cb43e7e32b0a487e34d0c97209b65629e1807ec188618a32f890c6bc2c8592e0bb7162bb61f38742eb3206438d3c155b1559ea83726606a4803f65a89a26b05a9e9e8c46080ba3a56b8d37a21576e1d9db04f7ab8e7d6d5c658d764458654005e9c69855f88afdb2512e139820635f46c376bc6ca26d25ab7d56b52aa6f7480"
}

fun test_vector_public_inputs_bytes(): vector<u8> {
    x"7b984d3877c277ada72e9ce3ec7132c684f69e0eaf1cedf5a5104d535b0e5b22"
}

fun mismatched_public_inputs_bytes(): vector<u8> {
    x"00984d3877c277ada72e9ce3ec7132c684f69e0eaf1cedf5a5104d535b0e5b22"
}

fun invalid_proof_points_bytes(): vector<u8> {
    x"4a"
}

fun listing_description(): vector<u8> {
    b"Jita gate fuel window"
}

fun scout_description(): vector<u8> {
    b"Scout ping from black rise"
}

fun test_vector_data(): vector<u256> {
    vector[1, 30000142, 42, 123456789]
}

fun mismatched_data(): vector<u256> {
    vector[2, 30000142, 42, 123456789]
}

fun configure_marketplace(ts: &mut ts::Scenario, caller: address) {
    ts::next_tx(ts, caller);
    {
        let mut marketplace = ts::take_shared<intel_market::IntelMarketplace>(ts);
        let mut pvk_bytes = intel_market::prepared_vk_bytes_for_testing(raw_verification_key_bytes());
        let delta_g2_neg_pc_bytes = pvk_bytes.pop_back();
        let gamma_g2_neg_pc_bytes = pvk_bytes.pop_back();
        let alpha_g1_beta_g2_bytes = pvk_bytes.pop_back();
        let vk_gamma_abc_g1_bytes = pvk_bytes.pop_back();
        intel_market::setup_pvk(
            &mut marketplace,
            vk_gamma_abc_g1_bytes,
            alpha_g1_beta_g2_bytes,
            gamma_g2_neg_pc_bytes,
            delta_g2_neg_pc_bytes,
            ts.ctx(),
        );
        ts::return_shared(marketplace);
    };
}

fun create_listing(ts: &mut ts::Scenario, caller: address) {
    ts::next_tx(ts, caller);
    {
        let mut marketplace = ts::take_shared<intel_market::IntelMarketplace>(ts);
        intel_market::create_listing(
            &mut marketplace,
            test_vector_proof_points_bytes(),
            test_vector_public_inputs_bytes(),
            EXPECTED_COMMITMENT,
            CLIENT_NONCE,
            LISTING_PRICE,
            REPORT_LOCATION,
            SOLAR_SYSTEM_ID,
            listing_description(),
            ts.ctx(),
        );
        ts::return_shared(marketplace);
    };
}

fun create_second_listing(ts: &mut ts::Scenario, caller: address) {
    ts::next_tx(ts, caller);
    {
        let mut marketplace = ts::take_shared<intel_market::IntelMarketplace>(ts);
        intel_market::create_listing(
            &mut marketplace,
            test_vector_proof_points_bytes(),
            test_vector_public_inputs_bytes(),
            EXPECTED_COMMITMENT,
            SECOND_CLIENT_NONCE,
            LISTING_PRICE,
            REPORT_SCOUTING,
            SOLAR_SYSTEM_ID,
            scout_description(),
            ts.ctx(),
        );
        ts::return_shared(marketplace);
    };
}

fun create_restricted_listing(ts: &mut ts::Scenario, caller: address, custodian_id: ID) {
    ts::next_tx(ts, caller);
    {
        let mut marketplace = ts::take_shared<intel_market::IntelMarketplace>(ts);
        let custodian = ts::take_shared_by_id<tribe_custodian::Custodian>(ts, custodian_id);
        intel_market::create_restricted_listing(
            &mut marketplace,
            &custodian,
            test_vector_proof_points_bytes(),
            test_vector_public_inputs_bytes(),
            EXPECTED_COMMITMENT,
            CLIENT_NONCE,
            LISTING_PRICE,
            REPORT_LOCATION,
            SOLAR_SYSTEM_ID,
            listing_description(),
            ts.ctx(),
        );
        ts::return_shared(custodian);
        ts::return_shared(marketplace);
    };
}

fun mint_payment(ts: &mut ts::Scenario, amount: u64): coin::Coin<SUI> {
    let mut treasury = coin::create_treasury_cap_for_testing<SUI>(ts.ctx());
    let payment = coin::mint(&mut treasury, amount, ts.ctx());
    transfer::public_transfer(treasury, ts.ctx().sender());
    payment
}

fun purchase_listing(ts: &mut ts::Scenario, buyer: address, amount: u64) {
    ts::next_tx(ts, buyer);
    {
        let mut listing = ts::take_shared<intel_market::IntelListing>(ts);
        let payment = mint_payment(ts, amount);
        intel_market::purchase(&mut listing, payment, ts.ctx());
        ts::return_shared(listing);
    };
}

fun purchase_restricted_listing(ts: &mut ts::Scenario, buyer: address, custodian_id: ID, amount: u64) {
    ts::next_tx(ts, buyer);
    {
        let mut listing = ts::take_shared<intel_market::IntelListing>(ts);
        let custodian = ts::take_shared_by_id<tribe_custodian::Custodian>(ts, custodian_id);
        let payment = mint_payment(ts, amount);
        intel_market::purchase_restricted(&mut listing, &custodian, payment, ts.ctx());
        ts::return_shared(custodian);
        ts::return_shared(listing);
    };
}

#[test]
fun test_init_creates_marketplace() {
    let mut scenario = ts::begin(admin());
    setup(&mut scenario);

    assert!(ts::has_most_recent_shared<intel_market::IntelMarketplace>());

    scenario.next_tx(admin());
    {
        let marketplace = scenario.take_shared<intel_market::IntelMarketplace>();
        assert!(intel_market::listing_count(&marketplace) == 0);
        ts::return_shared(marketplace);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = intel_market::EInvalidProof)]
fun test_setup_pvk() {
    let mut scenario = ts::begin(admin());
    setup(&mut scenario);

    configure_marketplace(&mut scenario, admin());

    scenario.next_tx(user_a());
    {
        let mut marketplace = scenario.take_shared<intel_market::IntelMarketplace>();
        intel_market::create_listing(
            &mut marketplace,
            invalid_proof_points_bytes(),
            test_vector_public_inputs_bytes(),
            EXPECTED_COMMITMENT,
            CLIENT_NONCE,
            LISTING_PRICE,
            REPORT_LOCATION,
            SOLAR_SYSTEM_ID,
            listing_description(),
            scenario.ctx(),
        );
        ts::return_shared(marketplace);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = intel_market::ENotAdmin)]
fun test_setup_pvk_non_admin_aborts() {
    let mut scenario = ts::begin(admin());
    setup(&mut scenario);

    configure_marketplace(&mut scenario, user_b());

    scenario.end();
}

#[test, expected_failure(abort_code = intel_market::EMarketplaceUninitialized)]
fun test_create_listing_requires_initialized_pvk() {
    let mut scenario = ts::begin(admin());
    setup(&mut scenario);

    create_listing(&mut scenario, user_a());

    scenario.end();
}

#[test]
fun test_create_listing_with_valid_proof() {
    let mut scenario = ts::begin(admin());
    setup(&mut scenario);
    configure_marketplace(&mut scenario, admin());

    create_listing(&mut scenario, user_a());

    scenario.next_tx(user_a());
    {
        let listing = scenario.take_shared<intel_market::IntelListing>();
        assert!(intel_market::seller(&listing) == user_a());
        assert!(intel_market::commitment(&listing) == EXPECTED_COMMITMENT);
        assert!(intel_market::client_nonce(&listing) == CLIENT_NONCE);
        assert!(intel_market::price(&listing) == LISTING_PRICE);
        assert!(intel_market::report_type(&listing) == REPORT_LOCATION);
        assert!(intel_market::solar_system_id(&listing) == SOLAR_SYSTEM_ID);
        assert!(intel_market::description(&listing) == listing_description());
        assert!(intel_market::status(&listing) == STATUS_ACTIVE);
        assert!(!option::is_some(&intel_market::buyer(&listing)));
        assert!(!option::is_some(&intel_market::restricted_to_tribe_id(&listing)));
        ts::return_shared(listing);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = intel_market::ECommitmentMismatch)]
fun test_create_listing_rejects_mismatched_commitment_bytes() {
    let mut scenario = ts::begin(admin());
    setup(&mut scenario);
    configure_marketplace(&mut scenario, admin());

    scenario.next_tx(user_a());
    {
        let mut marketplace = scenario.take_shared<intel_market::IntelMarketplace>();
        intel_market::create_listing(
            &mut marketplace,
            test_vector_proof_points_bytes(),
            mismatched_public_inputs_bytes(),
            EXPECTED_COMMITMENT,
            CLIENT_NONCE,
            LISTING_PRICE,
            REPORT_LOCATION,
            SOLAR_SYSTEM_ID,
            listing_description(),
            scenario.ctx(),
        );
        ts::return_shared(marketplace);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = intel_market::EInvalidProof)]
fun test_create_listing_invalid_proof_aborts() {
    let mut scenario = ts::begin(admin());
    setup(&mut scenario);
    configure_marketplace(&mut scenario, admin());

    scenario.next_tx(user_a());
    {
        let mut marketplace = scenario.take_shared<intel_market::IntelMarketplace>();
        intel_market::create_listing(
            &mut marketplace,
            invalid_proof_points_bytes(),
            test_vector_public_inputs_bytes(),
            EXPECTED_COMMITMENT,
            CLIENT_NONCE,
            LISTING_PRICE,
            REPORT_LOCATION,
            SOLAR_SYSTEM_ID,
            listing_description(),
            scenario.ctx(),
        );
        ts::return_shared(marketplace);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = intel_market::EInvalidProof)]
fun test_create_listing_rejects_invalid_pvk() {
    let mut scenario = ts::begin(admin());
    setup(&mut scenario);

    scenario.next_tx(admin());
    {
        let mut marketplace = scenario.take_shared<intel_market::IntelMarketplace>();
        let mut pvk_bytes = intel_market::prepared_vk_bytes_for_testing(raw_verification_key_bytes());
        let delta_g2_neg_pc_bytes = pvk_bytes.pop_back();
        let gamma_g2_neg_pc_bytes = pvk_bytes.pop_back();
        let alpha_g1_beta_g2_bytes = pvk_bytes.pop_back();
        let mut vk_gamma_abc_g1_bytes = pvk_bytes.pop_back();
        vk_gamma_abc_g1_bytes.pop_back();
        intel_market::setup_pvk(
            &mut marketplace,
            vk_gamma_abc_g1_bytes,
            alpha_g1_beta_g2_bytes,
            gamma_g2_neg_pc_bytes,
            delta_g2_neg_pc_bytes,
            scenario.ctx(),
        );
        ts::return_shared(marketplace);
    };

    create_listing(&mut scenario, user_a());

    scenario.end();
}

#[test]
fun test_create_listing_with_test_vectors() {
    let mut scenario = ts::begin(admin());
    setup(&mut scenario);
    configure_marketplace(&mut scenario, admin());

    create_listing(&mut scenario, user_a());

    scenario.next_tx(user_a());
    {
        let listing = scenario.take_shared<intel_market::IntelListing>();
        assert!(intel_market::commitment(&listing) == EXPECTED_COMMITMENT);
        assert!(intel_market::client_nonce(&listing) == CLIENT_NONCE);
        assert!(intel_market::status(&listing) == STATUS_ACTIVE);
        ts::return_shared(listing);
    };

    scenario.end();
}

#[test]
fun test_purchase_transfers_sui_to_seller() {
    let mut scenario = ts::begin(admin());
    setup(&mut scenario);
    configure_marketplace(&mut scenario, admin());
    create_listing(&mut scenario, user_a());

    purchase_listing(&mut scenario, user_b(), LISTING_PRICE);

    scenario.next_tx(user_b());
    {
        let listing = scenario.take_shared<intel_market::IntelListing>();
        assert!(intel_market::status(&listing) == STATUS_SOLD);
        let buyer = intel_market::buyer(&listing);
        assert!(option::is_some(&buyer));
        assert!(option::destroy_some(buyer) == user_b());
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
    configure_marketplace(&mut scenario, admin());
    create_listing(&mut scenario, user_a());

    purchase_listing(&mut scenario, user_b(), WRONG_PRICE);

    scenario.end();
}

#[test, expected_failure(abort_code = intel_market::EListingNotActive)]
fun test_purchase_sold_listing_aborts() {
    let mut scenario = ts::begin(admin());
    setup(&mut scenario);
    configure_marketplace(&mut scenario, admin());
    create_listing(&mut scenario, user_a());
    purchase_listing(&mut scenario, user_b(), LISTING_PRICE);

    purchase_listing(&mut scenario, OUTSIDER, LISTING_PRICE);

    scenario.end();
}

#[test]
fun test_cancel_listing_by_seller() {
    let mut scenario = ts::begin(admin());
    setup(&mut scenario);
    configure_marketplace(&mut scenario, admin());
    create_listing(&mut scenario, user_a());

    scenario.next_tx(user_a());
    {
        let mut listing = scenario.take_shared<intel_market::IntelListing>();
        intel_market::cancel_listing(&mut listing, scenario.ctx());
        ts::return_shared(listing);
    };

    scenario.next_tx(user_a());
    {
        let listing = scenario.take_shared<intel_market::IntelListing>();
        assert!(intel_market::status(&listing) == STATUS_CANCELLED);
        ts::return_shared(listing);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = intel_market::ENotSeller)]
fun test_cancel_listing_non_seller_aborts() {
    let mut scenario = ts::begin(admin());
    setup(&mut scenario);
    configure_marketplace(&mut scenario, admin());
    create_listing(&mut scenario, user_a());

    scenario.next_tx(user_b());
    {
        let mut listing = scenario.take_shared<intel_market::IntelListing>();
        intel_market::cancel_listing(&mut listing, scenario.ctx());
        ts::return_shared(listing);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = intel_market::ENotTribeMember)]
fun test_create_restricted_listing_requires_membership() {
    let mut scenario = ts::begin(admin());
    setup(&mut scenario);
    configure_marketplace(&mut scenario, admin());

    let seller_character = create_character(&mut scenario, user_a(), SELLER_TRIBE, SELLER_ITEM_ID, b"seller");
    let custodian_id = create_custodian(&mut scenario, user_a(), seller_character);

    create_restricted_listing(&mut scenario, user_b(), custodian_id);

    scenario.end();
}

#[test]
fun test_create_restricted_listing_with_member_succeeds() {
    let mut scenario = ts::begin(admin());
    setup(&mut scenario);
    configure_marketplace(&mut scenario, admin());

    let seller_character = create_character(&mut scenario, user_a(), SELLER_TRIBE, SELLER_ITEM_ID, b"seller");
    let custodian_id = create_custodian(&mut scenario, user_a(), seller_character);

    create_restricted_listing(&mut scenario, user_a(), custodian_id);

    scenario.next_tx(user_a());
    {
        let listing = scenario.take_shared<intel_market::IntelListing>();
        assert!(intel_market::seller(&listing) == user_a());
        assert!(intel_market::commitment(&listing) == EXPECTED_COMMITMENT);
        assert!(intel_market::client_nonce(&listing) == CLIENT_NONCE);
        assert!(intel_market::price(&listing) == LISTING_PRICE);
        assert!(intel_market::report_type(&listing) == REPORT_LOCATION);
        assert!(intel_market::solar_system_id(&listing) == SOLAR_SYSTEM_ID);
        assert!(intel_market::description(&listing) == listing_description());
        assert!(intel_market::status(&listing) == STATUS_ACTIVE);
        assert!(!option::is_some(&intel_market::buyer(&listing)));
        let restricted_to_tribe_id = intel_market::restricted_to_tribe_id(&listing);
        assert!(option::is_some(&restricted_to_tribe_id));
        assert!(option::destroy_some(restricted_to_tribe_id) == SELLER_TRIBE);
        ts::return_shared(listing);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = intel_market::ENotTribeMember)]
fun test_purchase_restricted_checks_buyer_membership() {
    let mut scenario = ts::begin(admin());
    setup(&mut scenario);
    configure_marketplace(&mut scenario, admin());

    let seller_character = create_character(&mut scenario, user_a(), SELLER_TRIBE, SELLER_ITEM_ID, b"seller");
    let custodian_id = create_custodian(&mut scenario, user_a(), seller_character);
    create_restricted_listing(&mut scenario, user_a(), custodian_id);

    purchase_restricted_listing(&mut scenario, user_b(), custodian_id, LISTING_PRICE);

    scenario.end();
}

#[test]
fun test_purchase_restricted_succeeds_for_eligible_member() {
    let mut scenario = ts::begin(admin());
    setup(&mut scenario);
    configure_marketplace(&mut scenario, admin());

    let seller_character = create_character(&mut scenario, user_a(), SELLER_TRIBE, SELLER_ITEM_ID, b"seller");
    let buyer_character = create_character(&mut scenario, user_b(), SELLER_TRIBE, BUYER_ITEM_ID, b"buyer");
    let custodian_id = create_custodian(&mut scenario, user_a(), seller_character);
    join_custodian(&mut scenario, user_b(), custodian_id, buyer_character);
    create_restricted_listing(&mut scenario, user_a(), custodian_id);

    purchase_restricted_listing(&mut scenario, user_b(), custodian_id, LISTING_PRICE);

    scenario.next_tx(user_b());
    {
        let listing = scenario.take_shared<intel_market::IntelListing>();
        assert!(intel_market::status(&listing) == STATUS_SOLD);
        let buyer = intel_market::buyer(&listing);
        assert!(option::is_some(&buyer));
        assert!(option::destroy_some(buyer) == user_b());
        let restricted_to_tribe_id = intel_market::restricted_to_tribe_id(&listing);
        assert!(option::is_some(&restricted_to_tribe_id));
        assert!(option::destroy_some(restricted_to_tribe_id) == SELLER_TRIBE);
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

#[test]
fun test_verify_intel_matching_data() {
    let mut scenario = ts::begin(admin());
    setup(&mut scenario);
    configure_marketplace(&mut scenario, admin());
    create_listing(&mut scenario, user_a());

    scenario.next_tx(user_a());
    {
        let listing = scenario.take_shared<intel_market::IntelListing>();
        assert!(intel_market::verify_intel(&listing, test_vector_data()) == true);
        ts::return_shared(listing);
    };

    scenario.end();
}

#[test]
fun test_verify_intel_mismatched_data() {
    let mut scenario = ts::begin(admin());
    setup(&mut scenario);
    configure_marketplace(&mut scenario, admin());
    create_listing(&mut scenario, user_a());

    scenario.next_tx(user_a());
    {
        let listing = scenario.take_shared<intel_market::IntelListing>();
        let matching_result = intel_market::verify_intel(&listing, test_vector_data());
        let mismatched_result = intel_market::verify_intel(&listing, mismatched_data());
        assert!(matching_result == true);
        assert!(mismatched_result == false);
        assert!(matching_result != mismatched_result);
        ts::return_shared(listing);
    };

    scenario.end();
}

#[test]
fun test_listing_count_increments() {
    let mut scenario = ts::begin(admin());
    setup(&mut scenario);
    configure_marketplace(&mut scenario, admin());

    scenario.next_tx(admin());
    {
        let marketplace = scenario.take_shared<intel_market::IntelMarketplace>();
        assert!(intel_market::listing_count(&marketplace) == 0);
        ts::return_shared(marketplace);
    };

    create_listing(&mut scenario, user_a());
    create_second_listing(&mut scenario, user_a());

    scenario.next_tx(admin());
    {
        let marketplace = scenario.take_shared<intel_market::IntelMarketplace>();
        assert!(intel_market::listing_count(&marketplace) == 2);
        ts::return_shared(marketplace);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = intel_market::EListingNotRestricted)]
fun test_purchase_restricted_rejects_global_listing() {
    let mut scenario = ts::begin(admin());
    setup(&mut scenario);
    configure_marketplace(&mut scenario, admin());

    let seller_character = create_character(&mut scenario, user_a(), SELLER_TRIBE, SELLER_ITEM_ID, b"seller");
    let buyer_character = create_character(&mut scenario, user_b(), SELLER_TRIBE, BUYER_ITEM_ID, b"buyer");
    let custodian_id = create_custodian(&mut scenario, user_a(), seller_character);
    join_custodian(&mut scenario, user_b(), custodian_id, buyer_character);

    create_listing(&mut scenario, user_a());
    purchase_restricted_listing(&mut scenario, user_b(), custodian_id, LISTING_PRICE);

    scenario.end();
}

#[test, expected_failure(abort_code = intel_market::EWrongTribe)]
fun test_purchase_restricted_rejects_wrong_custodian() {
    let mut scenario = ts::begin(admin());
    setup(&mut scenario);
    configure_marketplace(&mut scenario, admin());

    let seller_character = create_character(&mut scenario, user_a(), SELLER_TRIBE, SELLER_ITEM_ID, b"seller");
    let buyer_character = create_character(&mut scenario, user_b(), SELLER_TRIBE, BUYER_ITEM_ID, b"buyer");
    let wrong_character = create_character(&mut scenario, OUTSIDER, WRONG_TRIBE, WRONG_TRIBE_ITEM_ID, b"wrong");

    let custodian_id = create_custodian(&mut scenario, user_a(), seller_character);
    let wrong_custodian_id = create_custodian(&mut scenario, OUTSIDER, wrong_character);
    join_custodian(&mut scenario, user_b(), custodian_id, buyer_character);

    create_restricted_listing(&mut scenario, user_a(), custodian_id);
    purchase_restricted_listing(&mut scenario, user_b(), wrong_custodian_id, LISTING_PRICE);

    scenario.end();
}

#[test, expected_failure(abort_code = intel_market::EListingNotRestricted)]
fun test_purchase_rejects_restricted_listing() {
    let mut scenario = ts::begin(admin());
    setup(&mut scenario);
    configure_marketplace(&mut scenario, admin());

    let seller_character = create_character(&mut scenario, user_a(), SELLER_TRIBE, SELLER_ITEM_ID, b"seller");
    let buyer_character = create_character(&mut scenario, user_b(), SELLER_TRIBE, BUYER_ITEM_ID, b"buyer");
    let custodian_id = create_custodian(&mut scenario, user_a(), seller_character);
    join_custodian(&mut scenario, user_b(), custodian_id, buyer_character);

    create_restricted_listing(&mut scenario, user_a(), custodian_id);
    purchase_listing(&mut scenario, user_b(), LISTING_PRICE);

    scenario.end();
}

#[test, expected_failure(abort_code = intel_market::ESelfPurchase)]
fun test_purchase_rejects_self_purchase() {
    let mut scenario = ts::begin(admin());
    setup(&mut scenario);
    configure_marketplace(&mut scenario, admin());
    create_listing(&mut scenario, user_a());

    purchase_listing(&mut scenario, user_a(), LISTING_PRICE);

    scenario.end();
}
