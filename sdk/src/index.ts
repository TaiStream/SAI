// Core
export { SaiClient } from './client';

// Types
export {
    VisibilityTier,
} from './types';

export type {
    SaiConfig,
    Agent,
    AgentStats,
    RegistryStats,
    RegisterAgentParams,
    SetAgentNameParams,
    SetAgentUriParams,
    SetMetadataParams,
    RemoveMetadataParams,
    SetMetadataBatchParams,
    AddDelegateParams,
    RemoveDelegateParams,
    TransferOwnershipParams,
    GiveFeedbackParams,
    RequestValidationParams,
    SubmitValidationParams,
    ResolveValidationParams,
    ValidationStatus,
    AgentRegisteredEvent,
    AgentUpdatedEvent,
    FeedbackSubmittedEvent,
    CredUpdatedEvent,
    VisibilityTierChangedEvent,
    ValidationRequestedEvent,
    ValidationResponseSubmittedEvent,
    ValidationResolvedEvent,
} from './types';

// Constants
export { TESTNET, MAINNET, DEVNET, MODULE_NAME, SUI_CLOCK_OBJECT_ID } from './constants';

// Event parsers
export {
    parseAgentRegistered,
    parseAgentUpdated,
    parseFeedbackSubmitted,
    parseCredUpdated,
    parseAllCredUpdated,
    parseVisibilityTierChanged,
    parseValidationRequested,
    parseValidationResponseSubmitted,
    parseValidationResolved,
} from './events';

// Auth (8128-style signed HTTP requests)
export * as SaiAuth from './auth';
export {
    createSignableRequest,
    serializeCanonicalRequest,
    sha256Hex,
    signCanonicalRequest,
    signHttpRequest,
    verifySignedRequest,
} from './auth';
export type {
    HttpMethod,
    SignableRequestInput,
    CanonicalRequest,
    SignedHttpRequest,
    PersonalMessageSigner,
    VerifyOptions,
    VerifyResult,
} from './auth';

// Integration (optional policy bridge: signed request + SAI cred/tier checks)
export { SaiPolicyGuard } from './integration';
export type {
    SaiPolicy,
    AuthorizeInput,
    AuthorizeDecision,
} from './integration';
