use starknet::ContractAddress;

#[derive(Drop, Serde, starknet::Store)]
pub struct BitcoinHeader {
    hash: felt252,
    previous_block_hash: felt252,
    merkle_root: felt252,
    timestamp: u32,
    bits: u32,
    nonce: u32,
    height: u32,
}

#[starknet::interface]
trait IBitcoinHeaders<TContractState> {
    fn submit_header(ref self: TContractState, header: BitcoinHeader) -> felt252;
    fn get_header(self: @TContractState, height: u32) -> BitcoinHeader;
    fn get_header_hash(self: @TContractState, height: u32) -> felt252;
    fn get_best_height(self: @TContractState) -> u32;
    fn get_merkle_root(self: @TContractState, height: u32) -> felt252;
    fn set_admin(ref self: TContractState, new_admin: ContractAddress);
    fn get_admin(self: @TContractState) -> ContractAddress;
}