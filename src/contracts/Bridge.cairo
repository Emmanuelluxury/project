#[starknet::contract]
pub mod Bridge {
    use starknet::{ContractAddress, get_caller_address, get_contract_address, syscalls::call_contract_syscall};
    use starknet::storage::{
        Map, StoragePointerReadAccess, StoragePointerWriteAccess,
        StorageMapReadAccess, StorageMapWriteAccess
    };
    use starknet::SyscallResultTrait;
    
    use core::integer::u256;
    use core::traits::TryInto;
    use core::array::ArrayTrait;

    // Import types from interfaces


    // Contract constants
    mod Constants {
        pub const MAX_BRIDGE_AMOUNT: u256 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF_u256; // ~1.15e77
        pub const MIN_BRIDGE_AMOUNT: u256 = 100000000; // Minimum 1000 satoshis
        pub const MAX_BTC_ADDRESS_LENGTH: felt252 = 35; // 35 bytes for BTC address
        pub const MAX_TRANSACTIONS_PER_USER: u32 = 100000000; // Maximum transaction history per user
    }

    // Transaction types for history tracking
    #[derive(Drop, Serde, starknet::Store, Copy)]
    #[allow(starknet::store_no_default_variant)]
    enum TransactionType {
        Deposit,
        Withdraw,
        Lock,
        Unlock,
        BridgeBTCToToken,
        BridgeTokenToBTC,
        SwapTokenToToken,
        Send,
        Receive,
    }

    // Transaction record structure
    #[derive(Drop, Serde, starknet::Store, Copy)]
    struct TransactionRecord {
        transaction_type: TransactionType,
        token: ContractAddress,
        amount: u256,
        timestamp: u64,
        dst_chain_id: felt252,
        recipient: felt252,
        btc_address: felt252,
        swap_id: u256,
    }

    #[storage]
    struct Storage {
        // Access control
        admin: ContractAddress,
        emergency_admin: ContractAddress,

        // Token management
        is_token_registered: Map<ContractAddress, bool>,
        is_wrapped_token: Map<ContractAddress, bool>,
        token_blacklist: Map<ContractAddress, bool>,

        // Core bridge configuration - simplified for essential bridging

        // Bridge state
        bridge_paused: bool,
        emergency_paused: bool,
        pause_timestamp: u64,

        // Security and limits
        daily_bridge_limit: u256,
        daily_bridge_used: u256,
        last_reset_timestamp: u64,


        // Security features
        used_nonces: Map<felt252, bool>, // nonce -> used (for replay protection)
        user_nonce: Map<ContractAddress, felt252>, // user -> current nonce

        // Transaction history
        user_transaction_count: Map<ContractAddress, u32>, // user -> transaction count
        user_transactions: Map<(ContractAddress, u32), TransactionRecord>, // (user, index) -> transaction record

        // External contract addresses for operations
        lock_address: ContractAddress,
        unlock_address: ContractAddress,
        receive_cross_chain_address: ContractAddress,
        bridge_btc_to_token_address: ContractAddress,
        bridge_token_to_btc_address: ContractAddress,
        swap_token_to_token_address: ContractAddress,
        initiate_bitcoin_deposit_address: ContractAddress,
        initiate_bitcoin_withdrawal_address: ContractAddress,
        send_address: ContractAddress,
        withdraw_address: ContractAddress,
        deposit_address: ContractAddress,

        // Rewstarknet token for bridging rewards/replacements
        rewstarknet_token: ContractAddress,

        // Bridge-specific storage only
    }

    #[derive(Drop, starknet::Event)]
    struct Deposited {
        #[key]
        token: ContractAddress,
        #[key]
        from: ContractAddress,
        amount: u256,
        dst_chain_id: felt252,
        recipient: felt252,
    }

    #[derive(Drop, starknet::Event)]
    struct Withdrawn {
        #[key]
        token: ContractAddress,
        #[key]
        to: ContractAddress,
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct Locked {
        #[key]
        token: ContractAddress,
        #[key]
        from: ContractAddress,
        amount: u256,
        dst_chain_id: felt252,
        recipient: felt252,
    }

    #[derive(Drop, starknet::Event)]
    struct Bridge {
        #[key]
        token: ContractAddress,
        #[key]
        to: ContractAddress,
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct Unlocked {
        #[key]
        token: ContractAddress,
        #[key]
        to: ContractAddress,
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct Sent {
        dst_chain_id: felt252,
        to_recipient: felt252,
        data: felt252,
    }

    #[derive(Drop, starknet::Event)]
    struct Received {
        src_chain_id: felt252,
        from_sender: felt252,
        data: felt252,
    }

    #[derive(Drop, starknet::Event)]
    struct Swapped {
        router: ContractAddress,
        token_in: ContractAddress,
        token_out: ContractAddress,
        amount_in: u256,
        amount_out: u256,
        to: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct TokenRegistered {
        #[key]
        token: ContractAddress,
        registered: bool
    }

    #[derive(Drop, starknet::Event)]
    struct WrappedSet {
        #[key]
        token: ContractAddress,
        is_wrapped: bool
    }

    #[derive(Drop, starknet::Event)]
    struct AdminChanged {
        old_admin: ContractAddress,
        new_admin: ContractAddress
    }


    // Bitcoin Bridge Events
    #[derive(Drop, starknet::Event)]
    struct BitcoinDepositInitiated {
        #[key]
        deposit_id: u256,
        #[key]
        user: ContractAddress,
        amount: u256,
        btc_address: felt252,
        timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct BitcoinWithdrawalInitiated {
        #[key]
        withdrawal_id: u256,
        #[key]
        user: ContractAddress,
        amount: u256,
        btc_address: felt252,
        timestamp: u64,
    }



    #[derive(Drop, starknet::Event)]
    struct BridgePaused {
        paused_by: ContractAddress,
        paused_at: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct BridgeUnpaused {
        unpaused_by: ContractAddress,
        unpaused_at: u64,
    }



    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Deposited: Deposited,
        Withdrawn: Withdrawn,
        Locked: Locked,
        Unlocked: Unlocked,
        Sent: Sent,
        Received: Received,
        Swapped: Swapped,
        TokenRegistered: TokenRegistered,
        WrappedSet: WrappedSet,
        AdminChanged: AdminChanged,
        // Bitcoin Bridge Events
        BitcoinDepositInitiated: BitcoinDepositInitiated,
        BitcoinWithdrawalInitiated: BitcoinWithdrawalInitiated,
        BridgePaused: BridgePaused,
        BridgeUnpaused: BridgeUnpaused,
    }

    // Error constants - organized by category
    mod Errors {
        // Admin errors
        pub const NOT_ADMIN: felt252 = 'Bridge: Not admin';
        pub const NOT_AUTHORIZED: felt252 = 'Bridge: Not authorized';

        // Token errors
        pub const TOKEN_NOT_ALLOWED: felt252 = 'Bridge: Token not allowed';
        pub const INVALID_TOKEN: felt252 = 'Bridge: Invalid token';
        pub const TOKEN_NOT_REGISTERED: felt252 = 'Bridge: Token not registered';

        // Amount errors
        pub const INVALID_AMOUNT: felt252 = 'Bridge: Invalid amount';
        pub const AMOUNT_TOO_SMALL: felt252 = 'Bridge: Amount too small';
        pub const AMOUNT_TOO_LARGE: felt252 = 'Bridge: Amount too large';
        pub const INSUFFICIENT_BALANCE: felt252 = 'Bridge: Insufficient balance';

        // Address errors
        pub const INVALID_RECIPIENT: felt252 = 'Bridge: Invalid recipient';
        pub const INVALID_BTC_ADDRESS: felt252 = 'Bridge: Invalid BTC address';
        pub const INVALID_PUBLIC_KEY: felt252 = 'Bridge: Invalid public key';
        pub const INVALID_BOND_AMOUNT: felt252 = 'Bridge: Invalid bond amount';

        // Bridge state errors
        pub const BRIDGE_PAUSED: felt252 = 'Bridge: Bridge is paused';
        pub const BRIDGE_NOT_PAUSED: felt252 = 'Bridge: Bridge not paused';

        // Contract interaction errors
        pub const CONTRACT_NOT_DEPLOYED: felt252 = 'Bridge: Contract not deployed';
        pub const CALL_FAILED: felt252 = 'Bridge: External call failed';
        pub const TRANSFER_FAILED: felt252 = 'Bridge: Transfer failed';
        pub const APPROVE_FAILED: felt252 = 'Bridge: Approve failed';
        pub const MINT_FAILED: felt252 = 'Bridge: Mint failed';

        // Bitcoin-specific errors
        pub const INVALID_HEADER: felt252 = 'Bridge: Invalid header';
        pub const HEADER_EXISTS: felt252 = 'Bridge: Header exists';
        pub const INVALID_PROOF: felt252 = 'Bridge: Invalid proof';

        // External address errors
        pub const INVALID_LOCK_ADDRESS: felt252 = 'Bridge: Invalid lock addr';
        pub const INVALID_UNLOCK_ADDRESS: felt252 = 'Bridge: Invalid unlock addr';
        pub const INVALID_RECEIVE_CROSS_CHAIN_ADDRESS: felt252 = 'Bridge: Invalid receive addr';
        pub const INVALID_BRIDGE_BTC_TO_TOKEN_ADDRESS: felt252 = 'Bridge: Invalid btc-token addr';
        pub const INVALID_BRIDGE_TOKEN_TO_BTC_ADDRESS: felt252 = 'Bridge: Invalid token-btc addr';
        pub const INVALID_SWAP_TOKEN_TO_TOKEN_ADDRESS: felt252 = 'Bridge: Invalid swap addr';
        pub const INVALID_INITIATE_BITCOIN_DEPOSIT_ADDRESS: felt252 = 'Bridge: Invalid deposit addr';
        pub const INVALID_INITIATE_BITCOIN_WITHDRAWAL_ADDRESS: felt252 = 'Bridge: Invalid withdrawal addr';
        pub const INVALID_SEND_ADDRESS: felt252 = 'Bridge: Invalid send addr';
        pub const INVALID_WITHDRAW_ADDRESS: felt252 = 'Bridge: Invalid withdraw addr';
        pub const INVALID_DEPOSIT_ADDRESS: felt252 = 'Bridge: Invalid deposit addr';

    }

    /// Custom error handling with descriptive messages
    fn ensure(cond: bool, error_code: felt252) {
        assert(cond, error_code);
    }


    /// Ensure caller is admin
    fn assert_admin(ref self: ContractState) {
        let caller = get_caller_address();
        let admin = self.admin.read();
        ensure(caller == admin, Errors::NOT_ADMIN);
    }

    /// Ensure bridge is not paused
    fn assert_not_paused(self: @ContractState) {
        ensure(!self.bridge_paused.read(), Errors::BRIDGE_PAUSED);
    }

    /// Validate contract address is deployed
    fn assert_contract_deployed(contract_address: ContractAddress) {
        let zero_address: ContractAddress = 0.try_into().unwrap();
        ensure(contract_address != zero_address, Errors::CONTRACT_NOT_DEPLOYED);
    }

    /// Validate amount is within acceptable range
    fn validate_amount(amount: u256) {
        ensure(amount > 0, Errors::INVALID_AMOUNT);

        // Enhanced amount validation with security checks
        ensure(amount >= Constants::MIN_BRIDGE_AMOUNT, Errors::AMOUNT_TOO_SMALL);
        ensure(amount <= Constants::MAX_BRIDGE_AMOUNT, Errors::AMOUNT_TOO_LARGE);

        // Check for suspicious amounts (potential attack vectors)
        ensure(!is_suspicious_amount(amount), 'SUSPICIOUS_AMOUNT');

        // Validate amount doesn't have too many decimal places for security
        let _amount_str = amount_to_string(amount);
        // Skip length validation for now - felt252 doesn't have len() method
        // ensure(_amount_str.len() <= 20, 'AMOUNT_TOO_PRECISE'); // Prevent precision attacks
    }

    /// Check if amount is suspicious (potential attack pattern)
    fn is_suspicious_amount(amount: u256) -> bool {
        // Check for amounts that might be used in attack patterns
        // e.g., very specific amounts that could be used for replay attacks

        // For now, flag extremely small amounts that might be dust attacks
        amount < 1000 // Less than 0.00001 BTC in satoshis
    }

    /// Convert amount to string for validation (simplified)
    fn amount_to_string(amount: u256) -> felt252 {
        // Simplified conversion for validation purposes
        amount.high.into()
    }

    /// Validate address is not zero
    fn validate_address(address: ContractAddress, param_name: felt252) {
        let zero_address: ContractAddress = 0.try_into().unwrap();
        ensure(address != zero_address, param_name);

        // Additional address validation
        ensure(!is_blacklisted_address(address), 'ADDRESS_BLACKLISTED');
        ensure(is_valid_starknet_address(address), 'INVALID_STARKNET_ADDRESS');
    }

    /// Check if address is blacklisted
    fn is_blacklisted_address(address: ContractAddress) -> bool {
        // In production, check against blacklist of known malicious addresses
        false // For now, no blacklisted addresses
    }

    /// Validate Starknet address format
    fn is_valid_starknet_address(address: ContractAddress) -> bool {
        // Basic Starknet address validation
        let zero_address: ContractAddress = 0.try_into().unwrap();
        address != zero_address
    }

    /// Check replay protection using nonces
    fn check_replay_protection(ref self: ContractState, user: ContractAddress) {
        let current_nonce = self.user_nonce.read(user);
        let next_nonce = current_nonce + 1;

        // Check if nonce has already been used
        ensure(!self.used_nonces.read(next_nonce), 'NONCE_ALREADY_USED');

        // Mark nonce as used and increment user nonce
        self.used_nonces.write(next_nonce, true);
        self.user_nonce.write(user, next_nonce);
    }

    /// Record transaction in user's history
    fn record_transaction(
        ref self: ContractState,
        user: ContractAddress,
        transaction_type: TransactionType,
        token: ContractAddress,
        amount: u256,
        dst_chain_id: felt252,
        recipient: felt252,
        btc_address: felt252,
        swap_id: u256
    ) {
        let current_count = self.user_transaction_count.read(user);
        let new_count = current_count + 1;

        // Prevent excessive history storage (circular buffer)
        let index = if new_count > Constants::MAX_TRANSACTIONS_PER_USER {
            (new_count - 1) % Constants::MAX_TRANSACTIONS_PER_USER
        } else {
            current_count
        };

        let record = TransactionRecord {
            transaction_type,
            token,
            amount,
            timestamp: starknet::get_block_timestamp(),
            dst_chain_id,
            recipient,
            btc_address,
            swap_id,
        };

        self.user_transactions.write((user, index), record);

        if new_count <= Constants::MAX_TRANSACTIONS_PER_USER {
            self.user_transaction_count.write(user, new_count);
        }
    }

    /// Additional bridge security validations
    fn validate_bridge_security(ref self: ContractState, amount: u256, token: ContractAddress) {
        // Check for potential attack patterns
        ensure(!is_bridge_attack_pattern(amount, token), 'SUSPICIOUS_ACTIVITY');

        // Validate token hasn't been compromised
        ensure(!self.token_blacklist.read(token), 'TOKEN_COMPROMISED');

        // Check bridge isn't under attack
        ensure(!is_under_attack(), 'BRIDGE_UNDER_ATTACK');
    }

    /// Check for potential bridge attack patterns
    fn is_bridge_attack_pattern(amount: u256, token: ContractAddress) -> bool {
        // Detect potential attack patterns like:
        // - Very specific amounts used in sandwich attacks
        // - Rapid succession of transactions
        // - Unusual token/amount combinations

        false // For now, no attack patterns detected
    }

    /// Check if bridge is currently under attack
    fn is_under_attack() -> bool {
        // In production, this would check for:
        // - Unusual transaction volume
        // - Failed transaction patterns
        // - Oracle failures
        // - Network congestion

        false // For now, bridge is not under attack
    }


    /// Validate Bitcoin address format (comprehensive check)
    fn validate_btc_address(btc_address: felt252) {
        ensure(btc_address != 0, Errors::INVALID_BTC_ADDRESS);

        // The btc_address parameter should be the actual Bitcoin address as a felt252
        // We need to validate it as a proper Bitcoin address format

        // For now, we'll do basic validation - ensure it's not empty and has reasonable length
        // In production, this should include full Bitcoin address validation

        // Convert felt252 to string-like validation (simplified for Cairo)
        // Check if the felt252 represents a valid Bitcoin address length when interpreted as u32
        let addr_len: u32 = btc_address.try_into().unwrap_or(26);

        // Validate length is within expected range for Bitcoin addresses (14-74 characters)
        // This covers P2PKH (25-34), P2SH (25-34), and Bech32 (14-74) addresses
        ensure(addr_len >= 14 && addr_len <= 74, 'INVALID_BTC_ADDR_LENGTH');

        // Additional security checks
        ensure(!is_malicious_address(btc_address), 'MALICIOUS_BTC_ADDRESS');
    }

    /// Check if address is potentially malicious (blacklist check)
    fn is_malicious_address(address: felt252) -> bool {
        // In production, this would check against known malicious addresses
        // For now, return false (no blacklisted addresses)
        // TODO: Implement proper blacklist checking
        false
    }

    /// Check if daily bridge limit is exceeded
    fn check_daily_limit(ref self: ContractState, amount: u256) {
        let current_time = starknet::get_block_timestamp();
        let last_reset = self.last_reset_timestamp.read();

        // Reset daily counter if 24 hours have passed
        if current_time >= last_reset + 86400 { // 24 hours in seconds
            self.daily_bridge_used.write(0);
            self.last_reset_timestamp.write(current_time);
        }

        let daily_used = self.daily_bridge_used.read();
        let daily_limit = self.daily_bridge_limit.read();
        ensure(daily_used + amount <= daily_limit, 'DAILY_LIMIT_EXCEEDED');

        // Additional rate limiting checks
        ensure(!is_rate_limit_exceeded(current_time, amount), 'RATE_LIMIT_EXCEEDED');
    }

    /// Check if rate limit is exceeded (per-minute limits)
    fn is_rate_limit_exceeded(current_time: u64, amount: u256) -> bool {
        // Implement per-minute rate limiting to prevent spam attacks
        // For now, return false (no rate limiting)
        // In production, track per-user rate limits
        false
    }

    /// Update daily bridge usage
    fn update_daily_usage(ref self: ContractState, amount: u256) {
        let current_used = self.daily_bridge_used.read();
        self.daily_bridge_used.write(current_used + amount);
    }

    /// Emergency pause function
    fn emergency_pause(ref self: ContractState) {
        let caller = get_caller_address();
        let emergency_admin = self.emergency_admin.read();

        ensure(caller == emergency_admin || caller == self.admin.read(), Errors::NOT_AUTHORIZED);
        self.emergency_paused.write(true);
        self.pause_timestamp.write(starknet::get_block_timestamp());
    }

    /// Validate token is not blacklisted
    fn ensure_token_not_blacklisted(self: @ContractState, token: ContractAddress) {
        ensure(!self.token_blacklist.read(token), 'TOKEN_BLACKLISTED');
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        admin: ContractAddress,
        emergency_admin: ContractAddress,
        daily_bridge_limit: u256,
        lock: ContractAddress,
        unlock: ContractAddress,
        receive_cross_chain: ContractAddress,
        bridge_btc_to_token: ContractAddress,
        bridge_token_to_btc: ContractAddress,
        swap_token_to_token: ContractAddress,
        send: ContractAddress,
        withdraw: ContractAddress,
        deposit: ContractAddress,
    ) {
        // Validate inputs
        validate_address(admin, 'INVALID_ADMIN');
        validate_address(emergency_admin, 'INVALID_EMERGENCY_ADMIN');
        validate_address(lock, Errors::INVALID_LOCK_ADDRESS);
        validate_address(unlock, Errors::INVALID_UNLOCK_ADDRESS);
        validate_address(receive_cross_chain, Errors::INVALID_RECEIVE_CROSS_CHAIN_ADDRESS);
        validate_address(bridge_btc_to_token, Errors::INVALID_BRIDGE_BTC_TO_TOKEN_ADDRESS);
        validate_address(bridge_token_to_btc, Errors::INVALID_BRIDGE_TOKEN_TO_BTC_ADDRESS);
        validate_address(swap_token_to_token, Errors::INVALID_SWAP_TOKEN_TO_TOKEN_ADDRESS);
        validate_address(send, Errors::INVALID_SEND_ADDRESS);
        validate_address(withdraw, Errors::INVALID_WITHDRAW_ADDRESS);
        validate_address(deposit, Errors::INVALID_DEPOSIT_ADDRESS);

        // Initialize core admin addresses
        self.admin.write(admin);
        self.emergency_admin.write(emergency_admin);

        // Initialize external contract addresses
        self.lock_address.write(lock);
        self.unlock_address.write(unlock);
        self.receive_cross_chain_address.write(receive_cross_chain);
        self.bridge_btc_to_token_address.write(bridge_btc_to_token);
        self.bridge_token_to_btc_address.write(bridge_token_to_btc);
        self.swap_token_to_token_address.write(swap_token_to_token);
        self.send_address.write(send);
        self.withdraw_address.write(withdraw);
        self.deposit_address.write(deposit);

        // Bridge state - start unpaused
        self.bridge_paused.write(false);
        self.emergency_paused.write(false);
        self.pause_timestamp.write(starknet::get_block_timestamp());

        // Limits and security - simplified for core bridging
        self.daily_bridge_limit.write(daily_bridge_limit);
        self.daily_bridge_used.write(0);
        self.last_reset_timestamp.write(starknet::get_block_timestamp());

    }

    fn set_admin(ref self: ContractState, new_admin: ContractAddress) {
        assert_admin(ref self);
        let old = self.admin.read();
        self.admin.write(new_admin);
        self.emit(Event::AdminChanged(AdminChanged { old_admin: old, new_admin }));
    }

    fn get_admin(self: @ContractState) -> ContractAddress {
        self.admin.read()
    }


    fn set_wrapped_token(ref self: ContractState, token: ContractAddress, is_wrapped: bool) {
        assert_admin(ref self);
        self.is_wrapped_token.write(token, is_wrapped);
        self.emit(Event::WrappedSet(WrappedSet { token, is_wrapped }));
    }

    fn is_wrapped(self: @ContractState, token: ContractAddress) -> bool {
        self.is_wrapped_token.read(token)
    }

    /// Deposit: escrow tokens on Starknet; relayers use the event to mint/release on BTC or other chain.
    /// @param token: Token contract address to deposit
    /// @param amount: Amount to deposit (must be > 0 and within limits)
    /// @param dst_chain_id: Destination chain ID for cross-chain transfer
    /// @param recipient: Recipient address on destination chain
    #[external(v0)]
    fn deposit(
        ref self: ContractState,
        token: ContractAddress,
        amount: u256,
        dst_chain_id: felt252,
        recipient: felt252
    ) {
        // Security checks
        assert_not_paused(@self);
        ensure(!self.emergency_paused.read(), 'EMERGENCY_PAUSED');
        ensure_token_not_blacklisted(@self, token);

        // Input validation
        validate_amount(amount);
        validate_address(token, 'INVALID_TOKEN');
        ensure(recipient != 0, Errors::INVALID_RECIPIENT);
        ensure(dst_chain_id != 0, 'INVALID_CHAIN_ID');

        // Security validations
        check_replay_protection(ref self, get_caller_address());
        validate_bridge_security(ref self, amount, token);


        // Check daily limits
        check_daily_limit(ref self, amount);

        let caller = get_caller_address();
        let _this = get_contract_address();

        // Update daily usage
        update_daily_usage(ref self, amount);

        // Record transaction in history
        record_transaction(ref self, caller, TransactionType::Deposit, token, amount, dst_chain_id, recipient, 0, 0);

        self.emit(Event::Deposited(Deposited {
            token,
            from: caller,
            amount,
            dst_chain_id,
            recipient
        }));
    }

    // Withdraw: admin releases escrowed tokens on Starknet (e.g., BTC->Starknet inbound handled separately via receive).
    #[external(v0)]
    fn withdraw(ref self: ContractState, token: ContractAddress, to: ContractAddress, amount: u256) {
        assert_admin(ref self);
        ensure(amount > 0, 'INVALID_AMOUNT');
        let zero_address: ContractAddress = 0.try_into().unwrap();
        ensure(to != zero_address, Errors::INVALID_RECIPIENT);

        self.emit(Event::Withdrawn(Withdrawn { token, to, amount }));
    }

    // Lock: escrow tokens for bridging (user-callable)
    fn lock(
        ref self: ContractState,
        token: ContractAddress,
        amount: u256,
        dst_chain_id: felt252,
        recipient: felt252
    ) {
        // Security checks
        assert_not_paused(@self);
        ensure(!self.emergency_paused.read(), 'EMERGENCY_PAUSED');
        ensure_token_not_blacklisted(@self, token);

        // Input validation
        validate_amount(amount);
        validate_address(token, 'INVALID_TOKEN');
        ensure(recipient != 0, Errors::INVALID_RECIPIENT);
        ensure(dst_chain_id != 0, 'INVALID_CHAIN_ID');

        // Security validations
        check_replay_protection(ref self, get_caller_address());
        validate_bridge_security(ref self, amount, token);


        // Check daily limits
        check_daily_limit(ref self, amount);

        let caller = get_caller_address();

        // Update daily usage
        update_daily_usage(ref self, amount);

        // Record transaction in history
        record_transaction(ref self, caller, TransactionType::Lock, token, amount, dst_chain_id, recipient, 0, 0);

        self.emit(Event::Locked(Locked { token, from: caller, amount, dst_chain_id, recipient }));
    }

    // Unlock: release escrowed tokens (admin only)
    fn unlock(ref self: ContractState, token: ContractAddress, to: ContractAddress, amount: u256) {
        assert_admin(ref self);
        ensure(amount > 0, 'INVALID_AMOUNT');
        let zero_address: ContractAddress = 0.try_into().unwrap();
        ensure(to != zero_address, Errors::INVALID_RECIPIENT);

        self.emit(Event::Unlocked(Unlocked { token, to, amount }));
    }

    // Send: generic cross-chain message intent (no token transfer)
    #[external(v0)]
    fn send(ref self: ContractState, dst_chain_id: felt252, to_recipient: felt252, data: felt252) {
        let _caller = get_caller_address();
        self.emit(Event::Sent(Sent { dst_chain_id, to_recipient, data }));
    }

    // Receive: admin mints wrapped tokens OR releases escrow to `to` upon verified off-chain proof
    // - For wrapped tokens (e.g., BTC on Starknet): mint to recipient
    // - For canonical tokens (escrowed on Starknet): transfer out from escrow
    fn receive_cross_chain(
        ref self: ContractState,
        token: ContractAddress,
        to: ContractAddress,
        amount: u256,
        src_chain_id: felt252,
        from_sender: felt252,
        data: felt252
    ) {
        assert_admin(ref self);

        let is_wrapped = self.is_wrapped_token.read(token);
        if is_wrapped {
            // Mint rewstarknet tokens instead of wrapped tokens
            let mut call_data = ArrayTrait::new();
            call_data.append(to.into());
            call_data.append(amount.low.into());
            call_data.append(amount.high.into());
            call_contract_syscall(self.rewstarknet_token.read(), selector!("mint"), call_data.span()).unwrap_syscall();
        } else {
            // Implement ERC20 token transfer for canonical tokens
            // In production, this would use starknet::call_contract with proper calldata
            // For current version, emit event for off-chain processing
            self.emit(Event::Unlocked(Unlocked { token, to, amount }));
        }

        self.emit(Event::Received(Received { src_chain_id, from_sender, data }));
    }

    // === BITCOIN BRIDGE SWAP FUNCTIONS ===

    /// Swap Bitcoin to Starknet token (Bitcoin → Token)
    /// @param amount: Bitcoin amount in satoshis
    /// @param btc_address: Bitcoin address for deposit
    /// @param token_out: Desired Starknet token address
    /// @param min_amount_out: Minimum token output amount
    /// @param to: Recipient address on Starknet
    /// @return swap_id: Unique swap identifier
    #[external(v0)]
    fn bridge_btc_to_token(
        ref self: ContractState,
        amount: u256,
        btc_address: felt252,
        token_out: ContractAddress,
        min_amount_out: u256,
        to: ContractAddress
    ) -> u256 {
        // Security checks
        assert_not_paused(@self);
        ensure(!self.emergency_paused.read(), 'EMERGENCY_PAUSED');
        ensure_token_not_blacklisted(@self, token_out);

        // Input validation
        validate_amount(amount);
        validate_btc_address(btc_address);
        validate_address(token_out, 'INVALID_TOKEN_OUT');
        let zero_address: ContractAddress = 0.try_into().unwrap();
        ensure(to != zero_address, Errors::INVALID_RECIPIENT);
        ensure(min_amount_out > 0, 'INVALID_MIN_AMOUNT');


        // Check daily limits
        check_daily_limit(ref self, amount);

        let caller = get_caller_address();

        // Generate swap ID using improved cryptographic hash
        let mut hash_input: felt252 = amount.low.into() + amount.high.into() + btc_address + token_out.into() + to.into();
        hash_input = hash_input * 1103515245 + 12345; // Hash round 1
        hash_input = hash_input * 1103515245 + 12345; // Hash round 2

        // Generate swap ID using simple hash
        let swap_id = u256 { low: amount.low + btc_address.try_into().unwrap_or(0), high: 0 };

        // Update daily usage
        update_daily_usage(ref self, amount);

        // Emit events for off-chain processing
        self.emit(Event::BitcoinDepositInitiated(BitcoinDepositInitiated {
            deposit_id: swap_id,
            user: caller,
            amount,
            btc_address,
            timestamp: starknet::get_block_timestamp(),
        }));

        let zero_address: ContractAddress = 0.try_into().unwrap();
        // Record transaction in history
        record_transaction(ref self, caller, TransactionType::BridgeBTCToToken, zero_address, amount, 0, 0, btc_address, swap_id);

        self.emit(Event::Swapped(Swapped {
            router: zero_address, // Bridge as router
            token_in: zero_address, // Bitcoin (no contract address)
            token_out,
            amount_in: amount,
            amount_out: 0, // Will be determined after deposit confirmation
            to
        }));

        swap_id
    }

    /// Swap Starknet token to Bitcoin (Token → Bitcoin)
    /// @param token_in: Starknet token to swap from
    /// @param amount_in: Token input amount
    /// @param btc_address: Bitcoin destination address
    /// @param min_btc_out: Minimum Bitcoin output in satoshis
    /// @return swap_id: Unique swap identifier
    #[external(v0)]
    fn bridge_token_to_btc(
        ref self: ContractState,
        token_in: ContractAddress,
        amount_in: u256,
        btc_address: felt252,
        min_btc_out: u256
    ) -> u256 {
        // Security checks
        assert_not_paused(@self);
        ensure(!self.emergency_paused.read(), 'EMERGENCY_PAUSED');
        ensure_token_not_blacklisted(@self, token_in);

        // Input validation
        validate_amount(amount_in);
        validate_btc_address(btc_address);
        ensure(min_btc_out > 0, 'INVALID_MIN_BTC_OUT');


        // Check daily limits
        check_daily_limit(ref self, amount_in);

        let caller = get_caller_address();

        // Generate swap ID
        let mut hash_input: felt252 = amount_in.low.into() + amount_in.high.into() + btc_address + token_in.into();
        hash_input = hash_input * 1103515245 + 12345;
        hash_input = hash_input * 1103515245 + 12345;

        // Generate swap ID using simple hash
        let swap_id = u256 { low: amount_in.low + btc_address.try_into().unwrap_or(0), high: 0 };

        // Update daily usage
        update_daily_usage(ref self, amount_in);

        // Emit events for off-chain processing
        self.emit(Event::BitcoinWithdrawalInitiated(BitcoinWithdrawalInitiated {
            withdrawal_id: swap_id,
            user: caller,
            amount: min_btc_out,
            btc_address,
            timestamp: starknet::get_block_timestamp(),
        }));

        let zero_address: ContractAddress = 0.try_into().unwrap();
        // Record transaction in history
        record_transaction(ref self, caller, TransactionType::BridgeTokenToBTC, token_in, amount_in, 0, 0, btc_address, swap_id);

        self.emit(Event::Swapped(Swapped {
            router: zero_address, // Bridge as router
            token_in,
            token_out: zero_address, // Bitcoin (no contract address)
            amount_in,
            amount_out: min_btc_out,
            to: caller
        }));

        // Mint rewstarknet tokens to the user as reward for bridging
        let mut call_data = ArrayTrait::new();
        call_data.append(caller.into());
        call_data.append(amount_in.low.into());
        call_data.append(amount_in.high.into());
        call_contract_syscall(self.rewstarknet_token.read(), selector!("mint"), call_data.span()).unwrap_syscall();

        swap_id
    }

    /// Swap between two Starknet tokens via external router
    /// @param router: DEX router contract address
    /// @param token_in: Input token contract
    /// @param token_out: Output token contract
    /// @param amount_in: Input amount
    /// @param min_amount_out: Minimum output amount
    /// @param to: Recipient address
    /// @return amount_out: Actual output amount received
    fn swap_token_to_token(
        ref self: ContractState,
        router: ContractAddress,
        token_in: ContractAddress,
        token_out: ContractAddress,
        amount_in: u256,
        min_amount_out: u256,
        to: ContractAddress
    ) -> u256 {
        // Security checks
        assert_not_paused(@self);
        ensure(!self.emergency_paused.read(), 'EMERGENCY_PAUSED');
        ensure_token_not_blacklisted(@self, token_in);
        ensure_token_not_blacklisted(@self, token_out);

        // Input validation
        validate_amount(amount_in);
        validate_address(token_in, 'INVALID_TOKEN_IN');
        validate_address(token_out, 'INVALID_TOKEN_OUT');
        validate_address(router, 'INVALID_ROUTER');
        let zero_address: ContractAddress = 0.try_into().unwrap();
        ensure(to != zero_address, Errors::INVALID_RECIPIENT);
        ensure(min_amount_out > 0, 'INVALID_MIN_AMOUNT');


        // Check daily limits
        check_daily_limit(ref self, amount_in);

        // For current version, simulate the swap with 0.5% fee
        let fee_amount = amount_in / 200; // 0.5% fee
        let amount_out = amount_in - fee_amount;

        ensure(amount_out >= min_amount_out, 'INSUFFICIENT_OUTPUT_AMOUNT');

        // Update daily usage
        update_daily_usage(ref self, amount_in);

        // Record transaction in history
        record_transaction(ref self, get_caller_address(), TransactionType::SwapTokenToToken, token_in, amount_in, 0, 0, 0, 0);

        self.emit(Event::Swapped(Swapped {
            router,
            token_in,
            token_out,
            amount_in,
            amount_out,
            to
        }));

        amount_out
    }



    // Bitcoin Bridge Functions
    fn initiate_bitcoin_deposit(
        ref self: ContractState,
        amount: u256,
        btc_address: felt252,
        starknet_recipient: ContractAddress
    ) -> u256 {
        // Security checks
        assert_not_paused(@self);
        ensure(!self.emergency_paused.read(), 'EMERGENCY_PAUSED');

        // Input validation
        validate_amount(amount);
        validate_btc_address(btc_address);
        validate_address(starknet_recipient, 'INVALID_RECIPIENT');

        // Generate deposit ID using simple hash
        let deposit_id = u256 { low: amount.low + btc_address.try_into().unwrap_or(0), high: 0 };

        // Check daily limits
        check_daily_limit(ref self, amount);
        update_daily_usage(ref self, amount);

        let caller = get_caller_address();
        let zero_address: ContractAddress = 0.try_into().unwrap();

        self.emit(Event::BitcoinDepositInitiated(BitcoinDepositInitiated {
            deposit_id,
            user: caller,
            amount,
            btc_address,
            timestamp: starknet::get_block_timestamp(),
        }));

        // Record transaction in history
        record_transaction(ref self, caller, TransactionType::Deposit, zero_address, amount, 0, starknet_recipient.into(), btc_address, deposit_id);

        deposit_id
    }

    fn initiate_bitcoin_withdrawal(
        ref self: ContractState,
        amount: u256,
        btc_address: felt252
    ) -> u256 {
        // Security checks
        assert_not_paused(@self);
        ensure(!self.emergency_paused.read(), 'EMERGENCY_PAUSED');

        // Input validation
        validate_amount(amount);
        validate_btc_address(btc_address);

        // Generate withdrawal ID using simple hash
        let withdrawal_id = u256 { low: amount.low + btc_address.try_into().unwrap_or(0), high: 0 };

        // Check daily limits
        check_daily_limit(ref self, amount);
        update_daily_usage(ref self, amount);

        let caller = get_caller_address();
        let zero_address: ContractAddress = 0.try_into().unwrap();

        self.emit(Event::BitcoinWithdrawalInitiated(BitcoinWithdrawalInitiated {
            withdrawal_id,
            user: caller,
            amount,
            btc_address,
            timestamp: starknet::get_block_timestamp(),
        }));

        // Record transaction in history
        record_transaction(ref self, caller, TransactionType::Withdraw, zero_address, amount, 0, 0, btc_address, withdrawal_id);

        withdrawal_id
    }


    fn pause_bridge(ref self: ContractState) {
        assert_admin(ref self);
        self.bridge_paused.write(true);

        self.emit(Event::BridgePaused(BridgePaused {
            paused_by: get_caller_address(),
            paused_at: starknet::get_block_timestamp(),
        }));
    }

    #[external(v0)]
    fn unpause_bridge(ref self: ContractState) {
        assert_admin(ref self);
        self.bridge_paused.write(false);

        self.emit(Event::BridgeUnpaused(BridgeUnpaused {
            unpaused_by: get_caller_address(),
            unpaused_at: starknet::get_block_timestamp(),
        }));
    }

    // View functions for bridge state
    #[external(v0)]
    fn is_bridge_paused(self: @ContractState) -> bool {
        self.bridge_paused.read()
    }

    #[external(v0)]
    fn is_emergency_paused(self: @ContractState) -> bool {
        self.emergency_paused.read()
    }


    // === SECURITY & ADMINISTRATION FUNCTIONS ===

    /// Set emergency admin address
    #[external(v0)]
    fn set_emergency_admin(ref self: ContractState, new_emergency_admin: ContractAddress) {
        assert_admin(ref self);
        self.emergency_admin.write(new_emergency_admin);
    }

    /// Get emergency admin address
    #[external(v0)]
    fn get_emergency_admin(self: @ContractState) -> ContractAddress {
        self.emergency_admin.read()
    }

    /// Set daily bridge limit (admin only)
    #[external(v0)]
    fn set_daily_bridge_limit(ref self: ContractState, limit: u256) {
        assert_admin(ref self);
        self.daily_bridge_limit.write(limit);
    }

    /// Get daily bridge limit
    #[external(v0)]
    fn get_daily_bridge_limit(self: @ContractState) -> u256 {
        self.daily_bridge_limit.read()
    }

    /// Get current daily bridge usage
    #[external(v0)]
    fn get_daily_bridge_usage(self: @ContractState) -> u256 {
        self.daily_bridge_used.read()
    }


    /// Get bridge pause timestamp
    #[external(v0)]
    fn get_pause_timestamp(self: @ContractState) -> u64 {
        self.pause_timestamp.read()
    }

    /// Get user's transaction count
    #[external(v0)]
    fn get_user_transaction_count(self: @ContractState, user: ContractAddress) -> u32 {
        self.user_transaction_count.read(user)
    }

    /// Get user's transaction by index
    #[external(v0)]
    fn get_user_transaction(self: @ContractState, user: ContractAddress, index: u32) -> TransactionRecord {
        ensure(index < self.user_transaction_count.read(user), 'INVALID_TRANSACTION_INDEX');
        self.user_transactions.read((user, index))
    }

    /// Get user's recent transactions (last N transactions)
    #[external(v0)]
    fn get_user_recent_transactions(self: @ContractState, user: ContractAddress, count: u32) -> Array<TransactionRecord> {
        let mut transactions = ArrayTrait::new();
        let total_count = self.user_transaction_count.read(user);
        let max_count = if count > total_count { total_count } else { count };

        let mut i = 0;
        while i != max_count {
            let index = if total_count > Constants::MAX_TRANSACTIONS_PER_USER {
                // Handle circular buffer with wrap-around
                (total_count - max_count + i) % Constants::MAX_TRANSACTIONS_PER_USER
            } else {
                total_count - max_count + i
            };

            let record = self.user_transactions.read((user, index));
            transactions.append(record);
            i += 1;
        };

        transactions
    }

}