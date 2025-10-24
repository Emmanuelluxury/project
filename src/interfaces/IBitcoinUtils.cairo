use starknet::ContractAddress;

// Bitcoin script types
#[derive(Drop, Serde, starknet::Store, PartialEq, Copy)]
pub enum BitcoinAddressType {
    #[default]
    P2PKH,  // Pay to Public Key Hash
    P2SH,   // Pay to Script Hash
    P2WPKH, // Pay to Witness Public Key Hash (SegWit)
    P2WSH,  // Pay to Witness Script Hash (SegWit)
    P2TR,   // Pay to Taproot
}

// Bitcoin network parameters
#[derive(Drop, Serde, starknet::Store, PartialEq, Copy)]
pub enum BitcoinNetwork {
    #[default]
    Mainnet,
    Testnet,
    Regtest,
}

// Bitcoin address information
#[derive(Drop, Serde, Copy)]
pub struct BitcoinAddress {
    address_type: BitcoinAddressType,
    network: BitcoinNetwork,
    hash160: felt252, // 20-byte hash
    witness_version: u8, // For SegWit addresses
    witness_program: felt252, // For SegWit addresses
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
    witness: Array<Array<u8>>, // SegWit witness data
}

// Simplified Bitcoin transaction for Starknet
#[derive(Drop, Serde)]
pub struct BitcoinTransaction {
    version: u32,
    inputs: Array<BitcoinTxIn>,
    outputs: Array<BitcoinTxOut>,
    locktime: u32,
    txid: felt252,
    witness_txid: felt252, // For SegWit transactions
}

#[derive(Drop, Serde, starknet::Store)]
pub struct BitcoinNetworkConfig {
    magic: u32,
    genesis_hash: felt252,
    max_money: u64,
    address_prefixes: AddressPrefixes,
}

#[derive(Drop, Serde, starknet::Store)]
pub struct AddressPrefixes {
    p2pkh: u8,
    p2sh: u8,
    bech32_hrp: felt252,
}

#[starknet::interface]
trait IBitcoinUtils<TContractState> {
    // Address validation and parsing
    fn validate_bitcoin_address(self: @TContractState, address: felt252) -> (bool, BitcoinAddress);
    fn generate_deposit_address(
        ref self: TContractState,
        starknet_recipient: ContractAddress,
        network: BitcoinNetwork
    ) -> felt252;

    // Transaction operations
    fn parse_transaction(ref self: TContractState, raw_tx: Array<u8>) -> BitcoinTransaction;
    fn compute_txid(ref self: TContractState, tx_data: Array<u8>) -> felt252;

    // Amount conversion utilities
    fn satoshis_to_btc(self: @TContractState, satoshis: u64) -> u256;
    fn btc_to_satoshis(self: @TContractState, btc_amount: u256) -> u64;
    fn validate_bitcoin_amount(self: @TContractState, satoshis: u64) -> bool;

    // Network parameters
    fn get_network_params(self: @TContractState, network: BitcoinNetwork) -> BitcoinNetworkConfig;

    // Admin functions
    fn set_admin(ref self: TContractState, new_admin: ContractAddress);
    fn get_admin(self: @TContractState) -> ContractAddress;
}