import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:try_on_clothes_ai/core/models/ai_provider_config.dart';
import 'package:try_on_clothes_ai/core/services/impl/openai_service.dart';
import 'package:try_on_clothes_ai/core/services/ai_service.dart';

void main() {
  group('OpenAI (ChatGPT / DALL-E 3) Provider Tests', () {
    test('OpenAiConfig is registered in AiProviderConfig.builtIn', () {
      final config = AiProviderConfig.fromId('openai');
      expect(config, isNotNull);
      expect(config!.name, contains('OpenAI'));
      expect(config.signupUrl, 'https://platform.openai.com/api-keys');
      expect(config.apiKeyHint, contains('sk-'));
    });

    test('OpenAiService validates API key prefix', () {
      final validService = OpenAiService(apiKey: 'sk-proj-test1234567890');
      expect(validService.isAvailable, true);

      final invalidService = OpenAiService(apiKey: 'invalid_key');
      expect(invalidService.isAvailable, false);

      final emptyService = OpenAiService(apiKey: '');
      expect(emptyService.isAvailable, false);
    });

    test(
      'Throws AiServiceException when generating without valid key',
      () async {
        final service = OpenAiService(apiKey: '');
        expect(
          () => service.generateTryOn(
            personImage: Uint8List(10),
            clothesImage: Uint8List(10),
          ),
          throwsA(isA<AiServiceException>()),
        );
      },
    );
  });
}
