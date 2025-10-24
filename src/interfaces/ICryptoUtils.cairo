use starknet::ContractAddress;

#[starknet::interface]
trait ICryptoUtils<TContractState> {
    // Hash functions
    fn sha256(ref self: TContractState, data: Array<u8>) -> felt252;
    fn double_sha256(ref self: TContractState, data: Array<u8>) -> felt252;
    fn hash256(ref self: TContractState, data: Array<u8>) -> felt252;

    // Bitcoin-specific functions
    fn compute_txid(ref self: TContractState, tx_data: Array<u8>) -> felt252;
    fn compute_block_hash(ref self: TContractState, header_data: Array<u8>) -> felt252;
    fn compute_merkle_root(ref self: TContractState, txids: Array<felt252>) -> felt252;
    fn verify_merkle_proof(
        ref self: TContractState,
        txid: felt252,
        merkle_root: felt252,
        merkle_branch: Array<felt252>,
        position: u32
    ) -> bool;

    // Bitcoin utilities
    fn validate_bitcoin_address(self: @TContractState, address: felt252, network: felt252) -> bool;
    fn satoshis_to_btc(self: @TContractState, satoshis: u64) -> felt252;
    fn btc_to_satoshis(self: @TContractState, btc_amount: felt252) -> u64;

    // Admin functions
    fn set_admin(ref self: TContractState, new_admin: ContractAddress);
    fn get_admin(self: @TContractState) -> ContractAddress;
}