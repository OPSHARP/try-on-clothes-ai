import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Service that interacts with the native C++ library via JNI / MethodChannel
/// to obtain XOR-obfuscated pre-configured API keys.
class NativeKeyService {
  static const MethodChannel _channel = MethodChannel(
    'com.tryon.clothesai/native_api_key',
  );

  static final Map<String, String> _cachedKeys = {};

  /// Retrieves the native bundled API key for the given provider.
  /// Returns empty string if no native key exists or on error.
  static Future<String> getBundledApiKey(String provider) async {
    if (_cachedKeys.containsKey(provider)) {
      return _cachedKeys[provider]!;
    }

    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return '';
    }

    try {
      final String? key = await _channel.invokeMethod<String>('getApiKey', {
        'provider': provider,
      });
      final result = key ?? '';
      _cachedKeys[provider] = result;
      return result;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('NativeKeyService: could not fetch native key for $provider: $e');
      }
      return '';
    }
  }

  /// Queries the Android device's highest hardware refresh rate (e.g. 120Hz, 144Hz, 90Hz, 60Hz).
  static Future<double> getMaxFps() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return 60.0;
    }
    try {
      final double? fps = await _channel.invokeMethod<double>('getMaxFps');
      return fps ?? 60.0;
    } catch (_) {
      return 60.0;
    }
  }
}
