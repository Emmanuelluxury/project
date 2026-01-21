#[starknet::contract]
#[feature("deprecated-starknet-consts")]
pub mod OperatorRegistryV2 {
    use starknet::{ContractAddress, get_caller_address};
    use starknet::storage::{
        Map, StoragePointerReadAccess, StoragePointerWriteAccess,
        StorageMapReadAccess, StorageMapWriteAccess
    };
    use core::integer::u256;

    // Interface for ERC20 contract
    #[starknet::interface]
    trait IERC20<TContractState> {
        fn transfer_from(
            ref self: TContractState,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256
        ) -> bool;
    }

    // Operator information structure
    #[derive(Drop, Serde, starknet::Store)]
    struct Operator {
        operator_address: ContractAddress,
        public_key: felt252, // MuSig2 public key
        bond_amount: u256,
        is_active: bool,
        registered_at: u64,
        last_active: u64,
        total_withdrawals_signed: u256,
        slashing_count: u32,
    }

    // Withdrawal signature structure
    #[derive(Drop, Serde, starknet::Store)]
    struct WithdrawalSignature {
        withdrawal_id: u256,
        operator: ContractAddress,
        signature: felt252, // MuSig2 signature
        signed_at: u64,
    }

    #[storage]
    struct Storage {
        // Operators mapping
        operators: Map<ContractAddress, Operator>,
        // Public key to operator mapping
        operator_by_key: Map<felt252, ContractAddress>,
        // Active operators list
        active_operators: Map<u32, ContractAddress>, // index -> operator
        // Active operators count
        active_operators_count: u32,
        // Minimum bond amount required
        min_bond_amount: u256,
        // Required quorum for signatures (percentage)
        required_quorum_bps: u16,
        // Maximum slashing penalty (percentage of bond)
        max_slashing_bps: u16,
        // Admin address
        admin: ContractAddress,
        // sBTC contract for bond management
        sbtc_contract: ContractAddress,
        // Withdrawal signatures
        withdrawal_signatures: Map<(u256, ContractAddress), WithdrawalSignature>,
        // Signatures count per withdrawal
        withdrawal_signature_count: Map<u256, u32>,
    }

    #[derive(Drop, starknet::Event)]
    struct OperatorRegistered {
        #[key]
        operator: ContractAddress,
        public_key: felt252,
        bond_amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct OperatorActivated {
        #[key]
        operator: ContractAddress,
        activated_at: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct OperatorDeactivated {
        #[key]
        operator: ContractAddress,
        deactivated_at: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct OperatorSlashed {
        #[key]
        operator: ContractAddress,
        #[key]
        withdrawal_id: u256,
        slash_amount: u256,
        reason: felt252,
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

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        OperatorRegistered: OperatorRegistered,
        OperatorActivated: OperatorActivated,
        OperatorDeactivated: OperatorDeactivated,
        OperatorSlashed: OperatorSlashed,
        WithdrawalSigned: WithdrawalSigned,
        QuorumReached: QuorumReached,
    }

    mod Errors {
        pub const NOT_ADMIN: felt252 = 'Operator: Not admin';
        pub const OPERATOR_EXISTS: felt252 = 'Operator: Already exists';
        pub const OPERATOR_NOT_FOUND: felt252 = 'Operator: Not found';
        pub const INSUFFICIENT_BOND: felt252 = 'Operator: Insufficient bond';
        pub const INVALID_QUORUM: felt252 = 'Operator: Invalid quorum';
        pub const ALREADY_SIGNED: felt252 = 'Operator: Already signed';
        pub const NOT_ACTIVE: felt252 = 'Operator: Not active';
        pub const QUORUM_NOT_REACHED: felt252 = 'Operator: Quorum not reached';
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        admin: ContractAddress,
        sbtc_contract: ContractAddress,
        min_bond_amount: u256,
        required_quorum_bps: u16,
        max_slashing_bps: u16
    ) {
        self.admin.write(admin);
        self.sbtc_contract.write(sbtc_contract);
        self.min_bond_amount.write(min_bond_amount);
        self.required_quorum_bps.write(required_quorum_bps);
        self.max_slashing_bps.write(max_slashing_bps);
    }

    #[external(v0)]
    fn register_operator(
        ref self: ContractState,
        public_key: felt252,
        bond_amount: u256
    ) {
        let operator_address = get_caller_address();
        // Check if operator already exists (regardless of active status)
        let existing_operator = self.operators.read(operator_address);
        // Check if operator exists by checking if public_key is non-zero (since default felt252 is 0)
        if existing_operator.public_key != 0 {
            assert(false, Errors::OPERATOR_EXISTS);
        }
        
        // Check minimum bond amount
        assert(bond_amount >= self.min_bond_amount.read(), Errors::INSUFFICIENT_BOND);

        // 🔐 REAL BOND LOCK
        // Note: In a real implementation, you'd need to handle the contract address properly
        // For now, we'll use a placeholder - this needs proper implementation
        // The contract address should be obtained differently in a real implementation
        let contract_address = self.admin.read(); // Using admin as placeholder for contract address
        
        // Create interface dispatcher for ERC20 contract
        let sbtc = IERC20Dispatcher { contract_address: self.sbtc_contract.read() };
        // Transfer bond from operator to contract
        sbtc.transfer_from(operator_address, contract_address, bond_amount);

        let now = starknet::get_block_timestamp();

        let operator = Operator {
            operator_address,
            public_key,
            bond_amount,
            is_active: false,
            registered_at: now,
            last_active: now,
            total_withdrawals_signed: 0,
            slashing_count: 0,
        };

        self.operators.write(operator_address, operator);
        self.operator_by_key.write(public_key, operator_address);
        self.emit(Event::OperatorRegistered(OperatorRegistered {
            operator: operator_address,
            public_key,
            bond_amount,
        }));
    }

    #[external(v0)]
    fn activate_operator(ref self: ContractState, operator: ContractAddress) {
        self.assert_admin();
        let mut operator_data = self.operators.read(operator);
        assert(!operator_data.is_active, Errors::NOT_ACTIVE);

        operator_data.is_active = true;
        operator_data.last_active = starknet::get_block_timestamp();
        self.operators.write(operator, operator_data);

        // Add to active operators list
        let index = self.active_operators_count.read();
        self.active_operators.write(index, operator);
        self.active_operators_count.write(index + 1);

        self.emit(Event::OperatorActivated(OperatorActivated {
            operator,
            activated_at: starknet::get_block_timestamp(),
        }));
    }

    #[external(v0)]
    fn deactivate_operator(ref self: ContractState, operator: ContractAddress) {
        self.assert_admin();
        let mut operator_data = self.operators.read(operator);
        assert(operator_data.is_active, Errors::NOT_ACTIVE);

        operator_data.is_active = false;
        self.operators.write(operator, operator_data);

        // Remove operator from active list by replacing with the last operator
        let count = self.active_operators_count.read();
        if count > 0 {
            let last_index = count - 1;
            let last_operator = self.active_operators.read(last_index);
            // Find and replace the operator to be removed
            let mut found = false;
            let mut i = 0;
            while i < count && !found {
                if self.active_operators.read(i) == operator {
                    // Replace with last operator
                    self.active_operators.write(i, last_operator);
                    found = true;
                }
                i += 1;
            }
            // Reduce count
            self.active_operators_count.write(last_index);
        }

        self.emit(Event::OperatorDeactivated(OperatorDeactivated {
            operator,
            deactivated_at: starknet::get_block_timestamp(),
        }));
    }


    #[external(v0)]
    fn sign_withdrawal(
        ref self: ContractState,
        withdrawal_id: u256,
        signature: felt252
    ) {
        let operator = get_caller_address();
        let operator_data = self.operators.read(operator);
        assert(operator_data.is_active, Errors::NOT_ACTIVE);

        // Check if already signed
        let existing_signature = self.withdrawal_signatures.read((withdrawal_id, operator));
        assert(existing_signature.signed_at == 0, Errors::ALREADY_SIGNED);

        // Record signature
        let withdrawal_signature = WithdrawalSignature {
            withdrawal_id,
            operator,
            signature,
            signed_at: starknet::get_block_timestamp(),
        };

        self.withdrawal_signatures.write((withdrawal_id, operator), withdrawal_signature);

        // Update signature count
        let current_count = self.withdrawal_signature_count.read(withdrawal_id);
        self.withdrawal_signature_count.write(withdrawal_id, current_count + 1);

        // Update operator stats
        let mut updated_operator = operator_data;
        updated_operator.total_withdrawals_signed += 1;
        updated_operator.last_active = starknet::get_block_timestamp();
        self.operators.write(operator, updated_operator);

        self.emit(Event::WithdrawalSigned(WithdrawalSigned {
            withdrawal_id,
            operator,
            signature,
        }));

        // Check if quorum is reached
        self.check_quorum_reached(withdrawal_id);
    }

    #[external(v0)]
    fn slash_operator(
        ref self: ContractState,
        operator: ContractAddress,
        withdrawal_id: u256,
        slash_amount: u256,
        reason: felt252
    ) {
        self.assert_admin();
        let mut operator_data = self.operators.read(operator);
        assert(operator_data.is_active, Errors::NOT_ACTIVE);

        // Calculate actual slash amount (can't exceed max slashing percentage)
        let max_slash = (operator_data.bond_amount * self.max_slashing_bps.read().into()) / 10000;
        let actual_slash = if slash_amount > max_slash { max_slash } else { slash_amount };

        // Update operator bond
        operator_data.bond_amount -= actual_slash;
        operator_data.slashing_count += 1;

        // If bond falls below minimum, deactivate operator
        if operator_data.bond_amount < self.min_bond_amount.read() {
            operator_data.is_active = false;
        }

        self.operators.write(operator, operator_data);

        self.emit(Event::OperatorSlashed(OperatorSlashed {
            operator,
            withdrawal_id,
            slash_amount: actual_slash,
            reason,
        }));
    }

    #[external(v0)]
    fn get_operator(self: @ContractState, operator: ContractAddress) -> Operator {
        self.operators.read(operator)
    }

    #[external(v0)]
    fn get_operator_by_key(self: @ContractState, public_key: felt252) -> ContractAddress {
        self.operator_by_key.read(public_key)
    }

    #[external(v0)]
    fn get_active_operators_count(self: @ContractState) -> u32 {
        self.active_operators_count.read()
    }

    #[external(v0)]
    fn get_active_operator(self: @ContractState, index: u32) -> ContractAddress {
        assert(index < self.active_operators_count.read(), 'Invalid index');
        self.active_operators.read(index)
    }

    #[external(v0)]
    fn get_withdrawal_signatures_count(self: @ContractState, withdrawal_id: u256) -> u32 {
        self.withdrawal_signature_count.read(withdrawal_id)
    }

    #[external(v0)]
    fn has_signed_withdrawal(
        self: @ContractState,
        withdrawal_id: u256,
        operator: ContractAddress
    ) -> bool {
        let signature = self.withdrawal_signatures.read((withdrawal_id, operator));
        signature.signed_at != 0
    }

    #[external(v0)]
    fn is_quorum_reached(self: @ContractState, withdrawal_id: u256) -> bool {
        let signatures_count = self.withdrawal_signature_count.read(withdrawal_id);
        let required = self.calculate_required_signatures();
        signatures_count >= required
    }

    // Admin functions
    #[external(v0)]
    fn set_min_bond_amount(ref self: ContractState, amount: u256) {
        self.assert_admin();
        self.min_bond_amount.write(amount);
    }

    #[external(v0)]
    fn set_required_quorum(ref self: ContractState, quorum_bps: u16) {
        self.assert_admin();
        assert(quorum_bps <= 10000, Errors::INVALID_QUORUM); // Max 100%
        self.required_quorum_bps.write(quorum_bps);
    }

    #[external(v0)]
    fn set_max_slashing(ref self: ContractState, slashing_bps: u16) {
        self.assert_admin();
        assert(slashing_bps <= 10000, 'Invalid slashing percentage');
        self.max_slashing_bps.write(slashing_bps);
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

        fn calculate_required_signatures(self: @ContractState) -> u32 {
            let active_count = self.active_operators_count.read();
            let quorum_bps: u32 = self.required_quorum_bps.read().into();

            // ceil(active_count * quorum / 10000)
            ((active_count * quorum_bps) + 9999) / 10000
        }


        fn check_quorum_reached(ref self: ContractState, withdrawal_id: u256) {
            let signatures_count = self.withdrawal_signature_count.read(withdrawal_id);
            let required = self.calculate_required_signatures();

            if signatures_count >= required {
                self.emit(Event::QuorumReached(QuorumReached {
                    withdrawal_id,
                    signatures_count,
                    required_signatures: required,
                }));
            }
        }
    }
}
