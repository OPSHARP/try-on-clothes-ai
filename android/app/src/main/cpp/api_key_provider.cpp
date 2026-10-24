// Native API Key Provider - Implementation
// Provides XOR-obfuscated pre-configured API keys for AI generation services.

#include "api_key_provider.h"
#include <cstring>
#include <string>

// Auto-generated XOR-obfuscated API key for huggingface placeholder
// Re-generate using: python scripts/generate_obfuscated_key.py huggingface <YOUR_KEY>
static const char XOR_KEY_HUGGINGFACE[] = {'A', 'B', 'C', 'D'};
static const size_t XOR_KEY_HUGGINGFACE_LEN = 4;

static const unsigned char ENCRYPTED_KEY_HUGGINGFACE[] = {};
static const size_t ENCRYPTED_KEY_HUGGINGFACE_LEN = 0;

static std::string decode_huggingface_key() {
    if (ENCRYPTED_KEY_HUGGINGFACE_LEN == 0) {
        return "";
    }
    std::string result;
    result.reserve(ENCRYPTED_KEY_HUGGINGFACE_LEN);
    for (size_t i = 0; i < ENCRYPTED_KEY_HUGGINGFACE_LEN; i++) {
        result += static_cast<char>(
            ENCRYPTED_KEY_HUGGINGFACE[i] ^
            XOR_KEY_HUGGINGFACE[i % XOR_KEY_HUGGINGFACE_LEN]
        );
    }
    return result;
}

// ── JNI Entry Point ──

JNIEXPORT jstring JNICALL
Java_com_tryon_clothesai_NativeApiKeyProvider_getApiKey(JNIEnv *env,
                                                        jobject thiz,
                                                        jstring providerName) {
  if (providerName == nullptr) {
    return env->NewStringUTF("");
  }

  const char *pName = env->GetStringUTFChars(providerName, nullptr);
  std::string provider(pName ? pName : "");
  if (pName) {
    env->ReleaseStringUTFChars(providerName, pName);
  }

  if (provider == "huggingface") {
    std::string key = decode_huggingface_key();
    return env->NewStringUTF(key.c_str());
  }

  return env->NewStringUTF("");
}
