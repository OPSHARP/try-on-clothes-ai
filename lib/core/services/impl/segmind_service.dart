import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../ai_service.dart';
import '../rate_limiter.dart';
import '../../constants/app_constants.dart';

/// Segmind Virtual Try-On service.
///
/// Segmind provides a dedicated [Virtual Try-On API](https://www.segmind.com/models/virtual-try-on)
/// that takes a person image and a garment image, then produces a photo-realistic
/// output of the person wearing the selected garment.
///
/// ### API Details
/// - **Base URL**: `https://api.segmind.com/v1`
/// - **Authentication**: `x-api-key: <your_api_key>` header
/// - **Try-On Endpoint**: `POST /try-on-diffusion`
/// - **Input**: Person image (full body), garment image (flat or on-model)
/// - **Output**: JSON with `image` field containing a base64-encoded PNG string
///
/// ### Rate limiting & retries
/// - Shared singleton [RateLimiter] keeps all instances under API quotas.
/// - Exponential backoff on 429 (rate-limit) responses.
///
/// ### Authentication
/// - API key header (`x-api-key`) obtained from [segmind.com/api-keys](https://www.segmind.com/api-keys).
class SegmindService implements AiService {
  final Dio _dio;
  String _apiKey;

  /// Default model ID for Segmind Virtual Try-On.
  static const String defaultModelId = 'try-on-diffusion';

  /// Shared rate limiter across all instances.
  static final RateLimiter _rateLimiter = RateLimiter();

  @override
  bool get isAvailable => _apiKey.isNotEmpty;

  /// Create a Segmind try-on service.
  ///
  /// [apiKey] is your Segmind API key from segmind.com/api-keys.
  /// [modelId] specifies which Segmind model to use (default: `try-on-diffusion`).
  SegmindService({
    String apiKey = '',
    Dio? dio,
    String modelId = defaultModelId,
  }) : _apiKey = apiKey,
       _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 30),
               receiveTimeout: AppConstants.aiRequestTimeout,
               baseUrl: 'https://api.segmind.com/v1',
               headers: {
                 'x-api-key': apiKey,
                 'Content-Type': 'application/json',
               },
             ),
           );

  /// Allow updating the API key at runtime.
  void updateApiKey(String newKey) {
    _apiKey = newKey;
    _dio.options.headers['x-api-key'] = newKey;
  }

  // ── Image encoding ───────────────────────────────────────────────────────

  /// Convert image bytes to a base64 data URI for sending to Segmind.
  String _imageToDataUri(Uint8List bytes, {String mimeType = 'image/png'}) {
    final base64Str = base64Encode(bytes);
    return 'data:$mimeType;base64,$base64Str';
  }

  // ── Core generation ──────────────────────────────────────────────────────

  @override
  Future<AiGenerationResult> generateTryOn({
    required Uint8List personImage,
    required Uint8List clothesImage,
    Map<String, String> options = const {},
  }) async {
    final stopwatch = Stopwatch()..start();

    // Extract options and map category to Segmind's expected format ("Upper body", "Lower body", "Dress")
    final category = options['category'] ?? 'upper_body';
    final segmindCategory = category == 'lower_body'
        ? 'Lower body'
        : category == 'dresses'
            ? 'Dress'
            : 'Upper body';
    final garmentDesc = options['description'] ?? category.replaceAll('_', ' ');

    // ── Retry loop ──────────────────────────────────────────────────────────
    const maxRetries = RateLimiter.maxRetries;

    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        // ---- wait for a rate-limit slot before each attempt ----
        await _rateLimiter.waitForSlot();

        // ---- Step 1: Encode images as data URIs ----
        final personDataUri = _imageToDataUri(personImage);
        final garmentDataUri = _imageToDataUri(clothesImage);

        // ---- Step 2: Create generation request ----
        // Segmind Try-On Diffusion parameters: model_image, cloth_image, category, base64: true
        final payload = {
          'model_image': personDataUri,
          'cloth_image': garmentDataUri,
          'category': segmindCategory,
          'base64': true,
          'num_inference_steps': 30,
          // Fallback aliases for other Segmind models
          'person_image': personDataUri,
          'description': garmentDesc,
        };

        final response = await _dio.post<Map<String, dynamic>>(
          '/$defaultModelId',
          data: payload,
        );

        final data = response.data;
        if (data == null) {
          throw AiServiceException(
            'Segmind returned an empty response.',
            modelId: defaultModelId,
          );
        }

        // ---- Step 3: Extract the result image ----
        // Segmind returns the image as a base64 string in the `image` field,
        // or sometimes as a URL in the `output` field.
        Uint8List? imageBytes;

        final imageField = data['image'];
        if (imageField is String && imageField.isNotEmpty) {
          // Base64-encoded image (strip data URI prefix if present)
          String base64Str = imageField;
          if (base64Str.contains(',')) {
            base64Str = base64Str.split(',').last;
          }
          try {
            imageBytes = base64Decode(base64Str);
          } catch (_) {
            // Not valid base64, maybe it's a URL
          }
        }

        // Fallback: check for output field (URL or base64)
        if ((imageBytes == null || imageBytes.isEmpty) &&
            data['output'] != null) {
          final output = data['output'];
          if (output is String && output.isNotEmpty) {
            if (output.startsWith('http')) {
              // It's a URL — download it
              imageBytes = await _downloadImage(output);
            } else {
              // It's base64
              String base64Str = output;
              if (base64Str.contains(',')) {
                base64Str = base64Str.split(',').last;
              }
              try {
                imageBytes = base64Decode(base64Str);
              } catch (_) {}
            }
          } else if (output is List && output.isNotEmpty) {
            final first = output[0];
            if (first is String && first.startsWith('http')) {
              imageBytes = await _downloadImage(first);
            }
          }
        }

        // Fallback: images array
        if ((imageBytes == null || imageBytes.isEmpty) &&
            data['images'] != null) {
          final images = data['images'];
          if (images is List && images.isNotEmpty) {
            final first = images[0];
            if (first is String) {
              String base64Str = first;
              if (base64Str.contains(',')) {
                base64Str = base64Str.split(',').last;
              }
              try {
                imageBytes = base64Decode(base64Str);
              } catch (_) {}
            }
          }
        }

        if (imageBytes == null || imageBytes.isEmpty) {
          stopwatch.stop();
          throw AiServiceException(
            'Segmind generation completed but no output image was found in the response.',
            modelId: defaultModelId,
            processingTime: stopwatch.elapsed,
          );
        }

        stopwatch.stop();

        // ---- Success — reset error counter ----
        _rateLimiter.markSuccess();

        return AiGenerationResult(
          imageBytes: imageBytes,
          modelUsed: defaultModelId,
          processingTime: stopwatch.elapsed,
        );
      } on DioException catch (e) {
        final statusCode = e.response?.statusCode;

        // ── Rate-limited (429) → exponential backoff & retry ──
        if (statusCode == 429 && attempt < maxRetries) {
          final delay = _rateLimiter.getBackoffDelay();
          await Future.delayed(Duration(milliseconds: delay));
          continue;
        }

        // ── Non-retryable or exhausted retries → throw ──
        stopwatch.stop();
        String errorMessage;

        // Extract error text from response body if possible
        String? serverMsg;
        if (e.response?.data is Map) {
          final body = e.response!.data as Map;
          serverMsg =
              body['error'] as String? ??
              body['message'] as String? ??
              body['detail'] as String?;
        } else if (e.response?.data is String) {
          serverMsg = e.response!.data as String;
        }

        if (statusCode == 400) {
          errorMessage =
              'Invalid request: '
              '${serverMsg ?? 'The image format or parameters may be invalid.'}';
        } else if (statusCode == 401 || statusCode == 403) {
          errorMessage =
              'Access denied. Your Segmind API key may be invalid. '
              'Get a key at segmind.com/api-keys.';
        } else if (statusCode == 429) {
          errorMessage =
              'Rate limit exceeded after retries. '
              'Please wait a moment and try again.';
        } else if (statusCode != null && statusCode >= 500) {
          errorMessage =
              'Segmind server error ($statusCode): '
              '${serverMsg ?? 'The service may be temporarily unavailable.'}';
        } else {
          errorMessage =
              'Segmind API error ($statusCode): '
              '${serverMsg ?? e.message}';
        }

        throw AiServiceException(
          errorMessage,
          statusCode: statusCode,
          modelId: defaultModelId,
          processingTime: stopwatch.elapsed,
        );
      } catch (e) {
        // Don't wrap AiServiceException again
        if (e is AiServiceException) rethrow;

        stopwatch.stop();
        throw AiServiceException(
          'Unexpected error: ${e.toString()}',
          modelId: defaultModelId,
          processingTime: stopwatch.elapsed,
        );
      }
    }

    // Should never reach here, but just in case:
    stopwatch.stop();
    throw AiServiceException(
      'Generation failed after $maxRetries retries.',
      modelId: defaultModelId,
      processingTime: stopwatch.elapsed,
    );
  }

  // ── Image download ───────────────────────────────────────────────────────

  /// Download an image from a URL.
  Future<Uint8List> _downloadImage(String url) async {
    final response = await _dio.get<List<int>>(
      url,
      options: Options(responseType: ResponseType.bytes),
    );

    if (response.data == null || response.data!.isEmpty) {
      throw AiServiceException(
        'Failed to download result image (empty response).',
        modelId: defaultModelId,
      );
    }

    return Uint8List.fromList(response.data!);
  }

  // ── Lifecycle ────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _dio.close();
  }
}
