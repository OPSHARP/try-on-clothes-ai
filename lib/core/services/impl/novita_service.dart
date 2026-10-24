import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../ai_service.dart';
import '../rate_limiter.dart';
import '../../constants/app_constants.dart';

/// Novita AI Virtual Try-On Service.
///
/// Novita provides high-speed cloud GPU endpoints for IDM-VTON.
/// Documentation: https://novita.ai/docs
class NovitaService implements AiService {
  final Dio _dio;
  String _apiKey;

  static const String defaultBaseUrl = 'https://api.novita.ai/v3';
  static final RateLimiter _rateLimiter = RateLimiter();
  static const int _maxPollTimeMs = 120000;
  static const int _pollIntervalMs = 2000;

  @override
  bool get isAvailable => _apiKey.isNotEmpty;

  NovitaService({String apiKey = '', Dio? dio})
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

  String _imageToBase64(Uint8List bytes) {
    return base64Encode(bytes);
  }

  @override
  Future<AiGenerationResult> generateTryOn({
    required Uint8List personImage,
    required Uint8List clothesImage,
    Map<String, String> options = const {},
  }) async {
    final stopwatch = Stopwatch()..start();
    const maxRetries = RateLimiter.maxRetries;

    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        await _rateLimiter.waitForSlot();

        final modelB64 = _imageToBase64(personImage);
        final garmentB64 = _imageToBase64(clothesImage);

        // Novita async vton
        final response = await _dio.post(
          '/async/vton',
          data: {
            'model_image': 'data:image/png;base64,$modelB64',
            'cloth_image': 'data:image/png;base64,$garmentB64',
          },
        );

        final data = response.data;
        final taskId = data is Map ? (data['task_id'] ?? data['taskId'])?.toString() : null;

        if (taskId == null || taskId.isEmpty) {
          throw AiServiceException('Novita AI did not return a valid task ID.');
        }

        final outputUrl = await _pollTask(taskId);

        final downloadResponse = await _dio.get<List<int>>(
          outputUrl,
          options: Options(responseType: ResponseType.bytes),
        );

        final downloadBytes = downloadResponse.data;
        if (downloadBytes == null || downloadBytes.isEmpty) {
          throw AiServiceException('Downloaded result image from Novita AI is empty.');
        }

        final imageBytes = Uint8List.fromList(downloadBytes);
        stopwatch.stop();

        _rateLimiter.markSuccess();
        return AiGenerationResult(
          imageBytes: imageBytes,
          modelUsed: 'novita.ai/idm-vton',
          processingTime: stopwatch.elapsed,
        );
      } on DioException catch (e) {
        if (e.response?.statusCode == 429 && attempt < maxRetries) {
          final delayMs = _rateLimiter.getBackoffDelay();
          await Future<void>.delayed(Duration(milliseconds: delayMs));
          continue;
        }
        throw AiServiceException(
          e.response?.data?.toString() ?? e.message ?? 'Novita AI error',
          statusCode: e.response?.statusCode,
          processingTime: stopwatch.elapsed,
        );
      } catch (e) {
        if (e is AiServiceException) rethrow;
        throw AiServiceException('Novita AI generation error: $e');
      }
    }

    throw AiServiceException('Novita AI timed out after retries.');
  }

  Future<String> _pollTask(String taskId) async {
    final start = DateTime.now();
    while (DateTime.now().difference(start).inMilliseconds < _maxPollTimeMs) {
      await Future<void>.delayed(const Duration(milliseconds: _pollIntervalMs));

      final response = await _dio.get(
        '/async/task-result',
        queryParameters: {'task_id': taskId},
      );

      final data = response.data;
      if (data is! Map) continue;

      final status = (data['task']?['status'] ?? data['status'] ?? '').toString();
      if (status == 'TASK_STATUS_SUCCEED' || status.toLowerCase() == 'completed') {
        final images = data['images'] ?? data['task']?['images'];
        if (images is List && images.isNotEmpty) {
          final first = images.first;
          if (first is Map && first['image_url'] != null) {
            return first['image_url'].toString();
          } else if (first is String) {
            return first;
          }
        }
        throw AiServiceException('Novita AI returned success but missing image URL.');
      } else if (status == 'TASK_STATUS_FAILED' || status.toLowerCase() == 'failed') {
        final reason = data['task']?['reason'] ?? 'Task failed';
        throw AiServiceException('Novita AI processing failed: $reason');
      }
    }
    throw AiServiceException('Novita AI task timed out.');
  }

  @override
  void dispose() {
    _dio.close();
  }
}
