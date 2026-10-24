import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:try_on_clothes_ai/core/services/identity_lock_service.dart';

void main() {
  test('IdentityLockService strictly preserves original face and head pixels', () async {
    // 1. Original person image: top 20% has pure blue face/hair (0, 0, 255)
    final original = img.Image(width: 60, height: 100);
    for (var y = 0; y < 100; y++) {
      for (var x = 0; x < 60; x++) {
        if (y < 20) {
          original.setPixelRgba(x, y, 0, 0, 255, 255); // Original face
        } else {
          original.setPixelRgba(x, y, 100, 100, 100, 255); // Original body
        }
      }
    }
    final origBytes = Uint8List.fromList(img.encodeJpg(original, quality: 95));

    // 2. AI generated try-on image: model distorted face to green (0, 255, 0), new clothes in red (255, 0, 0)
    final generated = img.Image(width: 60, height: 100);
    for (var y = 0; y < 100; y++) {
      for (var x = 0; x < 60; x++) {
        if (y < 20) {
          generated.setPixelRgba(x, y, 0, 255, 0, 255); // Distorted AI face
        } else if (y < 60) {
          generated.setPixelRgba(x, y, 255, 0, 0, 255); // New red shirt
        } else {
          generated.setPixelRgba(x, y, 50, 50, 50, 255);
        }
      }
    }
    final genBytes = Uint8List.fromList(img.encodeJpg(generated, quality: 95));

    // 3. Lock Face & Body
    final lockedBytes = await IdentityLockService.lockFaceAndBody(
      originalPersonBytes: origBytes,
      generatedResultBytes: genBytes,
      category: 'upper_body',
    );

    expect(lockedBytes.isNotEmpty, true);
    final lockedImg = img.decodeImage(lockedBytes)!;

    // Check Face Zone (y = 5, x = 30): MUST be pure original blue (not AI green)
    final facePixel = lockedImg.getPixel(30, 5);
    expect(facePixel.b > 200, true, reason: 'Face must preserve original blue channel');
    expect(facePixel.g < 50, true, reason: 'Face must not be replaced by AI green');

    // Check Torso Garment Zone (y = 45, x = 30): MUST be new garment red
    final garmentPixel = lockedImg.getPixel(30, 45);
    expect(garmentPixel.r > 200, true, reason: 'Garment torso must apply the new red clothing');
  });
}
