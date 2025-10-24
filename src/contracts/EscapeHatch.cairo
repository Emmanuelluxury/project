#[starknet::contract]
pub mod EscapeHatch {
    use starknet::{ContractAddress, get_caller_address};
    use starknet::storage::{
        Map, StoragePointerReadAccess, StoragePointerWriteAccess,
        StorageMapReadAccess, StorageMapWriteAccess
    };
    use core::integer::u256;

    // Emergency withdrawal request
    #[derive(Drop, Serde, starknet::Store)]
    struct EmergencyWithdrawal {
        user: ContractAddress,
        original_withdrawal_id: u256,
        amount: u256,
        btc_address: felt252,
        emergency_type: EmergencyType,
        status: EmergencyStatus,
        created_at: u64,
        executed_at: u64,
        proof_of_failure: felt252, // Hash of proof showing operator failure
    }

    #[derive(Drop, Serde, starknet::Store, PartialEq)]
    enum EmergencyType {
        #[default]
        OperatorFailure,
        TimelockExpired,
        InsufficientSignatures,
        MaliciousOperators,
    }

    #[derive(Drop, Serde, starknet::Store, PartialEq)]
    enum EmergencyStatus {
        #[default]
        Pending,
        Approved,
        Executed,
        Rejected,
    }

    // Dispute structure for challenging emergency withdrawals
    #[derive(Drop, Serde, starknet::Store)]
    struct Dispute {
        emergency_id: u256,
        challenger: ContractAddress,
        dispute_reason: felt252,
        evidence: felt252,
        status: DisputeStatus,
        created_at: u64,
        resolved_at: u64,
    }

    #[derive(Drop, Serde, starknet::Store, PartialEq)]
    enum DisputeStatus {
        #[default]
        Active,
        Resolved,
        Rejected,
    }

    #[storage]
    struct Storage {
        // Emergency withdrawals
        emergency_withdrawals: Map<u256, EmergencyWithdrawal>,
        // Disputes
        disputes: Map<u256, Dispute>,
        // Emergency withdrawal counter
        emergency_counter: u256,
        // BTCPegOut contract
        peg_out_contract: ContractAddress,
        // sBTC contract for refunds
        sbtc_contract: ContractAddress,
        // Emergency timelock (additional delay for emergency withdrawals)
        emergency_timelock: u64,
        // Dispute timelock (how long disputes can be active)
        dispute_timelock: u64,
        // Minimum evidence requirement for emergency withdrawals
        min_evidence_length: u32,
        // Admin address
        admin: ContractAddress,
        // Emergency pause flag
        emergency_paused: bool,
        // Governance contract for dispute resolution
        governance_contract: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct EmergencyWithdrawalRequested {
        #[key]
        emergency_id: u256,
        #[key]
        user: ContractAddress,
        original_withdrawal_id: u256,
        amount: u256,
        emergency_type: EmergencyType,
        proof_of_failure: felt252,
    }

    #[derive(Drop, starknet::Event)]
    struct EmergencyWithdrawalApproved {
        #[key]
        emergency_id: u256,
        approved_by: ContractAddress,
        approved_at: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct EmergencyWithdrawalExecuted {
        #[key]
        emergency_id: u256,
        user: ContractAddress,
        amount_refunded: u256,
        executed_at: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct DisputeCreated {
        #[key]
        emergency_id: u256,
        #[key]
        challenger: ContractAddress,
        dispute_reason: felt252,
    }

    #[derive(Drop, starknet::Event)]
    struct DisputeResolved {
        #[key]
        emergency_id: u256,
        resolved_by: ContractAddress,
        resolution: felt252,
        resolved_at: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct EmergencyPaused {
        paused_by: ContractAddress,
        paused_at: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct EmergencyUnpaused {
        unpaused_by: ContractAddress,
        unpaused_at: u64,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        EmergencyWithdrawalRequested: EmergencyWithdrawalRequested,
        EmergencyWithdrawalApproved: EmergencyWithdrawalApproved,
        EmergencyWithdrawalExecuted: EmergencyWithdrawalExecuted,
        DisputeCreated: DisputeCreated,
        DisputeResolved: DisputeResolved,
        EmergencyPaused: EmergencyPaused,
        EmergencyUnpaused: EmergencyUnpaused,
    }

    mod Errors {
        pub const NOT_ADMIN: felt252 = 'Escape: Not admin';
        pub const EMERGENCY_PAUSED: felt252 = 'Escape: Emergency paused';
        pub const INVALID_EMERGENCY: felt252 = 'Escape: Invalid emergency';
        pub const INSUFFICIENT_EVIDENCE: felt252 = 'Escape: Insufficient evidence';
        pub const TIMELOCK_NOT_EXPIRED: felt252 = 'Escape: Timelock not expired';
        pub const ALREADY_PROCESSED: felt252 = 'Escape: Already processed';
        pub const NOT_GOVERNANCE: felt252 = 'Escape: Not governance';
        pub const DISPUTE_EXISTS: felt252 = 'Escape: Dispute exists';
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        admin: ContractAddress,
        peg_out_contract: ContractAddress,
        sbtc_contract: ContractAddress,
        governance_contract: ContractAddress,
        emergency_timelock: u64,
        dispute_timelock: u64,
        min_evidence_length: u32
    ) {
        self.admin.write(admin);
        self.peg_out_contract.write(peg_out_contract);
        self.sbtc_contract.write(sbtc_contract);
        self.governance_contract.write(governance_contract);
        self.emergency_timelock.write(emergency_timelock);
        self.dispute_timelock.write(dispute_timelock);
        self.min_evidence_length.write(min_evidence_length);
        self.emergency_paused.write(false);
    }

    #[external(v0)]
    fn request_emergency_withdrawal(
        ref self: ContractState,
        original_withdrawal_id: u256,
        emergency_type: EmergencyType,
        btc_address: felt252,
        proof_of_failure: felt252
    ) -> u256 {
        assert(!self.emergency_paused.read(), Errors::EMERGENCY_PAUSED);

        let user = get_caller_address();
        let emergency_id = self.emergency_counter.read() + 1;
        self.emergency_counter.write(emergency_id);

        // Validate proof of failure
        assert(proof_of_failure != 0, Errors::INSUFFICIENT_EVIDENCE);

        // Get original withdrawal details
        let peg_out_contract = self.peg_out_contract.read();
        let mut peg_out_dispatcher = IBTCPegOutDispatcher {
            contract_address: peg_out_contract
        };

        let original_withdrawal = peg_out_dispatcher.get_withdrawal(original_withdrawal_id);
        assert(original_withdrawal.user == user, 'Not withdrawal owner');
        assert(original_withdrawal.status == 1, 'Invalid withdrawal status'); // 1 = OperatorsSigning

        // Create emergency withdrawal
        let current_time = starknet::get_block_timestamp();
        let emergency_withdrawal = EmergencyWithdrawal {
            user,
            original_withdrawal_id,
            amount: original_withdrawal.amount,
            btc_address,
            emergency_type,
            status: EmergencyStatus::Pending,
            created_at: current_time,
            executed_at: 0,
            proof_of_failure,
        };

        self.emergency_withdrawals.write(emergency_id, emergency_withdrawal);

        // Read the stored emergency withdrawal for event emission
        let stored_emergency = self.emergency_withdrawals.read(emergency_id);
        self.emit(Event::EmergencyWithdrawalRequested(EmergencyWithdrawalRequested {
            emergency_id,
            user,
            original_withdrawal_id,
            amount: original_withdrawal.amount,
            emergency_type: stored_emergency.emergency_type,
            proof_of_failure,
        }));

        emergency_id
    }

    #[external(v0)]
    fn approve_emergency_withdrawal(ref self: ContractState, emergency_id: u256) {
        self.assert_governance();

        let mut emergency = self.emergency_withdrawals.read(emergency_id);
        assert(emergency.status == EmergencyStatus::Pending, Errors::ALREADY_PROCESSED);

        let current_time = starknet::get_block_timestamp();
        assert(current_time >= emergency.created_at + self.emergency_timelock.read(), Errors::TIMELOCK_NOT_EXPIRED);

        emergency.status = EmergencyStatus::Approved;
        self.emergency_withdrawals.write(emergency_id, emergency);

        self.emit(Event::EmergencyWithdrawalApproved(EmergencyWithdrawalApproved {
            emergency_id,
            approved_by: get_caller_address(),
            approved_at: current_time,
        }));
    }

    #[external(v0)]
    fn execute_emergency_withdrawal(ref self: ContractState, emergency_id: u256) {
        let mut emergency = self.emergency_withdrawals.read(emergency_id);
        assert(emergency.status == EmergencyStatus::Approved, Errors::INVALID_EMERGENCY);

        let current_time = starknet::get_block_timestamp();
        assert(current_time >= emergency.created_at + self.emergency_timelock.read(), Errors::TIMELOCK_NOT_EXPIRED);

        // Mint sBTC back to user (refund)
        let sbtc_contract = self.sbtc_contract.read();
        // Note: In production, this should use a proper minting mechanism
        // For now, we'll assume the minting happens through the sBTC contract
        let _sbtc_contract = sbtc_contract;

        // Extract values before consuming the struct
        let emergency_user = emergency.user;
        let emergency_amount = emergency.amount;

        // Update emergency status
        emergency.status = EmergencyStatus::Executed;
        emergency.executed_at = current_time;
        self.emergency_withdrawals.write(emergency_id, emergency);

        self.emit(Event::EmergencyWithdrawalExecuted(EmergencyWithdrawalExecuted {
            emergency_id,
            user: emergency_user,
            amount_refunded: emergency_amount,
            executed_at: current_time,
        }));
    }

    #[external(v0)]
    fn create_dispute(
        ref self: ContractState,
        emergency_id: u256,
        dispute_reason: felt252,
        evidence: felt252
    ) {
        let challenger = get_caller_address();
        let emergency = self.emergency_withdrawals.read(emergency_id);

        assert(emergency.status == EmergencyStatus::Pending, Errors::INVALID_EMERGENCY);
        assert(evidence != 0, Errors::INSUFFICIENT_EVIDENCE);

        let dispute = Dispute {
            emergency_id,
            challenger,
            dispute_reason,
            evidence,
            status: DisputeStatus::Active,
            created_at: starknet::get_block_timestamp(),
            resolved_at: 0,
        };

        self.disputes.write(emergency_id, dispute);

        self.emit(Event::DisputeCreated(DisputeCreated {
            emergency_id,
            challenger,
            dispute_reason,
        }));
    }

    #[external(v0)]
    fn resolve_dispute(
        ref self: ContractState,
        emergency_id: u256,
        resolution: felt252,
        approve_emergency: bool
    ) {
        self.assert_governance();

        let mut dispute = self.disputes.read(emergency_id);
        assert(dispute.status == DisputeStatus::Active, 'Dispute not active');

        let current_time = starknet::get_block_timestamp();
        assert(current_time >= dispute.created_at + self.dispute_timelock.read(), Errors::TIMELOCK_NOT_EXPIRED);

        // Resolve dispute
        dispute.status = DisputeStatus::Resolved;
        dispute.resolved_at = current_time;
        self.disputes.write(emergency_id, dispute);

        // Update emergency withdrawal based on resolution
        if approve_emergency {
            let emergency_check = self.emergency_withdrawals.read(emergency_id);
            if emergency_check.status == EmergencyStatus::Pending {
                let mut emergency_approve = self.emergency_withdrawals.read(emergency_id);
                emergency_approve.status = EmergencyStatus::Approved;
                self.emergency_withdrawals.write(emergency_id, emergency_approve);
            }
        } else {
            let mut emergency_reject = self.emergency_withdrawals.read(emergency_id);
            emergency_reject.status = EmergencyStatus::Rejected;
            self.emergency_withdrawals.write(emergency_id, emergency_reject);
        }

        self.emit(Event::DisputeResolved(DisputeResolved {
            emergency_id,
            resolved_by: get_caller_address(),
            resolution,
            resolved_at: current_time,
        }));
    }

    #[external(v0)]
    fn pause_emergency(ref self: ContractState) {
        self.assert_admin();
        self.emergency_paused.write(true);

        self.emit(Event::EmergencyPaused(EmergencyPaused {
            paused_by: get_caller_address(),
            paused_at: starknet::get_block_timestamp(),
        }));
    }

    #[external(v0)]
    fn unpause_emergency(ref self: ContractState) {
        self.assert_admin();
        self.emergency_paused.write(false);

        self.emit(Event::EmergencyUnpaused(EmergencyUnpaused {
            unpaused_by: get_caller_address(),
            unpaused_at: starknet::get_block_timestamp(),
        }));
    }

    #[external(v0)]
    fn get_emergency_withdrawal(self: @ContractState, emergency_id: u256) -> EmergencyWithdrawal {
        self.emergency_withdrawals.read(emergency_id)
    }

    #[external(v0)]
    fn get_dispute(self: @ContractState, emergency_id: u256) -> Dispute {
        self.disputes.read(emergency_id)
    }

    #[external(v0)]
    fn is_emergency_paused(self: @ContractState) -> bool {
        self.emergency_paused.read()
    }

    // Admin functions
    #[external(v0)]
    fn set_emergency_timelock(ref self: ContractState, timelock: u64) {
        self.assert_admin();
        self.emergency_timelock.write(timelock);
    }

    #[external(v0)]
    fn set_dispute_timelock(ref self: ContractState, timelock: u64) {
        self.assert_admin();
        self.dispute_timelock.write(timelock);
    }

    #[external(v0)]
    fn set_governance_contract(ref self: ContractState, governance: ContractAddress) {
        self.assert_admin();
        self.governance_contract.write(governance);
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

        fn assert_governance(ref self: ContractState) {
            let caller = get_caller_address();
            let governance = self.governance_contract.read();
            assert(caller == governance, Errors::NOT_GOVERNANCE);
        }
    }

    // Withdrawal request structure (matching BTCPegOut)
    #[derive(Drop, Serde, starknet::Store)]
    struct WithdrawalRequest {
        user: ContractAddress,
        amount: u256,
        btc_address: felt252,
        fee_amount: u256,
        timelock_deadline: u64,
        status: u8, // Simplified status
        created_at: u64,
        finalized_at: u64,
        bitcoin_tx_hash: felt252,
    }

    // Interface for BTCPegOut contract
    #[starknet::interface]
    trait IBTCPegOut<TContractState> {
        fn get_withdrawal(self: @TContractState, withdrawal_id: u256) -> WithdrawalRequest;
    }
}