pub mod interfaces{
    pub mod IERC20;
    pub mod IMintable;
    pub mod ISwapper;
    pub mod IBitcoinHeaders;
    pub mod IBitcoinClient;
    pub mod IBitcoinUtils;
    pub mod ICryptoUtils;
    pub mod IBTCDepositManager;
    pub mod IBTCPegOut;
    pub mod IOperatorRegistry;
    pub mod IEscapeHatch;
}

pub mod contracts{
    pub mod Bridge;
    pub mod BitcoinHeaders;
    pub mod BitcoinClient;
    pub mod BitcoinUtils;
    pub mod CryptoUtils;
    pub mod SPVVerifier;
    pub mod SBTC;
    pub mod BTCDepositManager;
    pub mod OperatorRegistry;
    pub mod BTCPegOut;
    pub mod EscapeHatch;
}

// use contracts::Bridge;