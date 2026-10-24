import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../ai_service.dart';
import '../rate_limiter.dart';
import '../../constants/app_constants.dart';

/// HuggingFace Virtual Try-On implementation using a Gradio 4.x Space.
///
/// Unlike a text-to-image model (like FLUX.1-dev), this service sends
/// **both** a person photo and a clothing photo to a HuggingFace Space
/// that runs a real Virtual Try-On (VTON) model, such as
/// [yisol/IDM-VTON](https://huggingface.co/spaces/yisol/IDM-VTON).
///
/// ### How it works (Gradio 4.x queue-based API)
///
/// Gradio 4.x Spaces don't accept direct HTTP POST to `/api/predict/`.
/// Instead they use an **asynchronous queue** with these steps:
///
/// 1. **Upload** both images via `POST /upload` (multipart/form-data).
///    The Space returns temporary file paths like `/tmp/gradio/xxx/p.png`.
/// 2. **Submit** a job via `POST /queue/join` with the file paths,
///    a random `session_hash`, `fn_index` and `trigger_id`.
/// 3. **Poll** `GET /queue/data?session_hash=<hash>` repeatedly
///    to receive Server-Sent Events (SSE) until `process_completed`.
/// 4. **Download** the result image from the URL returned in the SSE data.
///
/// ### Rate limiting & retries
/// - Shared singleton [RateLimiter] keeps all instances under free-tier quotas
/// - Exponential backoff on 429 (rate-limit) and 503 (cold start) responses
/// - Cold-start retries are transparent — the Space may need 1–2 min to wake
///
/// ### Configuration
/// The Space ID is set via [modelId] using `author/space-name` format.
/// Default: `yisol/IDM-VTON`.
/// Other popular free Spaces: `levihsu/OOTDiffusion`, `PAIR/PAIR-Diffusion`
class HuggingFaceService implements AiService {
  final Dio _dio;
  String _apiKey;
  final String _spaceReference;

  /// Default Space ID — [yisol/IDM-VTON](https://huggingface.co/spaces/yisol/IDM-VTON)
  /// is a well-known, free Virtual Try‑On model on HuggingFace Spaces.
  static const String defaultModelId = 'yisol/IDM-VTON';

  /// Default Hugging Face API token placeholder.
  /// Users can configure their own token in App Settings (BYOK).
  static const String defaultApiKey = '';

  /// Shared rate limiter across all instances.
  static final RateLimiter _rateLimiter = RateLimiter();

  /// Maximum time to wait for a generation to complete (milliseconds).
  static const int _maxPollTimeMs = 120000; // 2 minutes

  @override
  bool get isAvailable => true; // HuggingFace Spaces can be public (no API key required)

  /// Create a HuggingFace Virtual Try-On service.
  ///
  /// [apiKey] is your HuggingFace API token from huggingface.co/settings/tokens.
  /// [modelId] is the HuggingFace Space ID (format: `"author/space-name"`).
  ///   Defaults to [defaultModelId] (`yisol/IDM-VTON`).
  ///   Other options: `'levihsu/OOTDiffusion'`, `'PAIR/PAIR-Diffusion'`
  HuggingFaceService({
    String apiKey = defaultApiKey,
    Dio? dio,
    String modelId = defaultModelId,
  }) : _apiKey = apiKey.isNotEmpty ? apiKey : defaultApiKey,
       _spaceReference = modelId,
       _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 30),
               receiveTimeout: AppConstants.aiRequestTimeout,
             ),
           );

  /// Allow updating the API key at runtime.
  void updateApiKey(String newKey) {
    _apiKey = newKey.isNotEmpty ? newKey : defaultApiKey;
  }

  // ── URL helpers ──────────────────────────────────────────────────────────

  /// Convert `"author/space-name"` → `"https://author-space-name.hf.space"`.
  String _spaceUrl() {
    final parts = _spaceReference.split('/');
    if (parts.length != 2) {
      throw AiServiceException(
        'Invalid Space reference: "$_spaceReference". '
        'Use the format "author/space-name" (e.g. "yisol/IDM-VTON").',
        modelId: _spaceReference,
      );
    }
    return 'https://${parts[0].toLowerCase()}-${parts[1].toLowerCase()}.hf.space';
  }

  /// Generate a random session hash for the Gradio queue protocol.
  String _generateSessionHash() {
    final rng = Random.secure();
    final bytes = List<int>.generate(10, (_) => rng.nextInt(256));
    return base64UrlEncode(bytes).substring(0, 10);
  }

  // ── Image upload ─────────────────────────────────────────────────────────

  /// Upload an image to the Space's temporary storage.
  ///
  /// Returns the server-side path (e.g. `"/tmp/gradio/xxx/filename.png"`)
  /// or throws an [AiServiceException] on failure.
  Future<String> _uploadImage(Uint8List imageBytes, String filename) async {
    final spaceUrl = _spaceUrl();
    final uploadUrl = '$spaceUrl/upload';

    final formData = FormData.fromMap({
      'files': MultipartFile.fromBytes(imageBytes, filename: filename),
    });

    final response = await _dio.post<List<dynamic>>(
      uploadUrl,
      data: formData,
      options: Options(
        headers: {
          if (_apiKey.isNotEmpty) 'Authorization': 'Bearer $_apiKey',
        },
        responseType: ResponseType.json,
        // Don't set Content-Type; Dio sets it automatically for multipart
      ),
    );

    if (response.data == null || response.data!.isEmpty) {
      throw AiServiceException(
        'Upload failed: empty response from Space.',
        modelId: _spaceReference,
      );
    }

    final path = response.data![0] as String?;
    if (path == null || path.isEmpty) {
      throw AiServiceException(
        'Upload failed: invalid response format: ${response.data}',
        modelId: _spaceReference,
      );
    }

    return path;
  }

  // ── SSE event stream ────────────────────────────────────────────────────

  /// Connect to the Gradio SSE endpoint and wait for the job to complete.
  ///
  /// Unlike polling, this opens a SINGLE persistent connection that uses
  /// [`ResponseType.stream`] to read Server-Sent Events as they arrive.
  /// The connection naturally stays alive until the Space sends a
  /// `close_stream` event (which Gradio emits after `process_completed`).
  ///
  /// If the connection drops unexpectedly (no `close_stream`), we reconnect
  /// with exponential backoff up to the [deadline]. This handles transient
  /// network issues on mobile without losing the job's result events.
  Future<List<dynamic>> _pollForResults(
    String sessionHash,
    String eventId,
  ) async {
    final spaceUrl = _spaceUrl();
    final deadline = DateTime.now().millisecondsSinceEpoch + _maxPollTimeMs;
    int retryCount = 0;
    const maxRetries = 5;

    while (DateTime.now().millisecondsSinceEpoch < deadline) {
      final sseUrl =
          '$spaceUrl/queue/data?session_hash=$sessionHash&event_id=$eventId';

      try {
        // Use ResponseType.stream so we can read SSE events line-by-line as
        // the Space sends them, without waiting for the entire stream to end.
        final response = await _dio.get<ResponseBody>(
          sseUrl,
          options: Options(
            headers: {
              if (_apiKey.isNotEmpty) 'Authorization': 'Bearer $_apiKey',
              'Accept': 'text/event-stream',
              'Cache-Control': 'no-cache',
            },
            responseType: ResponseType.stream,
          ),
        );

        final responseBody = response.data;
        if (responseBody == null) {
          throw DioException(
            requestOptions: RequestOptions(path: ''),
            type: DioExceptionType.badResponse,
            message: 'Null stream response body',
          );
        }

        // ── Read SSE events line-by-line as chunks arrive in real-time ──
        String partial = '';
        await for (final chunk in responseBody.stream) {
          final decoded = utf8.decode(chunk);
          partial += decoded;

          // Split on newlines to extract and process complete SSE lines immediately
          while (partial.contains('\n')) {
            final newlineIdx = partial.indexOf('\n');
            final line = partial.substring(0, newlineIdx).trim();
            partial = partial.substring(newlineIdx + 1);

            if (!line.startsWith('data: ')) continue;
            final jsonStr = line.substring(6); // strip "data: " prefix

            try {
              final event = jsonDecode(jsonStr) as Map<String, dynamic>;
              final msg = event['msg'] as String?;

              if (msg == 'process_completed') {
                final success = event['success'] as bool? ?? true;
                if (!success) {
                  final output = event['output'] as Map<String, dynamic>?;
                  final errorDetail =
                      output?['error'] as String? ?? 'Unknown error';
                  throw AiServiceException(
                    'VTON model error: $errorDetail',
                    modelId: _spaceReference,
                  );
                }

                final output = event['output'] as Map<String, dynamic>?;
                if (output == null) {
                  throw AiServiceException(
                    'Space returned process_completed without output.',
                    modelId: _spaceReference,
                  );
                }

                final data = output['data'] as List<dynamic>?;
                if (data == null || data.isEmpty) {
                  throw AiServiceException(
                    'Space returned empty data after processing.',
                    modelId: _spaceReference,
                  );
                }

                return data;
              }
            } catch (e) {
              if (e is AiServiceException) rethrow;
              continue;
            }
          }
        }

        // ── Stream ended without process_completed ──
        // This shouldn't happen in normal Gradio operation, but if the
        // connection was interrupted we retry with exponential backoff.
        retryCount++;
        if (retryCount > maxRetries) {
          throw AiServiceException(
            'VTON Space stream closed without completion after '
            '$maxRetries reconnection attempts.',
            modelId: _spaceReference,
          );
        }

        final backoffMs = Duration(
          seconds: 1 << retryCount,
        ).inMilliseconds; // 2, 4, 8, 16, 32 sec
        await Future.delayed(Duration(milliseconds: backoffMs));
        continue;
      } on DioException catch (e) {
        // ── Cold start (503) → retry with backoff ──
        if (e.response?.statusCode == 503) {
          await Future.delayed(const Duration(seconds: 5));
          continue;
        }

        // ── Connection dropped → retry with exponential backoff ──
        // On mobile networks, long-lived SSE connections can be interrupted
        // by NAT timeouts or signal loss. Reconnect and continue.
        if (e.type == DioExceptionType.connectionError ||
            e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout) {
          retryCount++;
          if (retryCount > maxRetries) {
            throw AiServiceException(
              'VTON Space connection lost after $maxRetries retries. '
              'Please check your internet connection and try again.',
              modelId: _spaceReference,
            );
          }

          final backoffMs = Duration(seconds: 1 << retryCount).inMilliseconds;
          await Future.delayed(Duration(milliseconds: backoffMs));
          continue;
        }

        // ── Other errors → rethrow ──
        rethrow;
      }
    }

    throw AiServiceException(
      'Generation timed out after ${_maxPollTimeMs ~/ 1000} seconds. '
      'The VTON model may be overloaded. Please try again.',
      modelId: _spaceReference,
    );
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
    
    // Denoise steps control rendering quality:
    // Higher steps (35-40) provide sharper garment textures and more accurate edge alignment.
    final quality = options['quality'] ?? 'standard';
    int denoiseSteps = 30;
    if (quality == 'high') {
      denoiseSteps = 35;
    } else if (quality == 'ultra') {
      denoiseSteps = 40;
    }

    final useAutoMask = options['auto_mask'] != 'false'; // default true
    // Default to false: IDM-VTON's auto-crop cuts a centered box and pastes it back
    // into the original image, which creates harsh seams and cuts off arms/torso.
    // Setting crop to false processes the natural full body layout smoothly.
    final useCrop = options['crop'] == 'true';
    // Use a random seed to avoid consistently bad results from a fixed seed.
    final seed = Random().nextInt(1000000);

    final spaceUrl = _spaceUrl();

    // ── Retry loop ──────────────────────────────────────────────────────────
    const maxRetries = RateLimiter.maxRetries;

    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        // ---- wait for a rate-limit slot before each attempt ----
        await _rateLimiter.waitForSlot();

        // ---- Step 1: Upload person image ----
        final personPath = await _uploadImage(personImage, 'person.png');
        // ignore: avoid_print
        print('HuggingFace: Person image uploaded: $personPath');

        // ---- Step 2: Upload garment image ----
        final clothesPath = await _uploadImage(clothesImage, 'garment.png');
        // ignore: avoid_print
        print('HuggingFace: Garment image uploaded: $clothesPath');

        // ---- Step 3: Prepare Gradio data payload ----
        // The data array MUST match the Space's Gradio interface component
        // order EXACTLY — Gradio uses **positional** arguments, not named.
        //
        // Expected order for yisol/IDM-VTON (verified from Space /config):
        //   [0] human          ImageEditor     — person photo
        //   [1] garment        FileData/Image  — clothing photo
        //   [2] description    Textbox         — garment description (garment_des)
        //   [3] auto_mask      Checkbox        — constrain to clothing region (is_checked)
        //   [4] crop           Checkbox        — auto-crop garment (is_checked_crop)
        //   [5] denoise_steps  Slider          — rendering quality (30=optimal)
        //   [6] seed           Number          — random seed
        final sessionHash = _generateSessionHash();

        // FileData references for the Gradio components
        final personFileData = {
          'path': personPath,
          'meta': {'_type': 'gradio.FileData'},
        };

        final clothesFileData = {
          'path': clothesPath,
          'meta': {'_type': 'gradio.FileData'},
        };

        // The human image component is an ImageEditor (Gradio 4.x),
        // which expects: {background, layers, composite}
        final humanEditorData = {
          'background': personFileData,
          'layers': <dynamic>[],
          'composite': null,
        };

        // ── Positional data array ──
        // Order MUST match the Gradio inputs exactly.
        final dataArray = <dynamic>[
          humanEditorData, // [0] person photo
          clothesFileData, // [1] garment photo
          garmentDesc, // [2] garment description text
          useAutoMask, // [3] auto-mask checkbox
          useCrop, // [4] crop checkbox
          denoiseSteps, // [5] denoise steps slider
          seed, // [6] random seed
        ];

        final payload = {
          'data': dataArray,
          'event_data': null,
          'fn_index': 2,
          'trigger_id': 25,
          'session_hash': sessionHash,
        };

        // ---- Step 4: Submit to the queue ----
        // ignore: avoid_print
        print('HuggingFace: Submitting VTON job...');
        final queueResponse = await _dio.post<Map<String, dynamic>>(
          '$spaceUrl/queue/join',
          options: Options(
            headers: {
              if (_apiKey.isNotEmpty) 'Authorization': 'Bearer $_apiKey',
              'Content-Type': 'application/json',
            },
            responseType: ResponseType.json,
          ),
          data: payload,
        );

        final eventId = queueResponse.data?['event_id'] as String?;
        if (eventId == null || eventId.isEmpty) {
          throw AiServiceException(
            'Space did not return an event_id. '
            'Response: ${queueResponse.data}',
            modelId: _spaceReference,
          );
        }
        // ignore: avoid_print
        print('HuggingFace: Job submitted (event_id: $eventId)');

        // ---- Step 5: Poll for results (persistent SSE connection) ----
        final outputData = await _pollForResults(sessionHash, eventId);

        stopwatch.stop();

        // ---- Step 6: Extract result image from output ----
        final resultImageBytes = await _extractResultImage(
          outputData,
          spaceUrl,
        );

        if (resultImageBytes.isEmpty) {
          throw AiServiceException(
            'No image data in VTON Space response.',
            modelId: _spaceReference,
            processingTime: stopwatch.elapsed,
          );
        }

        // ---- Success — reset error counter ----
        _rateLimiter.markSuccess();

        return AiGenerationResult(
          imageBytes: resultImageBytes,
          modelUsed: _spaceReference,
          processingTime: stopwatch.elapsed,
        );
      } on DioException catch (e) {
        final statusCode = e.response?.statusCode;

        // ── Cold start (503) → wait & retry ──
        if (statusCode == 503 && attempt < maxRetries) {
          final delay = _rateLimiter.getBackoffDelay();
          // ignore: avoid_print
          print(
            'HuggingFace: Space cold-start (503), retrying in ${delay}ms '
            '(attempt ${attempt + 1}/$maxRetries)',
          );
          await Future.delayed(Duration(milliseconds: delay));
          continue;
        }

        // ── Rate-limited (429) → exponential backoff & retry ──
        if (statusCode == 429 && attempt < maxRetries) {
          final delay = _rateLimiter.getBackoffDelay();
          // ignore: avoid_print
          print(
            'HuggingFace: rate-limited (429), retrying in ${delay}ms '
            '(attempt ${attempt + 1}/$maxRetries)',
          );
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
          serverMsg = body['error'] as String?;
        } else if (e.response?.data is String) {
          serverMsg = e.response!.data as String;
        }

        if (statusCode == 400) {
          errorMessage =
              'Invalid request: '
              '${serverMsg ?? 'The image format or parameters may be invalid.'}';
        } else if (statusCode == 401 || statusCode == 403) {
          errorMessage =
              'Access denied. Your HuggingFace token may be invalid '
              'or the Space may be private.';
        } else if (statusCode == 429) {
          errorMessage =
              'Rate limit exceeded after retries. '
              'Please wait a moment and try again.';
        } else if (statusCode == 503) {
          errorMessage =
              'The VTON model is still loading. '
              'Please try again in a few seconds.';
        } else {
          // Include all available error details for debugging
          final dioErrorType = e.type.name;
          final detail =
              serverMsg ??
              e.message ??
              'No response received (type: $dioErrorType)';
          errorMessage = 'VTON Space error ($statusCode): $detail';
        }

        // ignore: avoid_print
        print(
          'HuggingFace: ERROR statusCode=$statusCode '
          'type=${e.type.name} message=${e.message} '
          'serverMsg=$serverMsg',
        );

        throw AiServiceException(
          errorMessage,
          statusCode: statusCode,
          modelId: _spaceReference,
          processingTime: stopwatch.elapsed,
        );
      } catch (e) {
        // Don't wrap AiServiceException again
        if (e is AiServiceException) rethrow;

        stopwatch.stop();
        throw AiServiceException(
          'Unexpected error: ${e.toString()}',
          modelId: _spaceReference,
          processingTime: stopwatch.elapsed,
        );
      }
    }

    // Should never reach here, but just in case:
    stopwatch.stop();
    throw AiServiceException(
      'Generation failed after $maxRetries retries.',
      modelId: _spaceReference,
      processingTime: stopwatch.elapsed,
    );
  }

  // ── Response parsing ─────────────────────────────────────────────────────

  /// Extract the result image from the Gradio 4.x output data array.
  ///
  /// The output data array from the `process_completed` event typically
  /// contains entries like:
  /// ```json
  /// {
  ///   "url": "https://yisol-idm-vton.hf.space/file/tmp/gradio/xxx/result.png",
  ///   "path": "/tmp/gradio/xxx/result.png",
  ///   "meta": {"_type": "gradio.FileData"}
  /// }
  /// ```
  /// Or sometimes just a file path string.
  Future<Uint8List> _extractResultImage(
    List<dynamic> outputData,
    String spaceUrl,
  ) async {
    if (outputData.isEmpty) {
      throw AiServiceException('No data in VTON Space response.');
    }

    // The first element is typically the composite result image
    final result = outputData[0];

    // ── Format 1: {"url": "...", "path": "..."} (FileData) ──
    if (result is Map<String, dynamic>) {
      // Try URL first (most direct)
      final url = result['url'] as String?;
      if (url != null && url.isNotEmpty) {
        return _downloadImage(url);
      }

      // Fall back to path relative to the Space
      final path = result['path'] as String?;
      if (path != null && path.isNotEmpty) {
        final downloadUrl = path.startsWith('http')
            ? path
            : '$spaceUrl/file$path';
        return _downloadImage(downloadUrl);
      }
    }

    // ── Format 2: "data:image/png;base64,..." (inline base64) ──
    if (result is String) {
      if (result.startsWith('data:image')) {
        final commaIdx = result.indexOf(',');
        if (commaIdx != -1 && commaIdx + 1 < result.length) {
          final base64Str = result.substring(commaIdx + 1);
          try {
            return Uint8List.fromList(base64Decode(base64Str));
          } catch (_) {
            throw AiServiceException(
              'Failed to decode base64 image from VTON response.',
            );
          }
        }
      }

      // Short string responses are likely error messages from the Space
      if (result.length < 200) {
        throw AiServiceException('VTON Space returned: $result');
      }
    }

    throw AiServiceException(
      'Could not parse result image from VTON Space response. '
      'Unexpected data format: ${result.runtimeType} — $result',
    );
  }

  /// Download an image from a URL (result file hosted by the Gradio Space).
  Future<Uint8List> _downloadImage(String url) async {
    final response = await _dio.get<List<int>>(
      url,
      options: Options(
        responseType: ResponseType.bytes,
        headers: {'Authorization': 'Bearer $_apiKey'},
      ),
    );

    if (response.data == null || response.data!.isEmpty) {
      throw AiServiceException(
        'Failed to download result image from VTON Space (empty response).',
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
