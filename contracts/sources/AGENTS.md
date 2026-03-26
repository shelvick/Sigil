# contracts/sources/

## Modules
- `sigil::standings_table` (`standings_table.move`) — legacy standings contract retained as immutable compatibility ballast.
- `sigil::tribe_custodian` (`tribe_custodian.move`) — per-tribe governance and inline standings shared object.
- `sigil::frontier_gate` (`frontier_gate.move`) — typed-witness gate-access extension keyed off Custodian standings.
- `sigil::intel_market` (`intel_market.move`) — Seal-era marketplace contract storing `seal_id`, `encrypted_blob_id`, preview metadata, seller/buyer state, and optional tribe restriction. The singleton `IntelMarketplace` remains metadata-only and does not track `listing_count`.
- `sigil::seal_policy` (`seal_policy.move`) — Seal decryption policy module authorizing the seller or the buyer of a sold listing.

## Marketplace Notes
- `intel_market::create_listing` and `intel_market::create_restricted_listing` no longer take a marketplace shared-object argument or any legacy commitment parameter.
- `intel_market.move` contains no proof-verification or PVK setup path.
- `seal_policy::seal_approve` validates `seal_id`, allows sellers always, and allows buyers only when the listing is sold and owned by the sender.

## Dependencies
- Marketplace contracts depend on `sigil::tribe_custodian` for restricted listings.
- `sigil::seal_policy` depends on `sigil::intel_market` accessor functions and listing status semantics.

## Patterns
- Keep policy modules thin: read immutable listing state and abort with explicit error codes when authorization fails.
- Use shared-object references only where runtime data is actually required; listing creation itself does not need the marketplace singleton as an input.
