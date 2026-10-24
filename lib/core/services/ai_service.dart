import 'dart:typed_data';

/// Result of an AI try-on generation.
class AiGenerationResult {
  final Uint8List imageBytes;
  final String? modelUsed;
  final Duration processingTime;

  AiGenerationResult({
    required this.imageBytes,
    this.modelUsed,
    required this.processingTime,
  });
}

/// Abstract interface for AI try-on generation services.
abstract class AiService {
  /// Generate a try-on image combining [personImage] wearing [clothesImage].
  ///
  /// [options] may include:
  /// - `model`: specific model ID to use
  /// - `category`: garment category (upper_body, lower_body, dresses)
  /// - `quality`: generation quality preference
  /// - `style`: style preference (realistic, fashion, etc.)
  Future<AiGenerationResult> generateTryOn({
    required Uint8List personImage,
    required Uint8List clothesImage,
    Map<String, String> options = const {},
  });

  /// Check if the service is available (API key configured, etc.).
  bool get isAvailable;

  /// Dispose any resources held by the service.
  void dispose();
}

/// Exception thrown by [AiService] implementations on failure.
class AiServiceException implements Exception {
  final String message;
  final int? statusCode;
  final String? modelId;
  final Duration? processingTime;

  AiServiceException(
    this.message, {
    this.statusCode,
    this.modelId,
    this.processingTime,
  });

  @override
  String toString() {
    final buffer = StringBuffer('AiServiceException: $message');
    if (statusCode != null) buffer.write(' (HTTP $statusCode)');
    if (modelId != null) buffer.write(' [model: $modelId]');
    return buffer.toString();
  }
}
