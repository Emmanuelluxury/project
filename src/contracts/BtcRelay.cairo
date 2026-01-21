#[starknet::contract]
pub mod BtcRelay {
    use starknet::{ContractAddress, get_caller_address};
    use starknet::storage::{
        Map, StoragePointerReadAccess, StoragePointerWriteAccess,
        StorageMapReadAccess, StorageMapWriteAccess
    };
    use core::integer::u256;

    // ─────────────────────────────────────────────────────────────
    // CONSTANTS
    // ─────────────────────────────────────────────────────────────

    const MAX_FORK_DEPTH: u32 = 100;
    const BITCOIN_DIFFICULTY_1: u256 = 0x00000000FFFF0000000000000000000000000000000000000000000000000000;

    // ─────────────────────────────────────────────────────────────
    // STRUCTS
    // ─────────────────────────────────────────────────────────────

    #[derive(Drop, Serde, starknet::Store, Copy)]
    struct BlockHeader {
        version: u32,
        prev_block_hash: felt252,
        merkle_root: felt252,
        timestamp: u32,
        bits: u32,
        nonce: u32,

        height: u32,
        cumulative_work: u256,
    }

    // ─────────────────────────────────────────────────────────────
    // STORAGE
    // ─────────────────────────────────────────────────────────────

    #[storage]
    struct Storage {
        headers: Map<felt252, BlockHeader>, // block_hash -> header
        best_block_hash: felt252,
        best_height: u32,

        confirmations_required: u32,
        admin: ContractAddress,
    }

    // ─────────────────────────────────────────────────────────────
    // EVENTS
    // ─────────────────────────────────────────────────────────────

    #[derive(Drop, starknet::Event)]
    struct HeaderSubmitted {
        #[key]
        block_hash: felt252,
        height: u32,
        cumulative_work: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct BestChainUpdated {
        #[key]
        block_hash: felt252,
        height: u32,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        HeaderSubmitted: HeaderSubmitted,
        BestChainUpdated: BestChainUpdated,
    }

    // ─────────────────────────────────────────────────────────────
    // ERRORS
    // ─────────────────────────────────────────────────────────────

    mod Errors {
        pub const NOT_ADMIN: felt252 = 'BtcRelay: not admin';
        pub const UNKNOWN_PARENT: felt252 = 'BtcRelay: unknown parent';
        pub const HEADER_EXISTS: felt252 = 'BtcRelay: header exists';
        pub const INVALID_WORK: felt252 = 'BtcRelay: invalid work';
        pub const NOT_CONFIRMED: felt252 = 1002; // BtcRelay: not enough confirmations
    }

    // ─────────────────────────────────────────────────────────────
    // CONSTRUCTOR
    // ─────────────────────────────────────────────────────────────

    #[constructor]
    fn constructor(
        ref self: ContractState,
        admin: ContractAddress,
        confirmations_required: u32,
        genesis_hash: felt252
    ) {
        self.admin.write(admin);
        self.confirmations_required.write(confirmations_required);
        self.best_block_hash.write(genesis_hash);
        self.best_height.write(0);
    }

    // ─────────────────────────────────────────────────────────────
    // HEADER SUBMISSION
    // ─────────────────────────────────────────────────────────────

    #[external(v0)]
    fn submit_header(
        ref self: ContractState,
        block_hash: felt252,
        parent_hash: felt252,
        header: BlockHeader
    ) {
        // Prevent overwrite
        assert(self.headers.read(block_hash).height == 0, Errors::HEADER_EXISTS);

        let parent = self.headers.read(parent_hash);
        assert(parent.height > 0 || parent_hash == self.best_block_hash.read(), Errors::UNKNOWN_PARENT);

        let work = calculate_work(header.bits);
        assert(work > 0, Errors::INVALID_WORK);

        let cumulative_work = parent.cumulative_work + work;

        let stored = BlockHeader {
            version: header.version,
            prev_block_hash: parent_hash,
            merkle_root: header.merkle_root,
            timestamp: header.timestamp,
            bits: header.bits,
            nonce: header.nonce,
            height: parent.height + 1,
            cumulative_work,
        };

        self.headers.write(block_hash, stored);

        self.emit(Event::HeaderSubmitted(HeaderSubmitted {
            block_hash,
            height: stored.height,
            cumulative_work,
        }));

        self.try_update_best_chain(block_hash);
    }

    // ─────────────────────────────────────────────────────────────
    // CONFIRMATION CHECK
    // ─────────────────────────────────────────────────────────────

    #[external(v0)]
    fn is_confirmed(self: @ContractState, block_hash: felt252) -> bool {
        let header = self.headers.read(block_hash);
        let best_height = self.best_height.read();

        best_height >= header.height + self.confirmations_required.read()
    }

    // ─────────────────────────────────────────────────────────────
    // INTERNAL LOGIC
    // ─────────────────────────────────────────────────────────────

    fn calculate_work(bits: u32) -> u256 {
        // Simplified Bitcoin work calculation:
        // work = difficulty_1 / target
        let target: u256 = bits.into();
        BITCOIN_DIFFICULTY_1 / target
    }

    // ─────────────────────────────────────────────────────────────
    // ADMIN
    // ─────────────────────────────────────────────────────────────

    #[external(v0)]
    fn set_confirmations_required(ref self: ContractState, confirmations: u32) {
        self.assert_admin();
        self.confirmations_required.write(confirmations);
    }

    #[external(v0)]
    fn get_best_block(self: @ContractState) -> felt252 {
        self.best_block_hash.read()
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn assert_admin(ref self: ContractState) {
            assert(get_caller_address() == self.admin.read(), Errors::NOT_ADMIN);
        }

        fn try_update_best_chain(ref self: ContractState, new_block: felt252) {
            let header = self.headers.read(new_block);
            let best = self.headers.read(self.best_block_hash.read());

            if header.cumulative_work > best.cumulative_work {
                self.best_block_hash.write(new_block);
                self.best_height.write(header.height);

                self.emit(Event::BestChainUpdated(BestChainUpdated {
                    block_hash: new_block,
                    height: header.height,
                }));
            }
        }
    }
}
