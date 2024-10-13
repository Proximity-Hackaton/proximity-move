module proximity::proximity {
    use sui::clock::{Clock};
    use sui::event;


    /// Error codes
    const EUSER_ALREADY_EXISTS: u64 = 0;
    const EUPDATE_TOO_SOON: u64 = 1;
    const EUPDATE_NOT_CORRECT_USER: u64 = 2;
    // Ensure here it is set to 10'000 miliseconds. 
    const TIME_UPDATE: u64 = 10_000;

    /// Event emitted when the UserRegistry is created.
    public struct RegistryCreatedEvent has copy, drop {
        registry_id: ID,
        creator: address,
    }

    /// Event emitted when a user's node is updated.
    public struct NodeUpdateEvent has copy, drop {
        user: ID,
        current_node : Current_Node,
    }

    /// Event emitted when a user's node is updated.
    public struct NewUserEvent has copy, drop {
        owner: address,
        user : ID,
    }

    /// The Node struct represents the current state of a user's neighbors.
    public struct Node has key, store {
        id: UID,
        owner: address,
        neighbors: vector<ID>,
        timestamp: u64,
        previous_node: option::Option<ID>,
    }

    /// The Node struct represents the current state of a user's neighbors.
    public struct Current_Node has copy, store, drop {
        neighbors: vector<ID>,
        timestamp: u64,
    }

    /// The User struct represents a user on the blockchain.
    public struct User has key, store {
        id: UID,
        owner: address,
        current_node: Current_Node,
        node: option::Option<ID>
    }

    /// A global resource to track all addresses that have created a User.
    public struct UserRegistry has key, store {
        id: UID,
        registered_users: vector<address>,
    }

    /// Initialize the UserRegistry as a shared object.
    fun init(ctx: &mut TxContext) {
        // Create the UserRegistry object
        let registry = UserRegistry {
            id: object::new(ctx),
            registered_users: vector::empty<address>(),
        };

        // Emit an event with the registry's object ID
        event::emit(RegistryCreatedEvent {
            registry_id: object::id(&registry),
            creator: ctx.sender(),
        });

        // Share the UserRegistry object so it's accessible globally
        transfer::share_object(registry);
    }

    /// Initialize a new User. Each address can only do this once.
    public entry fun init_myself(
        registry: &mut UserRegistry,
        _neighbors: vector<ID>,
        clock: &Clock,
        ctx: &mut TxContext) {
        let sender = ctx.sender();

        // Check if the sender is already registered
        if (vector::contains(&registry.registered_users, &sender)) {
            abort EUSER_ALREADY_EXISTS // Error code for "User already exists"
        };

        // Register the sender
        vector::push_back(&mut registry.registered_users, sender);

        // Get the current timestamp
        let current_time = clock.timestamp_ms();

        // Create the initial Node
        let node = Node {
            id: object::new(ctx),
            owner: sender,
            neighbors: _neighbors,
            timestamp: current_time,
            previous_node: option::none<ID>(),
        };

        let current = Current_Node {
            neighbors: node.neighbors,
            timestamp: node.timestamp
        };

        // Create the User object
        let user = User {
            id: object::new(ctx),
            owner: sender,
            current_node: current,
            node:  option::some<ID>(object::id(&node)),
        };

        // Emit the NewUserUpdate
        event::emit(
        NewUserEvent {
            owner: sender,
            user: object::id(&user),
        });

        // Emit the NodeUpdateEvent
        event::emit(NodeUpdateEvent {
            user: object::id(&user),
            current_node: user.current_node,
        });

        //It posts the first ever node
        transfer::share_object(node);
        transfer::share_object(user);
    }

    /// Update the user's node with new neighbors.
    public entry fun update_node(
        user: &mut User,
        new_neighbors: vector<ID>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let sender = ctx.sender();

        // Ensure the user is the owner of the User object
        assert!(user.owner == sender, EUPDATE_NOT_CORRECT_USER);

        // Get the current time
        let current_time = clock.timestamp_ms();

        let last_update_time = user.current_node.timestamp;
        if (current_time - last_update_time < TIME_UPDATE) {
            abort EUPDATE_TOO_SOON // Error code for "Update too soon"
        };


        // Create a new Node
        let new_node = Node {
            id: object::new(ctx),
            owner: sender,
            neighbors: new_neighbors,
            timestamp: current_time,
            previous_node: user.node,
        };

        // Update the user's node
        user.node = option::some<ID>(object::id(&new_node));
        user.current_node = Current_Node{neighbors: new_node.neighbors,timestamp: new_node.timestamp};

        // Emit the NodeUpdateEvent
        event::emit(NodeUpdateEvent {
            user: object::id(user),
            current_node: user.current_node,
        });

        transfer::share_object(new_node);
    }
    
    public entry fun ping_test(){}

    //This method is to purely simulate a graph, quick step (basically creates a fake user that detects random neighbors)
    public entry fun fake_user(_owner: address, _neighbors: vector<ID>, clock: &Clock, ctx: &mut TxContext){
        let current_time = clock.timestamp_ms();    
        // Create a new Node
        let new_node = Node {
            id: object::new(ctx),
            owner: _owner,
            neighbors: _neighbors,
            timestamp: current_time,
            previous_node: option::none<ID>(),
        };

        let current = Current_Node {
            neighbors: new_node.neighbors,
            timestamp: new_node.timestamp
        };

        // Create the User object
        let user = User {
            id: object::new(ctx),
            owner: _owner,
            current_node: current,
            node:  option::some<ID>(object::id(&new_node)),
        };

        //Emit the new user
        event::emit(
        NewUserEvent {
            owner: _owner,
            user: object::id(&user),
        });

        // Emit the NodeUpdateEvent
        event::emit(NodeUpdateEvent {
            user: object::id(&user),
            current_node: user.current_node,
        });

        transfer::share_object(user);
        transfer::share_object(new_node);

    }

    public entry fun fake_node_update(user: &mut User, new_neighbors: vector<ID>, clock: &Clock, ctx: &mut TxContext){
        let current_time = clock.timestamp_ms();
        // Create a vector of IDs


        let new_node = Node {
            id: object::new(ctx),
            owner: user.owner,
            neighbors: new_neighbors,
            timestamp: current_time,
            previous_node: user.node,
        };

        //Updates the current neighbor
        let current = Current_Node {
            neighbors: new_node.neighbors,
            timestamp: new_node.timestamp
        };
        
        //Updates the user
        user.current_node = current;

        // Emit the NodeUpdateEvent
        event::emit(NodeUpdateEvent {
            user: object::id(user),
            current_node: user.current_node,
        });

        transfer::share_object(new_node);
    }


    #[test_only]
    public fun init_test (ctx: &mut TxContext){
        init(ctx)
    }

    #[test_only]
    public fun get_registered_users (userRegistry : &UserRegistry):vector<address>{
        userRegistry.registered_users
    }

}
