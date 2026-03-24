#!/usr/bin/env node

// Builds the intel_commitment circuit and copies artifacts to priv/static/zk/.
//
// Prerequisites: circom must be on $PATH (or at ~/.local/bin/circom)
//
// Usage: npm run build (from circuits/ directory)
//
// Steps:
//   1. Compile circuit to WASM + R1CS
//   2. Run Groth16 trusted setup (Powers of Tau + Phase 2)
//   3. Export verification key
//   4. Copy runtime artifacts to priv/static/zk/
//   5. Generate test vectors

const { execSync } = require("child_process");
const fs = require("fs");
const path = require("path");

const CIRCUITS_DIR = path.join(__dirname, "..");
const BUILD_DIR = path.join(CIRCUITS_DIR, "build");
const PRIV_ZK_DIR = path.join(CIRCUITS_DIR, "..", "priv", "static", "zk");
const CIRCUIT = "intel_commitment";

// Find circom binary
const CIRCOM = fs.existsSync(path.join(process.env.HOME, ".local", "bin", "circom"))
  ? path.join(process.env.HOME, ".local", "bin", "circom")
  : "circom";

function run(cmd, opts = {}) {
  console.log(`  $ ${cmd}`);
  execSync(cmd, { stdio: "inherit", cwd: CIRCUITS_DIR, ...opts });
}

function main() {
  console.log("=== Sigil ZK Circuit Build ===\n");

  // Ensure build and output dirs exist
  fs.mkdirSync(BUILD_DIR, { recursive: true });
  fs.mkdirSync(PRIV_ZK_DIR, { recursive: true });

  // 1. Compile circuit
  console.log("1. Compiling circuit...");
  run(`${CIRCOM} ${CIRCUIT}.circom --r1cs --wasm --sym --output build/`);

  // 2. Trusted setup — Phase 1 (Powers of Tau)
  console.log("\n2. Trusted setup — Phase 1 (Powers of Tau)...");
  run(`npx snarkjs powersoftau new bn128 12 build/pot12_0000.ptau`);

  const entropy1 = require("crypto").randomBytes(64).toString("hex");
  run(`npx snarkjs powersoftau contribute build/pot12_0000.ptau build/pot12_0001.ptau --name="Sigil dev ceremony" -e="${entropy1}"`);

  run(`npx snarkjs powersoftau prepare phase2 build/pot12_0001.ptau build/pot12_final.ptau`);

  // 3. Trusted setup — Phase 2 (circuit-specific)
  console.log("\n3. Trusted setup — Phase 2 (circuit-specific)...");
  run(`npx snarkjs groth16 setup build/${CIRCUIT}.r1cs build/pot12_final.ptau build/${CIRCUIT}_0000.zkey`);

  const entropy2 = require("crypto").randomBytes(64).toString("hex");
  run(`npx snarkjs zkey contribute build/${CIRCUIT}_0000.zkey build/${CIRCUIT}_final.zkey --name="Sigil phase2" -e="${entropy2}"`);

  // 4. Export verification key
  console.log("\n4. Exporting verification key...");
  run(`npx snarkjs zkey export verificationkey build/${CIRCUIT}_final.zkey build/verification_key.json`);

  // 5. Copy runtime artifacts to priv/static/zk/
  console.log("\n5. Copying artifacts to priv/static/zk/...");

  const copies = [
    [`build/${CIRCUIT}_js/${CIRCUIT}.wasm`, `${CIRCUIT}.wasm`],
    [`build/${CIRCUIT}_final.zkey`, `${CIRCUIT}_final.zkey`],
    ["build/verification_key.json", "verification_key.json"]
  ];

  for (const [src, dest] of copies) {
    const srcPath = path.join(CIRCUITS_DIR, src);
    const destPath = path.join(PRIV_ZK_DIR, dest);
    fs.copyFileSync(srcPath, destPath);
    const size = (fs.statSync(destPath).size / 1024).toFixed(1);
    console.log(`  ${dest} (${size} KB)`);
  }

  // 6. Generate test vectors
  console.log("\n6. Generating test vectors...");
  run("node scripts/generate_test_vectors.js");

  // Copy test vectors to priv/static/zk/ for dev convenience
  const tvSrc = path.join(BUILD_DIR, "test_vectors", "test_vectors.json");
  const tvDest = path.join(PRIV_ZK_DIR, "test_vectors.json");
  if (fs.existsSync(tvSrc)) {
    fs.copyFileSync(tvSrc, tvDest);
  }

  console.log("\n=== Build complete ===");
  console.log(`Artifacts in: ${PRIV_ZK_DIR}`);
}

main();
