import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../ai_service.dart';
import '../rate_limiter.dart';
import '../../constants/app_constants.dart';

/// Replicate Virtual Try-On service using the
/// [yisol/idm-vton](https://replicate.com/yisol/idm-vton) model.
///
/// Unlike the HuggingFace Gradio SSE-polling approach, Replicate provides a
/// straightforward REST API:
///
/// 1. **Create prediction** via `POST /v1/models/{owner}/{name}/predictions`
///    with input images as base64 data URIs.
/// 2. **Poll** `GET /v1/predictions/{id}` until status is `succeeded` or `failed`.
/// 3. **Download** the result image from the output URL.
///
/// ### Rate limiting & retries
/// - Shared singleton [RateLimiter] keeps all instances under API quotas.
/// - Exponential backoff on 429 (rate-limit) responses.
///
/// ### Authentication
/// - Bearer token authentication via `Authorization: Bearer <api_key>` header.
/// - API key can be obtained from [replicate.com/account/api-tokens](https://replicate.com/account/api-tokens).
class ReplicateService implements AiService {
  final Dio _dio;
  String _apiKey;
  final String _modelReference;

  /// Default model — [yisol/idm-vton](https://replicate.com/yisol/idm-vton)
  /// is a well-known Virtual Try-On model available on Replicate.
  static const String defaultModelId = 'yisol/idm-vton';

  /// Shared rate limiter across all instances.
  static final RateLimiter _rateLimiter = RateLimiter();

  /// Maximum time to wait for a prediction to complete (milliseconds).
  static const int _maxPollTimeMs = 120000; // 2 minutes

  /// Interval between status polls (milliseconds).
  static const int _pollIntervalMs = 2000;

  @override
  bool get isAvailable => _apiKey.isNotEmpty;

  /// Create a Replicate try-on service.
  ///
  /// [apiKey] is your Replicate API token from replicate.com/account/api-tokens.
  /// [modelId] is the Replicate model reference (default: `yisol/idm-vton`).
  ReplicateService({
    String apiKey = '',
    Dio? dio,
    String modelId = defaultModelId,
  }) : _apiKey = apiKey,
       _modelReference = modelId,
       _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 30),
               receiveTimeout: AppConstants.aiRequestTimeout,
               headers: {
                 'Authorization': 'Bearer $apiKey',
                 'Content-Type': 'application/json',
               },
             ),
           );

  /// Allow updating the API key at runtime.
  void updateApiKey(String newKey) {
    _apiKey = newKey;
    _dio.options.headers['Authorization'] = 'Bearer $newKey';
  }

  // ── URL helpers ──────────────────────────────────────────────────────────

  /// Convert `"owner/name"` → `"https://api.replicate.com/v1/models/owner/name/predictions"`.
  String _createPredictionUrl() {
    return 'https://api.replicate.com/v1/models/$_modelReference/predictions';
  }

  /// Get the prediction status URL.
  String _predictionStatusUrl(String id) {
    return 'https://api.replicate.com/v1/predictions/$id';
  }

  // ── Image encoding ───────────────────────────────────────────────────────

  /// Convert image bytes to a base64 data URI for sending to Replicate.
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
    final garmentDesc = options['description'] ?? category.replaceAll('_', ' ');
    // auto_mask/crop default to true to preserve the person's face/body.
    // IDM-VTON on Replicate supports both parameters.
    final autoMask = options['auto_mask'] != 'false'; // default true
    final crop = options['crop'] == 'true'; // default false to preserve natural body bounds

    // ── Retry loop ──────────────────────────────────────────────────────────
    const maxRetries = RateLimiter.maxRetries;

    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        // ---- wait for a rate-limit slot before each attempt ----
        await _rateLimiter.waitForSlot();

        // ---- Step 1: Encode images as data URIs ----
        final humanDataUri = _imageToDataUri(personImage);
        final garmentDataUri = _imageToDataUri(clothesImage);

        // ---- Step 2: Create prediction ----
        final createUrl = _createPredictionUrl();
        final payload = {
          'input': {
            'human_img': humanDataUri,
            'garm_img': garmentDataUri,
            'garment_des': garmentDesc,
            'category': category,
            'crop': crop,
            'steps': 30,
            'human_image': humanDataUri,
            'garment_image': garmentDataUri,
            'description': garmentDesc,
            'auto_mask': autoMask,
          },
        };

        final createResponse = await _dio.post<Map<String, dynamic>>(
          createUrl,
          data: payload,
        );

        final predictionData = createResponse.data;
        if (predictionData == null) {
          throw AiServiceException(
            'Replicate returned an empty response when creating the prediction.',
            modelId: _modelReference,
          );
        }

        final predictionId = predictionData['id'] as String?;
        if (predictionId == null || predictionId.isEmpty) {
          throw AiServiceException(
            'Replicate did not return a prediction ID. '
            'Response: $predictionData',
            modelId: _modelReference,
          );
        }

        // ---- Step 3: Poll for completion ----
        final resultUrl = await _pollForResult(predictionId);

        stopwatch.stop();

        if (resultUrl == null || resultUrl.isEmpty) {
          throw AiServiceException(
            'Replicate prediction completed but no output URL was returned.',
            modelId: _modelReference,
            processingTime: stopwatch.elapsed,
          );
        }

        // ---- Step 4: Download the result image ----
        final imageBytes = await _downloadImage(resultUrl);

        if (imageBytes.isEmpty) {
          throw AiServiceException(
            'Downloaded result image is empty.',
            modelId: _modelReference,
            processingTime: stopwatch.elapsed,
          );
        }

        // ---- Success — reset error counter ----
        _rateLimiter.markSuccess();

        return AiGenerationResult(
          imageBytes: imageBytes,
          modelUsed: _modelReference,
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

        // ── Payment required (402) → no retry, clear message ──
        if (statusCode == 402) {
          stopwatch.stop();
          throw AiServiceException(
            'Replicate account payment is required. '
            'Please add billing at replicate.com/account/billing.',
            statusCode: statusCode,
            modelId: _modelReference,
            processingTime: stopwatch.elapsed,
          );
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
              'Access denied. Your Replicate API token may be invalid. '
              'Get a token at replicate.com/account/api-tokens.';
        } else if (statusCode == 429) {
          errorMessage =
              'Rate limit exceeded after retries. '
              'Please wait a moment and try again.';
        } else if (statusCode != null && statusCode >= 500) {
          errorMessage =
              'Replicate server error ($statusCode): '
              '${serverMsg ?? 'The service may be temporarily unavailable.'}';
        } else {
          errorMessage =
              'Replicate API error ($statusCode): '
              '${serverMsg ?? e.message}';
        }

        throw AiServiceException(
          errorMessage,
          statusCode: statusCode,
          modelId: _modelReference,
          processingTime: stopwatch.elapsed,
        );
      } catch (e) {
        // Don't wrap AiServiceException again
        if (e is AiServiceException) rethrow;

        stopwatch.stop();
        throw AiServiceException(
          'Unexpected error: ${e.toString()}',
          modelId: _modelReference,
          processingTime: stopwatch.elapsed,
        );
      }
    }

    // Should never reach here, but just in case:
    stopwatch.stop();
    throw AiServiceException(
      'Generation failed after $maxRetries retries.',
      modelId: _modelReference,
      processingTime: stopwatch.elapsed,
    );
  }

  // ── Polling ──────────────────────────────────────────────────────────────

  /// Poll the prediction status until it completes or fails.
  ///
  /// Returns the output URL on success, or throws [AiServiceException] on failure.
  Future<String?> _pollForResult(String predictionId) async {
    final statusUrl = _predictionStatusUrl(predictionId);
    final deadline = DateTime.now().millisecondsSinceEpoch + _maxPollTimeMs;

    while (DateTime.now().millisecondsSinceEpoch < deadline) {
      await Future.delayed(const Duration(milliseconds: _pollIntervalMs));

      try {
        final response = await _dio.get<Map<String, dynamic>>(
          statusUrl,
          options: Options(
            headers: {'Authorization': 'Bearer $_apiKey'},
            responseType: ResponseType.json,
          ),
        );

        final data = response.data;
        if (data == null) {
          continue;
        }

        final status = data['status'] as String?;

        if (status == 'succeeded') {
          // Output can be a string (single image URL), a list, or null
          final output = data['output'];
          if (output is String && output.isNotEmpty) {
            return output;
          }
          if (output is List && output.isNotEmpty) {
            final first = output[0];
            if (first is String && first.isNotEmpty) {
              return first;
            }
          }
          // Succeeded but no output — might be a metric value
          return null;
        }

        if (status == 'failed') {
          final error =
              data['error'] as String? ??
              data['detail'] as String? ??
              'Unknown error';
          throw AiServiceException(
            'Replicate prediction failed: $error',
            modelId: _modelReference,
          );
        }

        if (status == 'canceled') {
          throw AiServiceException(
            'Replicate prediction was canceled.',
            modelId: _modelReference,
          );
        }

        // 'starting' or 'processing' — continue polling
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
      'Replicate prediction timed out after ${_maxPollTimeMs ~/ 1000} seconds. '
      'The model may be overloaded. Please try again.',
      modelId: _modelReference,
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
        modelId: _modelReference,
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
