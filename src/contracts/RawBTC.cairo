#[starknet::contract]
pub mod RawBTC {
    use starknet::{
        ContractAddress,
        get_caller_address,
    };
    use starknet::storage::{Map, StoragePointerReadAccess, StoragePointerWriteAccess, StorageMapReadAccess, StorageMapWriteAccess};
    use core::integer::u256;

    // ─────────────────────────────────────────────────────────────
    // STORAGE
    // ─────────────────────────────────────────────────────────────

    #[storage]
    struct Storage {
        name: felt252,
        symbol: felt252,
        decimals: u8,

        total_supply: u256,

        balances: Map<ContractAddress, u256>,
        allowances: Map<(ContractAddress, ContractAddress), u256>,

        // Trusted contracts
        admin: ContractAddress,
        spv_verifier: ContractAddress,
        withdrawal_manager: ContractAddress,

        // Prevent double minting from same BTC tx
        btc_tx_used: Map<felt252, bool>,
    }

    // ─────────────────────────────────────────────────────────────
    // EVENTS
    // ─────────────────────────────────────────────────────────────

    #[derive(Drop, starknet::Event)]
    struct Minted {
        #[key]
        btc_tx_hash: felt252,
        #[key]
        to: ContractAddress,
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct Burned {
        #[key]
        from: ContractAddress,
        amount: u256,
        btc_destination: felt252,
    }

    #[derive(Drop, starknet::Event)]
    struct Transfer {
        #[key]
        from: ContractAddress,
        #[key]
        to: ContractAddress,
        amount: u256,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Minted: Minted,
        Burned: Burned,
        Transfer: Transfer,
    }

    // ─────────────────────────────────────────────────────────────
    // ERRORS
    // ─────────────────────────────────────────────────────────────

    mod Errors {
        pub const NOT_ADMIN: felt252 = 'RawBTC: not admin';
        pub const NOT_SPV: felt252 = 'RawBTC: not spv verifier';
        pub const NOT_WITHDRAWAL_MANAGER: felt252 = 'RawBTC: not withdrawal manager';
        pub const TX_ALREADY_USED: felt252 = 'RawBTC: btc tx already used';
        pub const INSUFFICIENT_BALANCE: felt252 = 'RawBTC: insufficient balance';
        pub const ZERO_AMOUNT: felt252 = 'RawBTC: zero amount';
    }

    // ─────────────────────────────────────────────────────────────
    // CONSTRUCTOR
    // ─────────────────────────────────────────────────────────────

    #[constructor]
    fn constructor(
        ref self: ContractState,
        admin: ContractAddress,
        spv_verifier: ContractAddress,
        withdrawal_manager: ContractAddress
    ) {
        self.name.write('Raw Bitcoin');
        self.symbol.write('rawBTC');
        self.decimals.write(8); // BTC precision
        self.admin.write(admin);
        self.spv_verifier.write(spv_verifier);
        self.withdrawal_manager.write(withdrawal_manager);
    }

    // ─────────────────────────────────────────────────────────────
    // MINT (BTC → STARKNET)
    // ─────────────────────────────────────────────────────────────
    // Called ONLY after:
    // 1. BTC tx is observed
    // 2. SPV proof verified
    // 3. Deposit confirmed final

    #[external(v0)]
    fn mint_from_btc(
        ref self: ContractState,
        btc_tx_hash: felt252,
        to: ContractAddress,
        amount: u256
    ) {
        let caller = get_caller_address();
        assert(caller == self.spv_verifier.read(), Errors::NOT_SPV);
        assert(amount > 0, Errors::ZERO_AMOUNT);
        assert(!self.btc_tx_used.read(btc_tx_hash), Errors::TX_ALREADY_USED);

        self.btc_tx_used.write(btc_tx_hash, true);

        let balance = self.balances.read(to);
        self.balances.write(to, balance + amount);

        let supply = self.total_supply.read();
        self.total_supply.write(supply + amount);

        self.emit(Event::Minted(Minted {
            btc_tx_hash,
            to,
            amount,
        }));
    }

    // ─────────────────────────────────────────────────────────────
    // BURN (STARKNET → BTC)
    // ─────────────────────────────────────────────────────────────
    // Burn is permissioned:
    // Only WithdrawalManager can burn
    // after operator quorum is reached

    #[external(v0)]
    fn burn_for_btc(
        ref self: ContractState,
        from: ContractAddress,
        amount: u256,
        btc_destination: felt252
    ) {
        let caller = get_caller_address();
        assert(caller == self.withdrawal_manager.read(), Errors::NOT_WITHDRAWAL_MANAGER);
        assert(amount > 0, Errors::ZERO_AMOUNT);

        let balance = self.balances.read(from);
        assert(balance >= amount, Errors::INSUFFICIENT_BALANCE);

        self.balances.write(from, balance - amount);

        let supply = self.total_supply.read();
        self.total_supply.write(supply - amount);

        self.emit(Event::Burned(Burned {
            from,
            amount,
            btc_destination,
        }));
    }

    // ─────────────────────────────────────────────────────────────
    // ERC20-LIKE VIEW FUNCTIONS (MINIMAL)
    // ─────────────────────────────────────────────────────────────

    #[external(v0)]
    fn balance_of(self: @ContractState, user: ContractAddress) -> u256 {
        self.balances.read(user)
    }

    #[external(v0)]
    fn total_supply(self: @ContractState) -> u256 {
        self.total_supply.read()
    }

    #[external(v0)]
    fn name(self: @ContractState) -> felt252 {
        self.name.read()
    }

    #[external(v0)]
    fn symbol(self: @ContractState) -> felt252 {
        self.symbol.read()
    }

    #[external(v0)]
    fn decimals(self: @ContractState) -> u8 {
        self.decimals.read()
    }

    // ─────────────────────────────────────────────────────────────
    // ADMIN CONTROLS
    // ─────────────────────────────────────────────────────────────

    #[external(v0)]
    fn set_spv_verifier(ref self: ContractState, new_spv: ContractAddress) {
        self.assert_admin();
        self.spv_verifier.write(new_spv);
    }

    #[external(v0)]
    fn set_withdrawal_manager(ref self: ContractState, new_manager: ContractAddress) {
        self.assert_admin();
        self.withdrawal_manager.write(new_manager);
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn assert_admin(ref self: ContractState) {
            assert(get_caller_address() == self.admin.read(), Errors::NOT_ADMIN);
        }
    }
}
