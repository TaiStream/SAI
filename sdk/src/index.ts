// Core
export { SaiClient } from './client';

// Types
export {
    AgentCategory,
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
    TransferOwnershipParams,
    GiveFeedbackParams,
    RequestValidationParams,
    SubmitValidationParams,
    ResolveValidationParams,
    ValidationStatus,
    AgentRegisteredEvent,
    AgentUpdatedEvent,
    SessionRecordedEvent,
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
    parseSessionRecorded,
    parseFeedbackSubmitted,
    parseCredUpdated,
    parseAllCredUpdated,
    parseVisibilityTierChanged,
    parseValidationRequested,
    parseValidationResponseSubmitted,
    parseValidationResolved,
} from './events';
