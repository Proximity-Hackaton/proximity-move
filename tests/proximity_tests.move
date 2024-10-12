module proximity::proximity_test {
    use sui::test_scenario;
    use sui::clock::{Self, Clock};
    use proximity::proximity;

    #[test]
    fun test_module_init() {
        // Create test addresses representing users
        let admin = @0xAD;
        let initial_owner = @0xCAFE;
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
}