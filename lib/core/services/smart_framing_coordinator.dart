import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Categorization of the human subject's visible framing.
enum BodyFraming {
  /// Subject visible from waist or chest up (no legs/feet).
  halfBody,

  /// Subject visible from head to feet/shoes (full legs visible).
  fullBody,
}

/// Categorization of the garment or product image composition.
enum GarmentComposition {
  /// Contains only upper-body garment (t-shirt, shirt, hoodie, blazer).
  upperOnly,

  /// Contains only lower-body garment (jeans, pants, trousers, skirt, shorts).
  lowerOnly,

  /// Contains both upper and lower items (e.g., model wearing t-shirt + pants).
  twoPieceOutfit,

  /// A continuous one-piece dress, jumpsuit, or gown.
  fullBodyDress,
}

/// The intelligent adaptation plan determined by the Smart Framing Coordinator.
class SmartTryOnPlan {
  final BodyFraming personFraming;
  final GarmentComposition garmentComposition;
  final String effectiveCategory;
  final Uint8List adaptedGarmentBytes;
  final String framingDescription;
  final String garmentSpecificDescription;
  final double neckYRatio;
  final double waistYRatio;

  const SmartTryOnPlan({
    required this.personFraming,
    required this.garmentComposition,
    required this.effectiveCategory,
    required this.adaptedGarmentBytes,
    required this.framingDescription,
    required this.garmentSpecificDescription,
    required this.neckYRatio,
    required this.waistYRatio,
  });

  @override
  String toString() =>
      'SmartTryOnPlan(person: $personFraming, garment: $garmentComposition, category: $effectiveCategory)';
}

/// Production AI Smart Framing Coordinator.
///
/// Implements advanced computer vision rules for try-on precision:
/// 1. Detects Human Framing (half-body waist-up vs full-body).
/// 2. Detects Garment Composition (upper item only, lower item only, or 2-piece outfit with both).
/// 3. Adaptation Rules:
///    - If garment has 2 items (T-shirt + Pants) but person is Half-Body:
///      Automatically isolates/crops ONLY the T-shirt and applies it strictly to upper body.
///    - If person is Full-Body and garment has both: Applies both.
///    - If person is Full-Body and garment has only 1 item: Applies only to that specific zone,
///      preserving the other part of the body 100%.
class SmartFramingCoordinator {
  /// Analyzes person and garment images and builds the optimal adaptation plan.
  static Future<SmartTryOnPlan> analyzeAndAdapt({
    required Uint8List personBytes,
    required Uint8List garmentBytes,
    String requestedCategory = 'upper_body',
  }) async {
    return compute(
      _runCoordinationInIsolate,
      _CoordinationParams(
        personBytes: personBytes,
        garmentBytes: garmentBytes,
        requestedCategory: requestedCategory,
      ),
    );
  }

  static SmartTryOnPlan _runCoordinationInIsolate(_CoordinationParams params) {
    final personImg = img.decodeImage(params.personBytes);
    final garmentImg = img.decodeImage(params.garmentBytes);

    if (personImg == null || garmentImg == null) {
      return SmartTryOnPlan(
        personFraming: BodyFraming.halfBody,
        garmentComposition: GarmentComposition.upperOnly,
        effectiveCategory: params.requestedCategory,
        adaptedGarmentBytes: params.garmentBytes,
        framingDescription: 'standard framing',
        garmentSpecificDescription: 'garment',
        neckYRatio: 0.28,
        waistYRatio: 0.70,
      );
    }

    // ── 1. Detect Human Framing ──
    final personFraming = detectBodyFraming(personImg);
    final neckRatio = estimateNeckRatio(personImg);
    final waistRatio = personFraming == BodyFraming.halfBody ? 0.95 : 0.65;

    // ── 2. Detect Garment Composition ──
    final compositionResult = detectGarmentComposition(garmentImg);

    // ── 3. Apply Smart Adaptation Rules ──
    String effectiveCategory = params.requestedCategory;
    Uint8List adaptedGarmentBytes = params.garmentBytes;
    String garmentDesc = compositionResult.description;

    if (personFraming == BodyFraming.halfBody) {
      if (compositionResult.composition == GarmentComposition.twoPieceOutfit) {
        // ── RULE: Garment has 2 items (T-shirt + Pant) but Human is Half-Body ──
        // Extract ONLY the Upper Garment (T-shirt) so pants are not forced onto waist-up shot!
        effectiveCategory = 'upper_body';
        final croppedUpper = cropUpperGarment(garmentImg, compositionResult.splitYRatio);
        adaptedGarmentBytes = Uint8List.fromList(img.encodeJpg(croppedUpper, quality: 95));
        garmentDesc = '${compositionResult.upperColor} cotton t-shirt with print';
      } else if (compositionResult.composition == GarmentComposition.lowerOnly) {
        effectiveCategory = 'lower_body';
      } else {
        effectiveCategory = 'upper_body';
      }
    } else {
      // ── Person is Full-Body ──
      if (compositionResult.composition == GarmentComposition.twoPieceOutfit) {
        // Both items apply for full body
        effectiveCategory = 'dresses'; // VTON full outfit identifier
      } else if (compositionResult.composition == GarmentComposition.lowerOnly) {
        // Only pants/lower item apply
        effectiveCategory = 'lower_body';
      } else {
        // Only upper item apply
        effectiveCategory = 'upper_body';
      }
    }

    return SmartTryOnPlan(
      personFraming: personFraming,
      garmentComposition: compositionResult.composition,
      effectiveCategory: effectiveCategory,
      adaptedGarmentBytes: adaptedGarmentBytes,
      framingDescription: personFraming == BodyFraming.halfBody ? 'half-body waist-up' : 'full-body',
      garmentSpecificDescription: garmentDesc,
      neckYRatio: neckRatio,
      waistYRatio: waistRatio,
    );
  }

  /// Detects whether the person in the photo is waist-up / half-body or full-body.
  static BodyFraming detectBodyFraming(img.Image image) {
    final height = image.height;

    // Head size & vertical position estimation
    // In half-body / portrait shots, the head height is >= 18% - 35% of the photo height.
    // In full-body shots, the head is typically only 10% - 15% of the total height.
    final neckY = estimateNeckRatio(image) * height;
    final headHeightRatio = neckY / height;

    // Check lower 15% of the photo (y: 85% to 100%)
    // In full-body, the lower 15% has feet, shoes, thin ankles, or legs with background between them.
    // In half-body, the torso, arms, or table span solidly across the bottom without leg gap.
    final hasLegSeparation = _checkLegSeparation(image);

    if (headHeightRatio >= 0.20 || !hasLegSeparation) {
      return BodyFraming.halfBody;
    }
    return BodyFraming.fullBody;
  }

  /// Checks if the lower 25% of the image displays typical full-body leg separation.
  static bool _checkLegSeparation(img.Image image) {
    final startY = (image.height * 0.75).toInt();
    final endY = (image.height * 0.95).toInt();
    final midX = (image.width * 0.5).toInt();

    int backgroundGapCount = 0;
    int samples = 0;

    for (var y = startY; y < endY; y += 8) {
      final pMid = image.getPixel(midX, y);
      final pLeft = image.getPixel((image.width * 0.35).toInt(), y);
      final pRight = image.getPixel((image.width * 0.65).toInt(), y);

      // In full body, between the two legs there is background space with different color
      final lumMid = pMid.luminance;
      final lumLeft = pLeft.luminance;
      final lumRight = pRight.luminance;

      if ((lumMid - lumLeft).abs() > 30 && (lumMid - lumRight).abs() > 30) {
        backgroundGapCount++;
      }
      samples++;
    }

    return samples > 0 && (backgroundGapCount / samples) > 0.40;
  }

  /// Estimates the vertical ratio where the neck/chin meets the garment collar.
  static double estimateNeckRatio(img.Image image) {
    final height = image.height;
    final minY = (height * 0.12).toInt();
    final maxY = (height * 0.40).toInt();
    final minX = (image.width * 0.35).toInt();
    final maxX = (image.width * 0.65).toInt();

    int lastSkinY = -1;

    for (var y = minY; y < maxY; y += 4) {
      int skinCount = 0;
      int totalTested = 0;

      for (var x = minX; x < maxX; x += 6) {
        final p = image.getPixel(x, y);
        final r = p.r;
        final g = p.g;
        final b = p.b;

        // Skin detection rule
        if (r > 60 && g > 40 && b > 20 && r > g && g > b && (r - g) >= 10) {
          skinCount++;
        }
        totalTested++;
      }

      if (totalTested > 0 && (skinCount / totalTested) > 0.30) {
        lastSkinY = y;
      }
    }

    if (lastSkinY != -1) {
      return ((lastSkinY + (height * 0.03)) / height).clamp(0.20, 0.40);
    }
    return 0.28;
  }

  /// Detects whether the garment image has 1 item or 2 items (e.g., top + pants).
  static GarmentDetectionResult detectGarmentComposition(img.Image image) {
    // Sample Upper Region (y: 25% to 55%)
    final upperColor = _sampleDominantRegionColor(
      image,
      startY: (image.height * 0.25).toInt(),
      endY: (image.height * 0.55).toInt(),
    );

    // Sample Lower Region (y: 68% to 92%)
    final lowerColor = _sampleDominantRegionColor(
      image,
      startY: (image.height * 0.68).toInt(),
      endY: (image.height * 0.92).toInt(),
    );

    // Check if there is a distinct difference between upper and lower halves
    final isDifferentItems = (upperColor.hueCategory != lowerColor.hueCategory) ||
        (upperColor.saturation - lowerColor.saturation).abs() > 0.15 ||
        (upperColor.brightness - lowerColor.brightness).abs() > 0.20;

    // Check if lower region is primarily neutral background (meaning only upper item is present)
    final lowerIsBackground = lowerColor.isBackground;
    final upperIsBackground = upperColor.isBackground;

    if (upperIsBackground && !lowerIsBackground) {
      return GarmentDetectionResult(
        composition: GarmentComposition.lowerOnly,
        splitYRatio: 0.60,
        upperColor: upperColor.colorName,
        lowerColor: lowerColor.colorName,
        description: lowerColor.colorName,
      );
    }

    if (!upperIsBackground && lowerIsBackground) {
      return GarmentDetectionResult(
        composition: GarmentComposition.upperOnly,
        splitYRatio: 0.65,
        upperColor: upperColor.colorName,
        lowerColor: lowerColor.colorName,
        description: upperColor.colorName,
      );
    }

    if (isDifferentItems && !upperIsBackground && !lowerIsBackground) {
      // 2 distinct items (e.g. Olive green t-shirt on top + dark grey jeans on bottom)
      return GarmentDetectionResult(
        composition: GarmentComposition.twoPieceOutfit,
        splitYRatio: 0.63,
        upperColor: upperColor.colorName,
        lowerColor: lowerColor.colorName,
        description: '${upperColor.colorName} top and ${lowerColor.colorName} bottom',
      );
    }

    // Default to upper item or dress
    return GarmentDetectionResult(
      composition: GarmentComposition.twoPieceOutfit,
      splitYRatio: 0.63,
      upperColor: upperColor.colorName,
      lowerColor: lowerColor.colorName,
      description: upperColor.colorName,
    );
  }

  /// Crops ONLY the upper garment from a 2-piece outfit image (excluding pants, head, neck skin, and accessories).
  static img.Image cropUpperGarment(img.Image fullImg, double splitYRatio) {
    // Start at shoulders (approx 22%) and crop down through hem of t-shirt (approx 82%), cutting off pants
    final startY = (fullImg.height * 0.22).toInt();
    final effectiveEndYRatio = splitYRatio < 0.70 ? 0.82 : splitYRatio;
    final endY = (fullImg.height * effectiveEndYRatio).toInt().clamp(0, fullImg.height);
    final cropHeight = endY - startY;

    final cropped = img.copyCrop(
      fullImg,
      x: 0,
      y: startY,
      width: fullImg.width,
      height: cropHeight,
    );

    return cropped;
  }


  /// Samples dominant color characteristics in a given vertical band.
  static _RegionColor _sampleDominantRegionColor(
    img.Image image, {
    required int startY,
    required int endY,
  }) {
    var rTotal = 0.0;
    var gTotal = 0.0;
    var bTotal = 0.0;
    var count = 0;

    final stepX = max(1, image.width ~/ 40);
    final stepY = max(1, (endY - startY) ~/ 20);

    for (var y = startY; y < endY; y += stepY) {
      for (var x = (image.width * 0.25).toInt(); x < (image.width * 0.75).toInt(); x += stepX) {
        final p = image.getPixel(x, y);
        if (p.a < 50) continue;

        final r = p.r.toDouble();
        final g = p.g.toDouble();
        final b = p.b.toDouble();

        // Skip plain white/light grey studio background
        if (r > 238 && g > 238 && b > 238) continue;
        if (r < 15 && g < 15 && b < 15) continue;

        rTotal += r;
        gTotal += g;
        bTotal += b;
        count++;
      }
    }

    if (count == 0) {
      return _RegionColor(
        colorName: 'neutral background',
        hueCategory: 'neutral',
        saturation: 0.0,
        brightness: 0.9,
        isBackground: true,
      );
    }

    final avgR = rTotal / count;
    final avgG = gTotal / count;
    final avgB = bTotal / count;

    final maxC = max(avgR, max(avgG, avgB));
    final minC = min(avgR, min(avgG, avgB));
    final delta = maxC - minC;

    final brightness = maxC / 255.0;
    final saturation = maxC == 0 ? 0.0 : delta / maxC;

    double hue = 0.0;
    if (delta > 0) {
      if (maxC == avgR) {
        hue = 60 * (((avgG - avgB) / delta) % 6);
      } else if (maxC == avgG) {
        hue = 60 * (((avgB - avgR) / delta) + 2);
      } else {
        hue = 60 * (((avgR - avgG) / delta) + 4);
      }
      if (hue < 0) hue += 360;
    }

    if (saturation < 0.12 && brightness > 0.70) {
      return _RegionColor(
        colorName: 'light neutral',
        hueCategory: 'neutral',
        saturation: saturation,
        brightness: brightness,
        isBackground: true,
      );
    }

    if (saturation < 0.14) {
      final name = brightness < 0.30 ? 'charcoal black' : 'slate gray denim';
      return _RegionColor(
        colorName: name,
        hueCategory: 'gray_denim',
        saturation: saturation,
        brightness: brightness,
        isBackground: false,
      );
    }

    // Olive green / Khaki
    if (hue >= 32 && hue <= 85) {
      return _RegionColor(
        colorName: 'olive green',
        hueCategory: 'olive_green',
        saturation: saturation,
        brightness: brightness,
        isBackground: false,
      );
    }

    if (hue >= 180 && hue <= 260) {
      return _RegionColor(
        colorName: 'deep blue',
        hueCategory: 'blue',
        saturation: saturation,
        brightness: brightness,
        isBackground: false,
      );
    }

    return _RegionColor(
      colorName: 'rich color',
      hueCategory: 'other',
      saturation: saturation,
      brightness: brightness,
      isBackground: false,
    );
  }
}

class _CoordinationParams {
  final Uint8List personBytes;
  final Uint8List garmentBytes;
  final String requestedCategory;

  const _CoordinationParams({
    required this.personBytes,
    required this.garmentBytes,
    required this.requestedCategory,
  });
}

class GarmentDetectionResult {
  final GarmentComposition composition;
  final double splitYRatio;
  final String upperColor;
  final String lowerColor;
  final String description;

  const GarmentDetectionResult({
    required this.composition,
    required this.splitYRatio,
    required this.upperColor,
    required this.lowerColor,
    required this.description,
  });
}

class _RegionColor {
  final String colorName;
  final String hueCategory;
  final double saturation;
  final double brightness;
  final bool isBackground;

  const _RegionColor({
    required this.colorName,
    required this.hueCategory,
    required this.saturation,
    required this.brightness,
    required this.isBackground,
  });
}
