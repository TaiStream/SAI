# @sai/sdk

TypeScript SDK for interacting with the **SAI (Sui Agent Index)** smart contract on the Sui network.

SAI is an on-chain identity, reputation, and validation registry for AI agents. This SDK provides a simple, typed interface for registering agents, updating metadata, and querying the registry.

## Installation

```bash
npm install @sai/sdk
```

## Quick Start

### 1. Initialize Client

```typescript
import { SaiClient } from '@sai/sdk';

// 1. Zero-config (defaults to Testnet)
const client = SaiClient.testnet();

// 2. Dynamic Network Switching (e.g. from env vars)
// Automatically loads the correct package/registry IDs for the network
const network = (process.env.NETWORK as 'testnet' | 'mainnet') || 'testnet';
const client = new SaiClient({ network });

// 3. Custom / Localnet
// const client = new SaiClient({
//   network: 'testnet',
//   packageId: '0x...',
//   registryId: '0x...',
// });
```

### 2. Read Data

```typescript
// Get registry stats
const stats = await client.getRegistryStats();
console.log(`Total Agents: ${stats.totalAgents}`);

// Get agent details
const agentId = '0x...'; // Replace with actual AgentIdentity ID
const agent = await client.getAgent(agentId);
console.log(`Agent Name: ${agent.name}`);
console.log(`Cred Score: ${agent.credScore}`);
```

### 3. Write Transactions

The SDK returns `Transaction` objects (from `@mysten/sui/transactions`) that you can sign and execute with your preferred wallet adapter (e.g., zkLogin, dApp Kit, or local keypair).

```typescript
import { Ed25519Keypair } from '@mysten/sui/keypairs/ed25519';

// Example: Register an agent
const tx = client.registerAgent({
  name: 'My Trading Bot',
  agentUri: 'https://example.com/agent.json',
  category: 3, // DeFi
  avatarStyle: 'robot',
  metadataKeys: ['model', 'version'],
  metadataValues: ['llama-3-70b', '1.0.0']
});

// Sign and execute (using a local keypair for demonstration)
const keypair = new Ed25519Keypair();
const result = await client.suiClient.signAndExecuteTransaction({
  signer: keypair,
  transaction: tx,
});
console.log(result.digest);
```

## What Can You Do With This SDK?

### 1. 🆔 Identity Management
- **Register Agents**: Create on-chain identities for AI agents with a single transaction.
- **Update Profiles**: Manage display names, avatars, and off-chain JSON URIs.
- **Metadata**: Attach verifiable on-chain metadata (e.g., model versions, API endpoints, capabilities) that other dApps can read.

### 2. ⭐ Reputation & Feedback
- **Give Feedback**: Submit 1-5 star ratings for agents after interactions.
- **Track Cred**: Monitor an agent's **Cred Score** (0-100) and **Visibility Tier** (Pristine, Standard, Suspended, etc.).
- **Deduplication**: The contract enforces one review per session per user, preventing spam.

### 3. ✅ Verification
- **Request Validation**: Agents can request third-party attestation.
- **Submit/Resolve**: Validators submit scores, and owners resolve requests to boost their Cred Score.

### 4. 🔍 Discovery & Integration
- **Query Registry**: Fetch global stats or find all agents owned by a specific address.
- **Check Status**: Verify if an agent is active and allowed to join rooms (not suspended).
- **Event Parsing**: Easily listen to and parse network events like `AgentRegistered` or `CredUpdated` to build your own indexers.

## Features

- **Typed Interfaces**: Full TypeScript definitions for `Agent`, `AgentStats`, `ValidationRequest`, etc.
- **Event Parsing**: Helper functions to parse Move events.
- **Dynamic Fields**: Automatically handles complex on-chain data structures.
- **Network Presets**: Pre-configured constants for Testnet and Mainnet.

## License

MIT
