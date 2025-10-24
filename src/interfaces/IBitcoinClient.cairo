use starknet::ContractAddress;

// Bitcoin network types
#[derive(Drop, Serde, starknet::Store, PartialEq, Copy)]
pub enum BitcoinNetwork {
    #[default]
    Mainnet,
    Testnet,
    Regtest,
}

// Bitcoin transaction output
#[derive(Drop, Serde)]
pub struct BitcoinTxOut {
    value: u64, // satoshis
    script_pubkey: Array<u8>,
}

// Bitcoin transaction input
#[derive(Drop, Serde)]
pub struct BitcoinTxIn {
    txid: felt252,
    vout: u32,
    script_sig: Array<u8>,
    sequence: u32,
}

// Bitcoin transaction (simplified for Starknet)
#[derive(Drop, Serde)]
pub struct BitcoinTransaction {
    version: u32,
    inputs: Array<BitcoinTxIn>,
    outputs: Array<BitcoinTxOut>,
    locktime: u32,
    txid: felt252,
}

// Block header information
#[derive(Drop, Serde, Copy)]
pub struct BitcoinHeader {
    version: u32,
    previous_block_hash: felt252,
    merkle_root: felt252,
    timestamp: u32,
    bits: u32,
    nonce: u32,
    hash: felt252,
}

#[starknet::interface]
trait IBitcoinClient<TContractState> {
    // Connection management
    fn connect_bitcoin_node(ref self: TContractState);
    fn is_connected(self: @TContractState) -> bool;

    // Block and network information
    fn get_block_height(self: @TContractState) -> u32;
    fn get_best_block_hash(self: @TContractState) -> felt252;
    fn update_block_height(ref self: TContractState);

    // Transaction operations
    fn get_transaction(self: @TContractState, txid: felt252) -> BitcoinTransaction;
    fn broadcast_transaction(ref self: TContractState, raw_tx: Array<u8>) -> felt252;
    fn is_transaction_confirmed(self: @TContractState, txid: felt252) -> bool;

    // Address operations
    fn get_address_balance(self: @TContractState, address: felt252) -> u64;
    fn get_utxos_for_address(self: @TContractState, address: felt252) -> Array<BitcoinTxOut>;

    // Block header operations
    fn get_block_header(self: @TContractState, block_height: u32) -> BitcoinHeader;

    // Configuration
    fn get_network(self: @TContractState) -> BitcoinNetwork;
    fn set_rpc_config(
        ref self: TContractState,
        host: felt252,
        port: u16,
        username: felt252,
        password: felt252
    );

    // Admin functions
    fn set_admin(ref self: TContractState, new_admin: ContractAddress);
    fn get_admin(self: @TContractState) -> ContractAddress;
}