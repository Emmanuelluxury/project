#[starknet::contract]
pub mod BitcoinUtils {
    use starknet::{ContractAddress, get_caller_address};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};

    // Bitcoin script types
    #[derive(Drop, Serde, starknet::Store, PartialEq, Copy)]
    enum BitcoinAddressType {
        #[default]
        P2PKH,  // Pay to Public Key Hash
        P2SH,   // Pay to Script Hash
        P2WPKH, // Pay to Witness Public Key Hash (SegWit)
        P2WSH,  // Pay to Witness Script Hash (SegWit)
        P2TR,   // Pay to Taproot
    }

    // Bitcoin network parameters
    #[derive(Drop, Serde, starknet::Store, PartialEq, Copy)]
    enum BitcoinNetwork {
        #[default]
        Mainnet,
        Testnet,
        Regtest,
    }

    // Bitcoin address information
    #[derive(Drop, Serde, Copy)]
    struct BitcoinAddress {
        address_type: BitcoinAddressType,
        network: BitcoinNetwork,
        hash160: felt252, // 20-byte hash
        witness_version: u8, // For SegWit addresses
        witness_program: felt252, // For SegWit addresses
    }

    // Bitcoin transaction output
    #[derive(Drop, Serde)]
    struct BitcoinTxOut {
        value: u64, // satoshis
        script_pubkey: Array<u8>,
    }

    // Bitcoin transaction input
    #[derive(Drop, Serde)]
    struct BitcoinTxIn {
        txid: felt252,
        vout: u32,
        script_sig: Array<u8>,
        sequence: u32,
        witness: Array<Array<u8>>, // SegWit witness data
    }

    // Simplified Bitcoin transaction for Starknet
    #[derive(Drop, Serde)]
    struct BitcoinTransaction {
        version: u32,
        inputs: Array<BitcoinTxIn>,
        outputs: Array<BitcoinTxOut>,
        locktime: u32,
        txid: felt252,
        witness_txid: felt252, // For SegWit transactions
    }

    #[storage]
    struct Storage {
        admin: ContractAddress,
        network_params: NetworkParameters,
    }

    #[derive(Drop, Serde, starknet::Store)]
    struct NetworkParameters {
        mainnet: BitcoinNetworkConfig,
        testnet: BitcoinNetworkConfig,
        regtest: BitcoinNetworkConfig,
    }

    #[derive(Drop, Serde, starknet::Store)]
    struct BitcoinNetworkConfig {
        magic: u32,
        genesis_hash: felt252,
        max_money: u64,
        address_prefixes: AddressPrefixes,
    }

    #[derive(Drop, Serde, starknet::Store)]
    struct AddressPrefixes {
        p2pkh: u8,
        p2sh: u8,
        bech32_hrp: felt252,
    }

    #[derive(Drop, starknet::Event)]
    struct AddressValidated {
        #[key]
        address: felt252,
        address_type: BitcoinAddressType,
        network: BitcoinNetwork,
        is_valid: bool,
    }

    #[derive(Drop, starknet::Event)]
    struct TransactionParsed {
        #[key]
        txid: felt252,
        input_count: u32,
        output_count: u32,
        total_input_value: u64,
        total_output_value: u64,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        AddressValidated: AddressValidated,
        TransactionParsed: TransactionParsed,
    }

    mod Errors {
        pub const NOT_ADMIN: felt252 = 'BTCUtils: Not admin';
        pub const INVALID_ADDRESS: felt252 = 'BTCUtils: Invalid address';
        pub const INVALID_NETWORK: felt252 = 'BTCUtils: Invalid network';
        pub const INVALID_TX: felt252 = 'BTCUtils: Invalid transaction';
        pub const UNSUPPORTED_ADDRESS: felt252 = 'BTCUtils: Unsupported address';
    }

    #[constructor]
    fn constructor(ref self: ContractState, admin: ContractAddress) {
        self.admin.write(admin);
        self.initialize_network_parameters();
    }

    /// Validate Bitcoin address format and extract information
    #[external(v0)]
    fn validate_bitcoin_address(self: @ContractState, address: felt252) -> (bool, BitcoinAddress) {
        let network = InternalImpl::detect_network(self, address);

        if network == BitcoinNetwork::Mainnet {
            let (is_valid, addr_info) = InternalImpl::validate_mainnet_address(self, address);
            // Event emission would be handled by the calling contract
            (is_valid, addr_info)
        } else if network == BitcoinNetwork::Testnet {
            let (is_valid, addr_info) = InternalImpl::validate_testnet_address(self, address);
            // Event emission would be handled by the calling contract
            (is_valid, addr_info)
        } else {
            (false, BitcoinAddress {
                address_type: BitcoinAddressType::P2PKH,
                network: BitcoinNetwork::Mainnet,
                hash160: 0,
                witness_version: 0,
                witness_program: 0,
            })
        }
    }

    /// Parse Bitcoin transaction from raw data
    #[external(v0)]
    fn parse_transaction(ref self: ContractState, raw_tx: Array<u8>) -> BitcoinTransaction {
        // This would implement proper Bitcoin transaction parsing
        // For now, return a placeholder structure

        let txid = 0; // Placeholder for transaction ID computation

        BitcoinTransaction {
            version: 1,
            inputs: ArrayTrait::new(),
            outputs: ArrayTrait::new(),
            locktime: 0,
            txid,
            witness_txid: txid, // For non-SegWit transactions
        }
    }

    /// Compute Bitcoin transaction ID (double SHA256)
    #[external(v0)]
    fn compute_txid(ref self: ContractState, tx_data: Array<u8>) -> felt252 {
        // Simplified transaction ID computation
        // In production, this would use proper Bitcoin transaction serialization and double SHA256
        let mut hash: felt252 = 0;

        let mut i = 0;
        let len = tx_data.len();
        while i != len {
            hash = hash * 31 + (*tx_data.at(i)).into();
            i += 1;
        }

        // Apply Bitcoin-style double hash pattern
        hash = hash * 1103515245 + 12345;
        hash = hash * 1103515245 + 12345;

        hash
    }

    /// Convert satoshis to BTC
    #[external(v0)]
    fn satoshis_to_btc(self: @ContractState, satoshis: u64) -> u256 {
        // 1 BTC = 100,000,000 satoshis
        let btc_value = satoshis * 100000000;
        u256 { low: btc_value.into(), high: 0 }
    }

    /// Convert BTC to satoshis
    #[external(v0)]
    fn btc_to_satoshis(self: @ContractState, btc_amount: u256) -> u64 {
        // 1 BTC = 100,000,000 satoshis
        (btc_amount.low / 100000000).try_into().unwrap()
    }

    /// Get Bitcoin network parameters
    #[external(v0)]
    fn get_network_params(self: @ContractState, network: BitcoinNetwork) -> BitcoinNetworkConfig {
        let params = self.network_params.read();

        match network {
            BitcoinNetwork::Mainnet => params.mainnet,
            BitcoinNetwork::Testnet => params.testnet,
            BitcoinNetwork::Regtest => params.regtest,
        }
    }

    /// Check if amount is within valid Bitcoin range
    #[external(v0)]
    fn validate_bitcoin_amount(self: @ContractState, satoshis: u64) -> bool {
        satoshis > 0 && satoshis <= 21_000_000_00000000 // Max Bitcoin supply in satoshis
    }

    /// Generate Bitcoin deposit address (for bridge operations)
    #[external(v0)]
    fn generate_deposit_address(
        ref self: ContractState,
        starknet_recipient: ContractAddress,
        network: BitcoinNetwork
    ) -> felt252 {
        // In production, this would generate a unique Bitcoin address
        // For now, return a deterministic address based on inputs
        let mut hash_input: felt252 = starknet_recipient.into();
        hash_input = hash_input * 1103515245 + 12345;

        // This is a placeholder - in production you'd generate proper addresses
        hash_input
    }

    // Admin functions
    #[external(v0)]
    fn set_admin(ref self: ContractState, new_admin: ContractAddress) {
        self.assert_admin();
        self.admin.write(new_admin);
    }

    #[external(v0)]
    fn get_admin(self: @ContractState) -> ContractAddress {
        self.admin.read()
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn assert_admin(ref self: ContractState) {
            let caller = get_caller_address();
            let admin = self.admin.read();
            assert(caller == admin, Errors::NOT_ADMIN);
        }

        fn initialize_network_parameters(ref self: ContractState) {
            let mainnet_config = BitcoinNetworkConfig {
                magic: 0xD9B4BEF9,
                genesis_hash: 0x000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f,
                max_money: 2100000000000000, // 21 million BTC in satoshis
                address_prefixes: AddressPrefixes {
                    p2pkh: 0x00,
                    p2sh: 0x05,
                    bech32_hrp: 'bc',
                },
            };

            let testnet_config = BitcoinNetworkConfig {
                magic: 0x0709110B,
                genesis_hash: 0x000000000933ea01ad0ee984209779baaec3ced90fa3f408719526f8d77f4943,
                max_money: 2100000000000000,
                address_prefixes: AddressPrefixes {
                    p2pkh: 0x6F,
                    p2sh: 0xC4,
                    bech32_hrp: 'tb',
                },
            };

            let regtest_config = BitcoinNetworkConfig {
                magic: 0xFABFB5DA,
                genesis_hash: 0x06226e46111a0b59caaf126043eb5bbf,
                max_money: 2100000000000000,
                address_prefixes: AddressPrefixes {
                    p2pkh: 0x6F,
                    p2sh: 0xC4,
                    bech32_hrp: 'bcrt',
                },
            };

            let params = NetworkParameters {
                mainnet: mainnet_config,
                testnet: testnet_config,
                regtest: regtest_config,
            };

            self.network_params.write(params);
        }

        fn detect_network(self: @ContractState, address: felt252) -> BitcoinNetwork {
            // Simple network detection based on address format
            // In production, this would decode the Base58Check or Bech32 address

            if address == 0 {
                return BitcoinNetwork::Mainnet;
            }

            // This is a simplified detection - in production you'd properly decode
            BitcoinNetwork::Mainnet
        }

        fn validate_mainnet_address(self: @ContractState, address: felt252) -> (bool, BitcoinAddress) {
            // Implement proper Bitcoin address validation
            // This would include Base58Check decoding, checksum verification, etc.

            (true, BitcoinAddress {
                address_type: BitcoinAddressType::P2PKH,
                network: BitcoinNetwork::Mainnet,
                hash160: address, // Placeholder
                witness_version: 0,
                witness_program: 0,
            })
        }

        fn validate_testnet_address(self: @ContractState, address: felt252) -> (bool, BitcoinAddress) {
            // Implement proper Bitcoin testnet address validation

            (true, BitcoinAddress {
                address_type: BitcoinAddressType::P2PKH,
                network: BitcoinNetwork::Testnet,
                hash160: address, // Placeholder
                witness_version: 0,
                witness_program: 0,
            })
        }
    }
}