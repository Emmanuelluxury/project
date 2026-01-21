#[starknet::contract]
pub mod BTCDepositManagerV2 {
    use starknet::{ContractAddress, get_caller_address};
    use starknet::storage::{
        Map, StoragePointerReadAccess, StoragePointerWriteAccess,
        StorageMapReadAccess, StorageMapWriteAccess
    };
    use core::integer::u256;

    // Bitcoin Header structure
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

    // Deposit request structure
    #[derive(Drop, Serde, starknet::Store, Copy)]
    struct DepositRequest {
        depositor: ContractAddress,
        amount: u256,
        btc_address: felt252, // Bitcoin address where funds were sent
        starknet_recipient: ContractAddress,
        block_height: u32,
        tx_hash: felt252,
        status: DepositStatus,
        timestamp: u64,
    }

    #[derive(Drop, Serde, starknet::Store, PartialEq, Copy)]
    enum DepositStatus {
        #[default]
        Pending,
        Confirmed,
        Minted,
        Failed,
    }

    // Merkle proof for SPV verification
    #[derive(Drop, Serde)]
    struct MerkleProof {
        merkle_root: felt252,
        tx_hash: felt252,
        merkle_branch: Array<felt252>,
        position: u32,
    }

    #[storage]
    struct Storage {
        deposits: Map<u256, DepositRequest>,
        bitcoin_headers_contract: ContractAddress,
        spv_verifier_contract: ContractAddress,
        sbtc_contract: ContractAddress,
        deposit_counter: u256,
        min_deposit_amount: u256,
        max_deposit_amount: u256,
        deposit_fee_bps: u16,
        min_confirmations: u32, // ✅ NEW
        admin: ContractAddress,
    }


    #[derive(Drop, starknet::Event)]
    struct DepositRequested {
        #[key]
        deposit_id: u256,
        #[key]
        depositor: ContractAddress,
        amount: u256,
        btc_address: felt252,
        starknet_recipient: ContractAddress,
        tx_hash: felt252,
    }

    #[derive(Drop, starknet::Event)]
    struct DepositConfirmed {
        #[key]
        tx_hash: felt252,
        block_height: u32,
        merkle_root: felt252,
    }

    #[derive(Drop, starknet::Event)]
    struct DepositMinted {
        #[key]
        tx_hash: felt252,
        #[key]
        recipient: ContractAddress,
        amount_minted: u256,
        fee_deducted: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct DepositFailed {
        #[key]
        tx_hash: felt252,
        reason: felt252,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        DepositRequested: DepositRequested,
        DepositConfirmed: DepositConfirmed,
        DepositMinted: DepositMinted,
        DepositFailed: DepositFailed,
    }

    mod Errors {
        pub const NOT_ADMIN: felt252 = 'Deposit: Not admin';
        pub const INVALID_AMOUNT: felt252 = 'Deposit: Invalid amount';
        pub const DEPOSIT_EXISTS: felt252 = 'Deposit: Deposit exists';
        pub const DEPOSIT_NOT_FOUND: felt252 = 'Deposit: Not found';
        pub const INVALID_PROOF: felt252 = 'Deposit: Invalid proof';
        pub const ALREADY_PROCESSED: felt252 = 'Deposit: Already processed';
        pub const INSUFFICIENT_AMOUNT: felt252 = 'Deposit: Insufficient amount';
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        admin: ContractAddress,
        bitcoin_headers_contract: ContractAddress,
        spv_verifier_contract: ContractAddress,
        sbtc_contract: ContractAddress,
        min_deposit_amount: u256,
        max_deposit_amount: u256,
        deposit_fee_bps: u16,
        min_confirmations: u32 // ✅ NEW
    ) {
        self.admin.write(admin);
        self.bitcoin_headers_contract.write(bitcoin_headers_contract);
        self.spv_verifier_contract.write(spv_verifier_contract);
        self.sbtc_contract.write(sbtc_contract);
        self.min_deposit_amount.write(min_deposit_amount);
        self.max_deposit_amount.write(max_deposit_amount);
        self.deposit_fee_bps.write(deposit_fee_bps);
        self.min_confirmations.write(min_confirmations);
    }

    #[external(v0)]
    fn request_deposit(
        ref self: ContractState,
        amount: u256,
        btc_address: felt252,
        starknet_recipient: ContractAddress
    ) -> u256 {
        let depositor = get_caller_address();
        let deposit_id = self.deposit_counter.read() + 1;
        self.deposit_counter.write(deposit_id);

        // Validate amount
        assert(amount >= self.min_deposit_amount.read(), Errors::INSUFFICIENT_AMOUNT);
        assert(amount <= self.max_deposit_amount.read(), Errors::INVALID_AMOUNT);

        // Create deposit request (without tx_hash initially)
        let deposit_request = DepositRequest {
            depositor,
            amount,
            btc_address,
            starknet_recipient,
            block_height: 0,
            tx_hash: 0,
            status: DepositStatus::Pending,
            timestamp: starknet::get_block_timestamp(),
        };

        // Store deposit request with deposit_id as key
        self.deposits.write(deposit_id, deposit_request);

        self.emit(Event::DepositRequested(DepositRequested {
            deposit_id,
            depositor,
            amount,
            btc_address,
            starknet_recipient,
            tx_hash: 0,
        }));

        deposit_id
    }

    #[external(v0)]
    fn confirm_deposit(
    ref self: ContractState,
    deposit_id: u256,
    tx_hash: felt252,
    block_height: u32,
    merkle_proof: MerkleProof
) {
    let mut deposit = self.deposits.read(deposit_id);

    assert(deposit.status == DepositStatus::Pending, Errors::ALREADY_PROCESSED);
    assert(deposit.tx_hash == 0, Errors::DEPOSIT_EXISTS);

    // Store merkle_root before moving merkle_proof
    let merkle_root = merkle_proof.merkle_root;

    // Verify SPV proof
    let mut spv = ISPVerifierDispatcher {
        contract_address: self.spv_verifier_contract.read()
    };

    let valid = spv.verify_transaction_inclusion(merkle_proof, block_height);
    assert(valid, Errors::INVALID_PROOF);

    // ✅ Enforce BTC finality
    let current_btc_height = IBitcoinHeadersDispatcher {
        contract_address: self.bitcoin_headers_contract.read()
    }.get_best_height();

    assert(
        current_btc_height >= block_height + self.min_confirmations.read(),
        Errors::INVALID_PROOF
    );

    deposit.tx_hash = tx_hash;
    deposit.block_height = block_height;
    deposit.status = DepositStatus::Confirmed;

    self.deposits.write(deposit_id, deposit);

    self.emit(Event::DepositConfirmed(DepositConfirmed {
        tx_hash,
        block_height,
        merkle_root,
    }));
   }

   #[external(v0)]
    fn mint_deposit(ref self: ContractState, deposit_id: u256) {
        let mut deposit = self.deposits.read(deposit_id);

        assert(deposit.status == DepositStatus::Confirmed, Errors::ALREADY_PROCESSED);

        let fee = (deposit.amount * self.deposit_fee_bps.read().into()) / 10000;
        let mint_amount = deposit.amount - fee;

        ISBTCDispatcher {
            contract_address: self.sbtc_contract.read()
        }.mint(deposit.starknet_recipient, mint_amount);

        // 🔐 LOCK FOREVER
        deposit.status = DepositStatus::Minted;
        self.deposits.write(deposit_id, deposit);

        self.emit(Event::DepositMinted(DepositMinted {
            tx_hash: deposit.tx_hash,
            recipient: deposit.starknet_recipient,
            amount_minted: mint_amount,
            fee_deducted: fee,
        }));
    }

    #[external(v0)]
    fn fail_deposit(ref self: ContractState, deposit_id: u256, reason: felt252) {
        self.assert_admin();
        let mut deposit = self.deposits.read(deposit_id);
        assert(deposit.status == DepositStatus::Pending, Errors::ALREADY_PROCESSED);

        deposit.status = DepositStatus::Failed;
        self.deposits.write(deposit_id, deposit);

        self.emit(Event::DepositFailed(DepositFailed {
            tx_hash: deposit.tx_hash,
            reason,
        }));
    }

    #[external(v0)]
    fn get_deposit(self: @ContractState, deposit_id: u256) -> DepositRequest {
        self.deposits.read(deposit_id)
    }

    #[external(v0)]
    fn get_deposit_status(self: @ContractState, deposit_id: u256) -> DepositStatus {
        let deposit = self.deposits.read(deposit_id);
        deposit.status
    }

    // Admin functions
    #[external(v0)]
    fn set_min_deposit_amount(ref self: ContractState, amount: u256) {
        self.assert_admin();
        self.min_deposit_amount.write(amount);
    }

    #[external(v0)]
    fn set_max_deposit_amount(ref self: ContractState, amount: u256) {
        self.assert_admin();
        self.max_deposit_amount.write(amount);
    }

    #[external(v0)]
    fn set_deposit_fee(ref self: ContractState, fee_bps: u16) {
        self.assert_admin();
        self.deposit_fee_bps.write(fee_bps);
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
    }

    // Interface for Bitcoin Headers contract
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

    // Interface for SPVVerifier contract
    #[starknet::interface]
    trait ISPVerifier<TContractState> {
        fn verify_transaction_inclusion(
            ref self: TContractState,
            merkle_proof: MerkleProof,
            block_height: u32
        ) -> bool;
    }

    // Interface for SBTC contract
    #[starknet::interface]
    trait ISBTC<TContractState> {
        fn mint(ref self: TContractState, to: ContractAddress, amount: u256);
        fn burn_from(ref self: TContractState, from: ContractAddress, amount: u256);
    }
}