import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:try_on_clothes_ai/core/services/on_device_stylist_service.dart';

void main() {
  test('OnDeviceStylistService analyzes synthetic image and returns styling profile', () async {
    // Generate a red synthetic image for clothes
    final clothes = img.Image(width: 80, height: 80);
    for (var y = 0; y < 80; y++) {
      for (var x = 0; x < 80; x++) {
        clothes.setPixelRgba(x, y, 220, 20, 30, 255);
      }
    }
    final clothesBytes = img.encodeJpg(clothes);

    // Generate a neutral studio portrait for person
    final person = img.Image(width: 80, height: 80);
    for (var y = 0; y < 80; y++) {
      for (var x = 0; x < 80; x++) {
        person.setPixelRgba(x, y, 140, 140, 140, 255);
      }
    }
    final personBytes = img.encodeJpg(person);

    final analysis = await OnDeviceStylistService.analyzeAndStyleGarment(
      personImage: personBytes,
      clothesImage: clothesBytes,
      category: 'upper_body',
      userDescription: 'slim fit cotton shirt',
    );

    expect(analysis.dominantColor, contains('crimson red'));
    expect(analysis.fabricType, isNotEmpty);
    expect(analysis.lightingEnvironment, isNotEmpty);
    expect(analysis.enrichedPrompt, contains('slim fit cotton shirt'));
    expect(analysis.enrichedPrompt, contains('crimson red'));
    expect(analysis.enrichedPrompt, contains('8k resolution'));
    expect(analysis.conciseDescription, contains('slim fit cotton shirt'));
  });
}
