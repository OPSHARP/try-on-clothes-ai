import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:try_on_clothes_ai/core/services/ai_service.dart';
import 'package:try_on_clothes_ai/core/services/ai_image_pipeline_service.dart';

class _MockAiService implements AiService {
  @override
  bool get isAvailable => true;

  @override
  Future<AiGenerationResult> generateTryOn({
    required Uint8List personImage,
    required Uint8List clothesImage,
    Map<String, String> options = const {},
  }) async {
    // Generate a simple test image simulating the raw VTON output
    final testImg = img.Image(width: 80, height: 100);
    final encoded = img.encodeJpg(testImg, quality: 85);
    return AiGenerationResult(
      imageBytes: Uint8List.fromList(encoded),
      modelUsed: 'mock-vton',
      processingTime: const Duration(milliseconds: 200),
    );
  }

  @override
  void dispose() {}
}

void main() {
  test('AiImagePipelineService executes 3-skill pipeline and enhances output', () async {
    final mockService = _MockAiService();
    final pipeline = AiImagePipelineService(mockService);

    final personImg = img.Image(width: 50, height: 50);
    final clothesImg = img.Image(width: 50, height: 50);
    final personBytes = Uint8List.fromList(img.encodeJpg(personImg));
    final clothesBytes = Uint8List.fromList(img.encodeJpg(clothesImg));

    final progressStages = <String>[];
    final progressValues = <double>[];

    final result = await pipeline.executePipeline(
      personImage: personBytes,
      clothesImage: clothesBytes,
      userGarmentDescription: 'Black silk blazer',
      category: 'upper_body',
      onProgress: (stage, progress) {
        progressStages.add(stage);
        progressValues.add(progress);
      },
    );

    expect(result.imageBytes.isNotEmpty, true);
    expect(progressStages.length, 6);
    expect(progressValues.last, 1.0);
    expect(result.modelUsed, contains('Identity Lock'));
    expect(result.modelUsed, contains('Enhancer'));
    expect(result.modelUsed, contains('Framing Coordinator'));
  });
}
