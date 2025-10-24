use starknet::ContractAddress;

#[starknet::interface]
trait IBTCPegOut<TContractState> {
    /// Request a Bitcoin withdrawal
    /// @param amount: Amount of sBTC to withdraw (will be burned)
    /// @param btc_address: Bitcoin address that will receive the funds
    /// @returns: Unique withdrawal ID
    fn request_withdrawal(
        ref self: TContractState,
        amount: u256,
        btc_address: felt252
    ) -> u256;

    /// Submit operator signatures for withdrawal
    /// @param withdrawal_id: ID of the withdrawal request
    /// @param signatures: Array of operator signatures
    fn submit_withdrawal_signatures(
        ref self: TContractState,
        withdrawal_id: u256,
        signatures: Array<felt252>
    );

    /// Get withdrawal status
    /// @param withdrawal_id: ID of the withdrawal
    /// @returns: Current status of the withdrawal
    fn get_withdrawal_status(self: @TContractState, withdrawal_id: u256) -> felt252;

    /// Get withdrawal details
    /// @param withdrawal_id: ID of the withdrawal
    /// @returns: Withdrawal amount, Bitcoin address, and requester
    fn get_withdrawal_details(self: @TContractState, withdrawal_id: u256) -> (u256, felt252, ContractAddress);

    /// Get required number of signatures for withdrawal
    /// @returns: Number of signatures required for quorum
    fn get_required_signatures(self: @TContractState) -> u32;

    /// Get current signature count for withdrawal
    /// @param withdrawal_id: ID of the withdrawal
    /// @returns: Current number of signatures collected
    fn get_signature_count(self: @TContractState, withdrawal_id: u256) -> u32;
}