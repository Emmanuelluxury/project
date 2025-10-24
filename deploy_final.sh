#!/bin/bash

# Starknet Bridge - FINAL DEPLOYMENT SCRIPT
# This script handles deployment with proper error handling and account management

set -e

echo "🚀 Starknet Bridge - Final Deployment Script"
echo "==========================================="

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Check dependencies
print_header "Checking Dependencies"
if ! command -v scarb &> /dev/null; then
    print_error "scarb not found. Install Starknet Foundry:"
    echo "curl -L https://github.com/foundry-rs/starknet-foundry/releases/download/v0.12.0/starknet-foundry_0.12.0_amd64.deb -o starknet-foundry.deb"
    echo "sudo dpkg -i starknet-foundry.deb"
    exit 1
fi

if ! command -v sncast &> /dev/null; then
    print_error "sncast not found. Install Starknet Foundry first."
    exit 1
fi

print_status "Dependencies OK"

# Build contracts
print_header "Building Contracts"
print_status "Building starknet_bridge contracts..."
scarb build

if [ $? -ne 0 ]; then
    print_error "Build failed"
    exit 1
fi

print_status "Build completed successfully"

# Check account status
print_header "Checking Account Status"
ACCOUNT_ADDRESS="0x7121a08333e23bb8729aba6b1e2b3042b0934d6ed1cd65e212d3a560b608fee"

print_status "Current account: $ACCOUNT_ADDRESS"

# Try to declare first (this will show if account needs deployment)
print_header "Testing Account and Network"
print_status "Testing contract declaration..."

DECLARE_OUTPUT=$(sncast declare --contract-name Bridge --package starknet_bridge 2>&1)

if [[ $DECLARE_OUTPUT == *"not found"* ]]; then
    print_warning "Account not deployed or insufficient funds"
    print_header "Account Deployment Required"

    echo ""
    echo -e "${YELLOW}🔴 ACTION REQUIRED: Fund Your Account${NC}"
    echo "========================================"
    echo ""
    echo "Your account needs testnet ETH. Please:"
    echo ""
    echo -e "${BLUE}1. Go to: https://faucet.sepolia.starknet.io/${NC}"
    echo -e "${BLUE}2. Enter your account address:${NC}"
    echo -e "${GREEN}   0x7121a08333e23bb8729aba6b1e2b3042b0934d6ed1cd65e212d3a560b608fee${NC}"
    echo -e "${BLUE}3. Request testnet ETH${NC}"
    echo -e "${BLUE}4. Wait 1-2 minutes for confirmation${NC}"
    echo ""

    read -p "Press Enter after you've funded your account..."

    # Try to deploy account
    print_status "Deploying account..."
    sncast account deploy --name deployer

    if [ $? -ne 0 ]; then
        print_error "Account deployment failed. Please ensure you have enough testnet ETH."
        echo ""
        echo "Alternative faucets to try:"
        echo "- https://starknet-faucet.vercel.app/"
        echo "- https://faucet.goerli.starknet.io/"
        exit 1
    fi

    print_status "Account deployed successfully"

elif [[ $DECLARE_OUTPUT == *"class_hash:"* ]]; then
    print_status "Account is ready for deployment"

    # Extract class hash
    CLASS_HASH=$(echo "$DECLARE_OUTPUT" | grep "class_hash:" | awk '{print $2}' | tr -d '\n')
    print_status "Class hash: $CLASS_HASH"

    # Deploy contract
    print_header "Deploying Bridge Contract"
    print_status "Deploying with class hash: $CLASS_HASH"

    DEPLOY_OUTPUT=$(sncast deploy \
      --class-hash $CLASS_HASH \
      --salt $(date +%s) \
      --unique \
      --constructor-args \
        0x7121a08333e23bb8729aba6b1e2b3042b0934d6ed1cd65e212d3a560b608fee \
        0x7121a08333e23bb8729aba6b1e2b3042b0934d6ed1cd65e212d3a560b608fee \
        0x0 0x0 0x0 0x0 0x0 0x0 0x0 \
        0x123 181 0x6d61696e6e6574 \
        1000000000000000000000 1000000000000000000 2>&1)

    if [ $? -ne 0 ]; then
        print_error "Deployment failed: $DEPLOY_OUTPUT"
        exit 1
    fi

    # Extract contract address
    CONTRACT_ADDRESS=$(echo "$DEPLOY_OUTPUT" | grep "contract_address:" | awk '{print $2}' | tr -d '\n')

    if [ -z "$CONTRACT_ADDRESS" ]; then
        print_error "Could not extract contract address"
        exit 1
    fi

    print_status "Bridge contract deployed successfully!"
    echo ""
    echo "🎉 DEPLOYMENT SUCCESSFUL!"
    echo "========================="
    echo "Bridge Contract Address: $CONTRACT_ADDRESS"
    echo "Class Hash: $CLASS_HASH"
    echo "Network: Starknet Sepolia"
    echo ""
    echo "View on StarkScan:"
    echo "https://sepolia.starkscan.co/contract/$CONTRACT_ADDRESS"

    # Save deployment info
    cat > deployment-success.json << EOF
{
  "deployment_time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "network": "starknet-sepolia",
  "status": "success",
  "bridge_contract": "$CONTRACT_ADDRESS",
  "class_hash": "$CLASS_HASH",
  "account": "$ACCOUNT_ADDRESS"
}
EOF

    print_status "Deployment details saved to deployment-success.json"
    exit 0

else
    print_error "Unexpected response from declare command:"
    echo "$DECLARE_OUTPUT"
    exit 1
fi

# If we get here, account was deployed, now try declaration again
print_header "Declaring Contracts"
print_status "Declaring Bridge contract..."

DECLARE_OUTPUT=$(sncast declare --contract-name Bridge --package starknet_bridge 2>&1)

if [[ $DECLARE_OUTPUT == *"class_hash:"* ]]; then
    CLASS_HASH=$(echo "$DECLARE_OUTPUT" | grep "class_hash:" | awk '{print $2}' | tr -d '\n')
    print_status "Class hash: $CLASS_HASH"

    # Deploy contract
    print_header "Deploying Bridge Contract"
    print_status "Deploying Bridge contract..."

    DEPLOY_OUTPUT=$(sncast deploy \
      --class-hash $CLASS_HASH \
      --salt $(date +%s) \
      --unique \
      --constructor-args \
        0x7121a08333e23bb8729aba6b1e2b3042b0934d6ed1cd65e212d3a560b608fee \
        0x7121a08333e23bb8729aba6b1e2b3042b0934d6ed1cd65e212d3a560b608fee \
        0x0 0x0 0x0 0x0 0x0 0x0 0x0 \
        0x123 181 0x6d61696e6e6574 \
        1000000000000000000000 1000000000000000000 2>&1)

    if [ $? -ne 0 ]; then
        print_error "Deployment failed: $DEPLOY_OUTPUT"
        exit 1
    fi

    CONTRACT_ADDRESS=$(echo "$DEPLOY_OUTPUT" | grep "contract_address:" | awk '{print $2}' | tr -d '\n')

    print_status "Bridge contract deployed successfully!"
    echo ""
    echo "🎉 DEPLOYMENT SUCCESSFUL!"
    echo "========================="
    echo "Bridge Contract Address: $CONTRACT_ADDRESS"
    echo "Network: Starknet Sepolia"
    echo ""
    echo "View on StarkScan:"
    echo "https://sepolia.starkscan.co/contract/$CONTRACT_ADDRESS"

else
    print_error "Contract declaration failed after account deployment"
    echo "Response: $DECLARE_OUTPUT"
    exit 1
fi