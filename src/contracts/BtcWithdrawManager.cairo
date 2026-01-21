#[starknet::contract]
pub mod BtcWithdrawManager {
    use starknet::{
        ContractAddress,
        get_caller_address,
        get_block_timestamp
    };
    use starknet::storage::{
        Map, StoragePointerReadAccess, StoragePointerWriteAccess,
        StorageMapReadAccess, StorageMapWriteAccess
    };
    use core::integer::u256;

    // ─────────────────────────────────────────────────────────────
    // EXTERNAL INTERFACES
    // ─────────────────────────────────────────────────────────────

    // Interface for RawBTC contract
    #[starknet::interface]
    trait IRawBTC<TContractState> {
        fn burn_for_btc(
            ref self: TContractState,
            from: ContractAddress,
            amount: u256,
            btc_destination: felt252
        );
    }

    // ─────────────────────────────────────────────────────────────
    // STRUCTS
    // ─────────────────────────────────────────────────────────────

    #[derive(Drop, Serde, starknet::Store, Copy)]
    struct WithdrawalRequest {
        requester: ContractAddress,
        btc_address: felt252,
        amount: u256,
        timestamp: u64,
        fulfilled: bool,
    }

    // ─────────────────────────────────────────────────────────────
    // STORAGE
    // ─────────────────────────────────────────────────────────────

    #[storage]
    struct Storage {
        raw_btc: ContractAddress,

        withdrawal_nonce: u256,
        withdrawals: Map<u256, WithdrawalRequest>,

        operators: Map<ContractAddress, bool>,
        admin: ContractAddress,
    }

    // ─────────────────────────────────────────────────────────────
    // EVENTS
    // ─────────────────────────────────────────────────────────────

    #[derive(Drop, starknet::Event)]
    struct WithdrawalRequested {
        #[key]
        withdrawal_id: u256,
        requester: ContractAddress,
        btc_address: felt252,
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct WithdrawalFulfilled {
        #[key]
        withdrawal_id: u256,
        operator: ContractAddress,
        btc_txid: felt252,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        WithdrawalRequested: WithdrawalRequested,
        WithdrawalFulfilled: WithdrawalFulfilled,
    }

    // ─────────────────────────────────────────────────────────────
    // ERRORS
    // ─────────────────────────────────────────────────────────────

    mod Errors {
        pub const NOT_ADMIN: felt252 = 'Withdraw: not admin';
        pub const NOT_OPERATOR: felt252 = 'Withdraw: not operator';
        pub const INVALID_AMOUNT: felt252 = 'Withdraw: invalid amount';
        pub const ALREADY_FULFILLED: felt252 = 'Withdraw: already fulfilled';
        pub const UNKNOWN_WITHDRAWAL: felt252 = 'Withdraw: unknown withdrawal';
    }

    // ─────────────────────────────────────────────────────────────
    // CONSTRUCTOR
    // ─────────────────────────────────────────────────────────────

    #[constructor]
    fn constructor(
        ref self: ContractState,
        admin: ContractAddress,
        raw_btc: ContractAddress
    ) {
        self.admin.write(admin);
        self.raw_btc.write(raw_btc);
        self.withdrawal_nonce.write(0);
    }

    // ─────────────────────────────────────────────────────────────
    // USER FLOW: REQUEST WITHDRAWAL
    // ─────────────────────────────────────────────────────────────

    #[external(v0)]
    fn request_withdrawal(
        ref self: ContractState,
        amount: u256,
        btc_address: felt252
    ) -> u256 {
        assert(amount > 0, Errors::INVALID_AMOUNT);

        let caller = get_caller_address();

        // Burn rawBTC
        let raw_btc_dispatcher = IRawBTCDispatcher {
            contract_address: self.raw_btc.read()
        };
        raw_btc_dispatcher.burn_for_btc(caller, amount, btc_address);

        // Create withdrawal request
        let withdrawal_id = self.withdrawal_nonce.read() + 1;
        self.withdrawal_nonce.write(withdrawal_id);

        let request = WithdrawalRequest {
            requester: caller,
            btc_address,
            amount,
            timestamp: get_block_timestamp(),
            fulfilled: false,
        };

        self.withdrawals.write(withdrawal_id, request);

        self.emit(Event::WithdrawalRequested(WithdrawalRequested {
            withdrawal_id,
            requester: caller,
            btc_address,
            amount,
        }));

        withdrawal_id
    }

    // ─────────────────────────────────────────────────────────────
    // OPERATOR FLOW: CONFIRM BTC TRANSFER
    // ─────────────────────────────────────────────────────────────

    #[external(v0)]
    fn fulfill_withdrawal(
        ref self: ContractState,
        withdrawal_id: u256,
        btc_txid: felt252
    ) {
        self.assert_operator();

        let mut request = self.withdrawals.read(withdrawal_id);
        assert(request.amount > 0, Errors::UNKNOWN_WITHDRAWAL);
        assert(!request.fulfilled, Errors::ALREADY_FULFILLED);

        request.fulfilled = true;
        self.withdrawals.write(withdrawal_id, request);

        self.emit(Event::WithdrawalFulfilled(WithdrawalFulfilled {
            withdrawal_id,
            operator: get_caller_address(),
            btc_txid,
        }));
    }

    // ─────────────────────────────────────────────────────────────
    // VIEW FUNCTIONS
    // ─────────────────────────────────────────────────────────────

    #[external(v0)]
    fn get_withdrawal(
        self: @ContractState,
        withdrawal_id: u256
    ) -> WithdrawalRequest {
        self.withdrawals.read(withdrawal_id)
    }

    // ─────────────────────────────────────────────────────────────
    // ADMIN
    // ─────────────────────────────────────────────────────────────

    #[external(v0)]
    fn set_operator(
        ref self: ContractState,
        operator: ContractAddress,
        enabled: bool
    ) {
        self.assert_admin();
        self.operators.write(operator, enabled);
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn assert_admin(ref self: ContractState) {
            assert(get_caller_address() == self.admin.read(), Errors::NOT_ADMIN);
        }

        fn assert_operator(ref self: ContractState) {
            assert(self.operators.read(get_caller_address()), Errors::NOT_OPERATOR);
        }
    }
}
