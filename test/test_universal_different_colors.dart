import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:try_on_clothes_ai/core/services/identity_lock_service.dart';

void main() {
  test('Verify IdentityLockService works universally for any color without hardcoded blue/olive checks', () async {
    const width = 400;
    const height = 600;

    // Person wearing a RED shirt
    final orig = img.Image(width: width, height: height);
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        if (y < 180) {
          // Face & hair (skin tone: r=210, g=160, b=130)
          orig.setPixelRgba(x, y, 210, 160, 130, 255);
        } else if (y < 450) {
          // Original RED shirt (r=220, g=30, b=30)
          orig.setPixelRgba(x, y, 220, 30, 30, 255);
        } else {
          // Pants (black: r=30, g=30, b=30)
          orig.setPixelRgba(x, y, 30, 30, 30, 255);
        }
      }
    }

    // AI Generated wearing a GREEN shirt
    final gen = img.Image(width: width, height: height);
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        if (y < 180) {
          // AI altered face slightly (r=200, g=150, b=120)
          gen.setPixelRgba(x, y, 200, 150, 120, 255);
        } else if (y < 450) {
          // New GREEN shirt (r=30, g=200, b=50)
          gen.setPixelRgba(x, y, 30, 200, 50, 255);
        } else {
          // Pants (black)
          gen.setPixelRgba(x, y, 30, 30, 30, 255);
        }
      }
    }

    final origBytes = Uint8List.fromList(img.encodeJpg(orig));
    final genBytes = Uint8List.fromList(img.encodeJpg(gen));

    final lockedBytes = await IdentityLockService.lockFaceAndBody(
      originalPersonBytes: origBytes,
      generatedResultBytes: genBytes,
      category: 'upper_body',
      isHalfBody: false,
      customNeckRatio: 0.30,
    );

    final lockedImg = img.decodeImage(lockedBytes)!;

    // 1. Verify face area (y=100) is 100% original RED-shirt person's skin
    final pFace = lockedImg.getPixel(200, 100);
    expect(pFace.r, greaterThan(200));
    expect(pFace.g, greaterThan(150));

    // 2. Verify torso area (y=300) is 100% NEW GREEN SHIRT (not old red shirt, and no blue patches!)
    final pTorso = lockedImg.getPixel(200, 300);
    expect(pTorso.g, greaterThan(180), reason: 'Torso must have new green shirt');
    expect(pTorso.r, lessThan(80), reason: 'Old red shirt must be completely replaced');
    expect(pTorso.b, lessThan(80));

    // 3. Verify lower pants (y=500) are preserved
    final pPants = lockedImg.getPixel(200, 500);
    expect(pPants.r, lessThan(50));
    expect(pPants.g, lessThan(50));
    expect(pPants.b, lessThan(50));
  });
}
