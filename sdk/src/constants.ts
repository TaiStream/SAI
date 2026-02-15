/**
 * Network presets for SAI deployments.
 * Zero-config: SaiClient.testnet() uses TESTNET constants automatically.
 */

export const TESTNET = {
    packageId: '0xb7a80f7fdebd5d32a1108f6192dca7a252d32a8bf0a09deb7b3a6fd68e3e60cd',
    registryId: '0x9ab1a5280e8e4eaea60487364a5125e5f16a2daa02b341df7e442aae19721edf',
    network: 'testnet' as const,
};

export const MAINNET = {
    packageId: '', // TBD on mainnet deployment
    registryId: '',
    network: 'mainnet' as const,
};

export const DEVNET = {
    packageId: '', // TBD
    registryId: '',
    network: 'devnet' as const,
};

/** Module name in the deployed package */
export const MODULE_NAME = 'agent_registry';

/** Clock object used by all entry functions */
export const SUI_CLOCK_OBJECT_ID = '0x0000000000000000000000000000000000000000000000000000000000000006';
