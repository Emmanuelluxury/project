use starknet::ContractAddress;

#[starknet::interface]
trait IOperatorRegistry<TContractState> {
    /// Register as a bridge operator
    /// @param public_key: Public key for MuSig2 signing
    /// @param bond_amount: Amount to bond (in sBTC)
    fn register_operator(
        ref self: TContractState,
        public_key: felt252,
        bond_amount: u256
    );

    /// Submit signatures for a withdrawal
    /// @param withdrawal_id: ID of the withdrawal to sign
    /// @param signature: MuSig2 signature
    fn submit_signature(
        ref self: TContractState,
        withdrawal_id: u256,
        signature: felt252
    );

    /// Slash an operator's bond for misbehavior
    /// @param operator: Address of the operator to slash
    /// @param reason: Reason for slashing
    fn slash_operator(
        ref self: TContractState,
        operator: ContractAddress,
        reason: felt252
    );

    /// Get operator information
    /// @param operator: Address of the operator
    /// @returns: Public key, bond amount, and registration status
    fn get_operator_info(self: @TContractState, operator: ContractAddress) -> (felt252, u256, bool);

    /// Get total number of registered operators
    /// @returns: Total operator count
    fn get_operator_count(self: @TContractState) -> u32;

    /// Get required signatures for quorum
    /// @returns: Number of signatures required
    fn calculate_required_signatures(self: @TContractState) -> u32;

    /// Get signature count for a withdrawal
    /// @param withdrawal_id: ID of the withdrawal
    /// @returns: Current signature count
    fn get_withdrawal_signatures_count(self: @TContractState, withdrawal_id: u256) -> u32;

    /// Check if operator is registered and active
    /// @param operator: Address of the operator
    /// @returns: Whether operator is active
    fn is_operator_active(self: @TContractState, operator: ContractAddress) -> bool;
}