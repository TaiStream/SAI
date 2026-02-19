/**
 * Transaction event parsers.
 *
 * After executing a transaction, pass the result to these parsers
 * to extract typed event data without manual Move event parsing.
 */

import type {
    AgentRegisteredEvent,
    AgentUpdatedEvent,
    FeedbackSubmittedEvent,
    CredUpdatedEvent,
    VisibilityTierChangedEvent,
    ValidationRequestedEvent,
    ValidationResponseSubmittedEvent,
    ValidationResolvedEvent,
} from './types';

/** Raw Sui event from transaction effects */
interface SuiEvent {
    type: string;
    parsedJson?: Record<string, any>;
}

/** Transaction effects containing events */
interface TransactionEffects {
    events?: SuiEvent[];
}

function findEvent(effects: TransactionEffects, packageId: string, eventName: string): Record<string, any> | null {
    if (!effects.events) return null;
    const suffix = `::agent_registry::${eventName}`;
    const event = effects.events.find((e) => e.type.endsWith(suffix) || e.type.includes(suffix));
    return event?.parsedJson ?? null;
}

function findAllEvents(effects: TransactionEffects, packageId: string, eventName: string): Record<string, any>[] {
    if (!effects.events) return [];
    const suffix = `::agent_registry::${eventName}`;
    return effects.events
        .filter((e) => e.type.endsWith(suffix) || e.type.includes(suffix))
        .map((e) => e.parsedJson!)
        .filter(Boolean);
}

export function parseAgentRegistered(effects: TransactionEffects, packageId: string): AgentRegisteredEvent | null {
    const data = findEvent(effects, packageId, 'AgentRegistered');
    if (!data) return null;
    return {
        agentId: String(data.agent_id),
        owner: String(data.owner),
        name: String(data.name),
        timestamp: Number(data.timestamp),
    };
}

export function parseAgentUpdated(effects: TransactionEffects, packageId: string): AgentUpdatedEvent | null {
    const data = findEvent(effects, packageId, 'AgentUpdated');
    if (!data) return null;
    return {
        agentId: String(data.agent_id),
        field: String(data.field),
        timestamp: Number(data.timestamp),
    };
}

export function parseFeedbackSubmitted(effects: TransactionEffects, packageId: string): FeedbackSubmittedEvent | null {
    const data = findEvent(effects, packageId, 'FeedbackSubmitted');
    if (!data) return null;
    return {
        feedbackId: Number(data.feedback_id),
        agentId: String(data.agent_id),
        client: String(data.client),
        value: Number(data.value),
        tag: String(data.tag),
        sessionId: String(data.session_id),
    };
}

export function parseCredUpdated(effects: TransactionEffects, packageId: string): CredUpdatedEvent | null {
    const data = findEvent(effects, packageId, 'CredUpdated');
    if (!data) return null;
    return {
        agentId: String(data.agent_id),
        oldCred: Number(data.old_cred),
        newCred: Number(data.new_cred),
        reason: String(data.reason),
    };
}

export function parseAllCredUpdated(effects: TransactionEffects, packageId: string): CredUpdatedEvent[] {
    return findAllEvents(effects, packageId, 'CredUpdated').map((data) => ({
        agentId: String(data.agent_id),
        oldCred: Number(data.old_cred),
        newCred: Number(data.new_cred),
        reason: String(data.reason),
    }));
}

export function parseVisibilityTierChanged(effects: TransactionEffects, packageId: string): VisibilityTierChangedEvent | null {
    const data = findEvent(effects, packageId, 'VisibilityTierChanged');
    if (!data) return null;
    return {
        agentId: String(data.agent_id),
        oldTier: Number(data.old_tier),
        newTier: Number(data.new_tier),
    };
}

export function parseValidationRequested(effects: TransactionEffects, packageId: string): ValidationRequestedEvent | null {
    const data = findEvent(effects, packageId, 'ValidationRequested');
    if (!data) return null;
    return {
        requestId: Number(data.request_id),
        agentId: String(data.agent_id),
        requestUri: String(data.request_uri),
    };
}

export function parseValidationResponseSubmitted(effects: TransactionEffects, packageId: string): ValidationResponseSubmittedEvent | null {
    const data = findEvent(effects, packageId, 'ValidationResponseSubmitted');
    if (!data) return null;
    return {
        requestId: Number(data.request_id),
        validator: String(data.validator),
        score: Number(data.score),
        tag: String(data.tag),
    };
}

export function parseValidationResolved(effects: TransactionEffects, packageId: string): ValidationResolvedEvent | null {
    const data = findEvent(effects, packageId, 'ValidationResolved');
    if (!data) return null;
    return {
        requestId: Number(data.request_id),
        agentId: String(data.agent_id),
        passed: Boolean(data.passed),
        averageScore: Number(data.avg_score),
    };
}
