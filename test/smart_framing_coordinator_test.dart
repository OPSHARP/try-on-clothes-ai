import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:try_on_clothes_ai/core/services/smart_framing_coordinator.dart';

void main() {
  test('SmartFramingCoordinator correctly analyzes and plans adaptation', () async {
    // Generate synthetic person and garment images in-memory (no local machine paths)
    final personImg = img.Image(width: 200, height: 300);
    final garmentImg = img.Image(width: 200, height: 300);

    final personBytes = Uint8List.fromList(img.encodeJpg(personImg));
    final garmentBytes = Uint8List.fromList(img.encodeJpg(garmentImg));

    final plan = await SmartFramingCoordinator.analyzeAndAdapt(
      personBytes: personBytes,
      garmentBytes: garmentBytes,
      requestedCategory: 'upper_body',
    );

    expect(plan.effectiveCategory, isNotEmpty);
    expect(plan.adaptedGarmentBytes, isNotEmpty);
    expect(plan.neckYRatio, isPositive);
    expect(plan.waistYRatio, isPositive);
  });
}
