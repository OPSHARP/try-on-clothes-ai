import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:try_on_clothes_ai/core/services/in_app_update_service.dart';

void main() {
  group('InAppUpdateService', () {
    test('instantiates with default idle states', () {
      final service = InAppUpdateService();
      expect(service.isChecking, isFalse);
      expect(service.isDownloading, isFalse);
      expect(service.updateInfo, isNull);
    });

    test('isSupported evaluates consistent with platform environment', () {
      final expected = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
      expect(InAppUpdateService.isSupported, expected);
    });
  });
}
