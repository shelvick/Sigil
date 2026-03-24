// Generate test vectors for Move contract and Elixir tests.
//
// Produces a known-good Groth16 proof from sample intel data,
// plus the verification key bytes formatted for sui::groth16.
//
// Usage: node scripts/generate_test_vectors.js

const snarkjs = require("snarkjs");
const fs = require("fs");
const path = require("path");
const { buildPoseidon } = require("circomlibjs");

const BUILD_DIR = path.join(__dirname, "..", "build");
const OUTPUT_DIR = path.join(__dirname, "..", "build", "test_vectors");

// Sample intel data (same encoding the Elixir app will use)
const SAMPLE_DATA = {
  report_type: 1n,         // 1 = location
  solar_system_id: 30000142n, // Jita (example)
  assembly_id: 42n,        // Simplified for testing
  content_hash: 123456789n // Simplified SHA256 stand-in for testing
};

async function main() {
  fs.mkdirSync(OUTPUT_DIR, { recursive: true });

  // 1. Compute expected Poseidon hash using circomlibjs
  const poseidon = await buildPoseidon();
  const dataArray = [
    SAMPLE_DATA.report_type,
    SAMPLE_DATA.solar_system_id,
    SAMPLE_DATA.assembly_id,
    SAMPLE_DATA.content_hash
  ];
  const poseidonHash = poseidon.F.toString(poseidon(dataArray));
  console.log("Poseidon commitment:", poseidonHash);

  // 2. Generate witness
  const input = { data: dataArray.map(x => x.toString()) };
  const wasmPath = path.join(BUILD_DIR, "intel_commitment_js", "intel_commitment.wasm");
  const zkeyPath = path.join(BUILD_DIR, "intel_commitment_final.zkey");

  console.log("Generating proof...");
  const { proof, publicSignals } = await snarkjs.groth16.fullProve(input, wasmPath, zkeyPath);

  console.log("Public signals (commitment):", publicSignals);
  console.log("Proof generated successfully!");

  // 3. Verify proof locally
  const vkeyPath = path.join(BUILD_DIR, "verification_key.json");
  const vkey = JSON.parse(fs.readFileSync(vkeyPath, "utf8"));
  const valid = await snarkjs.groth16.verify(vkey, publicSignals, proof);
  console.log("Local verification:", valid ? "PASSED" : "FAILED");

  if (!valid) {
    console.error("ERROR: Proof failed local verification!");
    process.exit(1);
  }

  // 4. Export proof in Sui-compatible format
  // sui::groth16 expects:
  //   - ProofPoints: concatenated [A (G1), B (G2), C (G1)] in compressed form
  //   - PublicProofInputs: concatenated 32-byte little-endian scalars
  //   - PreparedVerifyingKey: [alpha_g1, beta_g2, gamma_g2, delta_g2] + gamma_abc_g1

  // Convert proof points to byte arrays for Sui
  const proofCalldata = await snarkjs.groth16.exportSolidityCallData(proof, publicSignals);

  // 5. Write test vectors
  const testVectors = {
    // Input data
    input: {
      report_type: SAMPLE_DATA.report_type.toString(),
      solar_system_id: SAMPLE_DATA.solar_system_id.toString(),
      assembly_id: SAMPLE_DATA.assembly_id.toString(),
      content_hash: SAMPLE_DATA.content_hash.toString()
    },
    // Expected Poseidon hash
    expected_commitment: poseidonHash,
    // Public signals from proof
    public_signals: publicSignals,
    // Raw proof object (for JS tests)
    proof: proof,
    // Verification key (for reference)
    verification_key: vkey,
    // Solidity-style calldata (useful for byte extraction)
    calldata: proofCalldata
  };

  const outputPath = path.join(OUTPUT_DIR, "test_vectors.json");
  fs.writeFileSync(outputPath, JSON.stringify(testVectors, null, 2));
  console.log(`\nTest vectors written to: ${outputPath}`);

  // 6. Write a summary for human reference
  const summary = `# ZK Intel Commitment Test Vectors

Generated: ${new Date().toISOString()}
Circuit: intel_commitment.circom (Poseidon with 4 inputs on BN254)
Constraints: 300 non-linear, 436 linear

## Sample Input
- report_type: ${SAMPLE_DATA.report_type}
- solar_system_id: ${SAMPLE_DATA.solar_system_id}
- assembly_id: ${SAMPLE_DATA.assembly_id}
- content_hash: ${SAMPLE_DATA.content_hash}

## Expected Commitment (Poseidon hash)
${poseidonHash}

## Verification
- Local snarkjs verification: ${valid ? "PASSED" : "FAILED"}

## Files
- test_vectors.json: Complete proof + verification key + public signals
- Use in Move tests: extract proof bytes from calldata field
- Use in JS tests: load proof/publicSignals directly
- Use in Elixir tests: parse test_vectors.json for expected values
`;

  fs.writeFileSync(path.join(OUTPUT_DIR, "README.md"), summary);
  console.log("Summary written to: build/test_vectors/README.md");
}

main().then(() => {
  process.exit(0);
}).catch(err => {
  console.error("Error:", err);
  process.exit(1);
});
