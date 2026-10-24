import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../ai_service.dart';
import '../rate_limiter.dart';
import '../../constants/app_constants.dart';

/// OpenAI (ChatGPT / DALL-E 3) Image Generation & Try-On Service.
///
/// Combines **GPT-4o Vision** and **DALL-E 3 HD**:
/// 1. **GPT-4o Vision**: Analyzes the person image (body type, pose, lighting)
///    and the clothing item (fabric weave, cut, neckline, color, patterns).
/// 2. **DALL-E 3 HD**: Renders a photorealistic portrait of the garment worn
///    with studio lighting, authentic folds, and ultra-high-definition texture.
class OpenAiService implements AiService {
  final Dio _dio;
  String _apiKey;

  static const String defaultBaseUrl = 'https://api.openai.com/v1';
  static final RateLimiter _rateLimiter = RateLimiter();

  @override
  bool get isAvailable => _apiKey.isNotEmpty && _apiKey.startsWith('sk-');

  OpenAiService({String apiKey = '', Dio? dio})
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

  /// Update the OpenAI API key at runtime.
  void updateApiKey(String newKey) {
    _apiKey = newKey;
    _dio.options.headers['Authorization'] = 'Bearer $newKey';
  }

  String _imageToDataUri(Uint8List bytes, {String mimeType = 'image/jpeg'}) {
    final base64Str = base64Encode(bytes);
    return 'data:$mimeType;base64,$base64Str';
  }

  @override
  Future<AiGenerationResult> generateTryOn({
    required Uint8List personImage,
    required Uint8List clothesImage,
    Map<String, String> options = const {},
  }) async {
    if (!isAvailable) {
      throw AiServiceException(
        'OpenAI API key is missing or invalid. Please configure your key (sk-...) in Settings.',
        modelId: 'openai-dall-e-3',
      );
    }

    final stopwatch = Stopwatch()..start();
    await _rateLimiter.waitForSlot();

    try {
      final category = options['category'] ?? 'upper_body';
      final style = options['style'] ?? 'realistic';
      final userDescription = options['description'] ?? '';

      // ── Step 1: GPT-4o Vision Fashion & Garment Analysis ──
      String dallEPrompt = await _analyzeGarmentWithGpt4o(
        personImage: personImage,
        clothesImage: clothesImage,
        category: category,
        style: style,
        userDescription: userDescription,
      );

      // ── Step 2: DALL-E 3 HD Image Generation ──
      final imageBytes = await _generateWithDallE3(dallEPrompt);

      stopwatch.stop();
      return AiGenerationResult(
        imageBytes: imageBytes,
        modelUsed: 'OpenAI (GPT-4o Vision + DALL-E 3 HD)',
        processingTime: stopwatch.elapsed,
      );
    } on DioException catch (e) {
      stopwatch.stop();
      final statusCode = e.response?.statusCode;
      final errorData = e.response?.data;
      String message = 'OpenAI request failed.';

      if (errorData is Map && errorData['error'] is Map) {
        message = errorData['error']['message'] ?? message;
      } else if (e.message != null) {
        message = e.message!;
      }

      if (statusCode == 401) {
        message = 'Invalid OpenAI API key. Please check your key in Settings.';
      } else if (statusCode == 429) {
        message = 'OpenAI rate limit reached or insufficient account credits/balance.';
      }

      throw AiServiceException(
        message,
        statusCode: statusCode,
        modelId: 'openai-dall-e-3',
        processingTime: stopwatch.elapsed,
      );
    } catch (e) {
      stopwatch.stop();
      if (e is AiServiceException) rethrow;
      throw AiServiceException(
        'Unexpected OpenAI generation error: $e',
        modelId: 'openai-dall-e-3',
        processingTime: stopwatch.elapsed,
      );
    }
  }

  /// Leverages GPT-4o Vision to analyze both person & garment photos,
  /// generating an exact photorealistic fashion rendering prompt.
  Future<String> _analyzeGarmentWithGpt4o({
    required Uint8List personImage,
    required Uint8List clothesImage,
    required String category,
    required String style,
    required String userDescription,
  }) async {
    try {
      final personDataUri = _imageToDataUri(personImage);
      final clothesDataUri = _imageToDataUri(clothesImage);

      final payload = {
        'model': 'gpt-4o',
        'messages': [
          {
            'role': 'system',
            'content':
                'You are an elite haute-couture fashion stylist and photorealistic AI prompter. '
                'Your task is to craft a single, highly-detailed prompt for DALL-E 3 describing '
                'the person wearing the exact uploaded clothing item. '
                'Include exact colors, textile weave (cotton, silk, linen, wool, denim), stitching, '
                'neckline, sleeves, realistic folds, flattering fit, natural pose, and studio lighting. '
                'Output ONLY the prompt text, no pleasantries or preamble.',
          },
          {
            'role': 'user',
            'content': [
              {
                'type': 'text',
                'text':
                    'Image 1 is the person. Image 2 is the clothing item ($category). '
                    '${userDescription.isNotEmpty ? "User details: $userDescription. " : ""}'
                    'Write a detailed DALL-E 3 prompt to render this person wearing this exact clothing item '
                    'in a $style, 8k resolution, editorial fashion shoot look.',
              },
              {
                'type': 'image_url',
                'image_url': {'url': personDataUri, 'detail': 'low'},
              },
              {
                'type': 'image_url',
                'image_url': {'url': clothesDataUri, 'detail': 'low'},
              },
            ],
          },
        ],
        'max_tokens': 350,
        'temperature': 0.7,
      };

      final response = await _dio.post<Map<String, dynamic>>(
        '/chat/completions',
        data: payload,
      );

      final content =
          response.data?['choices']?[0]?['message']?['content'] as String?;
      if (content != null && content.trim().isNotEmpty) {
        return content.trim();
      }
    } catch (_) {
      // Fallback to local high-fidelity prompt if Vision times out
    }

    return 'Full body editorial fashion photograph of a person wearing a '
        'tailored $category garment, ${userDescription.isNotEmpty ? userDescription : "matching luxury fabric"}, '
        'authentic textile texture, crisp seams, natural folds, professional studio lighting, 8k resolution, sharp focus.';
  }

  /// Calls OpenAI DALL-E 3 HD generation endpoint with base64 return format.
  Future<Uint8List> _generateWithDallE3(String prompt) async {
    final payload = {
      'model': 'dall-e-3',
      'prompt': prompt,
      'n': 1,
      // 1024x1792 is portrait aspect ratio optimal for fashion & try-on
      'size': '1024x1792',
      'quality': 'hd',
      'response_format': 'b64_json',
    };

    final response = await _dio.post<Map<String, dynamic>>(
      '/images/generations',
      data: payload,
    );

    final dataList = response.data?['data'] as List<dynamic>?;
    if (dataList == null || dataList.isEmpty) {
      throw AiServiceException(
        'Empty response received from OpenAI DALL-E 3.',
        modelId: 'openai-dall-e-3',
      );
    }

    final b64Json = dataList[0]['b64_json'] as String?;
    if (b64Json != null && b64Json.isNotEmpty) {
      return base64Decode(b64Json);
    }

    // Fallback: If URL format was returned
    final url = dataList[0]['url'] as String?;
    if (url != null && url.isNotEmpty) {
      final imgResponse = await _dio.get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      if (imgResponse.data != null) {
        return Uint8List.fromList(imgResponse.data!);
      }
    }

    throw AiServiceException(
      'Failed to parse image from OpenAI DALL-E 3 response.',
      modelId: 'openai-dall-e-3',
    );
  }

  @override
  void dispose() {
    _dio.close(force: true);
  }
}
