module sigil::intel_market;

use sui::coin::{Self, Coin};
use sui::sui::SUI;
use sigil::tribe_custodian::{Self, Custodian};

const STATUS_ACTIVE: u8 = 0;
const STATUS_SOLD: u8 = 1;
const STATUS_CANCELLED: u8 = 2;

const ENotSeller: u64 = 0;
const EListingNotActive: u64 = 1;
const EWrongPayment: u64 = 3;
const ENotTribeMember: u64 = 5;
const EListingNotRestricted: u64 = 6;
const EWrongTribe: u64 = 7;
const ESelfPurchase: u64 = 10;

public struct IntelMarketplace has key {
    id: UID,
}

public struct IntelListing has key {
    id: UID,
    seller: address,
    seal_id: vector<u8>,
    encrypted_blob_id: vector<u8>,
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

public fun create_listing(
    seal_id: vector<u8>,
    encrypted_blob_id: vector<u8>,
    client_nonce: u64,
    price: u64,
    report_type: u8,
    solar_system_id: u32,
    description: vector<u8>,
    ctx: &mut TxContext,
) {
    create_listing_internal(
        seal_id,
        encrypted_blob_id,
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
    custodian: &Custodian,
    seal_id: vector<u8>,
    encrypted_blob_id: vector<u8>,
    client_nonce: u64,
    price: u64,
    report_type: u8,
    solar_system_id: u32,
    description: vector<u8>,
    ctx: &mut TxContext,
) {
    assert!(tribe_custodian::is_member(custodian, ctx.sender()), ENotTribeMember);

    create_listing_internal(
        seal_id,
        encrypted_blob_id,
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

public fun seller(listing: &IntelListing): address {
    listing.seller
}

public fun seal_id(listing: &IntelListing): vector<u8> {
    copy listing.seal_id
}

public fun encrypted_blob_id(listing: &IntelListing): vector<u8> {
    copy listing.encrypted_blob_id
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

fun share_marketplace(ctx: &mut TxContext) {
    transfer::share_object(IntelMarketplace { id: object::new(ctx) });
}

fun create_listing_internal(
    seal_id: vector<u8>,
    encrypted_blob_id: vector<u8>,
    client_nonce: u64,
    price: u64,
    report_type: u8,
    solar_system_id: u32,
    description: vector<u8>,
    restricted_to_tribe_id: Option<u32>,
    ctx: &mut TxContext,
) {
    transfer::share_object(IntelListing {
        id: object::new(ctx),
        seller: ctx.sender(),
        seal_id,
        encrypted_blob_id,
        client_nonce,
        price,
        report_type,
        solar_system_id,
        description,
        status: STATUS_ACTIVE,
        buyer: option::none(),
        restricted_to_tribe_id,
    });
}
