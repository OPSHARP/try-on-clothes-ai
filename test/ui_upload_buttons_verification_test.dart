import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Verify home_screen.dart removes sample model and change photo buttons', () {
    final homeScreenFile = File('lib/features/home/screens/home_screen.dart');
    expect(homeScreenFile.existsSync(), isTrue);

    final content = homeScreenFile.readAsStringSync();

    // 1. Verify "Sample Model" and model_male.jpg are completely removed
    expect(content.contains('Sample Model'), isFalse,
        reason: 'Sample Model badge should not exist in home_screen.dart');
    expect(content.contains('assets/images/presets/model_male.jpg'), isFalse,
        reason: 'model_male.jpg sample photo should not exist in home_screen.dart');

    // 2. Verify "Change Photo" / "Change Your Photo" / "Change Cloth Photo" buttons are removed
    expect(content.contains("'Change Photo'"), isFalse,
        reason: 'Change Photo button label should be removed');
    expect(content.contains("'Change Your Photo'"), isFalse,
        reason: 'Change Your Photo button label should be removed');
    expect(content.contains("'Change Cloth Photo'"), isFalse,
        reason: 'Change Cloth Photo button label should be removed');

    // 3. Verify "Choose Your Photo" and "Choose Cloth Photo" are present
    expect(content.contains('Choose Your Photo'), isTrue,
        reason: 'Choose Your Photo should be displayed');
    expect(content.contains('Choose Cloth Photo'), isTrue,
        reason: 'Choose Cloth Photo should be displayed');

    // 4. Verify user can tap photo directly to change
    expect(content.contains('Tap photo to change'), isTrue,
        reason: 'User should see tap photo to change hint on preview');
    expect(content.contains('Tap cloth to change'), isTrue,
        reason: 'User should see tap cloth to change hint on preview');
  });

  test('Verify try_on_screen.dart uses Choose Your Photo and Choose Cloth Photo', () {
    final tryOnScreenFile = File('lib/features/try_on/screens/try_on_screen.dart');
    expect(tryOnScreenFile.existsSync(), isTrue);

    final content = tryOnScreenFile.readAsStringSync();

    // Labels should be "Choose Your Photo" and "Choose Cloth Photo"
    expect(content.contains('Choose Your Photo'), isTrue);
    expect(content.contains('Choose Cloth Photo'), isTrue);

    // Old generic labels should be replaced
    expect(content.contains('Upload Person Photo'), isFalse);
    expect(content.contains('Upload Clothing Image'), isFalse);

    // Direct tap to change should be supported
    expect(content.contains('Tap to change'), isTrue);
  });
}
