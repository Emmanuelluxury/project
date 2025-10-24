#[starknet::contract]
pub mod SBTC {
    use starknet::{ContractAddress, get_caller_address};
    use starknet::storage::{
        Map, StoragePointerReadAccess, StoragePointerWriteAccess,
        StorageMapReadAccess, StorageMapWriteAccess
    };
    use core::integer::u256;
    use core::traits::TryInto;

    // Constants
    const NAME: felt252 = 'Starknet Bitcoin';
    const SYMBOL: felt252 = 'sBTC';
    const DECIMALS: u8 = 8;

    #[storage]
    struct Storage {
        // ERC20 standard storage
        balances: Map<ContractAddress, u256>,
        allowances: Map<(ContractAddress, ContractAddress), u256>,
        total_supply: u256,

        // Bridge-specific storage
        minter_address: ContractAddress,
        burner_address: ContractAddress,
        admin: ContractAddress,

        // Security features
        entered: bool, // Reentrancy guard
    }

    #[derive(Drop, starknet::Event)]
    struct Transfer {
        #[key]
        from: ContractAddress,
        #[key]
        to: ContractAddress,
        value: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct Approval {
        #[key]
        owner: ContractAddress,
        #[key]
        spender: ContractAddress,
        value: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct Mint {
        #[key]
        to: ContractAddress,
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct Burn {
        #[key]
        from: ContractAddress,
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct MinterChanged {
        old_minter: ContractAddress,
        new_minter: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct BurnerChanged {
        old_burner: ContractAddress,
        new_burner: ContractAddress,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Transfer: Transfer,
        Approval: Approval,
        Mint: Mint,
        Burn: Burn,
        MinterChanged: MinterChanged,
        BurnerChanged: BurnerChanged,
    }

    mod Errors {
        pub const INSUFFICIENT_BALANCE: felt252 = 'sBTC: insufficient balance';
        pub const INSUFFICIENT_ALLOWANCE: felt252 = 'sBTC: insufficient allowance';
        pub const ZERO_ADDRESS: felt252 = 'sBTC: zero address';
        pub const NOT_MINTER: felt252 = 'sBTC: not minter';
        pub const NOT_BURNER: felt252 = 'sBTC: not burner';
        pub const NOT_ADMIN: felt252 = 'sBTC: not admin';
        pub const INVALID_AMOUNT: felt252 = 'sBTC: invalid amount';
        pub const REENTRANCY_ATTACK: felt252 = 'sBTC: reentrancy attack';
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        admin: ContractAddress,
        initial_supply: u256,
        initial_holder: ContractAddress
    ) {
        self.admin.write(admin);

        if initial_holder != 0.try_into().unwrap() {
            self.balances.write(initial_holder, initial_supply);
            self.total_supply.write(initial_supply);

            self.emit(Event::Transfer(Transfer {
                from: 0.try_into().unwrap(),
                to: initial_holder,
                value: initial_supply,
            }));
        }
    }

    // ERC20 standard functions
    #[external(v0)]
    fn name(self: @ContractState) -> felt252 {
        NAME
    }

    #[external(v0)]
    fn symbol(self: @ContractState) -> felt252 {
        SYMBOL
    }

    #[external(v0)]
    fn decimals(self: @ContractState) -> u8 {
        DECIMALS
    }

    #[external(v0)]
    fn total_supply(self: @ContractState) -> u256 {
        self.total_supply.read()
    }

    #[external(v0)]
    fn balance_of(self: @ContractState, account: ContractAddress) -> u256 {
        self.balances.read(account)
    }

    #[external(v0)]
    fn allowance(self: @ContractState, owner: ContractAddress, spender: ContractAddress) -> u256 {
        self.allowances.read((owner, spender))
    }

    #[external(v0)]
    fn approve(ref self: ContractState, spender: ContractAddress, amount: u256) -> bool {
        let owner = get_caller_address();
        self._approve(owner, spender, amount);
        true
    }

    #[external(v0)]
    fn transfer(ref self: ContractState, recipient: ContractAddress, amount: u256) -> bool {
        let sender = get_caller_address();
        self.non_reentrant_enter();
        self._transfer(sender, recipient, amount);
        self.non_reentrant_exit();
        true
    }

    #[external(v0)]
    fn transfer_from(
        ref self: ContractState,
        sender: ContractAddress,
        recipient: ContractAddress,
        amount: u256
    ) -> bool {
        let spender = get_caller_address();
        let current_allowance = self.allowances.read((sender, spender));

        assert(current_allowance >= amount, Errors::INSUFFICIENT_ALLOWANCE);
        self._approve(sender, spender, current_allowance - amount);
        self._transfer(sender, recipient, amount);
        true
    }

    // Bridge-specific functions
    #[external(v0)]
    fn mint(ref self: ContractState, to: ContractAddress, amount: u256) {
        self.assert_minter();
        assert(to != 0.try_into().unwrap(), Errors::ZERO_ADDRESS);
        assert(amount > 0, Errors::INVALID_AMOUNT);

        self.non_reentrant_enter();

        // Update recipient balance
        let current_balance = self.balances.read(to);
        self.balances.write(to, current_balance + amount);

        // Update total supply
        let new_total_supply = self.total_supply.read() + amount;
        self.total_supply.write(new_total_supply);

        // Emit events
        self.emit(Event::Mint(Mint { to, amount }));
        self.emit(Event::Transfer(Transfer {
            from: 0.try_into().unwrap(),
            to,
            value: amount,
        }));

        self.non_reentrant_exit();
    }

    #[external(v0)]
    fn burn_from(ref self: ContractState, owner: ContractAddress, amount: u256) {
        self.assert_burner();
        assert(owner != 0.try_into().unwrap(), Errors::ZERO_ADDRESS);
        assert(amount > 0, Errors::INVALID_AMOUNT);

        self.non_reentrant_enter();

        // Check balance
        let current_balance = self.balances.read(owner);
        assert(current_balance >= amount, Errors::INSUFFICIENT_BALANCE);

        // Update balance
        self.balances.write(owner, current_balance - amount);

        // Update total supply
        let new_total_supply = self.total_supply.read() - amount;
        self.total_supply.write(new_total_supply);

        // Emit events
        self.emit(Event::Burn(Burn { from: owner, amount }));
        self.emit(Event::Transfer(Transfer {
            from: owner,
            to: 0.try_into().unwrap(),
            value: amount,
        }));

        self.non_reentrant_exit();
    }

    // Admin functions
    #[external(v0)]
    fn set_minter(ref self: ContractState, new_minter: ContractAddress) {
        self.assert_admin();
        let old_minter = self.minter_address.read();
        self.minter_address.write(new_minter);
        self.emit(Event::MinterChanged(MinterChanged { old_minter, new_minter }));
    }

    #[external(v0)]
    fn set_burner(ref self: ContractState, new_burner: ContractAddress) {
        self.assert_admin();
        let old_burner = self.burner_address.read();
        self.burner_address.write(new_burner);
        self.emit(Event::BurnerChanged(BurnerChanged { old_burner, new_burner }));
    }

    #[external(v0)]
    fn get_minter(self: @ContractState) -> ContractAddress {
        self.minter_address.read()
    }

    #[external(v0)]
    fn get_burner(self: @ContractState) -> ContractAddress {
        self.burner_address.read()
    }

    #[external(v0)]
    fn set_admin(ref self: ContractState, new_admin: ContractAddress) {
        self.assert_admin();
        self.admin.write(new_admin);
    }

    #[external(v0)]
    fn get_admin(self: @ContractState) -> ContractAddress {
        self.admin.read()
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _transfer(
            ref self: ContractState,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256
        ) {
            assert(sender != 0.try_into().unwrap(), Errors::ZERO_ADDRESS);
            assert(recipient != 0.try_into().unwrap(), Errors::ZERO_ADDRESS);
            assert(amount > 0, Errors::INVALID_AMOUNT);

            let sender_balance = self.balances.read(sender);
            assert(sender_balance >= amount, Errors::INSUFFICIENT_BALANCE);

            self.balances.write(sender, sender_balance - amount);
            let recipient_balance = self.balances.read(recipient);
            self.balances.write(recipient, recipient_balance + amount);

            self.emit(Event::Transfer(Transfer { from: sender, to: recipient, value: amount }));
        }

        fn _approve(
            ref self: ContractState,
            owner: ContractAddress,
            spender: ContractAddress,
            amount: u256
        ) {
            assert(owner != 0.try_into().unwrap(), Errors::ZERO_ADDRESS);
            assert(spender != 0.try_into().unwrap(), Errors::ZERO_ADDRESS);

            self.allowances.write((owner, spender), amount);
            self.emit(Event::Approval(Approval { owner, spender, value: amount }));
        }

        fn assert_minter(ref self: ContractState) {
            let caller = get_caller_address();
            let minter = self.minter_address.read();
            assert(caller == minter, Errors::NOT_MINTER);
        }

        fn assert_burner(ref self: ContractState) {
            let caller = get_caller_address();
            let burner = self.burner_address.read();
            assert(caller == burner, Errors::NOT_BURNER);
        }

        fn assert_admin(ref self: ContractState) {
            let caller = get_caller_address();
            let admin = self.admin.read();
            assert(caller == admin, Errors::NOT_ADMIN);
        }

        /// Reentrancy guard - prevents reentrancy attacks
        fn non_reentrant_enter(ref self: ContractState) {
            assert(!self.entered.read(), Errors::REENTRANCY_ATTACK);
            self.entered.write(true);
        }

        fn non_reentrant_exit(ref self: ContractState) {
            self.entered.write(false);
        }
    }
}