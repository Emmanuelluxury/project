use starknet::ContractAddress;

#[starknet::interface]
trait IBTCDepositManager<TContractState> {
    /// Request a new Bitcoin deposit
    /// @param amount: Amount of Bitcoin to deposit (in satoshis)
    /// @param btc_address: Bitcoin address that will send the funds
    /// @param starknet_recipient: Starknet address that will receive sBTC
    /// @returns: Unique deposit ID
    fn request_deposit(
        ref self: TContractState,
        amount: u256,
        btc_address: felt252,
        starknet_recipient: ContractAddress
    ) -> u256;

    /// Submit proof of Bitcoin transaction for deposit
    /// @param deposit_id: ID of the deposit request
    /// @param txid: Bitcoin transaction ID
    /// @param merkle_branch: Merkle proof branch
    /// @param header_height: Height of the block containing the transaction
    fn submit_deposit_proof(
        ref self: TContractState,
        deposit_id: u256,
        txid: felt252,
        merkle_branch: Array<felt252>,
        header_height: u32
    );

    /// Get deposit status
    /// @param deposit_id: ID of the deposit
    /// @returns: Current status of the deposit
    fn get_deposit_status(self: @TContractState, deposit_id: u256) -> felt252;

    /// Get deposit details
    /// @param deposit_id: ID of the deposit
    /// @returns: Deposit amount, Bitcoin address, and Starknet recipient
    fn get_deposit_details(self: @TContractState, deposit_id: u256) -> (u256, felt252, ContractAddress);
}