module sigil::intel_market;

use std::bcs;
use sui::groth16;
use sui::poseidon;
use sui::coin::{Self, Coin};
use sui::sui::SUI;
use sigil::tribe_custodian::{Self, Custodian};

const STATUS_ACTIVE: u8 = 0;
const STATUS_SOLD: u8 = 1;
const STATUS_CANCELLED: u8 = 2;

const ENotSeller: u64 = 0;
const EListingNotActive: u64 = 1;
const EInvalidProof: u64 = 2;
const EWrongPayment: u64 = 3;
const ENotAdmin: u64 = 4;
const ENotTribeMember: u64 = 5;
const EListingNotRestricted: u64 = 6;
const EWrongTribe: u64 = 7;
const ECommitmentMismatch: u64 = 8;
const EMarketplaceUninitialized: u64 = 9;
const ESelfPurchase: u64 = 10;

public struct IntelMarketplace has key {
    id: UID,
    pvk: Option<groth16::PreparedVerifyingKey>,
    admin: address,
    listing_count: u64,
}

public struct IntelListing has key {
    id: UID,
    seller: address,
    commitment: u256,
    client_nonce: u64,
    price: u64,
    report_type: u8,
    solar_system_id: u32,
    description: vector<u8>,
    status: u8,
    buyer: Option<address>,
    restricted_to_tribe_id: Option<u32>,
}

fun init(ctx: &mut TxContext) {
    share_marketplace(ctx);
}

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    share_marketplace(ctx);
}

#[test_only]
public fun prepared_vk_bytes_for_testing(verification_key_bytes: vector<u8>): vector<vector<u8>> {
    let curve = groth16::bn254();
    groth16::pvk_to_bytes(groth16::prepare_verifying_key(&curve, &verification_key_bytes))
}

public fun setup_pvk(
    marketplace: &mut IntelMarketplace,
    vk_gamma_abc_g1_bytes: vector<u8>,
    alpha_g1_beta_g2_bytes: vector<u8>,
    gamma_g2_neg_pc_bytes: vector<u8>,
    delta_g2_neg_pc_bytes: vector<u8>,
    ctx: &TxContext,
) {
    assert!(marketplace.admin == ctx.sender(), ENotAdmin);
    marketplace.pvk = option::some(groth16::pvk_from_bytes(
        vk_gamma_abc_g1_bytes,
        alpha_g1_beta_g2_bytes,
        gamma_g2_neg_pc_bytes,
        delta_g2_neg_pc_bytes,
    ));
}

public fun create_listing(
    marketplace: &mut IntelMarketplace,
    proof_points_bytes: vector<u8>,
    public_inputs_bytes: vector<u8>,
    commitment: u256,
    client_nonce: u64,
    price: u64,
    report_type: u8,
    solar_system_id: u32,
    description: vector<u8>,
    ctx: &mut TxContext,
) {
    create_listing_internal(
        marketplace,
        proof_points_bytes,
        public_inputs_bytes,
        commitment,
        client_nonce,
        price,
        report_type,
        solar_system_id,
        description,
        option::none(),
        ctx,
    );
}

public fun create_restricted_listing(
    marketplace: &mut IntelMarketplace,
    custodian: &Custodian,
    proof_points_bytes: vector<u8>,
    public_inputs_bytes: vector<u8>,
    commitment: u256,
    client_nonce: u64,
    price: u64,
    report_type: u8,
    solar_system_id: u32,
    description: vector<u8>,
    ctx: &mut TxContext,
) {
    assert!(tribe_custodian::is_member(custodian, ctx.sender()), ENotTribeMember);

    create_listing_internal(
        marketplace,
        proof_points_bytes,
        public_inputs_bytes,
        commitment,
        client_nonce,
        price,
        report_type,
        solar_system_id,
        description,
        option::some(tribe_custodian::tribe_id(custodian)),
        ctx,
    );
}

public fun purchase(listing: &mut IntelListing, payment: Coin<SUI>, ctx: &mut TxContext) {
    assert!(listing.status == STATUS_ACTIVE, EListingNotActive);
    assert!(listing.seller != ctx.sender(), ESelfPurchase);
    assert!(option::is_none(&listing.restricted_to_tribe_id), EListingNotRestricted);
    assert!(coin::value(&payment) == listing.price, EWrongPayment);

    transfer::public_transfer(payment, listing.seller);
    listing.buyer = option::some(ctx.sender());
    listing.status = STATUS_SOLD;
}

public fun purchase_restricted(
    listing: &mut IntelListing,
    custodian: &Custodian,
    payment: Coin<SUI>,
    ctx: &mut TxContext,
) {
    assert!(listing.status == STATUS_ACTIVE, EListingNotActive);
    assert!(listing.seller != ctx.sender(), ESelfPurchase);
    assert!(option::is_some(&listing.restricted_to_tribe_id), EListingNotRestricted);

    let restricted_tribe_id = *option::borrow(&listing.restricted_to_tribe_id);
    assert!(tribe_custodian::tribe_id(custodian) == restricted_tribe_id, EWrongTribe);
    assert!(tribe_custodian::is_member(custodian, ctx.sender()), ENotTribeMember);
    assert!(coin::value(&payment) == listing.price, EWrongPayment);

    transfer::public_transfer(payment, listing.seller);
    listing.buyer = option::some(ctx.sender());
    listing.status = STATUS_SOLD;
}

public fun cancel_listing(listing: &mut IntelListing, ctx: &TxContext) {
    assert!(listing.seller == ctx.sender(), ENotSeller);
    assert!(listing.status == STATUS_ACTIVE, EListingNotActive);
    listing.status = STATUS_CANCELLED;
}

public fun verify_intel(listing: &IntelListing, data: vector<u256>): bool {
    poseidon::poseidon_bn254(&data) == listing.commitment
}

public fun seller(listing: &IntelListing): address {
    listing.seller
}

public fun commitment(listing: &IntelListing): u256 {
    listing.commitment
}

public fun client_nonce(listing: &IntelListing): u64 {
    listing.client_nonce
}

public fun price(listing: &IntelListing): u64 {
    listing.price
}

public fun status(listing: &IntelListing): u8 {
    listing.status
}

public fun buyer(listing: &IntelListing): Option<address> {
    listing.buyer
}

public fun report_type(listing: &IntelListing): u8 {
    listing.report_type
}

public fun solar_system_id(listing: &IntelListing): u32 {
    listing.solar_system_id
}

public fun description(listing: &IntelListing): vector<u8> {
    copy listing.description
}

public fun restricted_to_tribe_id(listing: &IntelListing): Option<u32> {
    listing.restricted_to_tribe_id
}

public fun listing_count(marketplace: &IntelMarketplace): u64 {
    marketplace.listing_count
}

fun share_marketplace(ctx: &mut TxContext) {
    transfer::share_object(IntelMarketplace {
        id: object::new(ctx),
        pvk: option::none(),
        admin: ctx.sender(),
        listing_count: 0,
    });
}

fun create_listing_internal(
    marketplace: &mut IntelMarketplace,
    proof_points_bytes: vector<u8>,
    public_inputs_bytes: vector<u8>,
    commitment: u256,
    client_nonce: u64,
    price: u64,
    report_type: u8,
    solar_system_id: u32,
    description: vector<u8>,
    restricted_to_tribe_id: Option<u32>,
    ctx: &mut TxContext,
) {
    assert!(option::is_some(&marketplace.pvk), EMarketplaceUninitialized);

    let expected_public_inputs = bcs::to_bytes(&commitment);
    let public_inputs_copy = copy public_inputs_bytes;
    assert!(public_inputs_copy == expected_public_inputs, ECommitmentMismatch);

    let curve = groth16::bn254();
    let proof_points = groth16::proof_points_from_bytes(proof_points_bytes);
    let public_inputs = groth16::public_proof_inputs_from_bytes(public_inputs_bytes);
    let is_valid = groth16::verify_groth16_proof(
        &curve,
        option::borrow(&marketplace.pvk),
        &public_inputs,
        &proof_points,
    );
    assert!(is_valid, EInvalidProof);

    transfer::share_object(IntelListing {
        id: object::new(ctx),
        seller: ctx.sender(),
        commitment,
        client_nonce,
        price,
        report_type,
        solar_system_id,
        description,
        status: STATUS_ACTIVE,
        buyer: option::none(),
        restricted_to_tribe_id,
    });

    marketplace.listing_count = marketplace.listing_count + 1;
}
