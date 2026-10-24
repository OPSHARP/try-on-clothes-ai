import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'ai_service.dart';
import 'on_device_stylist_service.dart';
import 'identity_lock_service.dart';

import 'smart_framing_coordinator.dart';

/// Progress callback reporting current human-readable pipeline stage
/// and normalized progress from 0.0 to 1.0.
typedef PipelineProgressCallback = void Function(String stageMessage, double progress);

/// Parameters passed to the background isolate for post-processing enhancement.
class _EnhanceIsolateParams {
  final Uint8List rawBytes;
  final double contrast;
  final double saturation;
  final double sharpness;

  const _EnhanceIsolateParams({
    required this.rawBytes,
    this.contrast = 1.06,
    this.saturation = 1.05,
    this.sharpness = 0.25,
  });
}

/// AI Image Generation & Enhancement Pipeline Service.
///
/// Orchestrates a 5-skill advanced AI pipeline before returning the final try-on result:
/// 1. **Smart Framing & Composition Coordinator**: Detects half-body vs full-body framing,
///    and if garment contains 2 items (tshirt + pants) while person is half-body, cleanly
///    isolates and extracts ONLY the upper garment.
/// 2. **On-Device Vision Stylist**: Analyzes fabric, color, and generates a concise VTON prompt (<15 tokens).
/// 3. **Core VTON Model**: Executes garment warping diffusion with auto-masking.
/// 4. **Face & Body Identity Lock**: Locks human face, eyes, hair, and bare arms/scars 100% to the original photo.
/// 5. **Post-Processing HD Enhancer**: Applies micro-contrast, fabric grain sharpening, and vibrancy.
class AiImagePipelineService {
  final AiService _aiService;

  const AiImagePipelineService(this._aiService);

  /// Executes the full multi-skill generation & enhancement pipeline.
  Future<AiGenerationResult> executePipeline({
    required Uint8List personImage,
    required Uint8List clothesImage,
    String? userGarmentDescription,
    String category = 'upper_body',
    String style = 'realistic',
    String quality = 'standard',
    PipelineProgressCallback? onProgress,
  }) async {
    final stopwatch = Stopwatch()..start();

    // ── Skill 1: Smart Framing & Garment Adaptation Coordinator ──
    onProgress?.call('AI analyzing anatomy framing & garment composition...', 0.15);
    final framingPlan = await SmartFramingCoordinator.analyzeAndAdapt(
      personBytes: personImage,
      garmentBytes: clothesImage,
      requestedCategory: category,
    );

    final effectiveGarmentBytes = framingPlan.adaptedGarmentBytes;
    final effectiveCategory = framingPlan.effectiveCategory;

    // ── Skill 2: On-Device AI Vision Stylist ──
    onProgress?.call('AI Stylist harmonizing color, fabric & lighting...', 0.35);
    final stylistAnalysis = await OnDeviceStylistService.analyzeAndStyleGarment(
      personImage: personImage,
      clothesImage: effectiveGarmentBytes,
      userDescription: userGarmentDescription ?? framingPlan.garmentSpecificDescription,
      category: effectiveCategory,
      style: style,
    );

    // Normalize images in isolate if needed (e.g. valid orientation, capped resolution)
    final preparedPersonBytes = await compute(_normalizeImageBytes, personImage);
    final preparedClothesBytes = await compute(_normalizeImageBytes, effectiveGarmentBytes);

    // ── Skill 3: Core Virtual Try-On Generation (with clean VTON description) ──
    onProgress?.call('Synthesizing virtual garment drape with AI...', 0.60);
    final rawResult = await _aiService.generateTryOn(
      personImage: preparedPersonBytes,
      clothesImage: preparedClothesBytes,
      options: {
        'category': effectiveCategory,
        'style': style,
        'quality': quality,
        'description': stylistAnalysis.conciseDescription,
        'auto_mask': 'true',
        'crop': 'false',
      },
    );
    final rawResultBytes = rawResult.imageBytes;
    final baseModel = rawResult.modelUsed ?? 'IDM-VTON';

    // ── Skill 4: Post-Processing & Fabric Detail Enhancement ──
    // Enhances the generated garment's micro-texture, stitching, and drape vibrancy
    onProgress?.call('Enhancing fabric micro-texture & details...', 0.80);
    final enhancedGarmentBytes = await compute(
      _enhanceImageInIsolate,
      _EnhanceIsolateParams(
        rawBytes: rawResultBytes,
        contrast: 1.05,
        saturation: 1.04,
        sharpness: 0.20,
      ),
    );

    // ── Skill 5: Final Human Face & Body Identity Lock (Zero Distortion Guardian) ──
    // Guarantees face, hair, eyes, and head region remain 100% crisp from the original photo.
    onProgress?.call('Locking human face & body to original photo...', 0.95);
    final finalResultBytes = await IdentityLockService.lockFaceAndBody(
      originalPersonBytes: preparedPersonBytes,
      generatedResultBytes: enhancedGarmentBytes,
      category: effectiveCategory,
      isHalfBody: framingPlan.personFraming == BodyFraming.halfBody,
      customNeckRatio: framingPlan.neckYRatio,
      preserveForearms: true,
    );


    onProgress?.call('Finalizing ultra-realistic HD result...', 1.0);
    stopwatch.stop();

    return AiGenerationResult(
      imageBytes: finalResultBytes,
      modelUsed: '$baseModel + Framing Coordinator + HD Enhancer + Identity Lock',
      processingTime: stopwatch.elapsed,
    );
  }


  /// Normalizes incoming image bytes (EXIF orientation, bounding dimensions) in an isolate.
  static Uint8List _normalizeImageBytes(Uint8List inputBytes) {
    try {
      final decoded = img.decodeImage(inputBytes);
      if (decoded == null) return inputBytes;

      // Ensure dimensions do not exceed 1024x1365 for optimal model latency
      if (decoded.width > 1200 || decoded.height > 1600) {
        final resized = img.copyResize(
          decoded,
          width: 1024,
          interpolation: img.Interpolation.cubic,
        );
        return Uint8List.fromList(img.encodeJpg(resized, quality: 92));
      }
      return inputBytes;
    } catch (_) {
      return inputBytes;
    }
  }

  /// Background isolate image enhancer:
  /// 1. Unsharp mask micro-contrast for fabric texture and stitching.
  /// 2. Subtle contrast & saturation tuning so the garment looks natural, not washed out.
  /// 3. Encodes high-quality 95% JPEG output.
  static Uint8List _enhanceImageInIsolate(_EnhanceIsolateParams params) {
    try {
      final decoded = img.decodeImage(params.rawBytes);
      if (decoded == null) return params.rawBytes;

      // 1. Subtle color and contrast balancing
      var working = img.adjustColor(
        decoded,
        contrast: params.contrast,
        saturation: params.saturation,
        brightness: 1.01,
      );

      // 2. Adaptive high-pass sharpening kernel for fabric grain & stitching
      // [ 0,  -s,   0 ]
      // [-s, 1+4s, -s ]
      // [ 0,  -s,   0 ]
      final s = params.sharpness;
      if (s > 0) {
        final center = 1.0 + (4.0 * s);
        final kernel = <num>[
          0.0, -s, 0.0,
          -s, center, -s,
          0.0, -s, 0.0,
        ];
        working = img.convolution(working, filter: kernel, div: 1);
      }

      final encoded = img.encodeJpg(working, quality: 95);
      return Uint8List.fromList(encoded);
    } catch (e) {
      // Graceful fallback to original image if enhancement encountered an error
      return params.rawBytes;
    }
  }
}

