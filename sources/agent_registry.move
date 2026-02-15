/// Module: agent_registry
/// Sui-native Agent Identity Registry inspired by ERC-8004 (Trustless Agents).
///
/// Provides on-chain identity, reputation feedback, and validation for AI agents.
/// Designed as a portable standard for the Sui ecosystem — any dApp can integrate
/// this module to let AI agents register, build reputation, and get validated.
///
/// Three registries in one module (mirroring ERC-8004 architecture):
/// 1. Identity  — AgentIdentity object (≈ ERC-8004 Identity Registry / ERC-721)
/// 2. Feedback  — Per-session ratings from humans (≈ ERC-8004 Reputation Registry)
/// 3. Validation — Third-party attestations (≈ ERC-8004 Validation Registry)
///
/// Key design decisions vs ERC-8004:
/// - Uses Sui shared objects instead of ERC-721 (Sui-native identity model)
/// - On-chain feedback dedup per (client, agent, session) prevents spam
/// - Cred score with visibility tiers provides automatic access control
/// - Validation requires MIN_VALIDATORS before resolution (Sybil resistance)
///
/// Version: 1.0.0
#[allow(lint(public_entry))]
module sai::agent_registry {
    use sui::event;
    use sui::clock::{Self, Clock};
    use sui::table::{Self, Table};
    use sui::vec_map::{Self, VecMap};
    use std::string::{Self, String};

    // ============================= Error Codes =============================
    // Owner & auth errors (0x)
    const ENotAgentOwner: u64 = 0;

    // State errors (1x)
    const EAgentNotActive: u64 = 10;
    const EAgentAlreadyActive: u64 = 11;
    const EAgentSuspended: u64 = 12;

    // Input validation errors (2x)
    const EInvalidCategory: u64 = 20;
    const EInvalidFeedbackValue: u64 = 21;
    const EInvalidValidationScore: u64 = 22;
    const EEmptyName: u64 = 23;
    const EEmptyUri: u64 = 24;
    const EMetadataLengthMismatch: u64 = 25;

    // Feedback errors (3x)
    const ESelfFeedback: u64 = 30;
    const EDuplicateFeedback: u64 = 31;

    // Validation errors (4x)
    const ECannotValidateSelf: u64 = 40;
    const EAlreadyValidated: u64 = 41;
    const EValidationAlreadyResolved: u64 = 42;
    const EValidationRequestNotFound: u64 = 43;
    const EInsufficientValidators: u64 = 44;

    // ============================= Constants ===============================

    // ---- Cred scoring ----
    const STARTING_CRED: u64 = 70;
    const MAX_CRED: u64 = 100;

    // ---- Visibility tiers (returned by get_agent_visibility_tier) ----
    /// 90-100: Boosted — featured agent, prioritized in discovery
    const TIER_PRISTINE: u8 = 0;
    /// 70-89: Normal — available in rooms, standard visibility
    const TIER_STANDARD: u8 = 1;
    /// 50-69: Degraded — hidden from discovery, direct access only
    const TIER_RESTRICTED: u8 = 2;
    /// 30-49: Warning — requires owner action, limited functionality
    const TIER_PROBATION: u8 = 3;
    /// 0-29: Blocked — cannot join rooms, must recover cred
    const TIER_SUSPENDED: u8 = 4;

    const CRED_PRISTINE_MIN: u64 = 90;
    const CRED_STANDARD_MIN: u64 = 70;
    const CRED_RESTRICTED_MIN: u64 = 50;
    const CRED_PROBATION_MIN: u64 = 30;

    // ---- Feedback impact on cred (asymmetric by design) ----
    const POSITIVE_FEEDBACK_CRED: u64 = 1;   // +1 per positive (4-5 star)
    const NEGATIVE_FEEDBACK_CRED: u64 = 3;   // -3 per negative (1-2 star)

    // ---- Validation impact on cred ----
    const VALIDATION_PASS_CRED: u64 = 2;     // +2 per passed validation
    const VALIDATION_FAIL_CRED: u64 = 10;    // -10 per failed validation
    const VALIDATION_PASS_THRESHOLD: u64 = 60; // Average score >= 60 to pass

    // ---- Agent categories ----
    // Broad taxonomy for ecosystem-wide agent classification.
    // Any chain's agent should find a fitting category here.
    /// 0 = General / multi-purpose assistant
    /// 1 = Communication (translator, transcriber, meeting agent)
    /// 2 = Moderation / safety (content filter, compliance)
    /// 3 = DeFi / trading (portfolio, swap, yield, MEV)
    /// 4 = Data / analytics (indexer, oracle, researcher)
    /// 5 = Creative (image gen, music, writing, design)
    /// 6 = Gaming (NPC, companion, game master)
    /// 7 = Infrastructure (relayer, bridge, validator)
    /// 8 = Social (reputation, matching, recommendation)
    /// 9 = Custom / other
    const MAX_CATEGORY: u8 = 9;

    // ---- Validation request status ----
    const VALIDATION_PENDING: u8 = 0;
    const VALIDATION_PASSED: u8 = 1;
    const VALIDATION_FAILED: u8 = 2;

    // ---- Minimum validators required to resolve a validation request ----
    const MIN_VALIDATORS: u64 = 3;

    // ============================= Structs =================================

    /// Global registry tracking all agents (shared object, created at publish).
    /// Only one instance exists per deployment.
    public struct AgentRegistry has key {
        id: UID,
        /// owner address -> list of agent identity object IDs.
        /// Supports multiple agents per address for operators running
        /// specialized agents (e.g., translator + moderator).
        agents: Table<address, vector<ID>>,
        /// Total agents currently registered (decremented on unregister)
        total_agents: u64,
        /// Currently active agents
        total_active: u64,
        /// Total feedback entries submitted across all agents
        total_feedback: u64,
        /// Total validation requests resolved
        total_validations: u64,
        /// Monotonic counter for globally unique feedback IDs
        feedback_counter: u64,
        /// Monotonic counter for globally unique validation request IDs
        validation_counter: u64,
    }

    /// Agent Identity object — shared, logically owned by the registrant.
    ///
    /// This is the Sui-native equivalent of an ERC-8004 Identity Registry entry.
    /// On EVM chains, ERC-8004 uses ERC-721 tokens; on Sui, we use a shared
    /// object with an `owner` field for logical ownership and access control.
    ///
    /// The `agent_uri` points to an off-chain JSON registration file containing:
    /// - Agent type, name, description, image
    /// - Network endpoints (A2A, MCP servers)
    /// - Supported capabilities and trust models
    /// - Model information and version
    public struct AgentIdentity has key, store {
        id: UID,
        /// Address that registered this agent (logical owner)
        owner: address,
        /// Human-readable display name
        name: String,
        /// Off-chain URI pointing to the agent registration JSON file
        /// (mirrors ERC-8004 agentURI / tokenURI pattern)
        agent_uri: String,
        /// Extensible on-chain metadata as key-value pairs.
        /// Common keys: "model", "version", "framework", "a2a_endpoint", "mcp_endpoint"
        metadata: VecMap<String, String>,
        /// Agent category (0-4, validated on registration)
        category: u8,
        /// Avatar style identifier for rendering (maps to AvatarRenderer styles)
        avatar_style: String,
        /// Wallet address for receiving tips/payments (defaults to owner)
        wallet: address,

        // ---- Reputation ----
        /// Current credibility score (0-100, starts at 100)
        cred_score: u64,
        /// Total sessions this agent has participated in
        total_sessions: u64,
        /// Total feedback entries received
        total_feedback_received: u64,
        /// Count of positive feedback (4-5 stars)
        positive_feedback: u64,
        /// Count of negative feedback (1-2 stars)
        negative_feedback: u64,

        // ---- Status ----
        /// Whether this agent is currently active and discoverable
        is_active: bool,
        /// Timestamp (ms) when agent was registered
        registered_at: u64,
        /// Timestamp (ms) of last session participation (0 if never)
        last_session_at: u64,

        /// Feedback deduplication table: client address -> session_ids already reviewed.
        /// Enforces one feedback per (client, agent, session) triple on-chain.
        feedback_sessions: Table<address, vector<vector<u8>>>,
    }

    /// Per-interaction feedback from a human participant.
    /// Equivalent to an ERC-8004 Reputation Registry feedback entry.
    ///
    /// Transferred to the client who submitted it (owned object) so they
    /// retain proof of their review.
    public struct AgentFeedback has key, store {
        id: UID,
        /// Globally unique feedback ID (monotonic)
        feedback_id: u64,
        /// Object ID of the AgentIdentity this feedback is about
        agent_id: ID,
        /// Address of the human who submitted this feedback
        client: address,
        /// Star rating: 1-5 (1-2 = negative, 3 = neutral, 4-5 = positive)
        value: u8,
        /// Category tag for the interaction (e.g., "translation", "moderation")
        tag: String,
        /// KECCAK-256 hash of optional off-chain comment (for integrity verification)
        comment_hash: vector<u8>,
        /// Room/stream identifier linking this feedback to a specific session
        session_id: vector<u8>,
        /// Timestamp (ms) when feedback was submitted
        created_at: u64,
    }

    /// Validation request — agent owner requests third-party attestation.
    /// Equivalent to ERC-8004 Validation Registry.
    ///
    /// Shared object so multiple validators can submit their assessments.
    /// Requires MIN_VALIDATORS responses before it can be resolved.
    public struct ValidationRequest has key, store {
        id: UID,
        /// Globally unique request ID (monotonic)
        request_id: u64,
        /// Object ID of the AgentIdentity being validated
        agent_id: ID,
        /// Owner of the agent (cached for access control)
        agent_owner: address,
        /// Off-chain URI pointing to validation request details/criteria
        request_uri: String,
        /// Hash of request content (for integrity verification)
        request_hash: vector<u8>,

        // ---- Validator responses (parallel arrays) ----
        /// Addresses of validators who have responded
        validators: vector<address>,
        /// Score from each validator (0-100)
        scores: vector<u8>,
        /// Category tag from each validator
        tags: vector<String>,

        // ---- Aggregated result ----
        /// Current status: PENDING (0), PASSED (1), or FAILED (2)
        status: u8,
        /// Average score across all validators (computed on resolution)
        avg_score: u64,
        /// Timestamp (ms) when request was created
        created_at: u64,
        /// Timestamp (ms) when request was resolved (0 if pending)
        resolved_at: u64,
    }

    // ============================= Events ==================================

    /// Emitted when a new agent identity is registered
    public struct AgentRegistered has copy, drop {
        agent_id: ID,
        owner: address,
        name: String,
        category: u8,
        timestamp: u64,
    }

    /// Emitted when an agent's on-chain field is updated
    public struct AgentUpdated has copy, drop {
        agent_id: ID,
        field: String,
        timestamp: u64,
    }

    /// Emitted when an agent is deactivated (voluntarily or by auto-suspend)
    public struct AgentDeactivated has copy, drop {
        agent_id: ID,
        owner: address,
        timestamp: u64,
    }

    /// Emitted when an agent is reactivated by its owner
    public struct AgentReactivated has copy, drop {
        agent_id: ID,
        owner: address,
        timestamp: u64,
    }

    /// Emitted when an agent is removed from the registry
    public struct AgentUnregistered has copy, drop {
        agent_id: ID,
        owner: address,
        timestamp: u64,
    }

    /// Emitted when feedback is submitted for an agent
    public struct FeedbackSubmitted has copy, drop {
        feedback_id: u64,
        agent_id: ID,
        client: address,
        value: u8,
        tag: String,
        session_id: vector<u8>,
    }

    /// Emitted when an agent's cred score changes
    public struct CredUpdated has copy, drop {
        agent_id: ID,
        old_cred: u64,
        new_cred: u64,
        reason: String,
    }

    /// Emitted when an agent's visibility tier changes
    public struct VisibilityTierChanged has copy, drop {
        agent_id: ID,
        old_tier: u8,
        new_tier: u8,
    }

    /// Emitted when a session is recorded for an agent
    public struct SessionRecorded has copy, drop {
        agent_id: ID,
        session_id: vector<u8>,
        timestamp: u64,
    }

    /// Emitted when a validation request is created
    public struct ValidationRequested has copy, drop {
        request_id: u64,
        agent_id: ID,
        request_uri: String,
    }

    /// Emitted when a validator submits their assessment
    public struct ValidationResponseSubmitted has copy, drop {
        request_id: u64,
        validator: address,
        score: u8,
        tag: String,
    }

    /// Emitted when a validation request is resolved
    public struct ValidationResolved has copy, drop {
        request_id: u64,
        agent_id: ID,
        passed: bool,
        avg_score: u64,
    }

    // ============================= Init ====================================

    fun init(ctx: &mut TxContext) {
        let registry = AgentRegistry {
            id: object::new(ctx),
            agents: table::new(ctx),
            total_agents: 0,
            total_active: 0,
            total_feedback: 0,
            total_validations: 0,
            feedback_counter: 0,
            validation_counter: 0,
        };
        transfer::share_object(registry);
    }

    // ================ Identity Registry (Registration & Updates) ===========

    /// Register a new AI agent identity — **one transaction, full setup**.
    ///
    /// Because `register_agent` creates a shared object, you CANNOT update
    /// the agent in the same Programmable Transaction Block (PTB). This function
    /// therefore accepts ALL optional fields upfront so the agent is fully
    /// configured in a single transaction.
    ///
    /// For minimal registration, pass:
    /// - `avatar_style = ""` (empty string = platform default)
    /// - `wallet = @sender` (same as your address)
    /// - `metadata_keys = []`, `metadata_values = []` (no initial metadata)
    ///
    /// # Arguments
    /// * `name` — Human-readable display name (must not be empty)
    /// * `agent_uri` — URI to agent registration JSON (must not be empty)
    /// * `category` — 0=assistant, 1=translator, 2=moderator, 3=scribe, 4=custom
    /// * `avatar_style` — Avatar identifier (empty string for platform default)
    /// * `wallet` — Address for receiving tips/payments (use your own address if unsure)
    /// * `metadata_keys` — On-chain metadata keys (e.g., ["model", "a2a_endpoint"])
    /// * `metadata_values` — Corresponding values (must be same length as keys)
    ///
    /// # Errors
    /// * `EEmptyName` — if `name` is empty
    /// * `EEmptyUri` — if `agent_uri` is empty
    /// * `EInvalidCategory` — if `category` > 4
    /// * `EMetadataLengthMismatch` — if keys and values have different lengths
    public entry fun register_agent(
        registry: &mut AgentRegistry,
        name: String,
        agent_uri: String,
        category: u8,
        avatar_style: String,
        wallet: address,
        metadata_keys: vector<String>,
        metadata_values: vector<String>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);

        // Input validation
        assert!(string::length(&name) > 0, EEmptyName);
        assert!(string::length(&agent_uri) > 0, EEmptyUri);
        assert!(category <= MAX_CATEGORY, EInvalidCategory);
        let keys_len = vector::length(&metadata_keys);
        assert!(keys_len == vector::length(&metadata_values), EMetadataLengthMismatch);

        let now = clock::timestamp_ms(clock);

        // Build metadata map from key/value vectors
        let mut metadata = vec_map::empty<String, String>();
        let mut i = 0;
        while (i < keys_len) {
            vec_map::insert(
                &mut metadata,
                *vector::borrow(&metadata_keys, i),
                *vector::borrow(&metadata_values, i),
            );
            i = i + 1;
        };

        let agent = AgentIdentity {
            id: object::new(ctx),
            owner: sender,
            name,
            agent_uri,
            metadata,
            category,
            avatar_style,
            wallet,
            cred_score: STARTING_CRED,
            total_sessions: 0,
            total_feedback_received: 0,
            positive_feedback: 0,
            negative_feedback: 0,
            is_active: true,
            registered_at: now,
            last_session_at: 0,
            feedback_sessions: table::new(ctx),
        };

        let agent_id = object::id(&agent);

        // Multi-agent support: append to existing list or create new entry
        if (table::contains(&registry.agents, sender)) {
            vector::push_back(
                table::borrow_mut(&mut registry.agents, sender),
                agent_id,
            );
        } else {
            let mut ids = vector::empty<ID>();
            vector::push_back(&mut ids, agent_id);
            table::add(&mut registry.agents, sender, ids);
        };

        registry.total_agents = registry.total_agents + 1;
        registry.total_active = registry.total_active + 1;

        event::emit(AgentRegistered {
            agent_id,
            owner: sender,
            name: agent.name,
            category,
            timestamp: now,
        });

        transfer::share_object(agent);
    }

    /// Update agent display name.
    ///
    /// # Errors
    /// * `ENotAgentOwner` — if caller is not the agent owner
    /// * `EEmptyName` — if `new_name` is empty
    public entry fun set_agent_name(
        agent: &mut AgentIdentity,
        new_name: String,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == agent.owner, ENotAgentOwner);
        assert!(string::length(&new_name) > 0, EEmptyName);
        agent.name = new_name;
        event::emit(AgentUpdated {
            agent_id: object::id(agent),
            field: string::utf8(b"name"),
            timestamp: clock::timestamp_ms(clock),
        });
    }

    /// Update agent URI (off-chain registration file).
    ///
    /// The URI should point to a JSON file containing the agent's full registration
    /// metadata (capabilities, model info, A2A/MCP endpoints).
    ///
    /// # Errors
    /// * `ENotAgentOwner` — if caller is not the agent owner
    /// * `EEmptyUri` — if `new_uri` is empty
    public entry fun set_agent_uri(
        agent: &mut AgentIdentity,
        new_uri: String,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == agent.owner, ENotAgentOwner);
        assert!(string::length(&new_uri) > 0, EEmptyUri);
        agent.agent_uri = new_uri;
        event::emit(AgentUpdated {
            agent_id: object::id(agent),
            field: string::utf8(b"agent_uri"),
            timestamp: clock::timestamp_ms(clock),
        });
    }

    /// Set or update an on-chain metadata key-value pair.
    ///
    /// Common keys include: "model", "version", "framework", "a2a_endpoint",
    /// "mcp_endpoint", "supported_languages".
    ///
    /// If the key already exists, the old value is replaced.
    ///
    /// # Errors
    /// * `ENotAgentOwner` — if caller is not the agent owner
    public entry fun set_metadata(
        agent: &mut AgentIdentity,
        key: String,
        value: String,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == agent.owner, ENotAgentOwner);
        if (vec_map::contains(&agent.metadata, &key)) {
            vec_map::remove(&mut agent.metadata, &key);
        };
        vec_map::insert(&mut agent.metadata, key, value);
        event::emit(AgentUpdated {
            agent_id: object::id(agent),
            field: string::utf8(b"metadata"),
            timestamp: clock::timestamp_ms(clock),
        });
    }

    /// Remove an on-chain metadata key-value pair.
    ///
    /// # Errors
    /// * `ENotAgentOwner` — if caller is not the agent owner
    public entry fun remove_metadata(
        agent: &mut AgentIdentity,
        key: String,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == agent.owner, ENotAgentOwner);
        if (vec_map::contains(&agent.metadata, &key)) {
            vec_map::remove(&mut agent.metadata, &key);
        };
        event::emit(AgentUpdated {
            agent_id: object::id(agent),
            field: string::utf8(b"metadata"),
            timestamp: clock::timestamp_ms(clock),
        });
    }

    /// Set or update multiple metadata key-value pairs in a single transaction.
    ///
    /// This is the batch version of `set_metadata`. Useful for setting several
    /// fields at once without paying per-transaction gas for each.
    ///
    /// # Arguments
    /// * `keys` — Vector of metadata keys to set
    /// * `values` — Vector of metadata values (must be same length as keys)
    ///
    /// # Errors
    /// * `ENotAgentOwner` — if caller is not the agent owner
    /// * `EMetadataLengthMismatch` — if keys and values have different lengths
    public entry fun set_metadata_batch(
        agent: &mut AgentIdentity,
        keys: vector<String>,
        values: vector<String>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == agent.owner, ENotAgentOwner);
        let keys_len = vector::length(&keys);
        assert!(keys_len == vector::length(&values), EMetadataLengthMismatch);

        let mut i = 0;
        while (i < keys_len) {
            let key = *vector::borrow(&keys, i);
            if (vec_map::contains(&agent.metadata, &key)) {
                vec_map::remove(&mut agent.metadata, &key);
            };
            vec_map::insert(
                &mut agent.metadata,
                key,
                *vector::borrow(&values, i),
            );
            i = i + 1;
        };

        event::emit(AgentUpdated {
            agent_id: object::id(agent),
            field: string::utf8(b"metadata"),
            timestamp: clock::timestamp_ms(clock),
        });
    }

    /// Update agent wallet address (for receiving tips/payments).
    ///
    /// # Errors
    /// * `ENotAgentOwner` — if caller is not the agent owner
    public entry fun set_agent_wallet(
        agent: &mut AgentIdentity,
        new_wallet: address,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == agent.owner, ENotAgentOwner);
        agent.wallet = new_wallet;
        event::emit(AgentUpdated {
            agent_id: object::id(agent),
            field: string::utf8(b"wallet"),
            timestamp: clock::timestamp_ms(clock),
        });
    }

    /// Transfer ownership of an agent identity to a new address.
    ///
    /// This updates the logical owner. The new owner gains full control
    /// over the agent identity (can update fields, deactivate, etc.).
    ///
    /// # Errors
    /// * `ENotAgentOwner` — if caller is not the current agent owner
    public entry fun transfer_ownership(
        registry: &mut AgentRegistry,
        agent: &mut AgentIdentity,
        new_owner: address,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(sender == agent.owner, ENotAgentOwner);

        let agent_id = object::id(agent);

        // Remove from old owner's list
        if (table::contains(&registry.agents, sender)) {
            let old_ids = table::borrow_mut(&mut registry.agents, sender);
            let len = vector::length(old_ids);
            let mut i = 0;
            while (i < len) {
                if (*vector::borrow(old_ids, i) == agent_id) {
                    vector::remove(old_ids, i);
                    break
                };
                i = i + 1;
            };
            if (vector::is_empty(old_ids)) {
                table::remove(&mut registry.agents, sender);
            };
        };

        // Add to new owner's list
        if (table::contains(&registry.agents, new_owner)) {
            vector::push_back(
                table::borrow_mut(&mut registry.agents, new_owner),
                agent_id,
            );
        } else {
            let mut ids = vector::empty<ID>();
            vector::push_back(&mut ids, agent_id);
            table::add(&mut registry.agents, new_owner, ids);
        };

        agent.owner = new_owner;

        event::emit(AgentUpdated {
            agent_id,
            field: string::utf8(b"owner"),
            timestamp: clock::timestamp_ms(clock),
        });
    }

    /// Deactivate agent (owner voluntarily takes it offline).
    ///
    /// A deactivated agent cannot join rooms or receive new sessions.
    /// Can be reactivated later if cred score is above TIER_SUSPENDED.
    ///
    /// # Errors
    /// * `ENotAgentOwner` — if caller is not the agent owner
    /// * `EAgentNotActive` — if agent is already inactive
    public entry fun deactivate_agent(
        registry: &mut AgentRegistry,
        agent: &mut AgentIdentity,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == agent.owner, ENotAgentOwner);
        assert!(agent.is_active, EAgentNotActive);

        agent.is_active = false;
        if (registry.total_active > 0) {
            registry.total_active = registry.total_active - 1;
        };

        event::emit(AgentDeactivated {
            agent_id: object::id(agent),
            owner: agent.owner,
            timestamp: clock::timestamp_ms(clock),
        });
    }

    /// Reactivate a previously deactivated agent.
    ///
    /// Cannot reactivate if cred score has dropped to TIER_SUSPENDED (0-29).
    /// The agent must recover cred through validation passes first.
    ///
    /// # Errors
    /// * `ENotAgentOwner` — if caller is not the agent owner
    /// * `EAgentAlreadyActive` — if agent is already active
    /// * `EAgentSuspended` — if cred score is in TIER_SUSPENDED range
    public entry fun reactivate_agent(
        registry: &mut AgentRegistry,
        agent: &mut AgentIdentity,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == agent.owner, ENotAgentOwner);
        assert!(!agent.is_active, EAgentAlreadyActive);
        assert!(calculate_visibility_tier(agent.cred_score) != TIER_SUSPENDED, EAgentSuspended);

        agent.is_active = true;
        registry.total_active = registry.total_active + 1;

        event::emit(AgentReactivated {
            agent_id: object::id(agent),
            owner: agent.owner,
            timestamp: clock::timestamp_ms(clock),
        });
    }

    /// Unregister an agent (deactivates and removes from registry lookup).
    ///
    /// The `AgentIdentity` shared object remains on-chain (Sui shared objects
    /// cannot be deleted) but is permanently deactivated and unlinked from
    /// the registry's lookup table.
    ///
    /// # Errors
    /// * `ENotAgentOwner` — if caller is not the agent owner
    public entry fun unregister_agent(
        registry: &mut AgentRegistry,
        agent: &mut AgentIdentity,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(sender == agent.owner, ENotAgentOwner);

        let now = clock::timestamp_ms(clock);

        // Deactivate if still active
        if (agent.is_active) {
            agent.is_active = false;
            if (registry.total_active > 0) {
                registry.total_active = registry.total_active - 1;
            };
        };

        // Remove from registry lookup
        let agent_id = object::id(agent);
        if (table::contains(&registry.agents, sender)) {
            let agent_ids = table::borrow_mut(&mut registry.agents, sender);
            let len = vector::length(agent_ids);
            let mut i = 0;
            while (i < len) {
                if (*vector::borrow(agent_ids, i) == agent_id) {
                    vector::remove(agent_ids, i);
                    break
                };
                i = i + 1;
            };
            if (vector::is_empty(agent_ids)) {
                table::remove(&mut registry.agents, sender);
            };
        };

        if (registry.total_agents > 0) {
            registry.total_agents = registry.total_agents - 1;
        };

        event::emit(AgentUnregistered {
            agent_id,
            owner: agent.owner,
            timestamp: now,
        });
    }

    /// Record that agent participated in a session.
    ///
    /// Increments the session counter and updates `last_session_at`.
    ///
    /// NOTE: Currently owner-gated. In a production deployment with a gateway
    /// contract, this should be gated through a capability/witness pattern
    /// to prevent session count inflation by the owner.
    ///
    /// # Errors
    /// * `ENotAgentOwner` — if caller is not the agent owner
    /// * `EAgentNotActive` — if agent is not active
    public entry fun record_session(
        agent: &mut AgentIdentity,
        session_id: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == agent.owner, ENotAgentOwner);
        assert!(agent.is_active, EAgentNotActive);

        let now = clock::timestamp_ms(clock);
        agent.total_sessions = agent.total_sessions + 1;
        agent.last_session_at = now;

        event::emit(SessionRecorded {
            agent_id: object::id(agent),
            session_id,
            timestamp: now,
        });
    }

    // ================ Feedback Registry (Reputation) =======================

    /// Submit feedback for an agent after interacting with it in a session.
    ///
    /// Feedback is rated on a 1-5 star scale:
    /// - 4-5 stars: positive feedback (+1 cred)
    /// - 3 stars: neutral (no cred change)
    /// - 1-2 stars: negative feedback (-3 cred, asymmetric to discourage bad behavior)
    ///
    /// On-chain deduplication ensures each client can only submit ONE feedback
    /// per session per agent. The feedback object is transferred to the client
    /// as proof of their review.
    ///
    /// If the agent's cred drops to TIER_SUSPENDED (0-29), they are automatically
    /// deactivated and cannot join rooms until cred recovers.
    ///
    /// # Arguments
    /// * `value` — Star rating (1-5)
    /// * `tag` — Category tag for the interaction (e.g., "translation")
    /// * `comment_hash` — KECCAK-256 hash of optional off-chain comment
    /// * `session_id` — Room/stream identifier (used for dedup)
    ///
    /// # Errors
    /// * `ESelfFeedback` — if caller is the agent owner
    /// * `EInvalidFeedbackValue` — if value is not 1-5
    /// * `EDuplicateFeedback` — if caller already reviewed this agent in this session
    public entry fun give_feedback(
        registry: &mut AgentRegistry,
        agent: &mut AgentIdentity,
        value: u8,
        tag: String,
        comment_hash: vector<u8>,
        session_id: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(sender != agent.owner, ESelfFeedback);
        assert!(value >= 1 && value <= 5, EInvalidFeedbackValue);

        // ---- Duplicate feedback guard: one per (client, session) ----
        let has_prior = table::contains(&agent.feedback_sessions, sender);
        if (has_prior) {
            let sessions = table::borrow(&agent.feedback_sessions, sender);
            let session_count = vector::length(sessions);
            let mut j = 0;
            while (j < session_count) {
                assert!(*vector::borrow(sessions, j) != session_id, EDuplicateFeedback);
                j = j + 1;
            };
        };
        // Record this feedback session for future dedup checks
        if (has_prior) {
            vector::push_back(
                table::borrow_mut(&mut agent.feedback_sessions, sender),
                session_id,
            );
        } else {
            let mut sessions = vector::empty<vector<u8>>();
            vector::push_back(&mut sessions, session_id);
            table::add(&mut agent.feedback_sessions, sender, sessions);
        };

        let now = clock::timestamp_ms(clock);
        let feedback_id = registry.feedback_counter;
        registry.feedback_counter = feedback_id + 1;
        registry.total_feedback = registry.total_feedback + 1;

        let agent_id = object::id(agent);

        // Update agent feedback counters and cred
        agent.total_feedback_received = agent.total_feedback_received + 1;
        let old_cred = agent.cred_score;

        if (value >= 4) {
            agent.positive_feedback = agent.positive_feedback + 1;
            agent.cred_score = safe_add_cred(agent.cred_score, POSITIVE_FEEDBACK_CRED);
        } else if (value <= 2) {
            agent.negative_feedback = agent.negative_feedback + 1;
            agent.cred_score = safe_sub_cred(agent.cred_score, NEGATIVE_FEEDBACK_CRED);
        };
        // value == 3 is neutral, no cred change

        let new_cred = agent.cred_score;
        emit_cred_update_if_changed(
            registry, agent, agent_id, old_cred, new_cred,
            string::utf8(b"feedback"), now,
        );

        let feedback = AgentFeedback {
            id: object::new(ctx),
            feedback_id,
            agent_id,
            client: sender,
            value,
            tag,
            comment_hash,
            session_id,
            created_at: now,
        };

        event::emit(FeedbackSubmitted {
            feedback_id,
            agent_id,
            client: sender,
            value,
            tag: feedback.tag,
            session_id: feedback.session_id,
        });

        transfer::transfer(feedback, sender);
    }

    // ================ Validation Registry ==================================

    /// Create a validation request for third-party attestation.
    ///
    /// The agent owner initiates a request that validators can respond to.
    /// Use cases include: pre-deployment certification, periodic trust renewal,
    /// or high-stakes scenario verification.
    ///
    /// # Arguments
    /// * `request_uri` — URI pointing to validation request details/criteria
    /// * `request_hash` — Hash of the request content (integrity check)
    ///
    /// # Errors
    /// * `ENotAgentOwner` — if caller is not the agent owner
    public entry fun request_validation(
        registry: &mut AgentRegistry,
        agent: &AgentIdentity,
        request_uri: String,
        request_hash: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(sender == agent.owner, ENotAgentOwner);

        let now = clock::timestamp_ms(clock);
        let request_id = registry.validation_counter;
        registry.validation_counter = request_id + 1;

        let request = ValidationRequest {
            id: object::new(ctx),
            request_id,
            agent_id: object::id(agent),
            agent_owner: sender,
            request_uri,
            request_hash,
            validators: vector::empty(),
            scores: vector::empty(),
            tags: vector::empty(),
            status: VALIDATION_PENDING,
            avg_score: 0,
            created_at: now,
            resolved_at: 0,
        };

        event::emit(ValidationRequested {
            request_id,
            agent_id: object::id(agent),
            request_uri: request.request_uri,
        });

        transfer::share_object(request);
    }

    /// Validator submits their assessment of an agent (score 0-100).
    ///
    /// Validators are expected to be node operators with stake at risk
    /// (see `node_operator.move`). A validator cannot validate their own
    /// agent or submit multiple assessments for the same request.
    ///
    /// # Arguments
    /// * `score` — Assessment score (0-100)
    /// * `tag` — Category tag for the validation method used
    ///
    /// # Errors
    /// * `EValidationAlreadyResolved` — if request is no longer pending
    /// * `ECannotValidateSelf` — if validator is the agent owner
    /// * `EAlreadyValidated` — if validator already submitted for this request
    /// * `EInvalidValidationScore` — if score > 100
    public entry fun submit_validation(
        request: &mut ValidationRequest,
        score: u8,
        tag: String,
        ctx: &mut TxContext
    ) {
        let validator = tx_context::sender(ctx);
        assert!(request.status == VALIDATION_PENDING, EValidationAlreadyResolved);
        assert!(validator != request.agent_owner, ECannotValidateSelf);

        // Check not already validated
        let len = vector::length(&request.validators);
        let mut i = 0;
        while (i < len) {
            assert!(*vector::borrow(&request.validators, i) != validator, EAlreadyValidated);
            i = i + 1;
        };

        assert!(score <= 100, EInvalidValidationScore);

        // Emit event (String has copy, so tag is copied here and moved below)
        event::emit(ValidationResponseSubmitted {
            request_id: request.request_id,
            validator,
            score,
            tag,
        });

        vector::push_back(&mut request.validators, validator);
        vector::push_back(&mut request.scores, score);
        vector::push_back(&mut request.tags, tag);
    }

    /// Resolve a validation request after enough validators have responded.
    ///
    /// Only the agent owner can trigger resolution, giving them control over
    /// when to finalize (e.g., to wait for additional validators beyond the minimum).
    ///
    /// The validation passes if the average score >= VALIDATION_PASS_THRESHOLD (60).
    /// - Pass: +2 cred
    /// - Fail: -10 cred (strong penalty for failing validation)
    ///
    /// # Errors
    /// * `EValidationAlreadyResolved` — if already resolved
    /// * `EValidationRequestNotFound` — if agent doesn't match the request
    /// * `ENotAgentOwner` — if caller is not the agent owner
    /// * `EInsufficientValidators` — if fewer than MIN_VALIDATORS have responded
    public entry fun resolve_validation(
        registry: &mut AgentRegistry,
        agent: &mut AgentIdentity,
        request: &mut ValidationRequest,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(request.status == VALIDATION_PENDING, EValidationAlreadyResolved);
        assert!(object::id(agent) == request.agent_id, EValidationRequestNotFound);
        assert!(tx_context::sender(ctx) == request.agent_owner, ENotAgentOwner);

        let validator_count = vector::length(&request.validators);
        assert!(validator_count >= MIN_VALIDATORS, EInsufficientValidators);

        // Calculate average score
        let mut total_score: u64 = 0;
        let mut i = 0;
        while (i < validator_count) {
            total_score = total_score + (*vector::borrow(&request.scores, i) as u64);
            i = i + 1;
        };
        let avg = total_score / validator_count;
        request.avg_score = avg;

        let now = clock::timestamp_ms(clock);
        let passed = avg >= VALIDATION_PASS_THRESHOLD;
        request.status = if (passed) { VALIDATION_PASSED } else { VALIDATION_FAILED };
        request.resolved_at = now;

        registry.total_validations = registry.total_validations + 1;

        // Update agent cred
        let old_cred = agent.cred_score;
        if (passed) {
            agent.cred_score = safe_add_cred(agent.cred_score, VALIDATION_PASS_CRED);
        } else {
            agent.cred_score = safe_sub_cred(agent.cred_score, VALIDATION_FAIL_CRED);
        };

        let new_cred = agent.cred_score;
        let agent_id = object::id(agent);
        emit_cred_update_if_changed(
            registry, agent, agent_id, old_cred, new_cred,
            string::utf8(b"validation"), now,
        );

        event::emit(ValidationResolved {
            request_id: request.request_id,
            agent_id,
            passed,
            avg_score: avg,
        });
    }

    // ====================== View / Query Functions =========================

    /// Get agent's current cred score (0-100)
    public fun get_agent_cred(agent: &AgentIdentity): u64 {
        agent.cred_score
    }

    /// Get agent's current visibility tier (0-4)
    public fun get_agent_visibility_tier(agent: &AgentIdentity): u8 {
        calculate_visibility_tier(agent.cred_score)
    }

    /// Check if agent is currently active
    public fun is_agent_active(agent: &AgentIdentity): bool {
        agent.is_active
    }

    /// Check if agent can join a room (active AND not suspended)
    public fun can_join_room(agent: &AgentIdentity): bool {
        agent.is_active && calculate_visibility_tier(agent.cred_score) != TIER_SUSPENDED
    }

    /// Get comprehensive agent stats tuple:
    /// (cred_score, total_sessions, total_feedback, positive_feedback, is_active)
    public fun get_agent_stats(agent: &AgentIdentity): (u64, u64, u64, u64, bool) {
        (
            agent.cred_score,
            agent.total_sessions,
            agent.total_feedback_received,
            agent.positive_feedback,
            agent.is_active,
        )
    }

    /// Get registry-level stats:
    /// (total_agents, total_active, total_feedback, total_validations)
    public fun get_registry_stats(registry: &AgentRegistry): (u64, u64, u64, u64) {
        (
            registry.total_agents,
            registry.total_active,
            registry.total_feedback,
            registry.total_validations,
        )
    }

    public fun get_agent_name(agent: &AgentIdentity): String {
        agent.name
    }

    public fun get_agent_category(agent: &AgentIdentity): u8 {
        agent.category
    }

    public fun get_agent_owner(agent: &AgentIdentity): address {
        agent.owner
    }

    public fun get_agent_wallet(agent: &AgentIdentity): address {
        agent.wallet
    }

    public fun get_agent_uri(agent: &AgentIdentity): String {
        agent.agent_uri
    }

    public fun get_agent_avatar_style(agent: &AgentIdentity): String {
        agent.avatar_style
    }

    /// Get all on-chain metadata as a reference to the VecMap.
    /// Allows other contracts to read agent capabilities, endpoints, etc.
    public fun get_agent_metadata(agent: &AgentIdentity): &VecMap<String, String> {
        &agent.metadata
    }

    /// Look up a single metadata value by key. Returns empty string if key not found.
    public fun get_metadata_value(agent: &AgentIdentity, key: &String): String {
        if (vec_map::contains(&agent.metadata, key)) {
            *vec_map::get(&agent.metadata, key)
        } else {
            string::utf8(b"")
        }
    }

    public fun get_agent_id(agent: &AgentIdentity): ID {
        object::id(agent)
    }

    public fun get_agent_registered_at(agent: &AgentIdentity): u64 {
        agent.registered_at
    }

    public fun get_agent_last_session_at(agent: &AgentIdentity): u64 {
        agent.last_session_at
    }

    public fun get_agent_negative_feedback(agent: &AgentIdentity): u64 {
        agent.negative_feedback
    }

    /// Check if an address has registered at least one agent
    public fun is_agent_registered(registry: &AgentRegistry, owner: address): bool {
        table::contains(&registry.agents, owner)
    }

    /// Get the number of agents registered by an address
    public fun get_agent_count(registry: &AgentRegistry, owner: address): u64 {
        if (table::contains(&registry.agents, owner)) {
            vector::length(table::borrow(&registry.agents, owner))
        } else {
            0
        }
    }

    public fun get_feedback_value(feedback: &AgentFeedback): u8 {
        feedback.value
    }

    public fun get_feedback_agent_id(feedback: &AgentFeedback): ID {
        feedback.agent_id
    }

    public fun get_feedback_client(feedback: &AgentFeedback): address {
        feedback.client
    }

    /// Get validation request status:
    /// (status, avg_score, validator_count)
    public fun get_validation_status(request: &ValidationRequest): (u8, u64, u64) {
        (
            request.status,
            request.avg_score,
            (vector::length(&request.validators) as u64),
        )
    }

    public fun get_validation_agent_id(request: &ValidationRequest): ID {
        request.agent_id
    }

    // ======================== Internal Functions ============================

    /// Calculate visibility tier from cred score.
    /// Returns: TIER_PRISTINE (0), TIER_STANDARD (1), TIER_RESTRICTED (2),
    ///          TIER_PROBATION (3), or TIER_SUSPENDED (4).
    fun calculate_visibility_tier(cred: u64): u8 {
        if (cred >= CRED_PRISTINE_MIN) { TIER_PRISTINE }
        else if (cred >= CRED_STANDARD_MIN) { TIER_STANDARD }
        else if (cred >= CRED_RESTRICTED_MIN) { TIER_RESTRICTED }
        else if (cred >= CRED_PROBATION_MIN) { TIER_PROBATION }
        else { TIER_SUSPENDED }
    }

    /// Safely add to cred, capping at MAX_CRED (100)
    fun safe_add_cred(current: u64, amount: u64): u64 {
        let result = current + amount;
        if (result > MAX_CRED) { MAX_CRED } else { result }
    }

    /// Safely subtract from cred, flooring at 0
    fun safe_sub_cred(current: u64, amount: u64): u64 {
        if (amount > current) { 0 } else { current - amount }
    }

    /// Helper: emit cred/tier events and handle auto-suspend if needed.
    /// Extracted to avoid code duplication between give_feedback and resolve_validation.
    fun emit_cred_update_if_changed(
        registry: &mut AgentRegistry,
        agent: &mut AgentIdentity,
        agent_id: ID,
        old_cred: u64,
        new_cred: u64,
        reason: String,
        now: u64,
    ) {
        if (old_cred != new_cred) {
            event::emit(CredUpdated {
                agent_id,
                old_cred,
                new_cred,
                reason,
            });

            let old_tier = calculate_visibility_tier(old_cred);
            let new_tier = calculate_visibility_tier(new_cred);
            if (old_tier != new_tier) {
                event::emit(VisibilityTierChanged {
                    agent_id,
                    old_tier,
                    new_tier,
                });

                // Auto-suspend if cred drops to TIER_SUSPENDED
                if (new_tier == TIER_SUSPENDED && agent.is_active) {
                    agent.is_active = false;
                    if (registry.total_active > 0) {
                        registry.total_active = registry.total_active - 1;
                    };
                    event::emit(AgentDeactivated {
                        agent_id,
                        owner: agent.owner,
                        timestamp: now,
                    });
                };
            };
        };
    }

    // ========================= Test Helpers =================================
    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }
}
