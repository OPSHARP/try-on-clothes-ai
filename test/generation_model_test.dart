import 'package:flutter_test/flutter_test.dart';
import 'package:try_on_clothes_ai/data/models/generation_model.dart';

void main() {
  group('GenerationModel', () {
    test('creates instance with all fields including category', () {
      final now = DateTime.now();
      final model = GenerationModel(
        id: 'gen-123',
        userId: 'user-456',
        personImageUrl: 'https://example.com/person.png',
        clothesImageUrl: 'https://example.com/clothes.png',
        resultImageUrl: 'https://example.com/result.png',
        creditsUsed: 1,
        createdAt: now,
        status: GenerationStatus.completed,
        gender: 'female',
        bodySize: 'slim',
        style: 'realistic',
        quality: 'ultra',
        category: 'dresses',
      );

      expect(model.id, 'gen-123');
      expect(model.category, 'dresses');
      expect(model.gender, 'female');
      expect(model.status, GenerationStatus.completed);
    });

    test('serializes to map and deserializes from map correctly', () {
      final now = DateTime.now();
      final original = GenerationModel(
        id: 'gen-789',
        userId: 'user-001',
        personImageUrl: 'person.jpg',
        clothesImageUrl: 'clothes.jpg',
        resultImageUrl: 'result.jpg',
        creditsUsed: 1,
        createdAt: now,
        status: GenerationStatus.completed,
        category: 'upper_body',
      );

      final map = original.toMap();
      expect(map['category'], 'upper_body');
      expect(map['id'], 'gen-789');

      final deserialized = GenerationModel.fromMap(map);
      expect(deserialized.id, original.id);
      expect(deserialized.category, 'upper_body');
      expect(deserialized.status, GenerationStatus.completed);
    });

    test('handles backwards compatibility when category is absent in map', () {
      final legacyMap = {
        'id': 'legacy-id',
        'userId': 'local',
        'personImageUrl': 'p.png',
        'clothesImageUrl': 'c.png',
        'createdAt': DateTime.now().toIso8601String(),
        'status': 'completed',
        // 'category' is intentionally omitted
      };

      final model = GenerationModel.fromMap(legacyMap);
      expect(model.id, 'legacy-id');
      expect(model.category, isNull);
    });

    test('copyWith updates category and other fields properly', () {
      final model = GenerationModel(
        id: '1',
        userId: 'u1',
        personImageUrl: 'p',
        clothesImageUrl: 'c',
        createdAt: DateTime.now(),
        category: 'upper_body',
      );

      final updated = model.copyWith(category: 'lower_body');
      expect(updated.category, 'lower_body');
      expect(updated.id, '1');
    });
  });
}
