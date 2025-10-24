
#[starknet::interface]
trait IEscapeHatch<TContractState> {
    /// Trigger emergency escape for a withdrawal
    /// @param withdrawal_id: ID of the withdrawal to escape
    /// @param reason: Reason for triggering escape hatch
    fn trigger_escape(
        ref self: TContractState,
        withdrawal_id: u256,
        reason: felt252
    );

    /// Execute emergency unlock after timelock
    /// @param withdrawal_id: ID of the withdrawal to unlock
    fn emergency_unlock(
        ref self: TContractState,
        withdrawal_id: u256
    );

    /// Get escape hatch status for a withdrawal
    /// @param withdrawal_id: ID of the withdrawal
    /// @returns: Whether escape is active and remaining timelock
    fn get_escape_status(self: @TContractState, withdrawal_id: u256) -> (bool, u64);

    /// Get emergency unlock timelock duration
    /// @returns: Timelock duration in seconds
    fn get_emergency_timelock(self: @TContractState) -> u64;

    /// Check if emergency unlock is available for a withdrawal
    /// @param withdrawal_id: ID of the withdrawal
    /// @returns: Whether emergency unlock can be executed
    fn can_emergency_unlock(self: @TContractState, withdrawal_id: u256) -> bool;

    /// Get total number of active escape hatches
    /// @returns: Number of ongoing escape processes
    fn get_active_escape_count(self: @TContractState) -> u32;
}