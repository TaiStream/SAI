import type { SuiClient } from '@mysten/sui/client';

// --- Config ---

export interface SaiConfig {
    /** Bring your own SuiClient, or the SDK creates one from `network` */
    suiClient?: SuiClient;
    /** Deployed package ID (optional if network matches a preset) */
    packageId?: string;
    /** Shared AgentRegistry object ID (optional if network matches a preset) */
    registryId?: string;
    /** Network name (used to create SuiClient and load presets) */
    network?: 'testnet' | 'mainnet' | 'devnet';
}

// --- Agent ---

export interface Agent {
    objectId: string;
    owner: string;
    name: string;
    agentUri: string;
    wallet: string;
    credScore: number;
    totalFeedbackReceived: number;
    positiveFeedback: number;
    negativeFeedback: number;
    delegates: string[];
    isActive: boolean;
    registeredAt: number;
}

export interface AgentStats {
    credScore: number;
    totalFeedbackReceived: number;
    positiveFeedback: number;
    isActive: boolean;
}

// --- Enums ---

export enum VisibilityTier {
    Pristine = 0,
    Standard = 1,
    Restricted = 2,
    Probation = 3,
    Suspended = 4,
}

// --- Registry ---

export interface RegistryStats {
    totalAgents: number;
    totalActive: number;
    totalFeedback: number;
    totalValidations: number;
}

// --- Params ---

export interface RegisterAgentParams {
    name: string;
    agentUri: string;
    /** Wallet address for tips/payments. Defaults to sender if omitted. */
    wallet?: string;
    metadataKeys?: string[];
    metadataValues?: string[];
}

export interface SetAgentNameParams {
    agentObjectId: string;
    name: string;
}

export interface SetAgentUriParams {
    agentObjectId: string;
    agentUri: string;
}

export interface SetMetadataParams {
    agentObjectId: string;
    key: string;
    value: string;
}

export interface RemoveMetadataParams {
    agentObjectId: string;
    key: string;
}

export interface SetMetadataBatchParams {
    agentObjectId: string;
    keys: string[];
    values: string[];
}

export interface AddDelegateParams {
    agentObjectId: string;
    /** Address to authorize as a delegate */
    delegateAddress: string;
}

export interface RemoveDelegateParams {
    agentObjectId: string;
    /** Address to remove from delegates */
    delegateAddress: string;
}

export interface TransferOwnershipParams {
    agentObjectId: string;
    newOwner: string;
}

export interface GiveFeedbackParams {
    agentObjectId: string;
    /** Star rating (1-5) */
    value: 1 | 2 | 3 | 4 | 5;
    /** Category tag for the interaction */
    tag: string;
    /** KECCAK-256 hash of optional off-chain comment */
    commentHash: Uint8Array | number[];
    /** Interaction identifier (used for dedup) */
    interactionId: Uint8Array | number[];
}

export interface RequestValidationParams {
    agentObjectId: string;
    /** URI pointing to validation request details/criteria */
    requestUri: string;
    /** Hash of the request content */
    requestHash: Uint8Array | number[];
}

export interface SubmitValidationParams {
    /** ValidationRequest object ID */
    requestObjectId: string;
    /** Assessment score (0-100) */
    score: number;
    /** Category tag for the validation method */
    tag: string;
}

export interface ResolveValidationParams {
    agentObjectId: string;
    /** ValidationRequest object ID */
    requestObjectId: string;
}

// --- Validation ---

export interface ValidationStatus {
    status: 'pending' | 'passed' | 'failed';
    averageScore: number;
    validatorCount: number;
}

// --- Events ---

export interface AgentRegisteredEvent {
    agentId: string;
    owner: string;
    name: string;
    timestamp: number;
}

export interface AgentUpdatedEvent {
    agentId: string;
    field: string;
    timestamp: number;
}

export interface FeedbackSubmittedEvent {
    feedbackId: number;
    agentId: string;
    client: string;
    value: number;
    tag: string;
    sessionId: string;
}

export interface CredUpdatedEvent {
    agentId: string;
    oldCred: number;
    newCred: number;
    reason: string;
}

export interface VisibilityTierChangedEvent {
    agentId: string;
    oldTier: number;
    newTier: number;
}

export interface ValidationRequestedEvent {
    requestId: number;
    agentId: string;
    requestUri: string;
}

export interface ValidationResponseSubmittedEvent {
    requestId: number;
    validator: string;
    score: number;
    tag: string;
}

export interface ValidationResolvedEvent {
    requestId: number;
    agentId: string;
    passed: boolean;
    averageScore: number;
}
