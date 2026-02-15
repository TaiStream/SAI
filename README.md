# SAI — Sui Agent Index

On-chain identity, reputation, and validation registry for AI agents on Sui.

SAI is the Sui-native equivalent of [ERC-8004](https://eips.ethereum.org/EIPS/eip-8004) (Trustless Agents). It gives any AI agent — regardless of framework, model, or origin chain — a verifiable on-chain identity with reputation tracking and third-party validation.

**Package ID:** `0xb7a80f7fdebd5d32a1108f6192dca7a252d32a8bf0a09deb7b3a6fd68e3e60cd` (Testnet)
**Registry ID:** `0x9ab1a5280e8e4eaea60487364a5125e5f16a2daa02b341df7e442aae19721edf`

## Why

AI agents are joining group chats, live streams, DeFi protocols, and games. There's no standard way to answer: *who is this agent, can I trust it, and has anyone verified it?*

ERC-8004 solved this on Ethereum. SAI solves it on Sui — with better UX.

| | ERC-8004 (Ethereum) | SAI (Sui) |
|---|---|---|
| Identity | ERC-721 token | Shared object (no wrapping needed) |
| Registration | Multiple TXs for metadata | **1 TX — fully configured** |
| Reputation | Off-chain or separate contract | On-chain cred score with auto-suspension |
| Metadata | tokenURI only | On-chain key-value pairs + agentURI |
| Composability | Requires token approval flows | Direct shared object reference |

## Architecture

Three registries in one module (mirroring ERC-8004):

```
┌─────────────────────────────────────────────────┐
│                  AgentRegistry                  │
│            (shared, one per deploy)             │
├─────────────────────────────────────────────────┤
│                                                 │
│  1. Identity ──── AgentIdentity (shared object) │
│     name, agent_uri, metadata, category, wallet │
│                                                 │
│  2. Feedback ──── AgentFeedback (owned NFT)     │
│     1-5 star rating per session, dedup on-chain │
│                                                 │
│  3. Validation ── ValidationRequest (shared)    │
│     Multi-validator attestation, min 3 required │
│                                                 │
└─────────────────────────────────────────────────┘
```

## Quick Start

### Register an Agent (1 transaction)

```bash
sui client call \
  --package $PACKAGE_ID \
  --module agent_registry \
  --function register_agent \
  --args \
    $REGISTRY_ID \
    "My Trading Agent" \
    "https://example.com/agent.json" \
    3 \
    "robot" \
    $WALLET_ADDRESS \
    '["model","a2a_endpoint","framework"]' \
    '["claude-sonnet-4-5","https://agent.example.com/a2a","langchain"]' \
    "0x6" \
  --gas-budget 10000000
```

That's it. Name, URI, category, avatar, wallet, and all metadata — one transaction.

### Give Feedback

```bash
sui client call \
  --package $PACKAGE_ID \
  --module agent_registry \
  --function give_feedback \
  --args \
    $REGISTRY_ID \
    $AGENT_ID \
    5 \
    "helpful" \
    '[]' \
    "room-abc-123" \
    "0x6" \
  --gas-budget 10000000
```

### Read Agent On-Chain

```typescript
import { SuiClient } from '@mysten/sui/client';

const client = new SuiClient({ url: 'https://fullnode.testnet.sui.io' });

const agent = await client.getObject({
  id: AGENT_OBJECT_ID,
  options: { showContent: true },
});

const fields = agent.data.content.fields;
console.log(fields.name);       // "My Trading Agent"
console.log(fields.cred_score); // 70
console.log(fields.metadata);   // { model: "claude-sonnet-4-5", ... }
```

## Categories

Broad taxonomy — any agent type should fit.

| ID | Category | Examples |
|----|----------|----------|
| 0 | General / multi-purpose | Chatbot, assistant, copilot |
| 1 | Communication | Translator, transcriber, meeting agent |
| 2 | Moderation / safety | Content filter, compliance, anti-spam |
| 3 | DeFi / trading | Portfolio manager, swap agent, yield optimizer |
| 4 | Data / analytics | Indexer, oracle, researcher |
| 5 | Creative | Image gen, music, writing, design |
| 6 | Gaming | NPC, companion, game master |
| 7 | Infrastructure | Relayer, bridge operator, validator |
| 8 | Social | Reputation, matching, recommendation |
| 9 | Custom / other | Anything not covered above |

## Cred System

Agents start at **cred 70** (Standard tier). Reputation is earned, not given.

| Tier | Cred Range | Effect |
|------|-----------|--------|
| Pristine | 90-100 | Featured in discovery, priority placement |
| Standard | 70-89 | Normal visibility, full access |
| Restricted | 50-69 | Hidden from discovery, direct access only |
| Probation | 30-49 | Limited functionality, owner action required |
| Suspended | 0-29 | **Auto-deactivated**, cannot join rooms |

### How Cred Changes

| Action | Impact | Rationale |
|--------|--------|-----------|
| Positive feedback (4-5 stars) | +1 | Slow, steady trust building |
| Negative feedback (1-2 stars) | -3 | Asymmetric — bad behavior punished harder |
| Neutral feedback (3 stars) | 0 | No change |
| Validation pass (avg >= 60) | +2 | Third-party attestation is valuable |
| Validation fail (avg < 60) | -10 | Strong signal of untrustworthiness |

## Validation

Third-party attestation for high-stakes trust decisions. Requires **3+ independent validators** to prevent Sybil attacks.

```
Agent Owner                    Validators
     │                              │
     ├── request_validation() ──►   │
     │                              ├── submit_validation(score, tag)
     │                              ├── submit_validation(score, tag)
     │                              ├── submit_validation(score, tag)
     │                              │
     ├── resolve_validation() ──►   │
     │   (avg >= 60 = PASS)         │
     │   (avg < 60  = FAIL)         │
```

## Entry Functions

### Identity
| Function | Description |
|----------|-------------|
| `register_agent` | Register with full config in 1 TX |
| `set_agent_name` | Update display name |
| `set_agent_uri` | Update off-chain registration JSON URI |
| `set_metadata` | Set a single metadata key-value pair |
| `set_metadata_batch` | Set multiple metadata pairs in 1 TX |
| `remove_metadata` | Remove a metadata key |
| `set_agent_wallet` | Update payment wallet address |
| `transfer_ownership` | Transfer agent to new owner |
| `deactivate_agent` | Voluntarily take agent offline |
| `reactivate_agent` | Bring agent back online (if not suspended) |
| `unregister_agent` | Permanently deactivate and remove from registry |
| `record_session` | Record a session participation |

### Feedback
| Function | Description |
|----------|-------------|
| `give_feedback` | Submit 1-5 star rating (one per session per user) |

### Validation
| Function | Description |
|----------|-------------|
| `request_validation` | Create a validation request |
| `submit_validation` | Validator submits score (0-100) |
| `resolve_validation` | Finalize after 3+ validators respond |

### View Functions
| Function | Returns |
|----------|---------|
| `get_agent_cred` | Current cred score (0-100) |
| `get_agent_visibility_tier` | Tier (0=Pristine → 4=Suspended) |
| `is_agent_active` | Whether agent is active |
| `can_join_room` | Active AND not suspended |
| `get_agent_stats` | (cred, sessions, feedback, positive, active) |
| `get_agent_metadata` | Reference to full metadata VecMap |
| `get_metadata_value` | Single metadata value by key |
| `get_registry_stats` | (total_agents, active, feedback, validations) |

## Agent URI Schema

The `agent_uri` should point to a JSON file following this structure:

```json
{
  "name": "My Agent",
  "description": "A helpful trading assistant",
  "image": "https://example.com/avatar.png",
  "capabilities": ["swap", "portfolio-analysis", "price-alerts"],
  "endpoints": {
    "a2a": "https://agent.example.com/a2a",
    "mcp": "https://agent.example.com/mcp"
  },
  "model": {
    "provider": "anthropic",
    "name": "claude-sonnet-4-5",
    "version": "20250929"
  },
  "trust": {
    "source_chain": "sui",
    "registry_id": "0x...",
    "agent_id": "0x..."
  }
}
```

## License

MIT
