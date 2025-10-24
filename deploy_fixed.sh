#!/bin/bash

# Fixed Starknet Bridge Deployment Script
# This script provides the corrected deployment command

set -e

echo "🔧 Starknet Bridge - Fixed Deployment Command"
echo "=============================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}PROBLEM IDENTIFIED:${NC}"
echo "❌ Original command used '--constructor-calldata' (incorrect)"
echo "❌ Backslash line continuation caused shell parsing issues"
echo "❌ Arguments were interpreted as separate commands"
echo ""

echo -e "${GREEN}SOLUTION:${NC}"
echo "✅ Use '--constructor-args' instead of '--constructor-calldata'"
echo "✅ Format command as single line or use proper escaping"
echo "✅ All arguments properly passed to sncast"
echo ""

echo -e "${GREEN}CORRECTED DEPLOYMENT COMMAND:${NC}"
echo ""

# Note: Replace YOUR_CLASS_HASH with the actual class hash from declaration
cat << 'EOF'
sncast --account=emman deploy \
  --class-hash=YOUR_CLASS_HASH \
  --network=sepolia \
  --salt $(date +%s) \
  --unique \
  --constructor-args \
    0x05A684593120E8A8B5521261cC51D7eeF10077aca9389e5DD09402405Fff7fC8 \
    0x05A684593120E8A8B5521261cC51D7eeF10077aca9389e5DD09402405Fff7fC8 \
    0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef \
    0x234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1 \
    0x34567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef12 \
    0x4567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef123 \
    0x567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234 \
    0x67890abcdef1234567890abcdef1234567890abcdef1234567890abcdef12345 \
    0x7890abcdef1234567890abcdef1234567890abcdef1234567890abcdef123456 \
    0x0000000000000000000000000000000000000000000000000000000000000000 \
    3652501241 \
    0x746573746e6574 \
    1000000000 \
    0 \
    1000000 \
    0
EOF

echo ""
echo -e "${YELLOW}INSTRUCTIONS:${NC}"
echo "1. First, declare your contract to get the class hash:"
echo "   sncast declare --package starknet_bridge"
echo ""
echo "2. Copy the class_hash from the output"
echo ""
echo "3. Replace 'YOUR_CLASS_HASH' in the command above with the actual hash"
echo ""
echo "4. Run the corrected deployment command"
echo ""
echo -e "${GREEN}✅ Fixed deployment script created!${NC}"
echo ""

# Alternative: Create a deploy script that takes class hash as parameter
cat > deploy_with_class_hash.sh << 'EOF'
#!/bin/bash
# Usage: ./deploy_with_class_hash.sh <CLASS_HASH>

if [ $# -ne 1 ]; then
    echo "Usage: $0 <CLASS_HASH>"
    echo "Example: $0 0x06d8c0b5790fe2a3388a4cdef730a42679da285ceb604c64f5d88e87b2fc3c9b"
    exit 1
fi

CLASS_HASH=$1

echo "🚀 Deploying Bridge contract with class hash: $CLASS_HASH"

sncast --account=emman deploy \
  --class-hash=$CLASS_HASH \
  --network=sepolia \
  --salt $(date +%s) \
  --unique \
  --constructor-args \
    0x05A684593120E8A8B5521261cC51D7eeF10077aca9389e5DD09402405Fff7fC8 \
    0x05A684593120E8A8B5521261cC51D7eeF10077aca9389e5DD09402405Fff7fC8 \
    0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef \
    0x234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1 \
    0x34567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef12 \
    0x4567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef123 \
    0x567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234 \
    0x67890abcdef1234567890abcdef1234567890abcdef1234567890abcdef12345 \
    0x7890abcdef1234567890abcdef1234567890abcdef1234567890abcdef123456 \
    0x0000000000000000000000000000000000000000000000000000000000000000 \
    3652501241 \
    0x746573746e6574 \
    1000000000 \
    0 \
    1000000 \
    0
EOF

chmod +x deploy_with_class_hash.sh

echo -e "${GREEN}✅ Created deploy_with_class_hash.sh script${NC}"
echo "Usage: ./deploy_with_class_hash.sh <YOUR_CLASS_HASH>"
echo ""