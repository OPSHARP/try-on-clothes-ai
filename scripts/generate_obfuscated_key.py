#!/usr/bin/env python3
"""
Generates XOR-obfuscated C++ code for embedding API keys in native code.

Usage:
    python scripts/generate_obfuscated_key.py <provider_name> <api_key>

Example:
    python scripts/generate_obfuscated_key.py huggingface hf_xxxxxxxxxx
"""

import sys
import random
import string

def random_xor_key(length: int = 20) -> str:
    """Generate a random alphanumeric XOR key."""
    chars = string.ascii_letters + string.digits
    return ''.join(random.choice(chars) for _ in range(length))

def xor_encrypt(plaintext: str, key: str) -> list[int]:
    """XOR-encrypt plaintext with repeating key, return bytes."""
    result = []
    for i, c in enumerate(plaintext):
        result.append(ord(c) ^ ord(key[i % len(key)]))
    return result

def generate_cpp_code(provider_name: str, api_key: str, xor_key: str) -> str:
    """Generate C++ code snippet with XOR-obfuscated API key."""
    encrypted = xor_encrypt(api_key, xor_key)
    encrypted_str = ', '.join(f'0x{b:02X}' for b in encrypted)
    xor_key_str = ', '.join(f'\'{c}\'' for c in xor_key)

    return f"""// Auto-generated XOR-obfuscated API key for {provider_name}
// DO NOT EDIT MANUALLY — re-run generate_obfuscated_key.py to update
static const char XOR_KEY_{provider_name.upper()}[] = {{{xor_key_str}}};
static const size_t XOR_KEY_{provider_name.upper()}_LEN = {len(xor_key)};

static const unsigned char ENCRYPTED_KEY_{provider_name.upper()}[] = {{{encrypted_str}}};
static const size_t ENCRYPTED_KEY_{provider_name.upper()}_LEN = {len(api_key)};

std::string decode_{provider_name}_key() {{
    std::string result;
    result.reserve(ENCRYPTED_KEY_{provider_name.upper()}_LEN);
    for (size_t i = 0; i < ENCRYPTED_KEY_{provider_name.upper()}_LEN; i++) {{
        result += static_cast<char>(
            ENCRYPTED_KEY_{provider_name.upper()}[i] ^
            XOR_KEY_{provider_name.upper()}[i % XOR_KEY_{provider_name.upper()}_LEN]
        );
    }}
    return result;
}}
"""

def main():
    if len(sys.argv) != 3:
        print("Usage: python generate_obfuscated_key.py <provider_name> <api_key>")
        sys.exit(1)

    provider_name = sys.argv[1]
    api_key = sys.argv[2]

    if not api_key:
        print("Error: API key cannot be empty.")
        sys.exit(1)

    xor_key = random_xor_key(20)
    code = generate_cpp_code(provider_name, api_key, xor_key)

    print(f"// Provider: {provider_name}")
    print(f"// API Key: {api_key[:4]}...{api_key[-4:]}")
    print(f"// XOR Key: {xor_key}")
    print()
    print(code)

if __name__ == '__main__':
    main()
