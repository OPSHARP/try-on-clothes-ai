import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../ai_service.dart';
import '../rate_limiter.dart';
import '../../constants/app_constants.dart';

/// Fal.ai Virtual Try-On service.
///
/// Fal.ai offers a dedicated Virtual Try-On model accessible via
/// a straightforward REST API:
///
/// 1. **Submit generation** via `POST /fal-ai/virtual-try-on`
///    with images encoded as base64 data URIs.
/// 2. **Poll** the response URL until status is `COMPLETED` or `FAILED`.
/// 3. **Download** the result image from the output URL.
///
/// ### Rate limiting & retries
/// - Shared singleton [RateLimiter] keeps all instances under API quotas.
/// - Exponential backoff on 429 (rate-limit) responses.
///
/// ### Authentication
/// - API key sent via `Authorization: Key <api_key>` header.
/// - Get your key at [fal.ai/dashboard/api-keys](https://fal.ai/dashboard/api-keys).
class FalAiService implements AiService {
  final Dio _dio;
  String _apiKey;

  /// Default model reference.
  static const String defaultModelId = 'fal-ai/virtual-try-on';

  /// Shared rate limiter across all instances.
  static final RateLimiter _rateLimiter = RateLimiter();

  /// Maximum time to wait for a prediction to complete (milliseconds).
  static const int _maxPollTimeMs = 120000; // 2 minutes

  /// Interval between status polls (milliseconds).
  static const int _pollIntervalMs = 2000;

  @override
  bool get isAvailable => _apiKey.isNotEmpty;

  /// Create a Fal.ai try-on service.
  ///
  /// [apiKey] is your Fal.ai API key from fal.ai/dashboard/api-keys.
  /// [modelId] is the Fal.ai model path (default: `fal-ai/virtual-try-on`).
  FalAiService({String apiKey = '', Dio? dio, String modelId = defaultModelId})
    : _apiKey = apiKey,
      _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 30),
              receiveTimeout: AppConstants.aiRequestTimeout,
              baseUrl: 'https://fal.run',
              headers: {
                'Authorization': 'Key $apiKey',
                'Content-Type': 'application/json',
              },
            ),
          );

  /// Allow updating the API key at runtime.
  void updateApiKey(String newKey) {
    _apiKey = newKey;
    _dio.options.headers['Authorization'] = 'Key $newKey';
  }

  // ── Image encoding ───────────────────────────────────────────────────────

  /// Convert image bytes to a base64 data URI for sending to Fal.ai.
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

    // Extract options relevant to VTON
    final category = options['category'] ?? 'upper_body';

    // ── Retry loop ──────────────────────────────────────────────────────────
    const maxRetries = RateLimiter.maxRetries;

    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        // ---- wait for a rate-limit slot before each attempt ----
        await _rateLimiter.waitForSlot();

        // ---- Step 1: Encode images as data URIs ----
        final personDataUri = _imageToDataUri(personImage);
        final garmentDataUri = _imageToDataUri(clothesImage);

        // ---- Step 2: Create prediction ----
        // Read masking/cropping options from the options map (default: both enabled
        // to preserve the person's face/body and improve garment fit).
        final enableAutoMask = options['auto_mask'] != 'false'; // default true
        final enableGarmentCrop = options['crop'] != 'false'; // default true
        final garmentDesc =
            options['description'] ?? category.replaceAll('_', ' ');
        final payload = {
          'person_image_url': personDataUri,
          'garment_image_url': garmentDataUri,
          'category': category,
          'description': garmentDesc,
          'enable_auto_mask': enableAutoMask,
          'enable_garment_crop': enableGarmentCrop,
        };

        final createResponse = await _dio.post<Map<String, dynamic>>(
          '/$defaultModelId',
          data: payload,
        );

        final responseData = createResponse.data;
        if (responseData == null) {
          throw AiServiceException(
            'Fal.ai returned an empty response.',
            modelId: defaultModelId,
          );
        }

        // Fal.ai returns either a direct result or a request_id to poll
        final requestId = responseData['request_id'] as String?;
        if (requestId != null && requestId.isNotEmpty) {
          // ---- Step 3a: Async mode — poll for result ----
          final imageUrl = await _pollForResult(requestId);
          stopwatch.stop();

          if (imageUrl == null || imageUrl.isEmpty) {
            throw AiServiceException(
              'Fal.ai request completed but no image URL was returned.',
              modelId: defaultModelId,
              processingTime: stopwatch.elapsed,
            );
          }

          // ---- Step 4a: Download the result image ----
          final imageBytes = await _downloadImage(imageUrl);
          if (imageBytes.isEmpty) {
            throw AiServiceException(
              'Downloaded result image is empty.',
              modelId: defaultModelId,
              processingTime: stopwatch.elapsed,
            );
          }

          _rateLimiter.markSuccess();
          return AiGenerationResult(
            imageBytes: imageBytes,
            modelUsed: defaultModelId,
            processingTime: stopwatch.elapsed,
          );
        } else {
          // ---- Step 3b: Sync mode — result is in the response ----
          final output = responseData['output'] as Map<String, dynamic>?;
          if (output != null) {
            final imageUrl =
                output['image'] as String? ?? output['image_url'] as String?;
            if (imageUrl != null && imageUrl.isNotEmpty) {
              stopwatch.stop();
              final imageBytes = await _downloadImage(imageUrl);
              if (imageBytes.isEmpty) {
                throw AiServiceException(
                  'Downloaded result image is empty.',
                  modelId: defaultModelId,
                  processingTime: stopwatch.elapsed,
                );
              }

              _rateLimiter.markSuccess();
              return AiGenerationResult(
                imageBytes: imageBytes,
                modelUsed: defaultModelId,
                processingTime: stopwatch.elapsed,
              );
            }
          }

          // Check if the image is embedded directly as base64
          final imageBase64 =
              responseData['image'] as String? ??
              responseData['base64'] as String?;
          if (imageBase64 != null && imageBase64.isNotEmpty) {
            stopwatch.stop();
            try {
              final imageBytes = base64Decode(imageBase64);
              _rateLimiter.markSuccess();
              return AiGenerationResult(
                imageBytes: Uint8List.fromList(imageBytes),
                modelUsed: defaultModelId,
                processingTime: stopwatch.elapsed,
              );
            } catch (_) {
              throw AiServiceException(
                'Fal.ai returned invalid base64 image data.',
                modelId: defaultModelId,
                processingTime: stopwatch.elapsed,
              );
            }
          }

          throw AiServiceException(
            'Fal.ai response did not contain a result image or request_id. '
            'Response: $responseData',
            modelId: defaultModelId,
            processingTime: stopwatch.elapsed,
          );
        }
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
          serverMsg = body['detail'] as String? ?? body['error'] as String?;
        } else if (e.response?.data is String) {
          serverMsg = e.response!.data as String;
        }

        if (statusCode == 400) {
          errorMessage =
              'Invalid request: '
              '${serverMsg ?? 'The image format or parameters may be invalid.'}';
        } else if (statusCode == 401 || statusCode == 403) {
          errorMessage =
              'Access denied. Your Fal.ai API key may be invalid. '
              'Get a key at fal.ai/dashboard/api-keys.';
        } else if (statusCode == 429) {
          errorMessage =
              'Rate limit exceeded after retries. '
              'Please wait a moment and try again.';
        } else if (statusCode != null && statusCode >= 500) {
          errorMessage =
              'Fal.ai server error ($statusCode): '
              '${serverMsg ?? 'The service may be temporarily unavailable.'}';
        } else {
          errorMessage =
              'Fal.ai API error ($statusCode): '
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

  // ── Polling ──────────────────────────────────────────────────────────────

  /// Poll the request status until it completes or fails.
  ///
  /// Returns the image URL on success, or throws [AiServiceException] on failure.
  Future<String?> _pollForResult(String requestId) async {
    final statusUrl = '/$defaultModelId/requests/$requestId';
    final deadline = DateTime.now().millisecondsSinceEpoch + _maxPollTimeMs;

    while (DateTime.now().millisecondsSinceEpoch < deadline) {
      await Future.delayed(const Duration(milliseconds: _pollIntervalMs));

      try {
        final response = await _dio.get<Map<String, dynamic>>(
          statusUrl,
          options: Options(
            headers: {'Authorization': 'Key $_apiKey'},
            responseType: ResponseType.json,
          ),
        );

        final data = response.data;
        if (data == null) {
          continue;
        }

        final status = data['status'] as String?;

        if (status == 'COMPLETED' || status == 'SUCCEEDED') {
          final output = data['output'] as Map<String, dynamic>?;
          if (output != null) {
            final imageUrl =
                output['image'] as String? ?? output['image_url'] as String?;
            if (imageUrl != null && imageUrl.isNotEmpty) {
              return imageUrl;
            }
          }
          return null;
        }

        if (status == 'FAILED') {
          final error =
              data['error'] as String? ??
              data['detail'] as String? ??
              'Unknown error';
          throw AiServiceException(
            'Fal.ai request failed: $error',
            modelId: defaultModelId,
          );
        }

        if (status == 'CANCELED') {
          throw AiServiceException(
            'Fal.ai request was canceled.',
            modelId: defaultModelId,
          );
        }

        // 'IN_QUEUE' or 'PROCESSING' — continue polling
      } on DioException catch (e) {
        // Transient errors during polling — retry
        if (e.response?.statusCode == 429) {
          final delay = _rateLimiter.getBackoffDelay();
          await Future.delayed(Duration(milliseconds: delay));
          continue;
        }
        rethrow;
      }
    }

    throw AiServiceException(
      'Fal.ai request timed out after ${_maxPollTimeMs ~/ 1000} seconds. '
      'The model may be overloaded. Please try again.',
      modelId: defaultModelId,
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
