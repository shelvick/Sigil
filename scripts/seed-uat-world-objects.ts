/**
 * seed-uat-world-objects.ts
 *
 * Creates additional world objects for UAT beyond what create-test-resources provides.
 * Runs inside Docker container: cd /workspace/world-contracts && npx ts-node scripts/seed-uat-world-objects.ts
 *
 * Creates:
 *   - char_a2 (PLAYER_A, tribe 999 — no custodian, "solo player" testing)
 *   - char_c1 (ADMIN, tribe 200 — rival tribe leader)
 *   - NWN_B   (PLAYER_B's character — gives PLAYER_B owned assemblies)
 *   - TURRET_A (PLAYER_A's character — covers turret assembly type)
 *   - GATE_B   (PLAYER_B's character — unlinked gate for "Not linked" display)
 *
 * Outputs KEY=VALUE lines to stdout for shell parsing.
 */

import "dotenv/config";
import { Transaction } from "@mysten/sui/transactions";
import { bcs } from "@mysten/sui/bcs";
import { SuiJsonRpcClient } from "@mysten/sui/jsonRpc";
import { Ed25519Keypair } from "@mysten/sui/keypairs/ed25519";
import { decodeSuiPrivateKey } from "@mysten/sui/cryptography";
import {
    initializeContext,
    hydrateWorldConfig,
    handleError,
    getEnvConfig,
    extractEvent,
    hexToBytes,
    requireEnv,
    shareHydratedConfig,
} from "./utils/helper";
import { MODULES } from "./utils/config";
import { deriveObjectId } from "./utils/derive-object-id";
import { devInspectMoveCallFirstReturnValueBytes } from "./utils/dev-inspect";
import { LOCATION_HASH, GAME_CHARACTER_ID, GAME_CHARACTER_B_ID, NWN_ITEM_ID } from "./utils/constants";

function keypairFromPrivateKey(key: string): Ed25519Keypair {
    const { scheme, secretKey } = decodeSuiPrivateKey(key);
    if (scheme !== "ED25519") throw new Error("Only ED25519 keys are supported");
    return Ed25519Keypair.fromSecretKey(secretKey);
}

function delay(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms));
}

// ── Character Creation (admin-signed) ────────────────────────────────

async function createCharacter(
    ctx: ReturnType<typeof initializeContext>,
    characterAddress: string,
    gameCharacterId: number,
    tribeId: number,
    name: string
): Promise<string> {
    const { client, keypair, config } = ctx;
    const precomputedId = deriveObjectId(config.objectRegistry, gameCharacterId, config.packageId);

    const tx = new Transaction();
    const [character] = tx.moveCall({
        target: `${config.packageId}::${MODULES.CHARACTER}::create_character`,
        arguments: [
            tx.object(config.objectRegistry),
            tx.object(config.adminAcl),
            tx.pure.u32(gameCharacterId),
            tx.pure.string("dev"),
            tx.pure.u32(tribeId),
            tx.pure.address(characterAddress),
            tx.pure.string(name),
        ],
    });
    tx.moveCall({
        target: `${config.packageId}::${MODULES.CHARACTER}::share_character`,
        arguments: [character, tx.object(config.adminAcl)],
    });

    await client.signAndExecuteTransaction({
        transaction: tx,
        signer: keypair,
        options: { showObjectChanges: true },
    });

    return precomputedId;
}

// ── Network Node Creation (admin-signed) ─────────────────────────────

async function createNetworkNode(
    ctx: ReturnType<typeof initializeContext>,
    characterObjectId: string,
    itemId: bigint,
    typeId: bigint
): Promise<string> {
    const { client, keypair, config } = ctx;

    const tx = new Transaction();
    const [nwn] = tx.moveCall({
        target: `${config.packageId}::${MODULES.NETWORK_NODE}::anchor`,
        arguments: [
            tx.object(config.objectRegistry),
            tx.object(characterObjectId),
            tx.object(config.adminAcl),
            tx.pure.u64(itemId),
            tx.pure.u64(typeId),
            tx.pure(bcs.vector(bcs.u8()).serialize(hexToBytes(LOCATION_HASH))),
            tx.pure.u64(10000n),      // fuel max capacity
            tx.pure.u64(3600000n),    // burn rate 1 hour in ms
            tx.pure.u64(100n),        // max energy production
        ],
    });
    tx.moveCall({
        target: `${config.packageId}::${MODULES.NETWORK_NODE}::share_network_node`,
        arguments: [nwn, tx.object(config.adminAcl)],
    });

    const result = await client.signAndExecuteTransaction({
        transaction: tx,
        signer: keypair,
        options: { showEvents: true },
    });

    const event = extractEvent<{ network_node_id: string }>(result, "::network_node::NetworkNodeCreatedEvent");
    if (!event) throw new Error("NetworkNodeCreatedEvent not found");
    return event.network_node_id;
}

// ── Turret Creation (admin-signed) ───────────────────────────────────

async function createTurret(
    ctx: ReturnType<typeof initializeContext>,
    characterObjectId: string,
    networkNodeObjectId: string,
    itemId: bigint,
    typeId: bigint
): Promise<string> {
    const { client, keypair, config } = ctx;

    const tx = new Transaction();
    const [turret] = tx.moveCall({
        target: `${config.packageId}::${MODULES.TURRET}::anchor`,
        arguments: [
            tx.object(config.objectRegistry),
            tx.object(networkNodeObjectId),
            tx.object(characterObjectId),
            tx.object(config.adminAcl),
            tx.pure.u64(itemId),
            tx.pure.u64(typeId),
            tx.pure(bcs.vector(bcs.u8()).serialize(hexToBytes(LOCATION_HASH))),
        ],
    });
    tx.moveCall({
        target: `${config.packageId}::${MODULES.TURRET}::share_turret`,
        arguments: [turret, tx.object(config.adminAcl)],
    });

    const result = await client.signAndExecuteTransaction({
        transaction: tx,
        signer: keypair,
        options: { showEvents: true },
    });

    const event = extractEvent<{ turret_id: string }>(result, "::turret::TurretCreatedEvent");
    if (!event) throw new Error("TurretCreatedEvent not found");
    return event.turret_id;
}

// ── Gate Creation (admin-signed) ─────────────────────────────────────

async function createGate(
    ctx: ReturnType<typeof initializeContext>,
    characterObjectId: string,
    networkNodeObjectId: string,
    gateItemId: bigint,
    gateTypeId: bigint
): Promise<string> {
    const { client, keypair, config } = ctx;

    const tx = new Transaction();
    const [gate] = tx.moveCall({
        target: `${config.packageId}::${MODULES.GATE}::anchor`,
        arguments: [
            tx.object(config.objectRegistry),
            tx.object(networkNodeObjectId),
            tx.object(characterObjectId),
            tx.object(config.adminAcl),
            tx.pure.u64(gateItemId),
            tx.pure.u64(gateTypeId),
            tx.pure(bcs.vector(bcs.u8()).serialize(hexToBytes(LOCATION_HASH))),
        ],
    });
    tx.moveCall({
        target: `${config.packageId}::${MODULES.GATE}::share_gate`,
        arguments: [gate, tx.object(config.adminAcl)],
    });

    const result = await client.signAndExecuteTransaction({
        transaction: tx,
        signer: keypair,
        options: { showEvents: true },
    });

    const gateId = deriveObjectId(config.objectRegistry, gateItemId, config.packageId);
    return gateId;
}

// ── Bring Online (player-signed via borrow_owner_cap) ────────────────

async function getOwnerCap(
    objectId: string,
    client: SuiJsonRpcClient,
    config: ReturnType<typeof initializeContext>["config"],
    moduleName: string,
    senderAddress: string
): Promise<string> {
    const target = `${config.packageId}::${moduleName}::owner_cap_id`;
    const bytes = await devInspectMoveCallFirstReturnValueBytes(client, {
        target,
        senderAddress,
        arguments: (tx) => [tx.object(objectId)],
    });
    if (!bytes) throw new Error(`OwnerCap not found for ${objectId}`);
    return bcs.Address.parse(bytes);
}

async function bringOnline(
    ctx: ReturnType<typeof initializeContext>,
    objectId: string,
    objectModule: string,
    characterGameId: number,
    nwnObjectId: string | null
): Promise<void> {
    const { client, keypair, config } = ctx;
    const characterObjectId = deriveObjectId(config.objectRegistry, characterGameId, config.packageId);

    const ownerCapId = await getOwnerCap(objectId, client, config, objectModule, ctx.address);

    const objectType = `${config.packageId}::${objectModule}::${capitalize(objectModule)}`;
    const tx = new Transaction();

    const [ownerCap, receipt] = tx.moveCall({
        target: `${config.packageId}::${MODULES.CHARACTER}::borrow_owner_cap`,
        typeArguments: [objectType],
        arguments: [tx.object(characterObjectId), tx.object(ownerCapId)],
    });

    if (objectModule === "network_node") {
        tx.moveCall({
            target: `${config.packageId}::${MODULES.NETWORK_NODE}::online`,
            arguments: [tx.object(objectId), ownerCap, tx.object("0x6")],
        });
    } else if (objectModule === "gate") {
        tx.moveCall({
            target: `${config.packageId}::${MODULES.GATE}::online`,
            arguments: [
                tx.object(objectId),
                tx.object(nwnObjectId!),
                tx.object(config.energyConfig),
                ownerCap,
            ],
        });
    } else if (objectModule === "turret") {
        tx.moveCall({
            target: `${config.packageId}::${MODULES.TURRET}::online`,
            arguments: [
                tx.object(objectId),
                tx.object(nwnObjectId!),
                tx.object(config.energyConfig),
                ownerCap,
            ],
        });
    }

    tx.moveCall({
        target: `${config.packageId}::${MODULES.CHARACTER}::return_owner_cap`,
        typeArguments: [objectType],
        arguments: [tx.object(characterObjectId), ownerCap, receipt],
    });

    await client.signAndExecuteTransaction({
        transaction: tx,
        signer: keypair,
        options: { showEffects: true },
    });
}

// ── Deposit Fuel (sponsored: player sender, admin gas) ───────────────

async function depositFuel(
    playerCtx: ReturnType<typeof initializeContext>,
    adminKeypair: Ed25519Keypair,
    adminAddress: string,
    nwnObjectId: string,
    characterGameId: number
): Promise<void> {
    const { client, keypair: playerKeypair, config, address: playerAddress } = playerCtx;

    const characterObjectId = deriveObjectId(config.objectRegistry, characterGameId, config.packageId);
    const ownerCapId = await getOwnerCap(nwnObjectId, client, config, "network_node", playerAddress);

    const tx = new Transaction();
    tx.setSender(playerAddress);
    tx.setGasOwner(adminAddress);

    const [ownerCap, receipt] = tx.moveCall({
        target: `${config.packageId}::${MODULES.CHARACTER}::borrow_owner_cap`,
        typeArguments: [`${config.packageId}::${MODULES.NETWORK_NODE}::NetworkNode`],
        arguments: [tx.object(characterObjectId), tx.object(ownerCapId)],
    });

    tx.moveCall({
        target: `${config.packageId}::${MODULES.NETWORK_NODE}::deposit_fuel`,
        arguments: [
            tx.object(nwnObjectId),
            tx.object(config.adminAcl),
            ownerCap,
            tx.pure.u64(78437n),  // fuel type
            tx.pure.u64(10),      // volume
            tx.pure.u64(2n),      // quantity
            tx.object("0x6"),     // Clock
        ],
    });

    tx.moveCall({
        target: `${config.packageId}::${MODULES.CHARACTER}::return_owner_cap`,
        typeArguments: [`${config.packageId}::${MODULES.NETWORK_NODE}::NetworkNode`],
        arguments: [tx.object(characterObjectId), ownerCap, receipt],
    });

    // Sponsored transaction: build kind, reconstruct with gas
    const { executeSponsoredTransaction } = await import("./utils/transaction");
    await executeSponsoredTransaction(tx, client, playerKeypair, adminKeypair, playerAddress, adminAddress);
}

function capitalize(s: string): string {
    // network_node -> NetworkNode, gate -> Gate, turret -> Turret
    return s.split("_").map((p) => p.charAt(0).toUpperCase() + p.slice(1)).join("");
}

// ── Main ─────────────────────────────────────────────────────────────

async function main() {
    try {
        const env = getEnvConfig();
        const adminCtx = initializeContext(env.network, env.adminExportedKey);
        await hydrateWorldConfig(adminCtx);

        const playerAKey = requireEnv("PLAYER_A_PRIVATE_KEY");
        const playerBKey = requireEnv("PLAYER_B_PRIVATE_KEY");
        const playerAAddr = keypairFromPrivateKey(playerAKey).getPublicKey().toSuiAddress();
        const playerBAddr = keypairFromPrivateKey(playerBKey).getPublicKey().toSuiAddress();
        const adminAddr = adminCtx.address;
        const adminKeypair = keypairFromPrivateKey(env.adminExportedKey);

        // Player contexts for borrow_owner_cap operations
        const playerACtx = initializeContext(env.network, playerAKey);
        shareHydratedConfig(adminCtx, playerACtx);
        const playerBCtx = initializeContext(env.network, playerBKey);
        shareHydratedConfig(adminCtx, playerBCtx);

        const config = adminCtx.config;

        // Existing character IDs from basic seed
        const charAObjectId = deriveObjectId(config.objectRegistry, GAME_CHARACTER_ID, config.packageId);
        const charBObjectId = deriveObjectId(config.objectRegistry, GAME_CHARACTER_B_ID, config.packageId);
        const existingNwnId = deriveObjectId(config.objectRegistry, NWN_ITEM_ID, config.packageId);

        // 1. Create char_a2 (PLAYER_A, tribe 999 — solo/no-custodian)
        //    tribe_id=0 is rejected by Move contract; use 999 (no custodian) for "unaligned" testing
        console.error("Creating char_a2 (tribe 999, PLAYER_A)...");
        const charA2 = await createCharacter(adminCtx, playerAAddr, 811881, 999, "Ghost");
        await delay(3000);

        // 2. Create char_c1 (ADMIN, tribe 200 — rival)
        console.error("Creating char_c1 (tribe 200, ADMIN)...");
        const charC1 = await createCharacter(adminCtx, adminAddr, 900000002, 200, "Nyx Tanaka");
        await delay(3000);

        // 3. Create NWN_B for PLAYER_B
        console.error("Creating NWN_B (PLAYER_B)...");
        const nwnB = await createNetworkNode(adminCtx, charBObjectId, 5550000013n, 555n);
        await delay(3000);

        // 4. Deposit fuel into NWN_B
        console.error("Depositing fuel into NWN_B...");
        await depositFuel(playerBCtx, adminKeypair, adminAddr, nwnB, GAME_CHARACTER_B_ID);
        await delay(3000);

        // 5. Bring NWN_B online
        console.error("Bringing NWN_B online...");
        await bringOnline(playerBCtx, nwnB, "network_node", GAME_CHARACTER_B_ID, null);
        await delay(3000);

        // 6. Create TURRET_A for PLAYER_A (anchored to existing NWN)
        console.error("Creating TURRET_A (PLAYER_A)...");
        const turretA = await createTurret(adminCtx, charAObjectId, existingNwnId, 6001n, 5555n);
        await delay(3000);

        // 7. Bring TURRET_A online
        console.error("Bringing TURRET_A online...");
        await bringOnline(playerACtx, turretA, "turret", GAME_CHARACTER_ID, existingNwnId);
        await delay(3000);

        // 8. Create GATE_B for PLAYER_B (anchored to NWN_B, unlinked)
        console.error("Creating GATE_B (PLAYER_B)...");
        const gateB = await createGate(adminCtx, charBObjectId, nwnB, 90187n, 88086n);
        await delay(3000);

        // 9. Bring GATE_B online
        console.error("Bringing GATE_B online...");
        await bringOnline(playerBCtx, gateB, "gate", GAME_CHARACTER_B_ID, nwnB);

        // Output for shell parsing (stdout only — logs go to stderr)
        // Include existing character IDs so the shell doesn't depend on fragile grep parsing
        console.log(`CHAR_A1=${charAObjectId}`);
        console.log(`CHAR_B1=${charBObjectId}`);
        console.log(`CHAR_A2=${charA2}`);
        console.log(`CHAR_C1=${charC1}`);
        console.log(`NWN_A=${existingNwnId}`);
        console.log(`NWN_B=${nwnB}`);
        console.log(`TURRET_A=${turretA}`);
        console.log(`GATE_B=${gateB}`);
    } catch (error) {
        handleError(error);
    }
}

main();
