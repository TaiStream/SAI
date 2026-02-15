/**
 * SAI SDK Integration Tests
 *
 * Runs against Sui testnet — requires network access.
 * Write tests require a funded wallet (set SAI_TEST_PRIVATE_KEY env var).
 */

import { SaiClient } from '../src/client';
import { TESTNET } from '../src/constants';

let passed = 0;
let failed = 0;

function assert(condition: boolean, message: string) {
    if (condition) {
        console.log(`  PASS: ${message}`);
        passed++;
    } else {
        console.error(`  FAIL: ${message}`);
        failed++;
    }
}

async function runTests() {
    console.log('=== SAI SDK Integration Tests (Testnet) ===\n');

    const sai = SaiClient.testnet();

    // Test 1: Get registry stats
    console.log('Test 1: getRegistryStats');
    try {
        const stats = await sai.getRegistryStats();
        assert(typeof stats.totalAgents === 'number', `totalAgents is number: ${stats.totalAgents}`);
        assert(typeof stats.totalActive === 'number', `totalActive is number: ${stats.totalActive}`);
        assert(typeof stats.totalFeedback === 'number', `totalFeedback is number: ${stats.totalFeedback}`);
        assert(typeof stats.totalValidations === 'number', `totalValidations is number: ${stats.totalValidations}`);
        assert(stats.totalAgents >= 0, 'totalAgents non-negative');
        console.log(`  Registry: ${stats.totalAgents} agents, ${stats.totalActive} active`);
    } catch (err: any) {
        console.error(`  FAIL: getRegistryStats threw: ${err.message}`);
        failed++;
    }

    // Test 2: isAgentRegistered for non-existent address
    console.log('\nTest 2: isAgentRegistered (non-existent)');
    try {
        const registered = await sai.isAgentRegistered('0x0000000000000000000000000000000000000000000000000000000000000001');
        assert(typeof registered === 'boolean', `Returns boolean: ${registered}`);
    } catch (err: any) {
        console.error(`  FAIL: isAgentRegistered threw: ${err.message}`);
        failed++;
    }

    // Test 3: getAgentCount for non-existent address
    console.log('\nTest 3: getAgentCount (non-existent)');
    try {
        const count = await sai.getAgentCount('0x0000000000000000000000000000000000000000000000000000000000000001');
        assert(typeof count === 'number', `Returns number: ${count}`);
        assert(count === 0, 'Count is 0 for non-existent');
    } catch (err: any) {
        console.error(`  FAIL: getAgentCount threw: ${err.message}`);
        failed++;
    }

    // Test 4: getAgent with non-existent ID should throw
    console.log('\nTest 4: getAgent (non-existent) throws');
    try {
        await sai.getAgent('0x0000000000000000000000000000000000000000000000000000000000000099');
        console.error('  FAIL: Should have thrown');
        failed++;
    } catch (err: any) {
        assert(true, `Throws for non-existent agent: ${err.message}`);
    }

    // Test 5: SuiClient accessible
    console.log('\nTest 5: SuiClient is accessible');
    {
        assert(sai.suiClient !== null, 'suiClient exposed');
        assert(sai.packageId === TESTNET.packageId, 'packageId matches TESTNET');
        assert(sai.registryId === TESTNET.registryId, 'registryId matches TESTNET');
    }

    // Summary
    console.log(`\n=== Results: ${passed} passed, ${failed} failed ===`);
    process.exit(failed > 0 ? 1 : 0);
}

runTests().catch((err) => {
    console.error('Integration test runner error:', err);
    process.exit(1);
});
