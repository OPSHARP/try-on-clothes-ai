import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../ai_service.dart';
import '../rate_limiter.dart';
import '../../constants/app_constants.dart';

/// A generic custom API service that sends images to a user-provided
/// endpoint URL with their own API key.
///
/// The expected request format is:
/// ```json
/// {
///   "person_image": "<base64>",
///   "clothes_image": "<base64>",
///   "options": { ... }
/// }
/// ```
///
/// The expected response format is:
/// ```json
/// {
///   "result_image": "<base64>"
/// }
/// ```
///
/// Users configure the [endpointUrl] and [apiKey] in the Settings screen.
class CustomApiService implements AiService {
  final Dio _dio;
  String _apiKey;
  String _endpointUrl;

  /// Shared rate limiter across all instances.
  static final RateLimiter _rateLimiter = RateLimiter();

  @override
  bool get isAvailable {
    if (_apiKey.isEmpty || _endpointUrl.isEmpty) return false;
    final uri = Uri.tryParse(_endpointUrl);
    return uri != null &&
        (uri.isScheme('https') || uri.isScheme('http')) &&
        uri.hasAuthority;
  }

  /// Create a custom API service.
  ///
  /// [endpointUrl] is the full URL of the image generation endpoint.
  /// [apiKey] is the API key (if required by the endpoint).
  CustomApiService({String apiKey = '', String endpointUrl = '', Dio? dio})
    : _apiKey = apiKey,
      _endpointUrl = endpointUrl,
      _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 30),
              receiveTimeout: AppConstants.aiRequestTimeout,
              headers: {'Content-Type': 'application/json'},
            ),
          );

  /// Update the API key at runtime.
  void updateApiKey(String newKey) {
    _apiKey = newKey;
  }

  /// Update the endpoint URL at runtime.
  void updateEndpointUrl(String url) {
    _endpointUrl = url;
  }

  @override
  Future<AiGenerationResult> generateTryOn({
    required Uint8List personImage,
    required Uint8List clothesImage,
    Map<String, String> options = const {},
  }) async {
    if (!isAvailable) {
      throw AiServiceException(
        'Custom API is not configured. '
        'Please set the endpoint URL and API key in Settings.',
      );
    }

    await _rateLimiter.waitForSlot();

    try {
      // Build request payload using the standard interface options.
      final payload = <String, dynamic>{
        'person_image': base64Encode(personImage),
        'clothes_image': base64Encode(clothesImage),
      };
      if (options.isNotEmpty) {
        payload['options'] = options;
      }

      final headers = <String, dynamic>{'Content-Type': 'application/json'};
      if (_apiKey.isNotEmpty) {
        headers['Authorization'] = 'Bearer $_apiKey';
      }

      final stopwatch = Stopwatch()..start();

      final response = await _dio.post(
        _endpointUrl,
        data: payload,
        options: Options(headers: headers),
      );

      stopwatch.stop();

      if (response.statusCode != 200) {
        throw AiServiceException(
          'Custom API returned status ${response.statusCode}',
          statusCode: response.statusCode ?? 0,
          modelId: 'custom',
          processingTime: stopwatch.elapsed,
        );
      }

      final data = response.data;
      if (data is Map<String, dynamic>) {
        // Supports: 'result_image', 'image', 'output', or direct base64 string.
        final resultImageStr =
            (data['result_image'] ?? data['image'] ?? data['output'])
                as String?;

        if (resultImageStr == null || resultImageStr.isEmpty) {
          throw AiServiceException(
            'Custom API response did not contain a result image. '
            'Expected key: "result_image", "image", or "output".',
            statusCode: 0,
            modelId: 'custom',
            processingTime: stopwatch.elapsed,
          );
        }

        Uint8List imageBytes;
        try {
          imageBytes = base64Decode(resultImageStr);
        } catch (e) {
          throw AiServiceException(
            'Custom API returned invalid base64-encoded image data: $e',
            statusCode: 0,
            modelId: 'custom',
            processingTime: stopwatch.elapsed,
          );
        }

        return AiGenerationResult(
          imageBytes: imageBytes,
          modelUsed: 'custom',
          processingTime: stopwatch.elapsed,
        );
      }

      throw AiServiceException(
        'Custom API returned unexpected format. '
        'Expected a JSON object, got ${data.runtimeType}.',
        statusCode: 0,
        modelId: 'custom',
        processingTime: stopwatch.elapsed,
      );
    } on DioException catch (e) {
      throw AiServiceException(
        'Custom API request failed: ${e.message}',
        statusCode: e.response?.statusCode ?? 0,
        modelId: 'custom',
      );
    }
  }

  @override
  void dispose() {
    _dio.close();
  }
}
