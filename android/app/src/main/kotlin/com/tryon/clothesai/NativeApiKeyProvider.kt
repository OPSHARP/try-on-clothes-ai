package com.tryon.clothesai

/**
 * JNI bridge to the native C++ library (api_key_provider).
 * Loads the native .so and exposes the getApiKey function to Kotlin.
 */
class NativeApiKeyProvider {

    companion object {
        init {
            System.loadLibrary("api_key_provider")
        }
    }

    /**
     * Returns the XOR-decoded API key for the given provider.
     *
     * @param providerName "huggingface" or "replicate"
     * @return decoded API key string, or empty string if not configured
     */
    external fun getApiKey(providerName: String): String
}
