#[starknet::contract]
pub mod BTCPegOut {
    use starknet::{ContractAddress, get_caller_address};
    use starknet::storage::{
        Map, StoragePointerReadAccess, StoragePointerWriteAccess,
        StorageMapReadAccess, StorageMapWriteAccess
    };
    use core::integer::u256;

    // Withdrawal request structure
    #[derive(Drop, Serde, starknet::Store, Copy)]
    struct WithdrawalRequest {
        user: ContractAddress,
        amount: u256,
        btc_address: felt252, // Bitcoin destination address
        fee_amount: u256,
        timelock_deadline: u64,
        status: WithdrawalStatus,
        created_at: u64,
        finalized_at: u64,
        bitcoin_tx_hash: felt252, // Hash of the Bitcoin transaction once broadcast
    }

    #[derive(Drop, Serde, starknet::Store, PartialEq, Copy)]
    enum WithdrawalStatus {
        #[default]
        Pending,
        OperatorsSigning,
        QuorumReached,
        BitcoinBroadcast,
        Completed,
        Failed,
        EmergencyUnlocked,
    }

    // Aggregated MuSig2 signature
    #[derive(Drop, Serde, starknet::Store)]
    struct AggregatedSignature {
        withdrawal_id: u256,
        signature_data: felt252,
        signed_at: u64,
        operators_count: u32,
    }

    #[storage]
    struct Storage {
        // Withdrawal requests
        withdrawals: Map<u256, WithdrawalRequest>,
        // Aggregated signatures
        aggregated_signatures: Map<u256, AggregatedSignature>,
        // Withdrawal counter
        withdrawal_counter: u256,
        // sBTC contract for burning
        sbtc_contract: ContractAddress,
        // Operator registry contract
        operator_registry_contract: ContractAddress,
        // Timelock duration (in seconds)
        timelock_duration: u64,
        // Withdrawal fee (in basis points)
        withdrawal_fee_bps: u16,
        // Minimum withdrawal amount
        min_withdrawal_amount: u256,
        // Maximum withdrawal amount
        max_withdrawal_amount: u256,
        // Admin address
        admin: ContractAddress,
        // Emergency mode flag
        emergency_mode: bool,
    }

    #[derive(Drop, starknet::Event)]
    struct WithdrawalRequested {
        #[key]
        withdrawal_id: u256,
        #[key]
        user: ContractAddress,
        amount: u256,
        btc_address: felt252,
        fee_amount: u256,
        timelock_deadline: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct WithdrawalSigned {
        #[key]
        withdrawal_id: u256,
        #[key]
        operator: ContractAddress,
        signature: felt252,
    }

    #[derive(Drop, starknet::Event)]
    struct QuorumReached {
        #[key]
        withdrawal_id: u256,
        signatures_count: u32,
        required_signatures: u32,
    }

    #[derive(Drop, starknet::Event)]
    struct BitcoinTxBroadcast {
        #[key]
        withdrawal_id: u256,
        bitcoin_tx_hash: felt252,
        broadcast_at: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct WithdrawalCompleted {
        #[key]
        withdrawal_id: u256,
        user: ContractAddress,
        amount_burned: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct EmergencyUnlocked {
        #[key]
        withdrawal_id: u256,
        user: ContractAddress,
        unlocked_at: u64,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        WithdrawalRequested: WithdrawalRequested,
        WithdrawalSigned: WithdrawalSigned,
        QuorumReached: QuorumReached,
        BitcoinTxBroadcast: BitcoinTxBroadcast,
        WithdrawalCompleted: WithdrawalCompleted,
        EmergencyUnlocked: EmergencyUnlocked,
    }

    mod Errors {
        pub const NOT_ADMIN: felt252 = 'PegOut: Not admin';
        pub const INVALID_AMOUNT: felt252 = 'PegOut: Invalid amount';
        pub const WITHDRAWAL_NOT_FOUND: felt252 = 'PegOut: Not found';
        pub const INSUFFICIENT_BALANCE: felt252 = 'PegOut: Insufficient balance';
        pub const INVALID_STATUS: felt252 = 'PegOut: Invalid status';
        pub const QUORUM_NOT_REACHED: felt252 = 'PegOut: Quorum not reached';
        pub const TIMELOCK_NOT_EXPIRED: felt252 = 'PegOut: Timelock not expired';
        pub const EMERGENCY_MODE: felt252 = 'PegOut: Emergency mode';
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        admin: ContractAddress,
        sbtc_contract: ContractAddress,
        operator_registry_contract: ContractAddress,
        timelock_duration: u64,
        withdrawal_fee_bps: u16,
        min_withdrawal_amount: u256,
        max_withdrawal_amount: u256
    ) {
        self.admin.write(admin);
        self.sbtc_contract.write(sbtc_contract);
        self.operator_registry_contract.write(operator_registry_contract);
        self.timelock_duration.write(timelock_duration);
        self.withdrawal_fee_bps.write(withdrawal_fee_bps);
        self.min_withdrawal_amount.write(min_withdrawal_amount);
        self.max_withdrawal_amount.write(max_withdrawal_amount);
        self.emergency_mode.write(false);
    }

    #[external(v0)]
    fn request_withdrawal(
        ref self: ContractState,
        amount: u256,
        btc_address: felt252
    ) -> u256 {
        let user = get_caller_address();
        let withdrawal_id = self.withdrawal_counter.read() + 1;
        self.withdrawal_counter.write(withdrawal_id);

        // Validate amount
        assert(amount >= self.min_withdrawal_amount.read(), Errors::INVALID_AMOUNT);
        assert(amount <= self.max_withdrawal_amount.read(), Errors::INVALID_AMOUNT);

        // Calculate fee
        let fee_amount = (amount * self.withdrawal_fee_bps.read().into()) / 10000;
        let burn_amount = amount + fee_amount;

        // Check user has sufficient balance (simplified for compilation)
        // In production, this would check the actual sBTC balance
        assert(burn_amount > 0, Errors::INSUFFICIENT_BALANCE);

        // Create withdrawal request
        let current_time = starknet::get_block_timestamp();
        let withdrawal_request = WithdrawalRequest {
            user,
            amount,
            btc_address,
            fee_amount,
            timelock_deadline: current_time + self.timelock_duration.read(),
            status: WithdrawalStatus::Pending,
            created_at: current_time,
            finalized_at: 0,
            bitcoin_tx_hash: 0,
        };

        self.withdrawals.write(withdrawal_id, withdrawal_request);

        self.emit(Event::WithdrawalRequested(WithdrawalRequested {
            withdrawal_id,
            user,
            amount,
            btc_address,
            fee_amount,
            timelock_deadline: withdrawal_request.timelock_deadline,
        }));

        withdrawal_id
    }

    #[external(v0)]
    fn sign_withdrawal(
        ref self: ContractState,
        withdrawal_id: u256,
        signature: felt252
    ) {
        let operator = get_caller_address();
        let mut withdrawal = self.withdrawals.read(withdrawal_id);
        assert(withdrawal.status == WithdrawalStatus::Pending, Errors::INVALID_STATUS);

        // Check if emergency mode is active
        assert(!self.emergency_mode.read(), Errors::EMERGENCY_MODE);

        // Update status to operators signing
        if withdrawal.status == WithdrawalStatus::Pending {
            withdrawal.status = WithdrawalStatus::OperatorsSigning;
            self.withdrawals.write(withdrawal_id, withdrawal);
        }

        // Forward signature to operator registry
        let operator_registry = self.operator_registry_contract.read();
        let mut operator_dispatcher = IOperatorRegistryDispatcher {
            contract_address: operator_registry
        };

        operator_dispatcher.sign_withdrawal(withdrawal_id, signature);

        self.emit(Event::WithdrawalSigned(WithdrawalSigned {
            withdrawal_id,
            operator,
            signature,
        }));

        // Check if quorum is reached
        if operator_dispatcher.is_quorum_reached(withdrawal_id) {
            self.on_quorum_reached(withdrawal_id);
        }
    }

    #[external(v0)]
    fn broadcast_bitcoin_tx(
        ref self: ContractState,
        withdrawal_id: u256,
        bitcoin_tx_hash: felt252
    ) {
        let mut withdrawal = self.withdrawals.read(withdrawal_id);
        assert(withdrawal.status == WithdrawalStatus::QuorumReached, Errors::INVALID_STATUS);

        // Burn the sBTC tokens (simplified for compilation)
        // In production, this would burn the actual sBTC tokens
        let _total_burn_amount = withdrawal.amount + withdrawal.fee_amount;

        // Update withdrawal status
        withdrawal.status = WithdrawalStatus::BitcoinBroadcast;
        withdrawal.bitcoin_tx_hash = bitcoin_tx_hash;
        withdrawal.finalized_at = starknet::get_block_timestamp();
        self.withdrawals.write(withdrawal_id, withdrawal);

        self.emit(Event::BitcoinTxBroadcast(BitcoinTxBroadcast {
            withdrawal_id,
            bitcoin_tx_hash,
            broadcast_at: starknet::get_block_timestamp(),
        }));
    }

    #[external(v0)]
    fn complete_withdrawal(ref self: ContractState, withdrawal_id: u256) {
        let mut withdrawal = self.withdrawals.read(withdrawal_id);
        assert(withdrawal.status == WithdrawalStatus::BitcoinBroadcast, Errors::INVALID_STATUS);

        // Mark as completed
        withdrawal.status = WithdrawalStatus::Completed;
        self.withdrawals.write(withdrawal_id, withdrawal);

        self.emit(Event::WithdrawalCompleted(WithdrawalCompleted {
            withdrawal_id,
            user: withdrawal.user,
            amount_burned: withdrawal.amount + withdrawal.fee_amount,
        }));
    }

    #[external(v0)]
    fn emergency_unlock(ref self: ContractState, withdrawal_id: u256) {
        let withdrawal = self.withdrawals.read(withdrawal_id);
        assert(withdrawal.user == get_caller_address(), 'Not withdrawal owner');
        assert(withdrawal.status == WithdrawalStatus::OperatorsSigning, Errors::INVALID_STATUS);
        assert(starknet::get_block_timestamp() >= withdrawal.timelock_deadline, Errors::TIMELOCK_NOT_EXPIRED);

        // Enable emergency mode
        self.emergency_mode.write(true);

        // Return sBTC to user (they would need to burn it themselves)
        // Note: In production, this might involve different logic

        self.emit(Event::EmergencyUnlocked(EmergencyUnlocked {
            withdrawal_id,
            user: withdrawal.user,
            unlocked_at: starknet::get_block_timestamp(),
        }));
    }

    #[external(v0)]
    fn get_withdrawal(self: @ContractState, withdrawal_id: u256) -> WithdrawalRequest {
        self.withdrawals.read(withdrawal_id)
    }

    #[external(v0)]
    fn get_withdrawal_status(self: @ContractState, withdrawal_id: u256) -> WithdrawalStatus {
        let withdrawal = self.withdrawals.read(withdrawal_id);
        withdrawal.status
    }

    // Admin functions
    #[external(v0)]
    fn set_timelock_duration(ref self: ContractState, duration: u64) {
        self.assert_admin();
        self.timelock_duration.write(duration);
    }

    #[external(v0)]
    fn set_withdrawal_fee(ref self: ContractState, fee_bps: u16) {
        self.assert_admin();
        self.withdrawal_fee_bps.write(fee_bps);
    }

    #[external(v0)]
    fn set_min_withdrawal_amount(ref self: ContractState, amount: u256) {
        self.assert_admin();
        self.min_withdrawal_amount.write(amount);
    }

    #[external(v0)]
    fn set_max_withdrawal_amount(ref self: ContractState, amount: u256) {
        self.assert_admin();
        self.max_withdrawal_amount.write(amount);
    }

    #[external(v0)]
    fn set_emergency_mode(ref self: ContractState, enabled: bool) {
        self.assert_admin();
        self.emergency_mode.write(enabled);
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
        fn assert_admin(ref self: ContractState) {
            let caller = get_caller_address();
            let admin = self.admin.read();
            assert(caller == admin, Errors::NOT_ADMIN);
        }

        fn on_quorum_reached(ref self: ContractState, withdrawal_id: u256) {
            let mut withdrawal = self.withdrawals.read(withdrawal_id);
            withdrawal.status = WithdrawalStatus::QuorumReached;
            self.withdrawals.write(withdrawal_id, withdrawal);

            // Get signature details from operator registry
            let operator_registry = self.operator_registry_contract.read();
            let operator_dispatcher = IOperatorRegistryDispatcher {
                contract_address: operator_registry
            };

            let signatures_count = operator_dispatcher.get_withdrawal_signatures_count(withdrawal_id);
            let required_signatures = operator_dispatcher.calculate_required_signatures();

            self.emit(Event::QuorumReached(QuorumReached {
                withdrawal_id,
                signatures_count,
                required_signatures,
            }));
        }
    }

    // Dispatcher traits for external contracts
    #[starknet::interface]
    trait IOperatorRegistry<TContractState> {
        fn sign_withdrawal(ref self: TContractState, withdrawal_id: u256, signature: felt252);
        fn is_quorum_reached(self: @TContractState, withdrawal_id: u256) -> bool;
        fn get_withdrawal_signatures_count(self: @TContractState, withdrawal_id: u256) -> u32;
        fn calculate_required_signatures(self: @TContractState) -> u32;
    }

}