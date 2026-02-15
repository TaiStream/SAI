/**
 * Example: Query Agents on SAI (Read-Only)
 *
 * Demonstrates read operations — no wallet needed.
 *
 * Usage:
 *   npx tsx examples/query-agents.ts [agentObjectId]
 */

import { SaiClient, AgentCategory, VisibilityTier } from '../src';

async function main() {
    const sai = SaiClient.testnet();

    // Registry stats
    console.log('--- Registry Stats ---');
    const stats = await sai.getRegistryStats();
    console.log(`  Total agents: ${stats.totalAgents}`);
    console.log(`  Active: ${stats.totalActive}`);
    console.log(`  Total feedback: ${stats.totalFeedback}`);
    console.log(`  Total validations: ${stats.totalValidations}`);

    // If an agent ID is provided, query it
    const agentId = process.argv[2];
    if (agentId) {
        console.log(`\n--- Agent: ${agentId} ---`);
        try {
            const agent = await sai.getAgent(agentId);
            console.log(`  Name: ${agent.name}`);
            console.log(`  Owner: ${agent.owner}`);
            console.log(`  Category: ${AgentCategory[agent.category]}`);
            console.log(`  Avatar: ${agent.avatarStyle}`);
            console.log(`  Cred Score: ${agent.credScore}`);
            console.log(`  Active: ${agent.isActive}`);
            console.log(`  Sessions: ${agent.totalSessions}`);
            console.log(`  Feedback: ${agent.totalFeedbackReceived} (${agent.positiveFeedback} positive, ${agent.negativeFeedback} negative)`);

            const tier = await sai.getVisibilityTier(agentId);
            console.log(`  Visibility Tier: ${VisibilityTier[tier]}`);

            const canJoin = await sai.canJoinRoom(agentId);
            console.log(`  Can Join Room: ${canJoin}`);

            const metadata = await sai.getAgentMetadata(agentId);
            if (Object.keys(metadata).length > 0) {
                console.log('  Metadata:');
                for (const [k, v] of Object.entries(metadata)) {
                    console.log(`    ${k}: ${v}`);
                }
            }
        } catch (err: any) {
            console.error(`  Error: ${err.message}`);
        }
    } else {
        console.log('\nTip: Pass an agent object ID as argument to query a specific agent');
    }
}

main().catch(console.error);
