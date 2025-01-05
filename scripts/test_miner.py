import requests
import sys
import json
import os
import time
from datetime import datetime, timezone
from communex.compat.key import classic_load_key
from substrateinterface import Keypair
from communex.module import _signer as signer

# Define key directory path - use the same path as the miner
KEY_DIR = os.path.expanduser("~/.commune/key")

# Set higher rate limits for testing
os.environ["CONFIG_IP_LIMITER_BUCKET_SIZE"] = "1000"  # Allow more requests in the bucket
os.environ["CONFIG_IP_LIMITER_REFILL_RATE"] = "100"   # Refill faster

def create_auth_headers(keypair, body: bytes) -> dict:
    """Create authentication headers for the request."""
    # Create signature using communex signer
    signature = signer.sign(keypair, body)
    
    # Use hex-encoded public key instead of ss58 address
    public_key_hex = keypair.public_key.hex()
    
    print(f"Debug - Public key hex: {public_key_hex}")
    print(f"Debug - SS58 address: {keypair.ss58_address}")
    
    return {
        "X-Key": public_key_hex,  # Send hex-encoded public key
        "X-Signature": signature.hex(),
        "X-Crypto": str(keypair.crypto_type),  # Use actual crypto type from keypair
        "Content-Type": "application/json"
    }

def test_miner(port: int, prompt: str = "What is 2+2?", key_name: str = "test_miner"):
    """Test the miner by sending a direct request to its generate endpoint."""
    url = f"http://localhost:{port}/method/generate"
    
    # First ensure key directory exists
    os.makedirs(KEY_DIR, exist_ok=True)
    
    # Copy our test key to the commune key directory if it doesn't exist
    local_key_path = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), ".commune/key/test_miner.json")
    target_key_path = os.path.join(KEY_DIR, "test_miner.json")
    
    if os.path.exists(local_key_path) and not os.path.exists(target_key_path):
        print(f"Copying test key from {local_key_path} to {target_key_path}")
        with open(local_key_path, 'r') as f:
            key_data = f.read()
        with open(target_key_path, 'w') as f:
            f.write(key_data)
    
    # Load the keypair using communex
    try:
        # Remove .json if present in key_name
        key_name = key_name.replace('.json', '')
        print(f"Debug - Loading key from: {key_name}")
        keypair = classic_load_key(key_name)
        print(f"Debug - Keypair type: {type(keypair)}")
        print(f"Debug - Keypair class: {keypair.__class__.__name__}")
        print(f"Debug - Keypair ss58: {keypair.ss58_address}")
    except Exception as e:
        print(f"\nError loading key: {str(e)}")
        print(f"Make sure the key exists at {os.path.join(KEY_DIR, key_name + '.json')}")
        return False
    
    try:
        # Prepare request body with target_key
        timestamp = datetime.now(timezone.utc).isoformat()
        body = {
            "params": {
                "prompt": prompt,
                "target_key": keypair.ss58_address,  # Add target_key to params
                "timestamp": timestamp  # Add ISO timestamp with timezone
            }
        }
        body_bytes = json.dumps(body).encode()
        
        # Create headers with authentication
        headers = create_auth_headers(keypair, body_bytes)
        
        print(f"\nUsing keypair address: {keypair.ss58_address}")
        print(f"Request headers: {json.dumps(headers, indent=2)}")
        print(f"Request body: {json.dumps(body, indent=2)}")
        
        response = requests.post(
            url,
            data=body_bytes,  # Use data instead of json to match our signed body
            headers=headers,
            timeout=10
        )
        
        print(f"Request to: {url}")
        print(f"Status code: {response.status_code}")
        
        if response.status_code == 200:
            print("\nSuccess! Response:")
            print(json.dumps(response.json(), indent=2))
            return True
        elif response.status_code == 429:  # Rate limit exceeded
            remaining = response.headers.get('X-RateLimit-Remaining', '0')
            print(f"\nMiner is working! However, it has reached its rate limit (remaining requests: {remaining})")
            print("This is expected behavior - miners have rate limits based on their stake amount.")
            print("Try again later when the rate limit has reset.")
            return True  # Return True since the miner is working as expected
        else:
            print("\nError! Response:")
            print(response.text)
            return False
            
    except requests.exceptions.ConnectionError:
        print(f"\nError: Could not connect to miner at {url}")
        print("Make sure the miner is running and the port is correct")
        return False
    except Exception as e:
        print(f"\nUnexpected error: {str(e)}")
        return False

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python test_miner.py PORT [PROMPT] [KEY_NAME]")
        print("Example: python test_miner.py 50000 'What is the meaning of life?' test_miner")
        sys.exit(1)
        
    port = int(sys.argv[1])
    prompt = sys.argv[2] if len(sys.argv) > 2 else "What is 2+2?"
    key_name = sys.argv[3] if len(sys.argv) > 3 else "test_miner"
    
    success = test_miner(port, prompt, key_name)
    sys.exit(0 if success else 1)
