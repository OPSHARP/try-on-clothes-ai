// Native API Key Provider - Header
// Provides XOR-obfuscated API keys to the Flutter app via JNI.
// Keys are compiled into the .so binary as encoded byte arrays,
// making extraction significantly harder than plaintext strings.

#ifndef API_KEY_PROVIDER_H
#define API_KEY_PROVIDER_H

#include <jni.h>
#include <string>

extern "C" {

/**
 * Returns the XOR-decoded API key for the given provider name.
 *
 * @param env      JNI environment pointer
 * @param thiz     Java object reference
 * @param providerName  "huggingface" or "replicate"
 * @return         decoded API key string, or empty string if unknown provider
 */
JNIEXPORT jstring JNICALL
Java_com_tryon_clothesai_NativeApiKeyProvider_getApiKey(JNIEnv *env,
                                                        jobject thiz,
                                                        jstring providerName);

} // extern "C"

#endif // API_KEY_PROVIDER_H
