use starknet::ContractAddress;
use core::integer::u256;

#[starknet::interface]
trait IMintable<TContractState> {
    fn mint(ref self: TContractState, to: ContractAddress, amount: u256);
    fn burn_from(ref self: TContractState, owner: ContractAddress, amount: u256);
}