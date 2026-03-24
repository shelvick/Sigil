pragma circom 2.0.0;

include "node_modules/circomlib/circuits/poseidon.circom";

// Proves: "I know private data whose Poseidon hash equals the public commitment."
//
// Private inputs (known only to the seller):
//   data[4] — structured intel fields encoded as BN254 field elements:
//     [0] report_type    (1 = location, 2 = scouting)
//     [1] solar_system_id
//     [2] assembly_id    (numeric hash of the assembly address)
//     [3] content_hash   (SHA256 of notes text, truncated to fit BN254)
//
// Public output:
//   commitment — Poseidon(data[0..3]), verified on-chain via sui::poseidon
//
// The seller publishes `commitment` on-chain. The Groth16 proof convinces
// the Move contract that the seller knows the preimage without revealing it.
//
// Constraints: ~240 (Poseidon with 4 inputs on BN254)

template IntelCommitment() {
    signal input data[4];
    signal output commitment;

    component poseidon = Poseidon(4);
    for (var i = 0; i < 4; i++) {
        poseidon.inputs[i] <== data[i];
    }
    commitment <== poseidon.out;
}

// data[4] = private inputs (seller's secret), commitment = public output (always public)
component main = IntelCommitment();
