#!/bin/bash

echo "🚀 Starknet Bridge - Manual Deployment Guide"
echo "==========================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Step 1: Build Contracts${NC}"
echo "scarb build"
echo ""

echo -e "${GREEN}Step 2: Create Account (if needed)${NC}"
echo "sncast account create --name deployer"
echo ""

echo -e "${GREEN}Step 3: Declare Contracts${NC}"
echo "sncast declare --contract-name Bridge --package starknet_bridge"
echo ""

echo -e "${YELLOW}Step 4: Get Class Hash${NC}"
echo "Copy the class_hash from the declare output above"
echo ""

echo -e "${GREEN}Step 5: Deploy Main Bridge Contract${NC}"
echo "Replace YOUR_CLASS_HASH with the actual class hash from step 4:"
echo ""

BRIDGE_DEPLOY_CMD="sncast deploy --class-hash YOUR_CLASS_HASH --salt \$(date +%s) --unique --constructor-args 0x7f55e6e661b0d978818d95ffd5a22ef759e9bb45c8d72a12f7b6ff6bfffb044 0x7f55e6e661b0d978818d95ffd5a22ef759e9bb45c8d72a12f7b6ff6bfffb044 0x0 0x0 0x0 0x0 0x0 0x0 0x0 0x123 181 0x6d61696e6e6574 1000000000000000000000 1000000000000000000"

echo "$BRIDGE_DEPLOY_CMD"
echo ""

echo -e "${GREEN}Step 6: Deploy Supporting Contracts${NC}"
echo "After the main Bridge is deployed, deploy supporting contracts:"
echo ""

echo "Supporting contracts to deploy:"
echo "- SBTC (Token contract)"
echo "- BitcoinHeaders"
echo "- SPVVerifier"
echo "- BTCDepositManager"
echo "- OperatorRegistry"
echo "- BTCPegOut"
echo "- EscapeHatch"
echo "- BitcoinUtils"
echo "- CryptoUtils"
echo "- BitcoinClient"
echo ""

echo -e "${YELLOW}For each supporting contract:${NC}"
echo "sncast declare --contract-name [CONTRACT_NAME] --package starknet_bridge"
echo "sncast deploy --class-hash [CLASS_HASH] --salt \$(date +%s) --unique"
echo ""

echo -e "${GREEN}Step 7: Update Bridge Contract${NC}"
echo "Once all supporting contracts are deployed, call the Bridge contract"
echo "to register the supporting contract addresses using the setter functions."
echo ""

echo "==========================================="
echo -e "${GREEN}✅ Your contracts are ready for deployment!${NC}"
echo "==========================================="
echo ""
echo "Run each command in order, replacing YOUR_CLASS_HASH with the actual hash."
echo "Make sure you have enough ETH in your account for deployment fees."
echo ""