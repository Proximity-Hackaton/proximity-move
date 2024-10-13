module proximity::proximity {
    use sui::clock::{Clock};
    use sui::event;

    // ----- CONSTANTS  ----------------------------------------------------------------------------

    // ----- error codes -----
    const EUSER_ALREADY_EXISTS:     u64 = 0; // A user tried to register twice
    const EUPDATE_TOO_SOON:         u64 = 1; // Asked to update a node before the contract set interval
    const EUPDATE_NOT_CORRECT_USER: u64 = 2; // A user tried to modify another user's node

    // ----- config -----
    const UPDATE_MIN_INTERVAL: u64 = 10_000; // Minimal interval

    // ----- STRUCTURES ----------------------------------------------------------------------------

    /// The UserRegistery is a singleton in this contract.
    /// It is used to keep track of all the nodes that have entered the graph.
    public struct UserRegistry has key, store {
        id: UID,
        registered_users: vector<address>,
    }

    /// The RegisteryCreatedEvent happens one at initialization when the singleton Registery
    /// Off chain apps can listen to this event to get the registery id
    public struct RegistryCreatedEvent has copy, drop {
        registry_id: ID,
        creator: address,
    }

    /// The User struct represents a node in the graph and a user on the blockchain.
    /// There is a relation one to one between wallets and Users
    public struct User has key, store {
        id: UID,
        owner: address,
        current_node: Current_Node,
        node: option::Option<ID>
    }

    /// The NewUserEvent happens when a new node joins the graph
    /// Off chain apps can listen to this event to know new nodes
    public struct NewUserEvent has copy, drop {
        owner: address,
        user : ID,
    }

    /// The Node contains all the neighbours of a node in the graph for a defined time interval.
    /// Nodes are shared and immutable on the blockchain, they are part of the graph history.
    public struct Node has key, store {
        id: UID,
        owner: address,
        neighbors: vector<ID>,
        timestamp: u64,
        previous_node: option::Option<ID>,
    }

    /// Current_Node is a utility for managing users
    /// Current_Node represents a timestamp that hasn't been "committed" to the graph, the last in date
    public struct Current_Node has copy, store, drop {
        neighbors: vector<ID>,
        timestamp: u64,
    }

    /// The NodeUpdateEvent happens when a new node updates its edges
    /// Off chain apps can listen to this event to get the last version of the graph
    public struct NodeUpdateEvent has copy, drop {
        user: ID,
        current_node : Current_Node,
    }

    /// This capability is for development purposes only, it allows the creation of fake nodes in the graph that are not linked to a wallet
    public struct Dev_capability has key, store {
        id: UID,
        owner: address
    }

    // ----- INTERFACE -----------------------------------------------------------------------------

    /// In the initialization of the contract we
    /// - Create the singleton UserRegistery
    /// - Emits the RegisteryCreatedEvent to notify off chain listeners
    /// - Create a Dev_capability and transfers it to the caller
    fun init(ctx: &mut TxContext) {
        let registry = UserRegistry {
            id: object::new(ctx),
            registered_users: vector::empty<address>(),
        };

        event::emit(RegistryCreatedEvent {
            registry_id: object::id(&registry),
            creator: ctx.sender(),
        });

        transfer::share_object(registry);

        let _Dev_capability = Dev_capability{
            id: object::new(ctx),
            owner: ctx.sender()
        };
        
        transfer::transfer(_Dev_capability, ctx.sender());
    }

    /// When a user want to enter the graph it needs to call the init_myself function
    /// This function can only be called once by user and it, it:
    /// - Create the User structure, unique to the sender and transfer it
    /// - Create the initial Node and Current_Node for this User
    public entry fun init_myself(
        registry: &mut UserRegistry,
        _neighbors: vector<ID>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {

        let sender = ctx.sender();

        // Check if the sender is already registered
        assert!(!vector::contains(&registry.registered_users, &sender), EUSER_ALREADY_EXISTS);

        // Adds the user to the user to the registery
        vector::push_back(&mut registry.registered_users, sender);

        let current_time = clock.timestamp_ms();

        let node = Node {
            id: object::new(ctx),
            owner: sender,
            neighbors: _neighbors,
            timestamp: current_time,
            previous_node: option::none<ID>(),
        };

        let current_node = Current_Node {
            neighbors: node.neighbors,
            timestamp: node.timestamp
        };

        // Create the User object unique to the sender
        let user = User {
            id: object::new(ctx),
            owner: sender,
            current_node: current_node,
            node:  option::some<ID>(object::id(&node)),
        };

        event::emit(
        NewUserEvent {
            owner: sender,
            user: object::id(&user),
        });

        event::emit(NodeUpdateEvent {
            user: object::id(&user),
            current_node: user.current_node,
        });

        // Posts the first ever node
        transfer::freeze_object(node);
        transfer::share_object(user);
    }

    /// Users can update the neighbors of their Node in the graph, it
    /// - Creates a new Node object and link it with the precedent one 
    /// - Freezes the precedent Node
    /// - Update the User's Current_Node
    /// - Emit the event NodeUpdateEvent to notify listeners
    public entry fun update_node(
        user: &mut User,
        new_neighbors: vector<ID>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {

        let sender = ctx.sender();

        // Ensure the user is the owner of the User object
        assert!(user.owner == sender, EUPDATE_NOT_CORRECT_USER);

        let current_time = clock.timestamp_ms();
        let last_update_time = user.current_node.timestamp;

        // Check that the enforced time interval is respected
        assert!(current_time - last_update_time >= UPDATE_MIN_INTERVAL, EUPDATE_TOO_SOON);

        let new_node = Node {
            id: object::new(ctx),
            owner: sender,
            neighbors: new_neighbors,
            timestamp: current_time,
            previous_node: user.node,
        };

        // Update the user's node
        user.node = option::some<ID>(object::id(&new_node));
        // Create the new Current_Node
        user.current_node = Current_Node{neighbors: new_node.neighbors, timestamp: new_node.timestamp};

        event::emit(NodeUpdateEvent {
            user: object::id(user),
            current_node: user.current_node,
        });

        transfer::freeze_object(new_node);
    }
    
    /// This method is only for development/testing purposes !
    /// It allows an owner of the capability to:
    /// - Create a new fake user, which is not linked to a wallet and notifies the creation of a new user
    /// - Create the also fake first node of the user and notifies the creation of this node too
    public entry fun dev_init_fake_user(
        _Dev_capability: &Dev_capability, 
        _owner: address, 
        _neighbors: vector<ID>, 
        clock: &Clock, 
        ctx: &mut TxContext
    ){
        //Check Dev_capability
        assert!(_Dev_capability.owner == ctx.sender(), EUPDATE_NOT_CORRECT_USER);

        let current_time = clock.timestamp_ms();    

        let new_node = Node {
            id: object::new(ctx),
            owner: _owner,
            neighbors: _neighbors,
            timestamp: current_time,
            previous_node: option::none<ID>(),
        };

        let current_node = Current_Node {
            neighbors: new_node.neighbors,
            timestamp: new_node.timestamp
        };

        let user = User {
            id: object::new(ctx),
            owner: _owner,
            current_node: current_node,
            node:  option::some<ID>(object::id(&new_node)),
        };

        // Notify a new user has arrived
        event::emit(
        NewUserEvent {
            owner: _owner,
            user: object::id(&user),
        });

        // Notification for the first node
        event::emit(NodeUpdateEvent {
            user: object::id(&user),
            current_node: user.current_node,
        });

        transfer::share_object(user);
        transfer::freeze_object(new_node);
    }

    /// This method is only for development/testing purposes !
    /// It allows an owner of the capability to update the fake node with new neighbors the same way we update a normal node:
    /// It creates the necessary fake objects and notifies the listeners of their arrival with events
    public entry fun dev_fake_node_update(
        _Dev_capability: &Dev_capability, 
        user: &mut User, 
        new_neighbors: vector<ID>, 
        clock: &Clock, 
        ctx: &mut TxContext
    ){

       //Check Dev_capability
        assert!(_Dev_capability.owner == ctx.sender(), EUPDATE_NOT_CORRECT_USER);
        
        let current_time = clock.timestamp_ms();

        let new_node = Node {
            id: object::new(ctx),
            owner: user.owner,
            neighbors: new_neighbors,
            timestamp: current_time,
            previous_node: user.node,
        };

        let new_current_node = Current_Node {
            neighbors: new_node.neighbors,
            timestamp: new_node.timestamp
        };
        
        //Updates the user
        user.current_node = new_current_node;

        event::emit(NodeUpdateEvent {
            user: object::id(user),
            current_node: user.current_node,
        });

        transfer::freeze_object(new_node);
    }

    // ----- TESTING INTERFACE ----------------------------------------------------------------------------

    #[test_only]
    public fun init_test (ctx: &mut TxContext){
        init(ctx)
    }

    #[test_only]
    public fun get_min_update_interval (): u64{
        UPDATE_MIN_INTERVAL
    }

    #[test_only]
    public fun get_registered_users (userRegistry : &UserRegistry): vector<address>{
        userRegistry.registered_users
    }

    #[test_only]
    public fun get_user_curr_node (user : &User): Current_Node {
        user.current_node
    }

    #[test_only]
    public fun get_user_node (user : &User): Option<ID> {
        user.node
    }

    #[test_only]
    public fun get_curr_node_neighbors (curr_node: &Current_Node): vector<ID> {
        curr_node.neighbors
    }

    #[test_only]
    public fun get_node_neighbors (node: &Node): vector<ID> {
        node.neighbors
    }

    #[test_only]
    public fun get_previous_node (node: &Node): Option<ID> {
        node.previous_node
    }

}
