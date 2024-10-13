module proximity::proximity_test {
    use sui::test_scenario;
    use sui::clock::{Self};
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
        let user = @0xAD;
        // Begin a new test scenario
        // First transaction to emulate module initialization

        // Create a mock Clock object
        let mut scenario = test_scenario::begin(user);
        //let clock = clock::create_for_testing(scenario.ctx());
        proximity::init_test(scenario.ctx());

        // First transaction: Initialize the UserRegistry
        let prev_effects= scenario.next_tx(user);
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
        let user1 = @0x2;
        let user2 = @0x3;
        let user3 = @0x4;

        // Begin the test scenario with the admin address
        let mut scenario = ts::begin(user1);

        // Create a clock for testing
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        // === First Transaction ===
        // Initialize the proximity module
        ts::next_tx(&mut scenario, user1);
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
            proximity::init_myself(&mut registry, vector::empty<ID>(), &clock, ts::ctx(&mut scenario));

            // Return the UserRegistry to the shared pool
            ts::return_shared(registry);
        };

        // === User2 Initialization ===
        ts::next_tx(&mut scenario, user2);
        {
            let mut registry = ts::take_shared<proximity::UserRegistry>(& scenario);

            // User2 initializes themselves
            proximity::init_myself(&mut registry, vector::empty<ID>(), &clock, ts::ctx(&mut scenario));

            ts::return_shared(registry);
        };

        // === User3 Initialization ===
        ts::next_tx(&mut scenario, user3);
        {
            let mut registry = ts::take_shared<proximity::UserRegistry>(& scenario);

            // User3 initializes themselves
            proximity::init_myself(&mut registry, vector::empty<ID>(), &clock, ts::ctx(&mut scenario));

            ts::return_shared(registry);
        };

        // === Verify Registered Users ===
        ts::next_tx(&mut scenario, user1);
        {
            let registry = ts::take_shared<proximity::UserRegistry>(& scenario);

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
        let user = @0x1;

        let mut scenario = ts::begin(user);
        let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));

        ts::next_tx(&mut scenario, user);
        {
           proximity::init_test(ts::ctx(&mut scenario));
        };

        ts::next_tx(&mut scenario, user);
        {
            let mut registry = ts::take_shared<proximity::UserRegistry>(&scenario);

            // Initialize the user2 without assigning the result
            proximity::init_myself(&mut registry, vector::empty<ID>(), &clock, ts::ctx(&mut scenario));

            ts::return_shared(registry);
        };

        // Advance the Clock by TIME_UPDATE - 1 milliseconds, not enough time
        ts::next_tx(&mut scenario, user);
        {
            clock.increment_for_testing(proximity::get_min_update_interval() - 1)
        };

        ts::next_tx(&mut scenario, user);
        {
            // Retrieve the User object from the shared pool
            let mut user_obj = ts::take_shared<proximity::User>(&scenario);
            let new_neighbors = vector::empty<ID>();

            // Attempt to update the user's node immediately
            // This should abort with EUPDATE_TOO_SOON
            proximity::update_node(&mut user_obj, new_neighbors, &clock, ts::ctx(&mut scenario));
            ts::return_shared(user_obj);
        };

        // Clean up
        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    /// Test Scenario 4: Updating Node After Minimum Time Interval
    ///
    /// This test checks that after advancing the clock by `time_update`, the user can successfully
    /// update their node.
    ///
    /// Steps:
    /// 1. Initialize the proximity module and a user.
    /// 2. Advance the clock by `time_update` milliseconds.
    /// 3. Attempt to update the user's node and verify it succeeds.
    #[test]
    fun test_user_node_update_after_time() {
        use sui::test_scenario as ts;
        let user = @0x1;

        let mut scenario = ts::begin(user);
        let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));

        ts::next_tx(&mut scenario, user);
        {
            proximity::init_test(ts::ctx(&mut scenario));
        };

        ts::next_tx(&mut scenario, user);
        {
            let mut registry = ts::take_shared<proximity::UserRegistry>(&scenario);
            proximity::init_myself(&mut registry, vector::empty<ID>(), &clock, ts::ctx(&mut scenario));
            ts::return_shared(registry);
        };

        // Advance the Clock by TIME_UPDAT + 1 milliseconds
        ts::next_tx(&mut scenario, user);
        {
            clock.increment_for_testing(proximity::get_min_update_interval() + 1)
        };

        ts::next_tx(&mut scenario, user);
        {
            let mut user_obj = ts::take_shared<proximity::User>(&scenario);

            let new_neighbors = vector::empty<ID>();

            // Update the user2's node with new neighbors
            // This should succeed
            proximity::update_node(&mut user_obj, new_neighbors, &clock, ts::ctx(&mut scenario));
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
    /// Steps:
    /// 1. Initialize the proximity module and a user.
    /// 2. The user updates their node with a vector of neighbor IDs.
    /// 3. Retrieve the user's current node and verify the neighbors list is updated.
    #[test]
    fun test_user_node_update_with_neighbors() {
        use sui::test_scenario as ts;
        let user = @0x2;
        let neighbor1 = @0x3;
        let neighbor2 = @0x4;

        let mut scenario = ts::begin(user);
        let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    
        ts::next_tx(&mut scenario, user);
        {
            proximity::init_test(ts::ctx(&mut scenario));
        };
    
        ts::next_tx(&mut scenario, user);
        {
            let mut registry = ts::take_shared<proximity::UserRegistry>(&scenario);
            proximity::init_myself(&mut registry, vector::empty<ID>(), &clock, ts::ctx(&mut scenario));
            ts::return_shared(registry);
        };

        // Advance the Clock by TIME_UPDATE + 1 milliseconds
        ts::next_tx(&mut scenario, user);
        {
            clock.increment_for_testing(proximity::get_min_update_interval() + 1)
        };
        
        // The user updates their node with a vector of neighbor IDs
        ts::next_tx(&mut scenario, user);
        {
            let mut user_obj = ts::take_shared<proximity::User>(&scenario);
            let mut new_neighbors = vector::empty<ID>();
            vector::push_back<ID>(&mut new_neighbors, neighbor1.to_id());
            vector::push_back<ID>(&mut new_neighbors, neighbor2.to_id());
            proximity::update_node(&mut user_obj, new_neighbors, &clock, ts::ctx(&mut scenario));
            ts::return_shared(user_obj);
        };
        
        // Retrieve the user's current node and verify the neighbors list is updated
        ts::next_tx(&mut scenario, user);
        {
            let user_obj = ts::take_shared<proximity::User>(&scenario);
            let user_curr_node = proximity::get_user_curr_node(&user_obj);
            let curr_node_neighbors = proximity::get_curr_node_neighbors(&user_curr_node);
            assert!(vector::length<ID>(&curr_node_neighbors) == 2, 1001); // Error code 1001: Incorrect number of neighbors
            assert!(vector::contains<ID>(&curr_node_neighbors, &neighbor1.to_id()), 1002); // Error code 1002: Neighbor1 not found
            assert!(vector::contains(&curr_node_neighbors, &neighbor2.to_id()), 1003); // Error code 1003: Neighbor2 not found
            ts::return_shared(user_obj);
        };
        
        // Clean up the test scenario
        clock::destroy_for_testing(clock);
        ts::end(scenario);
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
    #[expected_failure(abort_code = proximity::EUPDATE_NOT_CORRECT_USER)]
    fun test_unauthorized_node_update_attempt() {
        use sui::test_scenario as ts;
        let user1 = @0x2;
        let user2 = @0x3;
        
        let mut scenario = ts::begin(user1);
        let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
        
        ts::next_tx(&mut scenario, user1);
        {
            // Initialize the proximity module
            proximity::init_test(ts::ctx(&mut scenario));
        };
        
        ts::next_tx(&mut scenario, user1);
        {
            // Initialize user1's registry entry with an empty neighbors list
            let mut registry1 = ts::take_shared<proximity::UserRegistry>(&scenario);
            proximity::init_myself(&mut registry1, vector::empty<ID>(), &clock, ts::ctx(&mut scenario));
            ts::return_shared(registry1);
        };
        
        ts::next_tx(&mut scenario, user2);
        {
            // Initialize user2's registry entry with an empty neighbors list
            let mut registry2 = ts::take_shared<proximity::UserRegistry>(&scenario);
            proximity::init_myself(&mut registry2, vector::empty<ID>(), &clock, ts::ctx(&mut scenario));
            ts::return_shared(registry2);
        };

        // Advance the Clock by TIME_UPDATE + 1 milliseconds
        ts::next_tx(&mut scenario, user1);
        {
            clock.increment_for_testing(proximity::get_min_update_interval() + 1)
        };

        // Get the user object for user1
        let mut user2_obj;
        ts::next_tx(&mut scenario, user2);
        {
           user2_obj = ts::take_shared<proximity::User>(&scenario);
        };
        
        ts::next_tx(&mut scenario, user1); 
        {
            // Attempt to update user1's node using user2's signer
            // This should fail with EUPDATE_NOT_CORRECT_USER because user2 is not the owner of user1's node
            proximity::update_node(&mut user2_obj, vector::empty<ID>(), &clock, ts::ctx(&mut scenario));
        };
        
        // Clean up the test scenario
        ts::return_shared(user2_obj);
        clock::destroy_for_testing(clock);
        ts::end(scenario);
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
    #[expected_failure(location = sui::test_scenario, abort_code = 3)] // 3 corresponds to EEmptyInventory in sui::test_scenario
    fun test_user_initialization_without_registry() {
        use sui::test_scenario as ts;
        let user = @0x2;

        let mut scenario = ts::begin(user);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        // === Attempt to Initialize the User Without Initializing the Module ===
        // Since we are not initializing the module, the UserRegistry does not exist.
        ts::next_tx(&mut scenario, user);
        {
            // Attempt to take the shared UserRegistry, which does not exist
            // This should abort with EEmptyInventory (abort code 3)
            let mut registry = ts::take_shared<proximity::UserRegistry>(&scenario);
            proximity::init_myself(&mut registry, vector::empty<ID>(), &clock, ts::ctx(&mut scenario));

            // Return the (non-existent) registry to the shared pool...
            ts::return_shared(registry);
        };

        // Clean up
        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    /// Test Scenario 8: User Node History Preservation
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
    fun test_nodes_link() {
        use sui::test_scenario as ts;
        let user = @0x2;
        let neighbor1 = @0x3;
        let neighbor2 = @0x4;
        let neighbor3 = @0x5;

        // Step 1: Initialize the proximity module and a user
        let mut scenario = ts::begin(user);
        let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));

        ts::next_tx(&mut scenario, user);
        {
            proximity::init_test(ts::ctx(&mut scenario));
        };

        ts::next_tx(&mut scenario, user);
        {
            // Initialize the user's registry entry with an empty neighbors list
            let mut registry = ts::take_shared<proximity::UserRegistry>(&scenario);
            proximity::init_myself(&mut registry, vector::empty<ID>(), &clock, ts::ctx(&mut scenario));
            ts::return_shared(registry);
        };

        ts::next_tx(&mut scenario, user);
        {
            clock.increment_for_testing(proximity::get_min_update_interval() + 1)
        };


        // Update the node 3 times
        ts::next_tx(&mut scenario, user);
        {
            let mut user_obj = ts::take_shared<proximity::User>(&scenario);
            let mut new_neighbors = vector::empty<ID>();
            vector::push_back<ID>(&mut new_neighbors, neighbor1.to_id());
            proximity::update_node(&mut user_obj, new_neighbors, &clock, ts::ctx(&mut scenario));
            ts::return_shared(user_obj);
        };

        // Advance the Clock by TIME_UPDATE + 1 milliseconds
        ts::next_tx(&mut scenario, user);
        {
            clock.increment_for_testing(proximity::get_min_update_interval() + 1)
        };

        ts::next_tx(&mut scenario, user);
        {
            let mut user_obj = ts::take_shared<proximity::User>(&scenario);
            let mut new_neighbors = vector::empty<ID>();
            vector::push_back<ID>(&mut new_neighbors, neighbor2.to_id());
            proximity::update_node(&mut user_obj, new_neighbors, &clock, ts::ctx(&mut scenario));
            ts::return_shared(user_obj);
        };

        // Advance the Clock by TIME_UPDATE + 1 milliseconds
        ts::next_tx(&mut scenario, user);
        {
            clock.increment_for_testing(proximity::get_min_update_interval() + 1)
        };

        ts::next_tx(&mut scenario, user);
        {
            let mut user_obj = ts::take_shared<proximity::User>(&scenario);
            let mut new_neighbors = vector::empty<ID>();
            vector::push_back<ID>(&mut new_neighbors, neighbor3.to_id());
            proximity::update_node(&mut user_obj, new_neighbors, &clock, ts::ctx(&mut scenario));
            ts::return_shared(user_obj);
        };

        // Verify the nodes
        ts::next_tx(&mut scenario, user);
        {
            let user_obj = ts::take_shared<proximity::User>(&scenario);
            let user_node3 = ts::take_immutable_by_id<proximity::Node>(&scenario, proximity::get_user_node(&user_obj).extract());
            let node_neighbours3 = proximity::get_node_neighbors(&user_node3);
            assert!(vector::length<ID>(&node_neighbours3) == 1, 1001); // Expect one neighbor in node 3
            assert!(vector::contains<ID>(&node_neighbours3, &neighbor3.to_id()), 1002); // Expect neighbour 3 in node 3

            let user_node2 = ts::take_immutable_by_id<proximity::Node>(&scenario, proximity::get_previous_node(&user_node3).extract());
            let node_neighbours2 = proximity::get_node_neighbors(&user_node2);
            assert!(vector::length<ID>(&node_neighbours2) == 1, 1003); // Expect one neighbor in node 2
            assert!(vector::contains<ID>(&node_neighbours2, &neighbor2.to_id()), 1004); // Expect neighbour 3 in node 3

            let user_node1 = ts::take_immutable_by_id<proximity::Node>(&scenario, proximity::get_previous_node(&user_node2).extract());
            let node_neighbours1 = proximity::get_node_neighbors(&user_node1);
            assert!(vector::length<ID>(&node_neighbours1) == 1, 1005); // Expect one neighbor in node 2
            assert!(vector::contains<ID>(&node_neighbours1, &neighbor1.to_id()), 1006); // Expect neighbour 3 in node 3

            ts::return_immutable(user_node1);
            ts::return_immutable(user_node2);
            ts::return_immutable(user_node3);
            ts::return_shared(user_obj);
        };

        // Clean up
        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    /// Test Scenario 9: Concurrent User Registrations
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
        use sui::test_scenario as ts;
        let user1 = @0x2;
        let user2 = @0x3;
        let user3 = @0x4;
        let user4 = @0x5;
        
        let mut scenario = ts::begin(user1);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));
        
        ts::next_tx(&mut scenario, user1);
        {
            // Initialize the proximity module
            proximity::init_test(ts::ctx(&mut scenario));
        };
        
        // Step 2: Simulate multiple users registering in quick succession
        
        // User1 registration
        ts::next_tx(&mut scenario, user1);
        {
            // Initialize user1's registry entry with an empty neighbors list
            let mut registry1 = ts::take_shared<proximity::UserRegistry>(&scenario);
            proximity::init_myself(&mut registry1, vector::empty<ID>(), &clock,ts::ctx(&mut scenario));
            ts::return_shared(registry1);
        };
        
        // User2 registration
        ts::next_tx(&mut scenario, user2);
        {
            // Initialize user2's registry entry with an empty neighbors list
            let mut registry2 = ts::take_shared<proximity::UserRegistry>(&scenario);
            proximity::init_myself(&mut registry2, vector::empty<ID>(), &clock,ts::ctx(&mut scenario));
            ts::return_shared(registry2);
        };
        
        // User3 registration
        ts::next_tx(&mut scenario, user3);
        {
            // Initialize user3's registry entry with an empty neighbors list
            let mut registry3 = ts::take_shared<proximity::UserRegistry>(&scenario);
            proximity::init_myself(&mut registry3, vector::empty<ID>(), &clock,ts::ctx(&mut scenario));
            ts::return_shared(registry3);
        };
        
        // User4 registration
        ts::next_tx(&mut scenario, user4);
        {
            // Initialize user4's registry entry with an empty neighbors list
            let mut registry4 = ts::take_shared<proximity::UserRegistry>(&scenario);
            proximity::init_myself(&mut registry4, vector::empty<ID>(), &clock,ts::ctx(&mut scenario));
            ts::return_shared(registry4);
        };
        
        // Step 3: Verify that all users are registered in the UserRegistry
        ts::next_tx(&mut scenario, user1);
        {
            // Retrieve the UserRegistry object
            let registry = ts::take_shared<proximity::UserRegistry>(&scenario);
            let registered_users= proximity::get_registered_users(&registry);

            // Verify that each user is registered
            assert!(vector::contains<address>(&registered_users, &user1), 1000); // Error code 1000: User1 not registered
            assert!(vector::contains<address>(&registered_users, &user2), 1001); // Error code 1001: User2 not registered
            assert!(vector::contains<address>(&registered_users, &user3), 1002); // Error code 1002: User3 not registered
            assert!(vector::contains<address>(&registered_users, &user4), 1003); // Error code 1003: User4 not registered
            ts::return_shared(registry);
        };
        
        // Clean up the test scenario
        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    /// Test Scenario 10: Edge Case with Zero Neighbors
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
        use sui::test_scenario as ts;
        let user = @0x1;

        let mut scenario = ts::begin(user);
        let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));

        ts::next_tx(&mut scenario, user);
        {
           proximity::init_test(ts::ctx(&mut scenario));
        };

        ts::next_tx(&mut scenario, user);
        {
            let mut registry = ts::take_shared<proximity::UserRegistry>(&scenario);
            proximity::init_myself(&mut registry, vector::empty<ID>(), &clock, ts::ctx(&mut scenario));
            ts::return_shared(registry);
        };

        // Advance the Clock by TIME_UPDATE + 1 milliseconds
        ts::next_tx(&mut scenario, user);
        {
            clock.increment_for_testing(proximity::get_min_update_interval() + 1)
        };

        ts::next_tx(&mut scenario, user);
        {
            let mut user_obj = ts::take_shared<proximity::User>(&scenario);
            let new_neighbors = vector::empty<ID>();
            proximity::update_node(&mut user_obj, new_neighbors, &clock, ts::ctx(&mut scenario));
            ts::return_shared(user_obj);
        };

        // Step 3: Verify that the update succeeded and the user's current node has zero neighbors
        ts::next_tx(&mut scenario, user);
        {
            let user_obj = ts::take_shared<proximity::User>(&scenario);
            let user_curr_node = proximity::get_user_curr_node(&user_obj);
            let curr_node_neighbors = proximity::get_curr_node_neighbors(&user_curr_node);
            assert!(vector::length<ID>(&curr_node_neighbors) == 0, 1001); // Error code 1001: Incorrect number of neighbors
            ts::return_shared(user_obj)
        };

        // Clean up
        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

}