/**
 * SAI SDK Unit Tests
 *
 * Tests transaction construction, type parsing, and event parsing.
 * Does NOT require network access — all tests use mocked data.
 */

import { SaiClient } from '../src/client';
import { AgentCategory, VisibilityTier } from '../src/types';
import { TESTNET, MODULE_NAME, SUI_CLOCK_OBJECT_ID } from '../src/constants';
import {
    parseAgentRegistered,
    parseSessionRecorded,
    parseFeedbackSubmitted,
    parseCredUpdated,
    parseValidationResolved,
    parseVisibilityTierChanged,
    parseAgentUpdated,
} from '../src/events';

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

function runTests() {
    console.log('=== SAI SDK Unit Tests ===\n');

    // --- Factory constructors ---
    console.log('Test 1: Factory constructors');
    {
        const client = SaiClient.testnet();
        assert(client.packageId === TESTNET.packageId, 'testnet() sets correct packageId');
        assert(client.registryId === TESTNET.registryId, 'testnet() sets correct registryId');
        assert(client.suiClient !== null, 'testnet() creates SuiClient');
    }

    // --- Custom config ---
    console.log('\nTest 2: Custom config');
    {
        const client = new SaiClient({
            packageId: '0xcustom',
            registryId: '0xregistry',
            network: 'testnet',
        });
        assert(client.packageId === '0xcustom', 'Custom packageId');
        assert(client.registryId === '0xregistry', 'Custom registryId');
    }

    // --- Transaction: registerAgent ---
    console.log('\nTest 3: registerAgent transaction');
    {
        const client = SaiClient.testnet();
        const tx = client.registerAgent({
            name: 'Test Agent',
            agentUri: 'https://example.com/agent.json',
            category: AgentCategory.Communication,
            avatarStyle: 'robot',
            metadataKeys: ['model'],
            metadataValues: ['claude'],
        });
        assert(tx !== null, 'Returns Transaction object');
        // Verify it serializes without error
        const data = tx.getData();
        assert(data !== null, 'Transaction has data');
    }

    // --- Transaction: setAgentName ---
    console.log('\nTest 4: setAgentName transaction');
    {
        const client = SaiClient.testnet();
        const tx = client.setAgentName({
            agentObjectId: '0xagent123',
            name: 'New Name',
        });
        assert(tx !== null, 'Returns Transaction object');
    }

    // --- Transaction: setAgentUri ---
    console.log('\nTest 5: setAgentUri transaction');
    {
        const client = SaiClient.testnet();
        const tx = client.setAgentUri({
            agentObjectId: '0xagent123',
            agentUri: 'https://new-uri.com/agent.json',
        });
        assert(tx !== null, 'Returns Transaction object');
    }

    // --- Transaction: setMetadata ---
    console.log('\nTest 6: setMetadata transaction');
    {
        const client = SaiClient.testnet();
        const tx = client.setMetadata({
            agentObjectId: '0xagent123',
            key: 'model',
            value: 'claude-haiku',
        });
        assert(tx !== null, 'Returns Transaction object');
    }

    // --- Transaction: setMetadataBatch ---
    console.log('\nTest 7: setMetadataBatch transaction');
    {
        const client = SaiClient.testnet();
        const tx = client.setMetadataBatch({
            agentObjectId: '0xagent123',
            keys: ['model', 'version'],
            values: ['claude', '1.0'],
        });
        assert(tx !== null, 'Returns Transaction object');
    }

    // --- Transaction: removeMetadata ---
    console.log('\nTest 8: removeMetadata transaction');
    {
        const client = SaiClient.testnet();
        const tx = client.removeMetadata({
            agentObjectId: '0xagent123',
            key: 'deprecated_key',
        });
        assert(tx !== null, 'Returns Transaction object');
    }

    // --- Transaction: setAgentWallet ---
    console.log('\nTest 9: setAgentWallet transaction');
    {
        const client = SaiClient.testnet();
        const tx = client.setAgentWallet('0xagent123', '0x0000000000000000000000000000000000000000000000000000000000000002');
        assert(tx !== null, 'Returns Transaction object');
    }

    // --- Transaction: transferOwnership ---
    console.log('\nTest 10: transferOwnership transaction');
    {
        const client = SaiClient.testnet();
        const tx = client.transferOwnership({
            agentObjectId: '0xagent123',
            newOwner: '0x0000000000000000000000000000000000000000000000000000000000000003',
        });
        assert(tx !== null, 'Returns Transaction object');
    }

    // --- Transaction: deactivateAgent ---
    console.log('\nTest 11: deactivateAgent transaction');
    {
        const client = SaiClient.testnet();
        const tx = client.deactivateAgent('0xagent123');
        assert(tx !== null, 'Returns Transaction object');
    }

    // --- Transaction: reactivateAgent ---
    console.log('\nTest 12: reactivateAgent transaction');
    {
        const client = SaiClient.testnet();
        const tx = client.reactivateAgent('0xagent123');
        assert(tx !== null, 'Returns Transaction object');
    }

    // --- Transaction: unregisterAgent ---
    console.log('\nTest 13: unregisterAgent transaction');
    {
        const client = SaiClient.testnet();
        const tx = client.unregisterAgent('0xagent123');
        assert(tx !== null, 'Returns Transaction object');
    }

    // --- Transaction: recordSession ---
    console.log('\nTest 14: recordSession transaction');
    {
        const client = SaiClient.testnet();
        const tx = client.recordSession('0xagent123', 'room-abc-123');
        assert(tx !== null, 'Returns Transaction object');
    }

    // --- Transaction: giveFeedback ---
    console.log('\nTest 15: giveFeedback transaction');
    {
        const client = SaiClient.testnet();
        const tx = client.giveFeedback({
            agentObjectId: '0xagent123',
            value: 5,
            tag: 'translation',
            commentHash: new Uint8Array(32),
            sessionId: new TextEncoder().encode('room-abc'),
        });
        assert(tx !== null, 'Returns Transaction object');
    }

    // --- Transaction: requestValidation ---
    console.log('\nTest 16: requestValidation transaction');
    {
        const client = SaiClient.testnet();
        const tx = client.requestValidation({
            agentObjectId: '0xagent123',
            requestUri: 'https://validation.com/request',
            requestHash: new Uint8Array(32),
        });
        assert(tx !== null, 'Returns Transaction object');
    }

    // --- Transaction: submitValidation ---
    console.log('\nTest 17: submitValidation transaction');
    {
        const client = SaiClient.testnet();
        const tx = client.submitValidation({
            requestObjectId: '0xrequest123',
            score: 85,
            tag: 'automated',
        });
        assert(tx !== null, 'Returns Transaction object');
    }

    // --- Transaction: resolveValidation ---
    console.log('\nTest 18: resolveValidation transaction');
    {
        const client = SaiClient.testnet();
        const tx = client.resolveValidation({
            agentObjectId: '0xagent123',
            requestObjectId: '0xrequest123',
        });
        assert(tx !== null, 'Returns Transaction object');
    }

    // --- Event parsing: AgentRegistered ---
    console.log('\nTest 19: parseAgentRegistered');
    {
        const effects = {
            events: [{
                type: `${TESTNET.packageId}::agent_registry::AgentRegistered`,
                parsedJson: {
                    agent_id: '0xagent1',
                    owner: '0xowner1',
                    name: 'Test Agent',
                    category: 1,
                    timestamp: 1700000000,
                },
            }],
        };
        const event = parseAgentRegistered(effects, TESTNET.packageId);
        assert(event !== null, 'Event parsed');
        assert(event!.agentId === '0xagent1', 'Correct agentId');
        assert(event!.owner === '0xowner1', 'Correct owner');
        assert(event!.name === 'Test Agent', 'Correct name');
        assert(event!.category === 1, 'Correct category');
        assert(event!.timestamp === 1700000000, 'Correct timestamp');
    }

    // --- Event parsing: SessionRecorded ---
    console.log('\nTest 20: parseSessionRecorded');
    {
        const effects = {
            events: [{
                type: `${TESTNET.packageId}::agent_registry::SessionRecorded`,
                parsedJson: {
                    agent_id: '0xagent1',
                    session_id: 'room-xyz',
                    timestamp: 1700000001,
                },
            }],
        };
        const event = parseSessionRecorded(effects, TESTNET.packageId);
        assert(event !== null, 'Event parsed');
        assert(event!.sessionId === 'room-xyz', 'Correct sessionId');
    }

    // --- Event parsing: FeedbackSubmitted ---
    console.log('\nTest 21: parseFeedbackSubmitted');
    {
        const effects = {
            events: [{
                type: `${TESTNET.packageId}::agent_registry::FeedbackSubmitted`,
                parsedJson: {
                    feedback_id: 42,
                    agent_id: '0xagent1',
                    client: '0xclient1',
                    value: 5,
                    tag: 'translation',
                    session_id: 'room-abc',
                },
            }],
        };
        const event = parseFeedbackSubmitted(effects, TESTNET.packageId);
        assert(event !== null, 'Event parsed');
        assert(event!.feedbackId === 42, 'Correct feedbackId');
        assert(event!.value === 5, 'Correct value');
    }

    // --- Event parsing: CredUpdated ---
    console.log('\nTest 22: parseCredUpdated');
    {
        const effects = {
            events: [{
                type: `${TESTNET.packageId}::agent_registry::CredUpdated`,
                parsedJson: {
                    agent_id: '0xagent1',
                    old_cred: 70,
                    new_cred: 71,
                    reason: 'feedback',
                },
            }],
        };
        const event = parseCredUpdated(effects, TESTNET.packageId);
        assert(event !== null, 'Event parsed');
        assert(event!.oldCred === 70, 'Correct oldCred');
        assert(event!.newCred === 71, 'Correct newCred');
        assert(event!.reason === 'feedback', 'Correct reason');
    }

    // --- Event parsing: ValidationResolved ---
    console.log('\nTest 23: parseValidationResolved');
    {
        const effects = {
            events: [{
                type: `${TESTNET.packageId}::agent_registry::ValidationResolved`,
                parsedJson: {
                    request_id: 1,
                    agent_id: '0xagent1',
                    passed: true,
                    avg_score: 85,
                },
            }],
        };
        const event = parseValidationResolved(effects, TESTNET.packageId);
        assert(event !== null, 'Event parsed');
        assert(event!.passed === true, 'Correct passed');
        assert(event!.averageScore === 85, 'Correct averageScore');
    }

    // --- Event parsing: VisibilityTierChanged ---
    console.log('\nTest 24: parseVisibilityTierChanged');
    {
        const effects = {
            events: [{
                type: `${TESTNET.packageId}::agent_registry::VisibilityTierChanged`,
                parsedJson: {
                    agent_id: '0xagent1',
                    old_tier: 1,
                    new_tier: 0,
                },
            }],
        };
        const event = parseVisibilityTierChanged(effects, TESTNET.packageId);
        assert(event !== null, 'Event parsed');
        assert(event!.oldTier === 1, 'Correct oldTier');
        assert(event!.newTier === 0, 'Correct newTier');
    }

    // --- Event parsing: AgentUpdated ---
    console.log('\nTest 25: parseAgentUpdated');
    {
        const effects = {
            events: [{
                type: `${TESTNET.packageId}::agent_registry::AgentUpdated`,
                parsedJson: {
                    agent_id: '0xagent1',
                    field: 'name',
                    timestamp: 1700000002,
                },
            }],
        };
        const event = parseAgentUpdated(effects, TESTNET.packageId);
        assert(event !== null, 'Event parsed');
        assert(event!.field === 'name', 'Correct field');
    }

    // --- Event parsing: null when not present ---
    console.log('\nTest 26: Event parsers return null for missing events');
    {
        const emptyEffects = { events: [] };
        assert(parseAgentRegistered(emptyEffects, TESTNET.packageId) === null, 'AgentRegistered null');
        assert(parseSessionRecorded(emptyEffects, TESTNET.packageId) === null, 'SessionRecorded null');
        assert(parseFeedbackSubmitted(emptyEffects, TESTNET.packageId) === null, 'FeedbackSubmitted null');
        assert(parseCredUpdated(emptyEffects, TESTNET.packageId) === null, 'CredUpdated null');
        assert(parseValidationResolved(emptyEffects, TESTNET.packageId) === null, 'ValidationResolved null');
    }

    // --- Enums ---
    console.log('\nTest 27: Enum values');
    {
        assert(AgentCategory.General === 0, 'General = 0');
        assert(AgentCategory.Communication === 1, 'Communication = 1');
        assert(AgentCategory.Custom === 9, 'Custom = 9');
        assert(VisibilityTier.Pristine === 0, 'Pristine = 0');
        assert(VisibilityTier.Suspended === 4, 'Suspended = 4');
    }

    // --- Constants ---
    console.log('\nTest 28: Constants');
    {
        assert(TESTNET.packageId.startsWith('0x'), 'Package ID is hex');
        assert(TESTNET.registryId.startsWith('0x'), 'Registry ID is hex');
        assert(MODULE_NAME === 'agent_registry', 'Module name correct');
        assert(SUI_CLOCK_OBJECT_ID.startsWith('0x'), 'Clock object is hex');
    }

    // --- registerAgent with no optional params ---
    console.log('\nTest 29: registerAgent minimal params');
    {
        const client = SaiClient.testnet();
        const tx = client.registerAgent({
            name: 'Minimal Agent',
            agentUri: 'https://min.com/agent.json',
            category: AgentCategory.General,
            avatarStyle: '',
        });
        assert(tx !== null, 'Minimal registration works');
    }

    // --- New Network Constructor ---
    console.log('\nTest 30: Constructor with network only');
    {
        const client = new SaiClient({ network: 'testnet' });
        assert(client.packageId === TESTNET.packageId, 'Constructor auto-filled testnet packageId');
        assert(client.registryId === TESTNET.registryId, 'Constructor auto-filled testnet registryId');

        try {
            new SaiClient({ network: 'mainnet' });
            assert(false, 'Should throw for mainnet with empty constants');
        } catch (e) {
            assert(true, 'Correctly threw error for incomplete mainnet config');
        }
    }

    // Summary
    console.log(`\n=== Results: ${passed} passed, ${failed} failed ===`);
    process.exit(failed > 0 ? 1 : 0);
}

runTests();
