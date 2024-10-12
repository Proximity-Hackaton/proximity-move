module proximity::proximity_test {
    use sui::test_scenario;
    use sui::clock::{Self, Clock};
    use proximity::proximity;

    /// Test Scenario 1: Module Initialization Verification
    ///
    /// In this test, we simulate the initialization of the `proximity::proximity` module.
    /// We aim to verify that:
    /// - The `UserRegistry` is correctly initialized and shared.
    /// - The initialization process behaves as expected without errors.
    ///
    /// Steps:
    /// 1. Define test addresses representing the admin and an initial owner.
    /// 2. Begin a new test scenario with the admin as the sender.
    /// 3. Call the `init_test` function to initialize the module.
    /// 4. Advance to the next transaction and capture the transaction effects.
    /// 5. Verify that exactly one shared object (the `UserRegistry`) was created.
    /// 6. End the test scenario.
    ///
    /// This test ensures that the module's initialization process sets up the necessary shared objects and that the initial state is as expected.
    #[test]
    fun test_module_init() {

        // Create test addresses representing users
        let admin = @0xAD;
        // Begin a new test scenario
        // First transaction to emulate module initialization

        // Create a mock Clock object
        let mut scenario = test_scenario::begin(admin);
        //let clock = clock::create_for_testing(scenario.ctx());
        proximity::init_test(scenario.ctx());

        // First transaction: Initialize the UserRegistry
        let prev_effects= scenario.next_tx(admin);
        {
            let shared_ids = prev_effects.shared();
            assert!(shared_ids.length() == 1, 1);
        };

        // End the test scenario
        scenario.end();
    }

    /// Test Scenario 2: Multiple User Registration Verification
    ///
    /// In this test, we simulate multiple users initializing themselves in the proximity network.
    /// We aim to verify that:
    /// - Each user is correctly added to the `registered_users` list in the `UserRegistry`.
    /// - The `get_registered_users` function returns the correct list of registered users.
    ///
    /// Steps:
    /// 1. Initialize the proximity module with an admin address.
    /// 2. Simulate multiple users (user1, user2, user3) initializing themselves.
    /// 3. Retrieve the list of registered users using `get_registered_users`.
    /// 4. Verify that all unique users are registered correctly.
    ///
    /// This test ensures that the module's user registration functionality works as expected and that
    /// the `UserRegistry` accurately reflects the current registered users.
    #[test]
    fun test_multiple_user_registration() {
        use sui::test_scenario as ts;

        // Initialize test addresses
        let admin = @0x1;
        let user1 = @0x2;
        let user2 = @0x3;
        let user3 = @0x4;

        // Begin the test scenario with the admin address
        let mut scenario = ts::begin(admin);

        // Create a clock for testing
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        // === First Transaction ===
        // Initialize the proximity module
        ts::next_tx(&mut scenario, admin);
        {
            // Call the module initialization function
            proximity::init_test(ts::ctx(&mut scenario));
        };

        // === User1 Initialization ===
        ts::next_tx(&mut scenario, user1);
        {
            // Retrieve the shared UserRegistry
            let mut registry = ts::take_shared<proximity::UserRegistry>(& scenario);

            // User1 initializes themselves
            proximity::init_myself(&mut registry, &clock, ts::ctx(&mut scenario));

            // Return the UserRegistry to the shared pool
            ts::return_shared(registry);
        };

        // === User2 Initialization ===
        ts::next_tx(&mut scenario, user2);
        {
            let mut registry = ts::take_shared<proximity::UserRegistry>(& scenario);

            // User2 initializes themselves
            proximity::init_myself(&mut registry, &clock, ts::ctx(&mut scenario));

            ts::return_shared(registry);
        };

        // === User3 Initialization ===
        ts::next_tx(&mut scenario, user3);
        {
            let mut registry = ts::take_shared<proximity::UserRegistry>(& scenario);

            // User3 initializes themselves
            proximity::init_myself(&mut registry, &clock, ts::ctx(&mut scenario));

            ts::return_shared(registry);
        };


        // === Verify Registered Users ===
        ts::next_tx(&mut scenario, admin);
        {
            let  registry = ts::take_shared<proximity::UserRegistry>(& scenario);

            let registered_users = proximity::get_registered_users(&registry);

            // Verify that all unique users are registered
            assert!(vector::contains<address>(&registered_users, &user1), 200);
            assert!(vector::contains<address>(&registered_users, &user2), 201);
            assert!(vector::contains<address>(&registered_users, &user3), 202);
            assert!(vector::length<address>(&registered_users) == 3, 203);

            ts::return_shared(registry);
        };

        // Clean up
        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    /// Test Scenario 3: Attempting to Update Node Too Soon
    ///
    /// This test verifies that attempting to update the user's node before the minimum time interval
    /// results in an abort with the error code `EUPDATE_TOO_SOON`.
    ///
    /// Steps:
    /// 1. Initialize the proximity module and a user.
    /// 2. Attempt to update the user's node immediately.
    /// 3. The test should abort with `EUPDATE_TOO_SOON`.
    #[test]
    #[expected_failure(abort_code = proximity::EUPDATE_TOO_SOON)]
    fun test_user_node_update_too_soon() {
    use sui::test_scenario as ts;
    let admin = @0x1;
    let user = @0x2;

    let mut scenario = ts::begin(admin);
    let clock = clock::create_for_testing(ts::ctx(&mut scenario));

    ts::next_tx(&mut scenario, admin);
    {
        proximity::init_test(ts::ctx(&mut scenario));
    };

    ts::next_tx(&mut scenario, user);
    {
        let mut registry = ts::take_shared<proximity::UserRegistry>(&scenario);

        // Initialize the user without assigning the result
        proximity::init_myself(&mut registry, &clock, ts::ctx(&mut scenario));

        ts::return_shared(registry);
    };

    ts::next_tx(&mut scenario, user);
    {
        // Retrieve the User object from the shared pool
        let mut user_obj = ts::take_shared<proximity::User>(&scenario);

        let new_neighbors = vector::empty<ID>();

        // Attempt to update the user's node immediately
        // This should abort with EUPDATE_TOO_SOON
        proximity::update_node(&mut user_obj, new_neighbors, &clock, ts::ctx(&mut scenario));

        // Return the User object to the shared pool
        ts::return_shared(user_obj);
    };

    // Clean up
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

    /// Test Scenario 4: Updating Node After Minimum Time Interval
    ///
    /// This test checks that after advancing the clock by `TIME_UPDATE`, the user can successfully
    /// update their node.
    ///
    /// Steps:
    /// 1. Initialize the proximity module and a user.
    /// 2. Advance the clock by `TIME_UPDATE` milliseconds.
    /// 3. Attempt to update the user's node and verify it succeeds.
    #[test]
    fun test_user_node_update_after_time() {
        use sui::test_scenario as ts;
        let admin = @0x1;
        let user = @0x2;
        let time_update = 10000;

        let mut scenario = ts::begin(admin);
        let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));

        ts::next_tx(&mut scenario, admin);
        {
            proximity::init_test(ts::ctx(&mut scenario));
        };

        ts::next_tx(&mut scenario, user);
        {
            let mut registry = ts::take_shared<proximity::UserRegistry>(&scenario);
            proximity::init_myself(&mut registry, &clock, ts::ctx(&mut scenario));
            ts::return_shared(registry);
        };

        // Advance the Clock by TIME_UPDATE milliseconds
        ts::next_tx(&mut scenario, admin);
        {
            clock.increment_for_testing(time_update*2)
        };

        ts::next_tx(&mut scenario, user);
        {
            let mut user_obj = ts::take_shared<proximity::User>(&scenario);

            let new_neighbors = vector::empty<ID>();

            // Update the user's node with new neighbors
            // This should succeed
            proximity::update_node(&mut user_obj, new_neighbors, &clock, ts::ctx(&mut scenario));

            // Return the User object to the shared pool
            ts::return_shared(user_obj);
        };

        // Clean up
        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }
      
    

    
    

    /// Test Scenario 5: User Updates Node with New Neighbors
    ///
    /// In this test, we simulate a user updating their node with a list of new neighbors.
    /// We aim to verify that:
    /// - The user's current node is updated with the new neighbors.
    /// - The `NodeUpdateEvent` is emitted with the correct information.
    /// Steps:
    /// 1. Initialize the proximity module and a user.
    /// 2. The user updates their node with a vector of neighbor IDs.
    /// 3. Retrieve the user's current node and verify the neighbors list is updated.
    /// 4. Check that the `NodeUpdateEvent` was emitted with the correct data.
    #[test]
    fun test_user_node_update_with_neighbors() {
        // Skeleton code for the test
    }

    /// Test Scenario 6: Unauthorized User Attempts to Update Another User's Node
    ///
    /// This test ensures that only the owner of a `User` object can update their node.
    /// We aim to verify that:
    /// - An unauthorized user cannot update another user's node.
    /// - The appropriate error (EUPDATE_NOT_CORRECT_USER) is thrown when this is attempted.
    /// Steps:
    /// 1. Initialize the proximity module and two users (user1 and user2).
    /// 2. User2 attempts to update user1's node.
    /// 3. Verify that the operation fails with the correct error code.
    #[test]
    fun test_unauthorized_node_update_attempt() {
        // Skeleton code for the test
    }

    /// Test Scenario 7: User Initialization Without Registry
    ///
    /// In this test, we simulate a user attempting to initialize themselves without a valid `UserRegistry`.
    /// We aim to verify that:
    /// - The operation fails gracefully if the `UserRegistry` is missing or invalid.
    /// - Appropriate error handling is in place for this scenario.
    /// Steps:
    /// 1. Do not initialize the proximity module or `UserRegistry`.
    /// 2. Attempt to initialize a user.
    /// 3. Verify that the operation fails and an appropriate error is thrown.
    #[test]
    fun test_user_initialization_without_registry() {
        // Skeleton code for the test
    }

    /// Test Scenario 8: Event Emission Verification
    ///
    /// This test focuses on verifying that the correct events are emitted during various operations.
    /// We aim to verify that:
    /// - `RegistryCreatedEvent` is emitted upon initialization of the `UserRegistry`.
    /// - `NewUserEvent` is emitted when a new user registers.
    /// - `NodeUpdateEvent` is emitted when a user updates their node.
    /// Steps:
    /// 1. Initialize the proximity module and capture events.
    /// 2. Register a new user and capture events.
    /// 3. Update the user's node and capture events.
    /// 4. Verify that the correct events were emitted at each step with the expected data.
    #[test]
    fun test_event_emission_during_operations() {
        // Skeleton code for the test
    }

    /// Test Scenario 9: User Node History Preservation
    ///
    /// This test checks that the user's previous nodes are correctly linked via the `previous_node` field.
    /// We aim to verify that:
    /// - Each new `Node` correctly references the previous node.
    /// - The chain of nodes can be traversed to access the user's node history.
    /// Steps:
    /// 1. Initialize the proximity module and a user.
    /// 2. Perform multiple node updates by the user.
    /// 3. After each update, verify that the `previous_node` field correctly references the prior node.
    
    #[test]
    fun test_user_unregistration() {
        // Skeleton code for the test
    }

    /// Test Scenario 10: Concurrent User Registrations
    ///
    /// This test simulates multiple users attempting to register simultaneously.
    /// We aim to verify that:
    /// - The `UserRegistry` handles concurrent registrations without conflicts.
    /// - All users are registered correctly.
    /// Steps:
    /// 1. Initialize the proximity module.
    /// 2. Simulate multiple users (e.g., user1 to userN) initializing themselves in the same transaction or in quick succession.
    /// 3. Verify that all users are registered in the `UserRegistry`.
    #[test]
    fun test_concurrent_user_registrations() {
        // Skeleton code for the test
    }

    /// Test Scenario 11: Edge Case with Zero Neighbors
    ///
    /// This test checks how the module handles a user updating their node with zero neighbors.
    /// We aim to verify that:
    /// - The module allows a user to have an empty neighbors list.
    /// - No errors are thrown during the update.
    /// Steps:
    /// 1. Initialize the proximity module and a user.
    /// 2. Update the user's node with an empty neighbors vector.
    /// 3. Verify that the update succeeds and the user's `current_node` reflects zero neighbors.
    #[test]
    fun test_user_update_with_zero_neighbors() {
        // Skeleton code for the test
    }

    /// Test Scenario 12: Handling of Invalid Neighbor IDs
    ///
    /// This test ensures that the module correctly handles cases where invalid or non-existent neighbor IDs are provided.
    /// We aim to verify that:
    /// - The module validates neighbor IDs during an update.
    /// - An appropriate error is thrown if invalid IDs are provided.
    /// Steps:
    /// 1. Initialize the proximity module and a user.
    /// 2. Attempt to update the user's node with a vector containing invalid neighbor IDs.
    /// 3. Verify that the operation fails with the correct error code.
    #[test]
    fun test_user_update_with_invalid_neighbors() {
        // Skeleton code for the test
    }
}