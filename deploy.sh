#!/bin/bash

# Starknet Bridge Deployment Script
# This script deploys the bridge system contracts

set -e  # Exit on any error

echo "🚀 Starting Starknet Bridge Deployment..."
echo "========================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if scarb is installed
if ! command -v scarb &> /dev/null; then
    print_error "scarb is not installed. Please install Starknet Foundry first."
    exit 1
fi

# Check if sncast is installed
if ! command -v sncast &> /dev/null; then
    print_error "sncast is not installed. Please install Starknet Foundry first."
    exit 1
fi

print_status "Building contracts..."
scarb build

if [ $? -ne 0 ]; then
    print_error "Failed to build contracts"
    exit 1
fi

print_status "Build completed successfully"

# Declare and deploy the main library (which contains all contracts)
print_status "Declaring starknet_bridge library..."

DECLARE_OUTPUT=$(sncast declare --package starknet_bridge 2>&1)

if [ $? -ne 0 ]; then
    print_error "Failed to declare contracts: $DECLARE_OUTPUT"
    exit 1
fi

# Extract class hash from output
CLASS_HASH=$(echo "$DECLARE_OUTPUT" | grep "class_hash:" | awk '{print $2}' | tr -d '\n')

if [ -z "$CLASS_HASH" ]; then
    print_error "Could not extract class hash"
    exit 1
fi

print_status "Library declared with class hash: $CLASS_HASH"

# For this deployment, we'll deploy a simple test contract first
# Then provide instructions for manual deployment of the main Bridge

print_status "Deploying a test contract to verify deployment works..."

# Deploy with minimal constructor arguments for testing
TEST_DEPLOY_OUTPUT=$(sncast deploy --class-hash $CLASS_HASH --salt $(date +%s) --unique 2>&1)

if [ $? -ne 0 ]; then
    print_error "Failed to deploy test contract: $TEST_DEPLOY_OUTPUT"
    exit 1
fi

# Extract contract address from output
CONTRACT_ADDRESS=$(echo "$TEST_DEPLOY_OUTPUT" | grep "contract_address:" | awk '{print $2}' | tr -d '\n')

if [ -z "$CONTRACT_ADDRESS" ]; then
    print_error "Could not extract contract address"
    exit 1
fi

print_status "Test contract deployed at: $CONTRACT_ADDRESS"

# Create deployment summary
cat > deployment-summary.json << EOF
{
  "network": "starknet-sepolia",
  "deployment_time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "status": "ready_for_manual_deployment",
  "class_hash": "$CLASS_HASH",
  "test_contract_address": "$CONTRACT_ADDRESS",
  "note": "This deployment contains all contracts in a single class. For production deployment, deploy the main Bridge contract with proper constructor arguments."
}
EOF

echo ""
echo "========================================="
echo "📋 Deployment Status:"
echo "========================================="
echo "✅ Contracts built successfully"
echo "✅ Library declared successfully"
echo "✅ Class hash: $CLASS_HASH"
echo "✅ Test deployment successful"
echo ""
echo "🚨 IMPORTANT: Manual Steps Required"
echo "========================================="
echo ""
echo "Your contracts are ready for deployment! Since your Bridge contract"
echo "requires specific constructor arguments (multiple contract addresses),"
echo "you'll need to deploy it manually with the proper parameters."
echo ""
echo "DEPLOYMENT COMMAND:"
echo "sncast deploy \\"
echo "  --class-hash $CLASS_HASH \\"
echo "  --salt \$(date +%s) \\"
echo "  --unique \\"
echo "  --constructor-args \\"
echo "    [ADMIN_ADDRESS] \\"  # Your admin account address
echo "    [EMERGENCY_ADMIN_ADDRESS] \\"  # Emergency admin address
echo "    [BTC_HEADERS_ADDRESS] \\"  # BitcoinHeaders contract address
echo "    [SPV_VERIFIER_ADDRESS] \\"  # SPVVerifier contract address
echo "    [SBTC_ADDRESS] \\"  # SBTC token contract address
echo "    [DEPOSIT_MANAGER_ADDRESS] \\"  # BTCDepositManager address
echo "    [OPERATOR_REGISTRY_ADDRESS] \\"  # OperatorRegistry address
echo "    [PEG_OUT_ADDRESS] \\"  # BTCPegOut contract address
echo "    [ESCAPE_HATCH_ADDRESS] \\"  # EscapeHatch contract address
echo "    0x123 \\"  # BTC genesis hash (example)
echo "    181 \\"  # BTC network magic (testnet=181)
echo "    0x6d61696e6e6574 \\"  # Network name 'mainnet'
echo "    1000000000000000000000 \\"  # Daily bridge limit
echo "    1000000000000000000"  # Min operator bond
echo ""
echo "Full deployment details saved to: deployment-summary.json"
echo ""
print_status "Ready for manual deployment!"