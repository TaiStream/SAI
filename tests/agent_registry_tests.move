#[test_only]
module sai::agent_registry_tests {
    use sui::test_scenario::{Self as ts, Scenario};
    use sui::clock::{Self, Clock};
    use std::string;
    use sai::agent_registry::{Self, AgentRegistry, AgentIdentity, AgentFeedback, ValidationRequest};

    // Test addresses (hex-only characters)
    const AGENT_OWNER: address = @0xA1;
    const AGENT_OWNER2: address = @0xA2;
    const USER1: address = @0xB1;
    const DELEGATE1: address = @0xC1;
    const DELEGATE2: address = @0xC2;
    const VALIDATOR1: address = @0xD1;
    const VALIDATOR2: address = @0xD2;
    const VALIDATOR3: address = @0xD3;

    // ========== Helper Functions ==========

    fun setup_test(): Scenario {
        let mut scenario = ts::begin(AGENT_OWNER);
        {
            agent_registry::init_for_testing(ts::ctx(&mut scenario));
        };
        scenario
    }

    fun create_clock(scenario: &mut Scenario): Clock {
        ts::next_tx(scenario, AGENT_OWNER);
        clock::create_for_testing(ts::ctx(scenario))
    }

    fun register_test_agent(scenario: &mut Scenario, clock: &Clock, owner: address) {
        ts::next_tx(scenario, owner);
        {
            let mut registry = ts::take_shared<AgentRegistry>(scenario);
            agent_registry::register_agent(
                &mut registry,
                string::utf8(b"Test Agent"),
                string::utf8(b"https://tai.network/agents/test.json"),
                owner,
                vector[],
                vector[],
                clock,
                ts::ctx(scenario)
            );
            ts::return_shared(registry);
        };
    }

    // ========== Registration Tests ==========

    #[test]
    fun test_register_agent_success() {
        let mut scenario = setup_test();
        let clock = create_clock(&mut scenario);

        ts::next_tx(&mut scenario, AGENT_OWNER);
        {
            let mut registry = ts::take_shared<AgentRegistry>(&scenario);

            agent_registry::register_agent(
                &mut registry,
                string::utf8(b"Meeting Assistant"),
                string::utf8(b"https://tai.network/agents/assistant.json"),
                AGENT_OWNER,
                vector[string::utf8(b"model")],
                vector[string::utf8(b"claude-haiku-4-5")],
                &clock,
                ts::ctx(&mut scenario)
            );

            let (total_agents, total_active, _, _) = agent_registry::get_registry_stats(&registry);
            assert!(total_agents == 1, 0);
            assert!(total_active == 1, 1);
            assert!(agent_registry::is_agent_registered(&registry, AGENT_OWNER), 2);

            ts::return_shared(registry);
        };

        ts::next_tx(&mut scenario, AGENT_OWNER);
        {
            let agent = ts::take_shared<AgentIdentity>(&scenario);

            // New agents start at STANDARD tier (cred 70), not PRISTINE
            assert!(agent_registry::get_agent_cred(&agent) == 70, 3);
            assert!(agent_registry::is_agent_active(&agent), 4);
            assert!(agent_registry::can_operate(&agent), 5);
            assert!(agent_registry::get_agent_owner(&agent) == AGENT_OWNER, 7);
            assert!(agent_registry::get_agent_visibility_tier(&agent) == 1, 8); // TIER_STANDARD

            let (cred, feedback, positive, active) = agent_registry::get_agent_stats(&agent);
            assert!(cred == 70, 9);
            assert!(feedback == 0, 11);
            assert!(positive == 0, 12);
            assert!(active == true, 13);

            ts::return_shared(agent);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    fun test_register_agent_multi() {
        // Contract supports multi-agent: same owner can register multiple agents
        let mut scenario = setup_test();
        let clock = create_clock(&mut scenario);

        register_test_agent(&mut scenario, &clock, AGENT_OWNER);

        ts::next_tx(&mut scenario, AGENT_OWNER);
        {
            let mut registry = ts::take_shared<AgentRegistry>(&scenario);
            agent_registry::register_agent(
                &mut registry,
                string::utf8(b"Second Agent"),
                string::utf8(b"https://example2.com"),
                AGENT_OWNER,
                vector[],
                vector[],
                &clock,
                ts::ctx(&mut scenario)
            );
            ts::return_shared(registry);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    fun test_register_multiple_agents() {
        let mut scenario = setup_test();
        let clock = create_clock(&mut scenario);

        register_test_agent(&mut scenario, &clock, AGENT_OWNER);
        register_test_agent(&mut scenario, &clock, AGENT_OWNER2);

        ts::next_tx(&mut scenario, AGENT_OWNER);
        {
            let registry = ts::take_shared<AgentRegistry>(&scenario);
            let (total_agents, total_active, _, _) = agent_registry::get_registry_stats(&registry);
            assert!(total_agents == 2, 0);
            assert!(total_active == 2, 1);
            ts::return_shared(registry);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // ========== Identity Update Tests ==========

    #[test]
    fun test_set_agent_uri() {
        let mut scenario = setup_test();
        let clock = create_clock(&mut scenario);
        register_test_agent(&mut scenario, &clock, AGENT_OWNER);

        ts::next_tx(&mut scenario, AGENT_OWNER);
        {
            let mut agent = ts::take_shared<AgentIdentity>(&scenario);
            agent_registry::set_agent_uri(
                &mut agent,
                string::utf8(b"https://tai.network/agents/v2.json"),
                &clock,
                ts::ctx(&mut scenario)
            );
            assert!(agent_registry::get_agent_uri(&agent) == string::utf8(b"https://tai.network/agents/v2.json"), 0);
            ts::return_shared(agent);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = agent_registry::ENotAgentOwner)]
    fun test_set_agent_uri_not_owner() {
        let mut scenario = setup_test();
        let clock = create_clock(&mut scenario);
        register_test_agent(&mut scenario, &clock, AGENT_OWNER);

        ts::next_tx(&mut scenario, USER1);
        {
            let mut agent = ts::take_shared<AgentIdentity>(&scenario);
            agent_registry::set_agent_uri(
                &mut agent,
                string::utf8(b"https://evil.com"),
                &clock,
                ts::ctx(&mut scenario)
            );
            ts::return_shared(agent);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    fun test_set_metadata() {
        let mut scenario = setup_test();
        let clock = create_clock(&mut scenario);
        register_test_agent(&mut scenario, &clock, AGENT_OWNER);

        ts::next_tx(&mut scenario, AGENT_OWNER);
        {
            let mut agent = ts::take_shared<AgentIdentity>(&scenario);
            agent_registry::set_metadata(
                &mut agent,
                string::utf8(b"model"),
                string::utf8(b"claude-haiku-4-5"),
                &clock,
                ts::ctx(&mut scenario)
            );
            agent_registry::set_metadata(
                &mut agent,
                string::utf8(b"model"),
                string::utf8(b"claude-sonnet-4-5"),
                &clock,
                ts::ctx(&mut scenario)
            );
            ts::return_shared(agent);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    fun test_set_agent_wallet() {
        let mut scenario = setup_test();
        let clock = create_clock(&mut scenario);
        register_test_agent(&mut scenario, &clock, AGENT_OWNER);

        ts::next_tx(&mut scenario, AGENT_OWNER);
        {
            let mut agent = ts::take_shared<AgentIdentity>(&scenario);
            let new_wallet = @0xFACE;
            agent_registry::set_agent_wallet(&mut agent, new_wallet, &clock, ts::ctx(&mut scenario));
            assert!(agent_registry::get_agent_wallet(&agent) == new_wallet, 0);
            ts::return_shared(agent);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // ========== Deactivate / Reactivate Tests ==========

    #[test]
    fun test_deactivate_and_reactivate() {
        let mut scenario = setup_test();
        let clock = create_clock(&mut scenario);
        register_test_agent(&mut scenario, &clock, AGENT_OWNER);

        ts::next_tx(&mut scenario, AGENT_OWNER);
        {
            let mut registry = ts::take_shared<AgentRegistry>(&scenario);
            let mut agent = ts::take_shared<AgentIdentity>(&scenario);

            agent_registry::deactivate_agent(&mut registry, &mut agent, &clock, ts::ctx(&mut scenario));
            assert!(!agent_registry::is_agent_active(&agent), 0);
            assert!(!agent_registry::can_operate(&agent), 1);

            let (_, total_active, _, _) = agent_registry::get_registry_stats(&registry);
            assert!(total_active == 0, 2);

            ts::return_shared(registry);
            ts::return_shared(agent);
        };

        ts::next_tx(&mut scenario, AGENT_OWNER);
        {
            let mut registry = ts::take_shared<AgentRegistry>(&scenario);
            let mut agent = ts::take_shared<AgentIdentity>(&scenario);

            agent_registry::reactivate_agent(&mut registry, &mut agent, &clock, ts::ctx(&mut scenario));
            assert!(agent_registry::is_agent_active(&agent), 3);
            assert!(agent_registry::can_operate(&agent), 4);

            ts::return_shared(registry);
            ts::return_shared(agent);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // ========== Feedback Tests ==========

    #[test]
    fun test_positive_feedback_increases_cred() {
        let mut scenario = setup_test();
        let clock = create_clock(&mut scenario);
        register_test_agent(&mut scenario, &clock, AGENT_OWNER);

        ts::next_tx(&mut scenario, USER1);
        {
            let mut registry = ts::take_shared<AgentRegistry>(&scenario);
            let mut agent = ts::take_shared<AgentIdentity>(&scenario);

            agent_registry::give_feedback(
                &mut registry, &mut agent, 5,
                string::utf8(b"meeting-assistant"), b"", b"room-123",
                &clock, ts::ctx(&mut scenario)
            );

            // 70 + 1 (positive feedback) = 71
            assert!(agent_registry::get_agent_cred(&agent) == 71, 0);

            let (_, total_feedback, positive, _) = agent_registry::get_agent_stats(&agent);
            assert!(total_feedback == 1, 1);
            assert!(positive == 1, 2);

            ts::return_shared(registry);
            ts::return_shared(agent);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    fun test_negative_feedback_decreases_cred() {
        let mut scenario = setup_test();
        let clock = create_clock(&mut scenario);
        register_test_agent(&mut scenario, &clock, AGENT_OWNER);

        ts::next_tx(&mut scenario, USER1);
        {
            let mut registry = ts::take_shared<AgentRegistry>(&scenario);
            let mut agent = ts::take_shared<AgentIdentity>(&scenario);

            agent_registry::give_feedback(
                &mut registry, &mut agent, 1,
                string::utf8(b"bad-response"), b"", b"room-123",
                &clock, ts::ctx(&mut scenario)
            );

            // 70 - 3 (negative feedback) = 67 → TIER_RESTRICTED
            assert!(agent_registry::get_agent_cred(&agent) == 67, 0);
            assert!(agent_registry::get_agent_visibility_tier(&agent) == 2, 1);

            ts::return_shared(registry);
            ts::return_shared(agent);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    fun test_neutral_feedback_no_cred_change() {
        let mut scenario = setup_test();
        let clock = create_clock(&mut scenario);
        register_test_agent(&mut scenario, &clock, AGENT_OWNER);

        ts::next_tx(&mut scenario, USER1);
        {
            let mut registry = ts::take_shared<AgentRegistry>(&scenario);
            let mut agent = ts::take_shared<AgentIdentity>(&scenario);

            agent_registry::give_feedback(
                &mut registry, &mut agent, 3,
                string::utf8(b"ok"), b"", b"room-123",
                &clock, ts::ctx(&mut scenario)
            );

            // Neutral feedback = no cred change, stays at 70
            assert!(agent_registry::get_agent_cred(&agent) == 70, 0);
            ts::return_shared(registry);
            ts::return_shared(agent);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = agent_registry::ESelfFeedback)]
    fun test_cannot_self_feedback() {
        let mut scenario = setup_test();
        let clock = create_clock(&mut scenario);
        register_test_agent(&mut scenario, &clock, AGENT_OWNER);

        ts::next_tx(&mut scenario, AGENT_OWNER);
        {
            let mut registry = ts::take_shared<AgentRegistry>(&scenario);
            let mut agent = ts::take_shared<AgentIdentity>(&scenario);

            agent_registry::give_feedback(
                &mut registry, &mut agent, 5,
                string::utf8(b"self-boost"), b"", b"room-123",
                &clock, ts::ctx(&mut scenario)
            );

            ts::return_shared(registry);
            ts::return_shared(agent);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = agent_registry::EInvalidFeedbackValue)]
    fun test_invalid_feedback_value_zero() {
        let mut scenario = setup_test();
        let clock = create_clock(&mut scenario);
        register_test_agent(&mut scenario, &clock, AGENT_OWNER);

        ts::next_tx(&mut scenario, USER1);
        {
            let mut registry = ts::take_shared<AgentRegistry>(&scenario);
            let mut agent = ts::take_shared<AgentIdentity>(&scenario);

            agent_registry::give_feedback(
                &mut registry, &mut agent, 0,
                string::utf8(b"test"), b"", b"room-123",
                &clock, ts::ctx(&mut scenario)
            );

            ts::return_shared(registry);
            ts::return_shared(agent);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = agent_registry::EInvalidFeedbackValue)]
    fun test_invalid_feedback_value_six() {
        let mut scenario = setup_test();
        let clock = create_clock(&mut scenario);
        register_test_agent(&mut scenario, &clock, AGENT_OWNER);

        ts::next_tx(&mut scenario, USER1);
        {
            let mut registry = ts::take_shared<AgentRegistry>(&scenario);
            let mut agent = ts::take_shared<AgentIdentity>(&scenario);

            agent_registry::give_feedback(
                &mut registry, &mut agent, 6,
                string::utf8(b"test"), b"", b"room-123",
                &clock, ts::ctx(&mut scenario)
            );

            ts::return_shared(registry);
            ts::return_shared(agent);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    fun test_feedback_creates_nft_for_reviewer() {
        let mut scenario = setup_test();
        let clock = create_clock(&mut scenario);
        register_test_agent(&mut scenario, &clock, AGENT_OWNER);

        ts::next_tx(&mut scenario, USER1);
        {
            let mut registry = ts::take_shared<AgentRegistry>(&scenario);
            let mut agent = ts::take_shared<AgentIdentity>(&scenario);

            agent_registry::give_feedback(
                &mut registry, &mut agent, 4,
                string::utf8(b"helpful"), b"", b"room-123",
                &clock, ts::ctx(&mut scenario)
            );

            ts::return_shared(registry);
            ts::return_shared(agent);
        };

        ts::next_tx(&mut scenario, USER1);
        {
            let feedback = ts::take_from_sender<AgentFeedback>(&scenario);
            assert!(agent_registry::get_feedback_value(&feedback) == 4, 0);
            ts::return_to_sender(&scenario, feedback);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // ========== Cred Tier Transition Tests ==========

    #[test]
    fun test_cred_drops_to_standard_tier() {
        let mut scenario = setup_test();
        let clock = create_clock(&mut scenario);
        register_test_agent(&mut scenario, &clock, AGENT_OWNER);

        let mut i = 0;
        let users = vector[@0xB1, @0xB2, @0xB3, @0xB4];
        while (i < 4) {
            let user = *vector::borrow(&users, i);
            ts::next_tx(&mut scenario, user);
            {
                let mut registry = ts::take_shared<AgentRegistry>(&scenario);
                let mut agent = ts::take_shared<AgentIdentity>(&scenario);

                agent_registry::give_feedback(
                    &mut registry, &mut agent, 1,
                    string::utf8(b"bad"), b"", b"room",
                    &clock, ts::ctx(&mut scenario)
                );

                ts::return_shared(registry);
                ts::return_shared(agent);
            };
            i = i + 1;
        };

        ts::next_tx(&mut scenario, AGENT_OWNER);
        {
            let agent = ts::take_shared<AgentIdentity>(&scenario);
            // 70 - (4 * 3) = 58 → TIER_RESTRICTED
            assert!(agent_registry::get_agent_cred(&agent) == 58, 0);
            assert!(agent_registry::get_agent_visibility_tier(&agent) == 2, 1);
            assert!(agent_registry::can_operate(&agent), 2);
            ts::return_shared(agent);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // ========== Validation Tests ==========

    #[test]
    fun test_request_validation() {
        let mut scenario = setup_test();
        let clock = create_clock(&mut scenario);
        register_test_agent(&mut scenario, &clock, AGENT_OWNER);

        ts::next_tx(&mut scenario, AGENT_OWNER);
        {
            let mut registry = ts::take_shared<AgentRegistry>(&scenario);
            let agent = ts::take_shared<AgentIdentity>(&scenario);

            agent_registry::request_validation(
                &mut registry, &agent,
                string::utf8(b"https://tai.network/validations/req-001.json"),
                b"hash123",
                &clock, ts::ctx(&mut scenario)
            );

            ts::return_shared(registry);
            ts::return_shared(agent);
        };

        ts::next_tx(&mut scenario, AGENT_OWNER);
        {
            let request = ts::take_shared<ValidationRequest>(&scenario);
            let (status, avg_score, validator_count) = agent_registry::get_validation_status(&request);
            assert!(status == 0, 0);
            assert!(avg_score == 0, 1);
            assert!(validator_count == 0, 2);
            ts::return_shared(request);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    fun test_submit_validations_and_resolve_pass() {
        let mut scenario = setup_test();
        let clock = create_clock(&mut scenario);
        register_test_agent(&mut scenario, &clock, AGENT_OWNER);

        ts::next_tx(&mut scenario, AGENT_OWNER);
        {
            let mut registry = ts::take_shared<AgentRegistry>(&scenario);
            let agent = ts::take_shared<AgentIdentity>(&scenario);
            agent_registry::request_validation(
                &mut registry, &agent,
                string::utf8(b"https://tai.network/validations/req-001.json"),
                b"hash123", &clock, ts::ctx(&mut scenario)
            );
            ts::return_shared(registry);
            ts::return_shared(agent);
        };

        ts::next_tx(&mut scenario, VALIDATOR1);
        {
            let mut request = ts::take_shared<ValidationRequest>(&scenario);
            agent_registry::submit_validation(&mut request, 80, string::utf8(b"safety"), ts::ctx(&mut scenario));
            ts::return_shared(request);
        };

        ts::next_tx(&mut scenario, VALIDATOR2);
        {
            let mut request = ts::take_shared<ValidationRequest>(&scenario);
            agent_registry::submit_validation(&mut request, 70, string::utf8(b"accuracy"), ts::ctx(&mut scenario));
            ts::return_shared(request);
        };

        ts::next_tx(&mut scenario, VALIDATOR3);
        {
            let mut request = ts::take_shared<ValidationRequest>(&scenario);
            agent_registry::submit_validation(&mut request, 90, string::utf8(b"helpfulness"), ts::ctx(&mut scenario));
            ts::return_shared(request);
        };

        ts::next_tx(&mut scenario, AGENT_OWNER);
        {
            let mut registry = ts::take_shared<AgentRegistry>(&scenario);
            let mut agent = ts::take_shared<AgentIdentity>(&scenario);
            let mut request = ts::take_shared<ValidationRequest>(&scenario);

            agent_registry::resolve_validation(
                &mut registry, &mut agent, &mut request,
                &clock, ts::ctx(&mut scenario)
            );

            let (status, avg_score, validator_count) = agent_registry::get_validation_status(&request);
            assert!(status == 1, 0);
            assert!(avg_score == 80, 1);
            assert!(validator_count == 3, 2);
            // 70 + 2 (validation pass) = 72
            assert!(agent_registry::get_agent_cred(&agent) == 72, 3);

            let (_, _, _, total_validations) = agent_registry::get_registry_stats(&registry);
            assert!(total_validations == 1, 4);

            ts::return_shared(registry);
            ts::return_shared(agent);
            ts::return_shared(request);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    fun test_validation_failure_decreases_cred() {
        let mut scenario = setup_test();
        let clock = create_clock(&mut scenario);
        register_test_agent(&mut scenario, &clock, AGENT_OWNER);

        ts::next_tx(&mut scenario, AGENT_OWNER);
        {
            let mut registry = ts::take_shared<AgentRegistry>(&scenario);
            let agent = ts::take_shared<AgentIdentity>(&scenario);
            agent_registry::request_validation(
                &mut registry, &agent,
                string::utf8(b"https://test.com"), b"hash",
                &clock, ts::ctx(&mut scenario)
            );
            ts::return_shared(registry);
            ts::return_shared(agent);
        };

        let validators = vector[VALIDATOR1, VALIDATOR2, VALIDATOR3];
        let scores = vector[30u8, 40u8, 50u8];
        let mut i = 0;
        while (i < 3) {
            let v = *vector::borrow(&validators, i);
            let s = *vector::borrow(&scores, i);
            ts::next_tx(&mut scenario, v);
            {
                let mut request = ts::take_shared<ValidationRequest>(&scenario);
                agent_registry::submit_validation(&mut request, s, string::utf8(b"test"), ts::ctx(&mut scenario));
                ts::return_shared(request);
            };
            i = i + 1;
        };

        ts::next_tx(&mut scenario, AGENT_OWNER);
        {
            let mut registry = ts::take_shared<AgentRegistry>(&scenario);
            let mut agent = ts::take_shared<AgentIdentity>(&scenario);
            let mut request = ts::take_shared<ValidationRequest>(&scenario);

            agent_registry::resolve_validation(
                &mut registry, &mut agent, &mut request,
                &clock, ts::ctx(&mut scenario)
            );

            let (status, _, _) = agent_registry::get_validation_status(&request);
            assert!(status == 2, 0);
            // 70 - 10 (validation fail) = 60 → TIER_RESTRICTED
            assert!(agent_registry::get_agent_cred(&agent) == 60, 1);
            assert!(agent_registry::get_agent_visibility_tier(&agent) == 2, 2);

            ts::return_shared(registry);
            ts::return_shared(agent);
            ts::return_shared(request);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = agent_registry::ECannotValidateSelf)]
    fun test_cannot_validate_own_agent() {
        let mut scenario = setup_test();
        let clock = create_clock(&mut scenario);
        register_test_agent(&mut scenario, &clock, AGENT_OWNER);

        ts::next_tx(&mut scenario, AGENT_OWNER);
        {
            let mut registry = ts::take_shared<AgentRegistry>(&scenario);
            let agent = ts::take_shared<AgentIdentity>(&scenario);
            agent_registry::request_validation(
                &mut registry, &agent,
                string::utf8(b"https://test.com"), b"hash",
                &clock, ts::ctx(&mut scenario)
            );
            ts::return_shared(registry);
            ts::return_shared(agent);
        };

        ts::next_tx(&mut scenario, AGENT_OWNER);
        {
            let mut request = ts::take_shared<ValidationRequest>(&scenario);
            agent_registry::submit_validation(&mut request, 100, string::utf8(b"self"), ts::ctx(&mut scenario));
            ts::return_shared(request);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = agent_registry::EAlreadyValidated)]
    fun test_cannot_validate_twice() {
        let mut scenario = setup_test();
        let clock = create_clock(&mut scenario);
        register_test_agent(&mut scenario, &clock, AGENT_OWNER);

        ts::next_tx(&mut scenario, AGENT_OWNER);
        {
            let mut registry = ts::take_shared<AgentRegistry>(&scenario);
            let agent = ts::take_shared<AgentIdentity>(&scenario);
            agent_registry::request_validation(
                &mut registry, &agent,
                string::utf8(b"https://test.com"), b"hash",
                &clock, ts::ctx(&mut scenario)
            );
            ts::return_shared(registry);
            ts::return_shared(agent);
        };

        ts::next_tx(&mut scenario, VALIDATOR1);
        {
            let mut request = ts::take_shared<ValidationRequest>(&scenario);
            agent_registry::submit_validation(&mut request, 80, string::utf8(b"first"), ts::ctx(&mut scenario));
            ts::return_shared(request);
        };

        ts::next_tx(&mut scenario, VALIDATOR1);
        {
            let mut request = ts::take_shared<ValidationRequest>(&scenario);
            agent_registry::submit_validation(&mut request, 90, string::utf8(b"second"), ts::ctx(&mut scenario));
            ts::return_shared(request);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = agent_registry::EInsufficientValidators)]
    fun test_cannot_resolve_without_min_validators() {
        let mut scenario = setup_test();
        let clock = create_clock(&mut scenario);
        register_test_agent(&mut scenario, &clock, AGENT_OWNER);

        ts::next_tx(&mut scenario, AGENT_OWNER);
        {
            let mut registry = ts::take_shared<AgentRegistry>(&scenario);
            let agent = ts::take_shared<AgentIdentity>(&scenario);
            agent_registry::request_validation(
                &mut registry, &agent,
                string::utf8(b"https://test.com"), b"hash",
                &clock, ts::ctx(&mut scenario)
            );
            ts::return_shared(registry);
            ts::return_shared(agent);
        };

        ts::next_tx(&mut scenario, VALIDATOR1);
        {
            let mut request = ts::take_shared<ValidationRequest>(&scenario);
            agent_registry::submit_validation(&mut request, 80, string::utf8(b"test"), ts::ctx(&mut scenario));
            ts::return_shared(request);
        };

        ts::next_tx(&mut scenario, VALIDATOR2);
        {
            let mut request = ts::take_shared<ValidationRequest>(&scenario);
            agent_registry::submit_validation(&mut request, 70, string::utf8(b"test"), ts::ctx(&mut scenario));
            ts::return_shared(request);
        };

        ts::next_tx(&mut scenario, AGENT_OWNER);
        {
            let mut registry = ts::take_shared<AgentRegistry>(&scenario);
            let mut agent = ts::take_shared<AgentIdentity>(&scenario);
            let mut request = ts::take_shared<ValidationRequest>(&scenario);

            agent_registry::resolve_validation(
                &mut registry, &mut agent, &mut request,
                &clock, ts::ctx(&mut scenario)
            );

            ts::return_shared(registry);
            ts::return_shared(agent);
            ts::return_shared(request);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // ========== Name Update Tests ==========

    #[test]
    fun test_set_agent_name() {
        let mut scenario = setup_test();
        let clock = create_clock(&mut scenario);
        register_test_agent(&mut scenario, &clock, AGENT_OWNER);

        ts::next_tx(&mut scenario, AGENT_OWNER);
        {
            let mut agent = ts::take_shared<AgentIdentity>(&scenario);
            agent_registry::set_agent_name(
                &mut agent,
                string::utf8(b"Renamed Agent"),
                &clock,
                ts::ctx(&mut scenario)
            );
            assert!(agent_registry::get_agent_name(&agent) == string::utf8(b"Renamed Agent"), 0);
            ts::return_shared(agent);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = agent_registry::EEmptyName)]
    fun test_set_agent_name_empty() {
        let mut scenario = setup_test();
        let clock = create_clock(&mut scenario);
        register_test_agent(&mut scenario, &clock, AGENT_OWNER);

        ts::next_tx(&mut scenario, AGENT_OWNER);
        {
            let mut agent = ts::take_shared<AgentIdentity>(&scenario);
            agent_registry::set_agent_name(
                &mut agent,
                string::utf8(b""),
                &clock,
                ts::ctx(&mut scenario)
            );
            ts::return_shared(agent);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // ========== Remove Metadata Tests ==========

    #[test]
    fun test_remove_metadata() {
        let mut scenario = setup_test();
        let clock = create_clock(&mut scenario);

        // Register with metadata
        ts::next_tx(&mut scenario, AGENT_OWNER);
        {
            let mut registry = ts::take_shared<AgentRegistry>(&scenario);
            agent_registry::register_agent(
                &mut registry,
                string::utf8(b"Agent"),
                string::utf8(b"https://example.com"),
                AGENT_OWNER,
                vector[string::utf8(b"model"), string::utf8(b"version")],
                vector[string::utf8(b"gpt-4"), string::utf8(b"1.0")],
                &clock,
                ts::ctx(&mut scenario)
            );
            ts::return_shared(registry);
        };

        ts::next_tx(&mut scenario, AGENT_OWNER);
        {
            let mut agent = ts::take_shared<AgentIdentity>(&scenario);

            // Verify metadata exists
            let key = string::utf8(b"model");
            assert!(agent_registry::get_metadata_value(&agent, &key) == string::utf8(b"gpt-4"), 0);

            // Remove it
            agent_registry::remove_metadata(
                &mut agent,
                string::utf8(b"model"),
                &clock,
                ts::ctx(&mut scenario)
            );

            // Verify removed (returns empty string)
            assert!(agent_registry::get_metadata_value(&agent, &key) == string::utf8(b""), 1);

            // Other key still exists
            let version_key = string::utf8(b"version");
            assert!(agent_registry::get_metadata_value(&agent, &version_key) == string::utf8(b"1.0"), 2);

            ts::return_shared(agent);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // ========== Batch Metadata Tests ==========

    #[test]
    fun test_set_metadata_batch() {
        let mut scenario = setup_test();
        let clock = create_clock(&mut scenario);
        register_test_agent(&mut scenario, &clock, AGENT_OWNER);

        ts::next_tx(&mut scenario, AGENT_OWNER);
        {
            let mut agent = ts::take_shared<AgentIdentity>(&scenario);
            agent_registry::set_metadata_batch(
                &mut agent,
                vector[
                    string::utf8(b"model"),
                    string::utf8(b"a2a_endpoint"),
                    string::utf8(b"framework"),
                ],
                vector[
                    string::utf8(b"claude-haiku-4-5"),
                    string::utf8(b"https://agent.example.com/a2a"),
                    string::utf8(b"langchain"),
                ],
                &clock,
                ts::ctx(&mut scenario)
            );

            let k1 = string::utf8(b"model");
            let k2 = string::utf8(b"a2a_endpoint");
            let k3 = string::utf8(b"framework");
            assert!(agent_registry::get_metadata_value(&agent, &k1) == string::utf8(b"claude-haiku-4-5"), 0);
            assert!(agent_registry::get_metadata_value(&agent, &k2) == string::utf8(b"https://agent.example.com/a2a"), 1);
            assert!(agent_registry::get_metadata_value(&agent, &k3) == string::utf8(b"langchain"), 2);

            ts::return_shared(agent);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = agent_registry::EMetadataLengthMismatch)]
    fun test_set_metadata_batch_length_mismatch() {
        let mut scenario = setup_test();
        let clock = create_clock(&mut scenario);
        register_test_agent(&mut scenario, &clock, AGENT_OWNER);

        ts::next_tx(&mut scenario, AGENT_OWNER);
        {
            let mut agent = ts::take_shared<AgentIdentity>(&scenario);
            agent_registry::set_metadata_batch(
                &mut agent,
                vector[string::utf8(b"model")],
                vector[string::utf8(b"gpt-4"), string::utf8(b"extra")],
                &clock,
                ts::ctx(&mut scenario)
            );
            ts::return_shared(agent);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // ========== Transfer Ownership Tests ==========

    #[test]
    fun test_transfer_ownership() {
        let mut scenario = setup_test();
        let clock = create_clock(&mut scenario);
        register_test_agent(&mut scenario, &clock, AGENT_OWNER);

        ts::next_tx(&mut scenario, AGENT_OWNER);
        {
            let mut registry = ts::take_shared<AgentRegistry>(&scenario);
            let mut agent = ts::take_shared<AgentIdentity>(&scenario);

            agent_registry::transfer_ownership(
                &mut registry, &mut agent, AGENT_OWNER2,
                &clock, ts::ctx(&mut scenario)
            );

            assert!(agent_registry::get_agent_owner(&agent) == AGENT_OWNER2, 0);
            // Old owner no longer has agents
            assert!(agent_registry::get_agent_count(&registry, AGENT_OWNER) == 0, 1);
            // New owner has the agent
            assert!(agent_registry::get_agent_count(&registry, AGENT_OWNER2) == 1, 2);

            ts::return_shared(registry);
            ts::return_shared(agent);
        };

        // New owner can update the agent
        ts::next_tx(&mut scenario, AGENT_OWNER2);
        {
            let mut agent = ts::take_shared<AgentIdentity>(&scenario);
            agent_registry::set_agent_name(
                &mut agent,
                string::utf8(b"New Owner's Agent"),
                &clock,
                ts::ctx(&mut scenario)
            );
            assert!(agent_registry::get_agent_name(&agent) == string::utf8(b"New Owner's Agent"), 3);
            ts::return_shared(agent);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = agent_registry::ENotAgentOwner)]
    fun test_transfer_ownership_not_owner() {
        let mut scenario = setup_test();
        let clock = create_clock(&mut scenario);
        register_test_agent(&mut scenario, &clock, AGENT_OWNER);

        ts::next_tx(&mut scenario, USER1);
        {
            let mut registry = ts::take_shared<AgentRegistry>(&scenario);
            let mut agent = ts::take_shared<AgentIdentity>(&scenario);

            agent_registry::transfer_ownership(
                &mut registry, &mut agent, USER1,
                &clock, ts::ctx(&mut scenario)
            );

            ts::return_shared(registry);
            ts::return_shared(agent);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // ========== Unregister Tests ==========

    #[test]
    fun test_unregister_agent() {
        let mut scenario = setup_test();
        let clock = create_clock(&mut scenario);
        register_test_agent(&mut scenario, &clock, AGENT_OWNER);

        ts::next_tx(&mut scenario, AGENT_OWNER);
        {
            let mut registry = ts::take_shared<AgentRegistry>(&scenario);
            let mut agent = ts::take_shared<AgentIdentity>(&scenario);

            // Verify agent is active and registered
            assert!(agent_registry::is_agent_active(&agent), 0);
            assert!(agent_registry::get_agent_count(&registry, AGENT_OWNER) == 1, 1);

            agent_registry::unregister_agent(
                &mut registry, &mut agent,
                &clock, ts::ctx(&mut scenario)
            );

            // Agent deactivated
            assert!(!agent_registry::is_agent_active(&agent), 2);
            // Removed from registry lookup
            assert!(agent_registry::get_agent_count(&registry, AGENT_OWNER) == 0, 3);
            // Counters updated
            let (total_agents, total_active, _, _) = agent_registry::get_registry_stats(&registry);
            assert!(total_agents == 0, 4);
            assert!(total_active == 0, 5);

            ts::return_shared(registry);
            ts::return_shared(agent);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = agent_registry::ENotAgentOwner)]
    fun test_unregister_agent_not_owner() {
        let mut scenario = setup_test();
        let clock = create_clock(&mut scenario);
        register_test_agent(&mut scenario, &clock, AGENT_OWNER);

        ts::next_tx(&mut scenario, USER1);
        {
            let mut registry = ts::take_shared<AgentRegistry>(&scenario);
            let mut agent = ts::take_shared<AgentIdentity>(&scenario);

            agent_registry::unregister_agent(
                &mut registry, &mut agent,
                &clock, ts::ctx(&mut scenario)
            );

            ts::return_shared(registry);
            ts::return_shared(agent);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // ========== Validation Edge Case Tests ==========

    // ========== Delegate Tests ==========

    #[test]
    fun test_add_delegate() {
        let mut scenario = setup_test();
        let clock = create_clock(&mut scenario);
        register_test_agent(&mut scenario, &clock, AGENT_OWNER);

        ts::next_tx(&mut scenario, AGENT_OWNER);
        {
            let mut agent = ts::take_shared<AgentIdentity>(&scenario);
            agent_registry::add_delegate(&mut agent, DELEGATE1, &clock, ts::ctx(&mut scenario));
            assert!(agent_registry::is_authorized(&agent, DELEGATE1), 0);
            assert!(vector::length(agent_registry::get_agent_delegates(&agent)) == 1, 1);
            ts::return_shared(agent);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    fun test_remove_delegate() {
        let mut scenario = setup_test();
        let clock = create_clock(&mut scenario);
        register_test_agent(&mut scenario, &clock, AGENT_OWNER);

        ts::next_tx(&mut scenario, AGENT_OWNER);
        {
            let mut agent = ts::take_shared<AgentIdentity>(&scenario);
            agent_registry::add_delegate(&mut agent, DELEGATE1, &clock, ts::ctx(&mut scenario));
            assert!(agent_registry::is_authorized(&agent, DELEGATE1), 0);

            agent_registry::remove_delegate(&mut agent, DELEGATE1, &clock, ts::ctx(&mut scenario));
            assert!(!agent_registry::is_authorized(&agent, DELEGATE1), 1);
            assert!(vector::length(agent_registry::get_agent_delegates(&agent)) == 0, 2);
            ts::return_shared(agent);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = agent_registry::ENotAgentOwner)]
    fun test_add_delegate_not_owner() {
        let mut scenario = setup_test();
        let clock = create_clock(&mut scenario);
        register_test_agent(&mut scenario, &clock, AGENT_OWNER);

        ts::next_tx(&mut scenario, USER1);
        {
            let mut agent = ts::take_shared<AgentIdentity>(&scenario);
            agent_registry::add_delegate(&mut agent, DELEGATE1, &clock, ts::ctx(&mut scenario));
            ts::return_shared(agent);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = agent_registry::EDelegateAlreadyExists)]
    fun test_duplicate_delegate() {
        let mut scenario = setup_test();
        let clock = create_clock(&mut scenario);
        register_test_agent(&mut scenario, &clock, AGENT_OWNER);

        ts::next_tx(&mut scenario, AGENT_OWNER);
        {
            let mut agent = ts::take_shared<AgentIdentity>(&scenario);
            agent_registry::add_delegate(&mut agent, DELEGATE1, &clock, ts::ctx(&mut scenario));
            agent_registry::add_delegate(&mut agent, DELEGATE1, &clock, ts::ctx(&mut scenario));
            ts::return_shared(agent);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = agent_registry::EDelegateNotFound)]
    fun test_delegate_not_found() {
        let mut scenario = setup_test();
        let clock = create_clock(&mut scenario);
        register_test_agent(&mut scenario, &clock, AGENT_OWNER);

        ts::next_tx(&mut scenario, AGENT_OWNER);
        {
            let mut agent = ts::take_shared<AgentIdentity>(&scenario);
            agent_registry::remove_delegate(&mut agent, DELEGATE1, &clock, ts::ctx(&mut scenario));
            ts::return_shared(agent);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = agent_registry::ETooManyDelegates)]
    fun test_too_many_delegates() {
        let mut scenario = setup_test();
        let clock = create_clock(&mut scenario);
        register_test_agent(&mut scenario, &clock, AGENT_OWNER);

        ts::next_tx(&mut scenario, AGENT_OWNER);
        {
            let mut agent = ts::take_shared<AgentIdentity>(&scenario);
            // Add 11 delegates (MAX_DELEGATES = 10, so 11th should fail)
            let addrs = vector[
                @0xE01, @0xE02, @0xE03, @0xE04, @0xE05,
                @0xE06, @0xE07, @0xE08, @0xE09, @0xE0A,
                @0xE0B,
            ];
            let mut i = 0;
            while (i < 11) {
                agent_registry::add_delegate(
                    &mut agent,
                    *vector::borrow(&addrs, i),
                    &clock,
                    ts::ctx(&mut scenario)
                );
                i = i + 1;
            };
            ts::return_shared(agent);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    fun test_is_authorized_owner_wallet_delegate() {
        let mut scenario = setup_test();
        let clock = create_clock(&mut scenario);

        // Register with a different wallet address
        ts::next_tx(&mut scenario, AGENT_OWNER);
        {
            let mut registry = ts::take_shared<AgentRegistry>(&scenario);
            agent_registry::register_agent(
                &mut registry,
                string::utf8(b"Test Agent"),
                string::utf8(b"https://tai.network/agents/test.json"),
                @0xFACE, // wallet differs from owner
                vector[],
                vector[],
                &clock,
                ts::ctx(&mut scenario)
            );
            ts::return_shared(registry);
        };

        ts::next_tx(&mut scenario, AGENT_OWNER);
        {
            let mut agent = ts::take_shared<AgentIdentity>(&scenario);
            agent_registry::add_delegate(&mut agent, DELEGATE1, &clock, ts::ctx(&mut scenario));

            // Owner is authorized
            assert!(agent_registry::is_authorized(&agent, AGENT_OWNER), 0);
            // Wallet is authorized
            assert!(agent_registry::is_authorized(&agent, @0xFACE), 1);
            // Delegate is authorized
            assert!(agent_registry::is_authorized(&agent, DELEGATE1), 2);
            // Random address is NOT authorized
            assert!(!agent_registry::is_authorized(&agent, @0xDEAD), 3);

            ts::return_shared(agent);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    fun test_transfer_clears_delegates() {
        let mut scenario = setup_test();
        let clock = create_clock(&mut scenario);
        register_test_agent(&mut scenario, &clock, AGENT_OWNER);

        ts::next_tx(&mut scenario, AGENT_OWNER);
        {
            let mut agent = ts::take_shared<AgentIdentity>(&scenario);
            agent_registry::add_delegate(&mut agent, DELEGATE1, &clock, ts::ctx(&mut scenario));
            agent_registry::add_delegate(&mut agent, DELEGATE2, &clock, ts::ctx(&mut scenario));
            assert!(vector::length(agent_registry::get_agent_delegates(&agent)) == 2, 0);
            ts::return_shared(agent);
        };

        ts::next_tx(&mut scenario, AGENT_OWNER);
        {
            let mut registry = ts::take_shared<AgentRegistry>(&scenario);
            let mut agent = ts::take_shared<AgentIdentity>(&scenario);

            agent_registry::transfer_ownership(
                &mut registry, &mut agent, AGENT_OWNER2,
                &clock, ts::ctx(&mut scenario)
            );

            // Delegates should be cleared
            assert!(vector::length(agent_registry::get_agent_delegates(&agent)) == 0, 1);
            assert!(!agent_registry::is_authorized(&agent, DELEGATE1), 2);
            assert!(!agent_registry::is_authorized(&agent, DELEGATE2), 3);
            // New owner is authorized
            assert!(agent_registry::is_authorized(&agent, AGENT_OWNER2), 4);

            ts::return_shared(registry);
            ts::return_shared(agent);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // ========== Validation Edge Case Tests ==========

    #[test]
    #[expected_failure(abort_code = agent_registry::EInvalidValidationScore)]
    fun test_invalid_validation_score() {
        let mut scenario = setup_test();
        let clock = create_clock(&mut scenario);
        register_test_agent(&mut scenario, &clock, AGENT_OWNER);

        ts::next_tx(&mut scenario, AGENT_OWNER);
        {
            let mut registry = ts::take_shared<AgentRegistry>(&scenario);
            let agent = ts::take_shared<AgentIdentity>(&scenario);
            agent_registry::request_validation(
                &mut registry, &agent,
                string::utf8(b"https://test.com"), b"hash",
                &clock, ts::ctx(&mut scenario)
            );
            ts::return_shared(registry);
            ts::return_shared(agent);
        };

        ts::next_tx(&mut scenario, VALIDATOR1);
        {
            let mut request = ts::take_shared<ValidationRequest>(&scenario);
            agent_registry::submit_validation(&mut request, 101, string::utf8(b"test"), ts::ctx(&mut scenario));
            ts::return_shared(request);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }
}
