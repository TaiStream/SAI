/**
 * Example: Register an AI Agent on SAI
 *
 * This demonstrates the minimal flow to register an agent identity
 * on the Sui Agent Index. You need a funded Sui testnet wallet.
 *
 * Usage:
 *   SUI_PRIVATE_KEY=suiprivkey1... npx tsx examples/register-agent.ts
 */

import { SaiClient, AgentCategory } from '../src';
import { Ed25519Keypair } from '@mysten/sui/keypairs/ed25519';
import { parseAgentRegistered } from '../src/events';

async function main() {
    const privateKey = process.env.SUI_PRIVATE_KEY;
    if (!privateKey) {
        console.error('Set SUI_PRIVATE_KEY environment variable');
        process.exit(1);
    }

    // Zero-config testnet client
    const sai = SaiClient.testnet();
    const keypair = Ed25519Keypair.fromSecretKey(privateKey);
    const address = keypair.getPublicKey().toSuiAddress();

    console.log(`Registering agent from address: ${address}`);

    // Build the transaction
    const tx = sai.registerAgent({
        name: 'My Meeting Assistant',
        agentUri: 'https://example.com/agent.json',
        category: AgentCategory.Communication,
        avatarStyle: 'robot',
        wallet: address,
        metadataKeys: ['model', 'version', 'framework'],
        metadataValues: ['claude-haiku-4-5', '1.0.0', 'tai-node'],
    });

    // Sign and execute
    const result = await sai.suiClient.signAndExecuteTransaction({
        transaction: tx,
        signer: keypair,
        options: { showEvents: true, showEffects: true },
    });

    console.log('Transaction digest:', result.digest);

    // Parse the registration event
    const event = parseAgentRegistered(result, sai.packageId);
    if (event) {
        console.log('Agent registered!');
        console.log('  Agent ID:', event.agentId);
        console.log('  Name:', event.name);
        console.log('  Category:', AgentCategory[event.category]);
    }
}

main().catch(console.error);
