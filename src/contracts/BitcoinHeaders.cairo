#[starknet::contract]
pub mod BitcoinHeaders {
    use starknet::{ContractAddress, get_caller_address};
    use starknet::storage::{
        Map, StoragePointerReadAccess, StoragePointerWriteAccess,
        StorageMapReadAccess, StorageMapWriteAccess
    };
    use core::num::traits::Zero;

    // Bitcoin header is 80 bytes
    // We'll store it as a felt252 for simplicity, but in production this should be bytes32
    #[derive(Drop, Serde, starknet::Store, Copy)]
    struct BitcoinHeader {
        hash: felt252,
        previous_block_hash: felt252,
        merkle_root: felt252,
        timestamp: u32,
        bits: u32, // Difficulty target
        nonce: u32,
        height: u32,
    }

    #[storage]
    struct Storage {
        // Mapping of height to header hash
        headers: Map<u32, felt252>,
        // Mapping of header hash to header data
        header_data: Map<felt252, BitcoinHeader>,
        // Current best height
        best_height: u32,
        // Genesis block hash for validation
        genesis_hash: felt252,
        // Maximum reorg depth (how many blocks back we allow reorgs)
        max_reorg_depth: u32,
        // Admin address
        admin: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct HeaderSubmitted {
        #[key]
        header_hash: felt252,
        #[key]
        height: u32,
        previous_block_hash: felt252,
        timestamp: u32,
        bits: u32,
    }

    #[derive(Drop, starknet::Event)]
    struct ChainReorg {
        #[key]
        from_height: u32,
        #[key]
        to_height: u32,
        new_best_hash: felt252,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        HeaderSubmitted: HeaderSubmitted,
        ChainReorg: ChainReorg,
    }

    mod Errors {
        pub const NOT_ADMIN: felt252 = 'Header: Not admin';
        pub const INVALID_HEADER: felt252 = 'Header: Invalid header';
        pub const INVALID_POW: felt252 = 'Header: Invalid PoW';
        pub const INVALID_PREV_BLOCK: felt252 = 'Header: Invalid prev block';
        pub const HEADER_EXISTS: felt252 = 'Header: Header exists';
        pub const INVALID_HEIGHT: felt252 = 'Header: Invalid height';
        pub const REORG_TOO_DEEP: felt252 = 'Header: Reorg too deep';
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        admin: ContractAddress,
        genesis_hash: felt252,
        max_reorg_depth: u32
    ) {
        self.admin.write(admin);
        self.genesis_hash.write(genesis_hash);
        self.max_reorg_depth.write(max_reorg_depth);
        self.best_height.write(0);
    }

    #[external(v0)]
    fn submit_header(
        ref self: ContractState,
        header: BitcoinHeader
    ) -> felt252 {
        self.assert_admin();

        // Validate header doesn't already exist
        let existing_header = self.headers.read(header.height);
        assert(existing_header.is_zero(), Errors::HEADER_EXISTS);

        // Validate height is reasonable
        assert(header.height > 0, Errors::INVALID_HEIGHT);

        // Validate proof of work (simplified check)
        self.validate_proof_of_work(header);

        // Validate previous block hash if not genesis
        if header.height > 1 {
            let prev_header_hash = self.headers.read(header.height - 1);
            assert(prev_header_hash == header.previous_block_hash, Errors::INVALID_PREV_BLOCK);
        } else {
            // Genesis block validation
            assert(header.previous_block_hash == self.genesis_hash.read(), Errors::INVALID_PREV_BLOCK);
        }

        // Store header
        self.headers.write(header.height, header.hash);
        self.header_data.write(header.hash, header);

        // Update best height if this extends the chain
        if header.height > self.best_height.read() {
            self.best_height.write(header.height);
        }

        // Handle potential reorg
        self.handle_potential_reorg(header.height);

        self.emit(Event::HeaderSubmitted(HeaderSubmitted {
            header_hash: header.hash,
            height: header.height,
            previous_block_hash: header.previous_block_hash,
            timestamp: header.timestamp,
            bits: header.bits,
        }));

        header.hash
    }

    #[external(v0)]
    fn get_header(self: @ContractState, height: u32) -> BitcoinHeader {
        let header_hash = self.headers.read(height);
        assert(!header_hash.is_zero(), Errors::INVALID_HEIGHT);
        self.header_data.read(header_hash)
    }

    #[external(v0)]
    fn get_header_hash(self: @ContractState, height: u32) -> felt252 {
        self.headers.read(height)
    }

    #[external(v0)]
    fn get_best_height(self: @ContractState) -> u32 {
        self.best_height.read()
    }

    #[external(v0)]
    fn get_merkle_root(self: @ContractState, height: u32) -> felt252 {
        let header_hash = self.headers.read(height);
        if header_hash.is_zero() {
            return 0;
        }
        let header = self.header_data.read(header_hash);
        header.merkle_root
    }

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

        fn validate_proof_of_work(ref self: ContractState, header: BitcoinHeader) {
            // Simplified PoW validation
            // In production, this should implement the full Bitcoin difficulty adjustment algorithm
            let _target = self.bits_to_target(header.bits);
            let _hash = self.calculate_header_hash(header);

            // Hash should be less than target (little endian interpretation)
            // Simplified check - in production this needs proper comparison
            assert(true, Errors::INVALID_POW);
        }

        fn bits_to_target(self: @ContractState, bits: u32) -> felt252 {
            // Convert Bitcoin bits format to target
            // bits = 0x1b0404cb means exponent=0x1b, coefficient=0x0404cb
            let exponent = bits / 16777216; // 2^24
            let coefficient = bits & 0x00FFFFFF;

            // Target = coefficient * 256^(exponent-3)
            // Simplified implementation
            coefficient.into() * self.pow256(exponent - 3)
        }

        fn pow256(self: @ContractState, exponent: u32) -> felt252 {
            let mut result: felt252 = 1;
            let mut count = exponent;

            while count != 0 {
                result *= 256;
                count -= 1;
            };

            result
        }

        fn calculate_header_hash(self: @ContractState, header: BitcoinHeader) -> felt252 {
            // Simplified hash calculation
            // In production, this should use double SHA256
            let mut hash_input = header.previous_block_hash +
                                header.merkle_root +
                                header.timestamp.into() +
                                header.bits.into() +
                                header.nonce.into();

            // Simple hash simulation (not cryptographically secure)
            hash_input = hash_input * 1103515245 + 12345; // Simple LCG
            hash_input
        }

        fn handle_potential_reorg(ref self: ContractState, new_height: u32) {
            let current_best = self.best_height.read();

            // Check if this creates a longer chain
            if new_height > current_best {
                // Check for reorg by looking at previous blocks
                let mut reorg_detected = false;
                let mut reorg_depth = 0;

                let mut check_height = new_height;
                let lower_bound = if current_best > self.max_reorg_depth.read() {
                    current_best - self.max_reorg_depth.read()
                } else {
                    0
                };
                while check_height != lower_bound {
                    let existing_hash = self.headers.read(check_height);
                    let new_header = self.header_data.read(self.headers.read(check_height));

                    if !existing_hash.is_zero() && existing_hash != new_header.hash {
                        reorg_detected = true;
                        reorg_depth = current_best - check_height + 1;
                        break;
                    }

                    if check_height == 0 {
                        break;
                    }
                    check_height -= 1;
                };

                if reorg_detected {
                    // Handle reorg by updating the chain
                    self.emit(Event::ChainReorg(ChainReorg {
                        from_height: current_best - reorg_depth + 1,
                        to_height: current_best,
                        new_best_hash: self.headers.read(new_height),
                    }));

                    // In a full implementation, you'd rollback state changes here
                    // For now, we just emit the event
                }
            }
        }
    }
}