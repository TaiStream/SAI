import { SuiClient, getFullnodeUrl } from '@mysten/sui/client';
import { Transaction } from '@mysten/sui/transactions';
import { bcs } from '@mysten/sui/bcs';
import { TESTNET, MAINNET, DEVNET, MODULE_NAME, SUI_CLOCK_OBJECT_ID } from './constants';
import type {
    SaiConfig,
    Agent,
    AgentStats,
    RegistryStats,
    ValidationStatus,
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
} from './types';
import { AgentCategory, VisibilityTier } from './types';

export class SaiClient {
    readonly suiClient: SuiClient;
    readonly packageId: string;
    readonly registryId: string;

    // --- Factory constructors ---

    static testnet(): SaiClient {
        return new SaiClient(TESTNET);
    }

    static mainnet(): SaiClient {
        return new SaiClient(MAINNET);
    }

    static devnet(): SaiClient {
        return new SaiClient(DEVNET);
    }

    constructor(config: SaiConfig) {
        const network = config.network ?? 'testnet';

        // Auto-fill IDs from presets if not provided
        if (!config.packageId || !config.registryId) {
            let preset;
            switch (network) {
                case 'testnet': preset = TESTNET; break;
                case 'mainnet': preset = MAINNET; break;
                case 'devnet': preset = DEVNET; break;
                default: preset = TESTNET;
            }

            this.packageId = config.packageId ?? preset.packageId;
            this.registryId = config.registryId ?? preset.registryId;
        } else {
            this.packageId = config.packageId;
            this.registryId = config.registryId;
        }

        // Validate that we have IDs (mainnet/devnet might be empty in constants)
        if (!this.packageId || !this.registryId) {
            throw new Error(`SaiClient: Missing packageId or registryId. configuration for '${network}' might be incomplete.`);
        }

        if (config.suiClient) {
            this.suiClient = config.suiClient;
        } else {
            this.suiClient = new SuiClient({ url: getFullnodeUrl(network) });
        }
    }

    // ============================================
    // MOVE CALL TARGET HELPER
    // ============================================

    private target(fn: string): `${string}::${string}::${string}` {
        return `${this.packageId}::${MODULE_NAME}::${fn}`;
    }

    // ============================================
    // READ FUNCTIONS
    // ============================================

    /** Fetch a full Agent from an AgentIdentity object ID */
    async getAgent(agentObjectId: string): Promise<Agent> {
        const obj = await this.suiClient.getObject({
            id: agentObjectId,
            options: { showContent: true, showOwner: true },
        });

        if (!obj.data?.content || obj.data.content.dataType !== 'moveObject') {
            throw new Error(`Agent not found: ${agentObjectId}`);
        }

        const fields = obj.data.content.fields as Record<string, any>;
        return this.parseAgentFields(agentObjectId, fields);
    }

    /** Get all agent object IDs owned by an address via the registry */
    async getAgentsByOwner(ownerAddress: string): Promise<Agent[]> {
        // Query owned objects of type AgentIdentity
        const objects = await this.suiClient.getOwnedObjects({
            owner: ownerAddress,
            filter: {
                StructType: `${this.packageId}::${MODULE_NAME}::AgentIdentity`,
            },
            options: { showContent: true },
        });

        // AgentIdentity is a shared object, so we can't use getOwnedObjects directly.
        // Instead, query the registry's Table to get agent IDs, then fetch each.
        // For now, use dynamic field lookup on the registry.
        const registryObj = await this.suiClient.getObject({
            id: this.registryId,
            options: { showContent: true },
        });

        if (!registryObj.data?.content || registryObj.data.content.dataType !== 'moveObject') {
            throw new Error('Registry not found');
        }

        // Look up the dynamic field for this owner in the agents Table
        const agentIds = await this.getAgentIdsFromRegistry(ownerAddress);
        if (agentIds.length === 0) return [];

        // Fetch each agent in parallel
        const agents = await Promise.all(
            agentIds.map((id) => this.getAgent(id))
        );
        return agents;
    }

    /** Get agent metadata as key-value record */
    async getAgentMetadata(agentObjectId: string): Promise<Record<string, string>> {
        const agent = await this.getAgent(agentObjectId);
        // Metadata is embedded in the agent object — fetch raw fields
        const obj = await this.suiClient.getObject({
            id: agentObjectId,
            options: { showContent: true },
        });

        if (!obj.data?.content || obj.data.content.dataType !== 'moveObject') {
            throw new Error(`Agent not found: ${agentObjectId}`);
        }

        const fields = obj.data.content.fields as Record<string, any>;
        return this.parseVecMap(fields.metadata);
    }

    /** Get agent stats (cred, sessions, feedback, active status) */
    async getAgentStats(agentObjectId: string): Promise<AgentStats> {
        const agent = await this.getAgent(agentObjectId);
        return {
            credScore: agent.credScore,
            totalSessions: agent.totalSessions,
            totalFeedbackReceived: agent.totalFeedbackReceived,
            positiveFeedback: agent.positiveFeedback,
            isActive: agent.isActive,
        };
    }

    /** Check if agent can join a room (active AND cred >= 30) */
    async canJoinRoom(agentObjectId: string): Promise<boolean> {
        const agent = await this.getAgent(agentObjectId);
        return agent.isActive && this.calculateVisibilityTier(agent.credScore) !== VisibilityTier.Suspended;
    }

    /** Get agent's current visibility tier */
    async getVisibilityTier(agentObjectId: string): Promise<VisibilityTier> {
        const agent = await this.getAgent(agentObjectId);
        return this.calculateVisibilityTier(agent.credScore);
    }

    /** Get registry-level stats */
    async getRegistryStats(): Promise<RegistryStats> {
        const obj = await this.suiClient.getObject({
            id: this.registryId,
            options: { showContent: true },
        });

        if (!obj.data?.content || obj.data.content.dataType !== 'moveObject') {
            throw new Error('Registry not found');
        }

        const fields = obj.data.content.fields as Record<string, any>;
        return {
            totalAgents: Number(fields.total_agents),
            totalActive: Number(fields.total_active),
            totalFeedback: Number(fields.total_feedback),
            totalValidations: Number(fields.total_validations),
        };
    }

    /** Check if an address has registered at least one agent */
    async isAgentRegistered(ownerAddress: string): Promise<boolean> {
        const ids = await this.getAgentIdsFromRegistry(ownerAddress);
        return ids.length > 0;
    }

    /** Get count of agents registered by an address */
    async getAgentCount(ownerAddress: string): Promise<number> {
        const ids = await this.getAgentIdsFromRegistry(ownerAddress);
        return ids.length;
    }

    /** Get validation request status */
    async getValidationStatus(requestObjectId: string): Promise<ValidationStatus> {
        const obj = await this.suiClient.getObject({
            id: requestObjectId,
            options: { showContent: true },
        });

        if (!obj.data?.content || obj.data.content.dataType !== 'moveObject') {
            throw new Error(`Validation request not found: ${requestObjectId}`);
        }

        const fields = obj.data.content.fields as Record<string, any>;
        const statusCode = Number(fields.status);
        const statusMap: Record<number, 'pending' | 'passed' | 'failed'> = {
            0: 'pending',
            1: 'passed',
            2: 'failed',
        };

        return {
            status: statusMap[statusCode] ?? 'pending',
            averageScore: Number(fields.avg_score),
            validatorCount: Array.isArray(fields.validators) ? fields.validators.length : 0,
        };
    }

    // ============================================
    // WRITE FUNCTIONS (return Transaction objects)
    // ============================================

    /** Register a new agent identity */
    registerAgent(params: RegisterAgentParams): Transaction {
        const tx = new Transaction();

        tx.moveCall({
            target: this.target('register_agent'),
            arguments: [
                tx.object(this.registryId),
                tx.pure.string(params.name),
                tx.pure.string(params.agentUri),
                tx.pure.u8(params.category),
                tx.pure.string(params.avatarStyle),
                tx.pure.address(params.wallet ?? '0x0'),
                tx.pure(bcs.vector(bcs.string()).serialize(params.metadataKeys ?? [])),
                tx.pure(bcs.vector(bcs.string()).serialize(params.metadataValues ?? [])),
                tx.object(SUI_CLOCK_OBJECT_ID),
            ],
        });

        return tx;
    }

    /** Update agent display name */
    setAgentName(params: SetAgentNameParams): Transaction {
        const tx = new Transaction();
        tx.moveCall({
            target: this.target('set_agent_name'),
            arguments: [
                tx.object(params.agentObjectId),
                tx.pure.string(params.name),
                tx.object(SUI_CLOCK_OBJECT_ID),
            ],
        });
        return tx;
    }

    /** Update agent URI */
    setAgentUri(params: SetAgentUriParams): Transaction {
        const tx = new Transaction();
        tx.moveCall({
            target: this.target('set_agent_uri'),
            arguments: [
                tx.object(params.agentObjectId),
                tx.pure.string(params.agentUri),
                tx.object(SUI_CLOCK_OBJECT_ID),
            ],
        });
        return tx;
    }

    /** Set or update a single metadata key-value pair */
    setMetadata(params: SetMetadataParams): Transaction {
        const tx = new Transaction();
        tx.moveCall({
            target: this.target('set_metadata'),
            arguments: [
                tx.object(params.agentObjectId),
                tx.pure.string(params.key),
                tx.pure.string(params.value),
                tx.object(SUI_CLOCK_OBJECT_ID),
            ],
        });
        return tx;
    }

    /** Remove a metadata key */
    removeMetadata(params: RemoveMetadataParams): Transaction {
        const tx = new Transaction();
        tx.moveCall({
            target: this.target('remove_metadata'),
            arguments: [
                tx.object(params.agentObjectId),
                tx.pure.string(params.key),
                tx.object(SUI_CLOCK_OBJECT_ID),
            ],
        });
        return tx;
    }

    /** Set or update multiple metadata key-value pairs in a single transaction */
    setMetadataBatch(params: SetMetadataBatchParams): Transaction {
        const tx = new Transaction();
        tx.moveCall({
            target: this.target('set_metadata_batch'),
            arguments: [
                tx.object(params.agentObjectId),
                tx.pure(bcs.vector(bcs.string()).serialize(params.keys)),
                tx.pure(bcs.vector(bcs.string()).serialize(params.values)),
                tx.object(SUI_CLOCK_OBJECT_ID),
            ],
        });
        return tx;
    }

    /** Update agent wallet address */
    setAgentWallet(agentObjectId: string, newWallet: string): Transaction {
        const tx = new Transaction();
        tx.moveCall({
            target: this.target('set_agent_wallet'),
            arguments: [
                tx.object(agentObjectId),
                tx.pure.address(newWallet),
                tx.object(SUI_CLOCK_OBJECT_ID),
            ],
        });
        return tx;
    }

    /** Transfer ownership of an agent to a new address */
    transferOwnership(params: TransferOwnershipParams): Transaction {
        const tx = new Transaction();
        tx.moveCall({
            target: this.target('transfer_ownership'),
            arguments: [
                tx.object(this.registryId),
                tx.object(params.agentObjectId),
                tx.pure.address(params.newOwner),
                tx.object(SUI_CLOCK_OBJECT_ID),
            ],
        });
        return tx;
    }

    /** Deactivate agent (owner voluntarily takes it offline) */
    deactivateAgent(agentObjectId: string): Transaction {
        const tx = new Transaction();
        tx.moveCall({
            target: this.target('deactivate_agent'),
            arguments: [
                tx.object(this.registryId),
                tx.object(agentObjectId),
                tx.object(SUI_CLOCK_OBJECT_ID),
            ],
        });
        return tx;
    }

    /** Reactivate a previously deactivated agent */
    reactivateAgent(agentObjectId: string): Transaction {
        const tx = new Transaction();
        tx.moveCall({
            target: this.target('reactivate_agent'),
            arguments: [
                tx.object(this.registryId),
                tx.object(agentObjectId),
                tx.object(SUI_CLOCK_OBJECT_ID),
            ],
        });
        return tx;
    }

    /** Unregister an agent (permanently deactivate + unlink from registry) */
    unregisterAgent(agentObjectId: string): Transaction {
        const tx = new Transaction();
        tx.moveCall({
            target: this.target('unregister_agent'),
            arguments: [
                tx.object(this.registryId),
                tx.object(agentObjectId),
                tx.object(SUI_CLOCK_OBJECT_ID),
            ],
        });
        return tx;
    }

    /** Record agent session participation */
    recordSession(agentObjectId: string, sessionId: string): Transaction {
        const tx = new Transaction();
        const sessionBytes = new TextEncoder().encode(sessionId);
        tx.moveCall({
            target: this.target('record_session'),
            arguments: [
                tx.object(agentObjectId),
                tx.pure(bcs.vector(bcs.u8()).serialize(Array.from(sessionBytes))),
                tx.object(SUI_CLOCK_OBJECT_ID),
            ],
        });
        return tx;
    }

    /** Submit feedback for an agent */
    giveFeedback(params: GiveFeedbackParams): Transaction {
        const tx = new Transaction();
        tx.moveCall({
            target: this.target('give_feedback'),
            arguments: [
                tx.object(this.registryId),
                tx.object(params.agentObjectId),
                tx.pure.u8(params.value),
                tx.pure.string(params.tag),
                tx.pure(bcs.vector(bcs.u8()).serialize(Array.from(params.commentHash))),
                tx.pure(bcs.vector(bcs.u8()).serialize(Array.from(params.sessionId))),
                tx.object(SUI_CLOCK_OBJECT_ID),
            ],
        });
        return tx;
    }

    /** Request third-party validation for an agent */
    requestValidation(params: RequestValidationParams): Transaction {
        const tx = new Transaction();
        tx.moveCall({
            target: this.target('request_validation'),
            arguments: [
                tx.object(this.registryId),
                tx.object(params.agentObjectId),
                tx.pure.string(params.requestUri),
                tx.pure(bcs.vector(bcs.u8()).serialize(Array.from(params.requestHash))),
                tx.object(SUI_CLOCK_OBJECT_ID),
            ],
        });
        return tx;
    }

    /** Submit a validation assessment (validator role) */
    submitValidation(params: SubmitValidationParams): Transaction {
        const tx = new Transaction();
        tx.moveCall({
            target: this.target('submit_validation'),
            arguments: [
                tx.object(params.requestObjectId),
                tx.pure.u8(params.score),
                tx.pure.string(params.tag),
            ],
        });
        return tx;
    }

    /** Resolve a validation request (agent owner role) */
    resolveValidation(params: ResolveValidationParams): Transaction {
        const tx = new Transaction();
        tx.moveCall({
            target: this.target('resolve_validation'),
            arguments: [
                tx.object(this.registryId),
                tx.object(params.agentObjectId),
                tx.object(params.requestObjectId),
                tx.object(SUI_CLOCK_OBJECT_ID),
            ],
        });
        return tx;
    }

    // ============================================
    // INTERNAL HELPERS
    // ============================================

    private parseAgentFields(objectId: string, fields: Record<string, any>): Agent {
        return {
            objectId,
            owner: String(fields.owner),
            name: String(fields.name),
            agentUri: String(fields.agent_uri),
            category: Number(fields.category) as AgentCategory,
            avatarStyle: String(fields.avatar_style),
            wallet: String(fields.wallet),
            credScore: Number(fields.cred_score),
            totalSessions: Number(fields.total_sessions),
            totalFeedbackReceived: Number(fields.total_feedback_received),
            positiveFeedback: Number(fields.positive_feedback),
            negativeFeedback: Number(fields.negative_feedback),
            isActive: Boolean(fields.is_active),
            registeredAt: Number(fields.registered_at),
            lastSessionAt: Number(fields.last_session_at),
        };
    }

    private parseVecMap(raw: any): Record<string, string> {
        const result: Record<string, string> = {};
        if (!raw) return result;

        // VecMap fields come as { fields: { contents: [{ fields: { key, value } }] } }
        const contents = raw?.fields?.contents ?? raw?.contents ?? [];
        for (const entry of contents) {
            const k = entry?.fields?.key ?? entry?.key;
            const v = entry?.fields?.value ?? entry?.value;
            if (k !== undefined && v !== undefined) {
                result[String(k)] = String(v);
            }
        }
        return result;
    }

    private calculateVisibilityTier(cred: number): VisibilityTier {
        if (cred >= 90) return VisibilityTier.Pristine;
        if (cred >= 70) return VisibilityTier.Standard;
        if (cred >= 50) return VisibilityTier.Restricted;
        if (cred >= 30) return VisibilityTier.Probation;
        return VisibilityTier.Suspended;
    }

    /** Look up agent IDs from the registry Table via dynamic field */
    private async getAgentIdsFromRegistry(ownerAddress: string): Promise<string[]> {
        try {
            // The registry has a Table<address, vector<ID>> called 'agents'
            // Tables in Sui are stored as dynamic fields on the table's UID
            const registryObj = await this.suiClient.getObject({
                id: this.registryId,
                options: { showContent: true },
            });

            if (!registryObj.data?.content || registryObj.data.content.dataType !== 'moveObject') {
                return [];
            }

            const fields = registryObj.data.content.fields as Record<string, any>;
            const tableId = fields.agents?.fields?.id?.id ?? fields.agents?.id?.id;

            if (!tableId) return [];

            // Query the dynamic field for this owner
            const dynamicField = await this.suiClient.getDynamicFieldObject({
                parentId: tableId,
                name: {
                    type: 'address',
                    value: ownerAddress,
                },
            });

            if (!dynamicField.data?.content || dynamicField.data.content.dataType !== 'moveObject') {
                return [];
            }

            const dfFields = dynamicField.data.content.fields as Record<string, any>;
            const agentIds = dfFields.value ?? [];
            return Array.isArray(agentIds) ? agentIds.map(String) : [];
        } catch {
            return [];
        }
    }
}
