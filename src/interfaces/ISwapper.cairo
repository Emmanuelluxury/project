use starknet::ContractAddress;
use core::integer::u256;

#[starknet::interface]
trait ISwapper<TContractState> {
    fn swap(
        ref self: TContractState,
        token_in: ContractAddress,
        token_out: ContractAddress,
        amount_in: u256,
        min_amount_out: u256,
        recipient: ContractAddress
    ) -> u256;
}