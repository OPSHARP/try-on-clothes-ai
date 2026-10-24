import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../ai_service.dart';
import '../rate_limiter.dart';
import '../../constants/app_constants.dart';

/// Fashn.ai Dedicated Virtual Try-On Service.
///
/// Fashn.ai is the industry-leading specialized AI Virtual Try-On API
/// specifically built for high-precision garment transfer and apparel try-on.
///
/// ### API Flow
/// 1. Submit prediction via `POST /run` with base64 data URIs.
/// 2. Poll `GET /status/{id}` until status is `completed`.
/// 3. Download the high-fidelity output image.
class FashnService implements AiService {
  final Dio _dio;
  String _apiKey;

  static const String defaultBaseUrl = 'https://api.fashn.ai/v1';
  static final RateLimiter _rateLimiter = RateLimiter();
  static const int _maxPollTimeMs = 120000;
  static const int _pollIntervalMs = 2500;

  @override
  bool get isAvailable => _apiKey.isNotEmpty;

  FashnService({String apiKey = '', Dio? dio})
      : _apiKey = apiKey,
        _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 30),
                receiveTimeout: AppConstants.aiRequestTimeout,
                baseUrl: defaultBaseUrl,
                headers: {
                  'Authorization': 'Bearer $apiKey',
                  'Content-Type': 'application/json',
                },
              ),
            );

  void updateApiKey(String newKey) {
    _apiKey = newKey;
    _dio.options.headers['Authorization'] = 'Bearer $newKey';
  }

  String _imageToDataUri(Uint8List bytes, {String mimeType = 'image/png'}) {
    final base64Str = base64Encode(bytes);
    return 'data:$mimeType;base64,$base64Str';
  }

  @override
  Future<AiGenerationResult> generateTryOn({
    required Uint8List personImage,
    required Uint8List clothesImage,
    Map<String, String> options = const {},
  }) async {
    final stopwatch = Stopwatch()..start();
    final rawCategory = options['category'] ?? 'upper_body';
    
    // Map to Fashn category: 'tops', 'bottoms', 'one-pieces'
    String fashnCategory = 'tops';
    if (rawCategory == 'lower_body') {
      fashnCategory = 'bottoms';
    } else if (rawCategory == 'dresses') {
      fashnCategory = 'one-pieces';
    }

    const maxRetries = RateLimiter.maxRetries;

    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        await _rateLimiter.waitForSlot();

        final modelDataUri = _imageToDataUri(personImage);
        final garmentDataUri = _imageToDataUri(clothesImage);

        // 1. Submit try-on request
        final runResponse = await _dio.post(
          '/run',
          data: {
            'model_image': modelDataUri,
            'garment_image': garmentDataUri,
            'category': fashnCategory,
            'nsfw_filter': true,
            'cover_feet': false,
            'adjust_hands': true,
            'restore_background': true,
          },
        );

        final runData = runResponse.data;
        final predictionId = runData is Map ? runData['id']?.toString() : null;

        if (predictionId == null || predictionId.isEmpty) {
          throw AiServiceException('Fashn.ai did not return a valid task ID.');
        }

        // 2. Poll for completion
        final outputUrl = await _pollPrediction(predictionId);

        // 3. Download the result image
        final downloadResponse = await _dio.get<List<int>>(
          outputUrl,
          options: Options(responseType: ResponseType.bytes),
        );

        final data = downloadResponse.data;
        if (data == null || data.isEmpty) {
          throw AiServiceException('Downloaded result image from Fashn.ai is empty.');
        }

        final imageBytes = Uint8List.fromList(data);
        stopwatch.stop();

        _rateLimiter.markSuccess();
        return AiGenerationResult(
          imageBytes: imageBytes,
          modelUsed: 'fashn.ai/v1',
          processingTime: stopwatch.elapsed,
        );
      } on DioException catch (e) {
        if (e.response?.statusCode == 429 && attempt < maxRetries) {
          final delayMs = _rateLimiter.getBackoffDelay();
          await Future<void>.delayed(Duration(milliseconds: delayMs));
          continue;
        }
        throw _mapDioError(e, stopwatch.elapsed);
      } catch (e) {
        if (e is AiServiceException) rethrow;
        throw AiServiceException('Fashn.ai generation error: $e');
      }
    }

    throw AiServiceException('Fashn.ai generation timed out after retries.');
  }

  Future<String> _pollPrediction(String id) async {
    final start = DateTime.now();
    while (DateTime.now().difference(start).inMilliseconds < _maxPollTimeMs) {
      await Future<void>.delayed(const Duration(milliseconds: _pollIntervalMs));

      final response = await _dio.get('/status/$id');
      final data = response.data;
      if (data is! Map) continue;

      final status = (data['status'] ?? '').toString().toLowerCase();
      if (status == 'completed' || status == 'succeeded') {
        final output = data['output'];
        if (output is List && output.isNotEmpty) {
          return output.first.toString();
        } else if (output is String && output.isNotEmpty) {
          return output;
        }
        throw AiServiceException('Fashn.ai completed with no output URL.');
      } else if (status == 'failed') {
        final errorMsg = data['error'] ?? 'Task failed';
        throw AiServiceException('Fashn.ai processing failed: $errorMsg');
      }
    }
    throw AiServiceException('Fashn.ai processing timed out after 2 minutes.');
  }

  AiServiceException _mapDioError(DioException e, Duration elapsed) {
    final status = e.response?.statusCode;
    if (status == 401 || status == 403) {
      return AiServiceException(
        'Invalid Fashn.ai API key. Please check your key at fashn.ai.',
        statusCode: status,
        processingTime: elapsed,
      );
    }
    return AiServiceException(
      e.response?.data?.toString() ?? e.message ?? 'Fashn.ai network error',
      statusCode: status,
      processingTime: elapsed,
    );
  }

  @override
  void dispose() {
    _dio.close();
  }
}
