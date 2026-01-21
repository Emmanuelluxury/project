#!/usr/bin/env python3
import json
import hashlib
import sys

def compute_class_hash(sierra_path):
    with open(sierra_path, 'r') as f:
        data = json.load(f)
    
    # Sort keys and use compact separators
    s = json.dumps(data, separators=(',', ':'), sort_keys=True)
    
    # Compute SHA256 hash
    h = hashlib.sha256(s.encode()).digest()
    
    # Convert to field element (mod 2^250)
    h_int = int.from_bytes(h, 'big')
    
    # Format as hex with 0x prefix and 64 hex digits
    return f"0x{h_int:064x}"

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python3 compute_class_hash.py <path_to_sierra.json>")
        sys.exit(1)
    
    class_hash = compute_class_hash(sys.argv[1])
    print(class_hash)
