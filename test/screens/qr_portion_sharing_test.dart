import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_of_record/models/food.dart';
import 'package:meal_of_record/models/food_portion.dart';
import 'package:meal_of_record/models/food_serving.dart';

/// Replicates the serialization logic from QrPortionSharingScreen for unit testing.
/// This avoids needing a full widget test with SharedPreferences for pure logic tests.
Map<String, dynamic> serializePortions(
  List<FoodPortion> portions, {
  required bool includeImages,
}) {
  final foods = <Map<String, dynamic>>[];
  final portionsList = <Map<String, dynamic>>[];

  final foodMap = <String, Food>{};
  for (final p in portions) {
    final key = '${p.food.id}_${p.food.source}';
    foodMap[key] = p.food;
  }

  for (final entry in foodMap.entries) {
    final foodJson = entry.value.toJson();

    if (!includeImages) {
      final thumb = foodJson['thumbnail'] as String?;
      if (thumb != null && !thumb.startsWith('http')) {
        foodJson['thumbnail'] = null;
      }
    }

    foods.add(foodJson);
  }

  for (final p in portions) {
    portionsList.add({
      'food_key': '${p.food.id}_${p.food.source}',
      'grams': p.grams,
      'unit': p.unit,
    });
  }

  return {'type': 'portions', 'foods': foods, 'portions': portionsList};
}

List<String> buildChunks(String jsonStr, {int chunkSize = 600}) {
  if (jsonStr.length <= chunkSize) {
    return ['1/1|$jsonStr'];
  }
  final total = (jsonStr.length / chunkSize).ceil();
  final chunks = <String>[];
  for (int i = 0; i < total; i++) {
    int end = (i + 1) * chunkSize;
    if (end > jsonStr.length) end = jsonStr.length;
    final sub = jsonStr.substring(i * chunkSize, end);
    chunks.add('${i + 1}/$total|$sub');
  }
  return chunks;
}

void main() {
  Food makeFood(
    int id,
    String name, {
    String? thumbnail,
    String source = 'test',
  }) {
    return Food(
      id: id,
      name: name,
      calories: 1.0,
      protein: 0.1,
      fat: 0.05,
      carbs: 0.2,
      fiber: 0.02,
      source: source,
      thumbnail: thumbnail,
      servings: [FoodServing(foodId: id, unit: 'g', grams: 1.0, quantity: 1.0)],
    );
  }

  group('Portion serialization', () {
    test('serializes FoodPortions to JSON with type "portions"', () {
      final food1 = makeFood(1, 'Chicken');
      final food2 = makeFood(2, 'Rice');
      final portions = [
        FoodPortion(food: food1, grams: 200, unit: 'g'),
        FoodPortion(food: food2, grams: 300, unit: 'g'),
      ];

      final result = serializePortions(portions, includeImages: false);

      expect(result['type'], 'portions');
      expect((result['foods'] as List).length, 2);
      expect((result['portions'] as List).length, 2);

      final firstPortion =
          (result['portions'] as List)[0] as Map<String, dynamic>;
      expect(firstPortion['food_key'], '1_test');
      expect(firstPortion['grams'], 200);
      expect(firstPortion['unit'], 'g');
    });

    test('deduplicates foods with same id and source', () {
      final food = makeFood(1, 'Chicken');
      final portions = [
        FoodPortion(food: food, grams: 100, unit: 'g'),
        FoodPortion(food: food, grams: 200, unit: 'g'),
      ];

      final result = serializePortions(portions, includeImages: false);

      expect((result['foods'] as List).length, 1);
      expect((result['portions'] as List).length, 2);
    });
  });

  group('Deserialization', () {
    test('JSON round-trip produces equivalent portions', () {
      final food1 = makeFood(1, 'Chicken');
      final food2 = makeFood(2, 'Rice');
      final originalPortions = [
        FoodPortion(food: food1, grams: 200, unit: 'g'),
        FoodPortion(food: food2, grams: 300, unit: 'g'),
      ];

      final serialized = serializePortions(
        originalPortions,
        includeImages: false,
      );
      final jsonStr = jsonEncode(serialized);
      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;

      expect(decoded['type'], 'portions');

      // Rebuild food lookup
      final foodList = (decoded['foods'] as List).cast<Map<String, dynamic>>();
      final foodLookup = <String, Food>{};
      for (final fJson in foodList) {
        final food = Food.fromJson(fJson);
        foodLookup['${food.id}_${food.source}'] = food;
      }

      final portionsList = (decoded['portions'] as List)
          .cast<Map<String, dynamic>>();
      final rebuilt = <FoodPortion>[];
      for (final pJson in portionsList) {
        final foodKey = pJson['food_key'] as String;
        final grams = (pJson['grams'] as num).toDouble();
        final unit = pJson['unit'] as String;
        final food = foodLookup[foodKey]!;
        rebuilt.add(FoodPortion(food: food, grams: grams, unit: unit));
      }

      expect(rebuilt.length, 2);
      expect(rebuilt[0].food.name, 'Chicken');
      expect(rebuilt[0].grams, 200);
      expect(rebuilt[1].food.name, 'Rice');
      expect(rebuilt[1].grams, 300);
    });
  });

  group('Thumbnail toggle', () {
    test('include images ON keeps all thumbnail references', () {
      final food = makeFood(1, 'Chicken', thumbnail: 'local:abc-123');
      final portions = [FoodPortion(food: food, grams: 100, unit: 'g')];

      final result = serializePortions(portions, includeImages: true);
      final foodJson = (result['foods'] as List)[0] as Map<String, dynamic>;

      expect(foodJson['thumbnail'], 'local:abc-123');
    });

    test('include images OFF strips local: thumbnail references', () {
      final food = makeFood(1, 'Chicken', thumbnail: 'local:abc-123');
      final portions = [FoodPortion(food: food, grams: 100, unit: 'g')];

      final result = serializePortions(portions, includeImages: false);
      final foodJson = (result['foods'] as List)[0] as Map<String, dynamic>;

      expect(foodJson['thumbnail'], isNull);
    });

    test('include images OFF keeps valid URL thumbnails', () {
      final food = makeFood(
        1,
        'Cheese',
        thumbnail: 'https://images.openfoodfacts.org/images/products/123.jpg',
      );
      final portions = [FoodPortion(food: food, grams: 50, unit: 'g')];

      final result = serializePortions(portions, includeImages: false);
      final foodJson = (result['foods'] as List)[0] as Map<String, dynamic>;

      expect(foodJson['thumbnail'], startsWith('http'));
    });
  });

  group('Chunking', () {
    test('small payload fits in single chunk', () {
      final chunks = buildChunks('hello');
      expect(chunks.length, 1);
      expect(chunks[0], '1/1|hello');
    });

    test('large payload splits correctly with index/total|data format', () {
      final longData = 'A' * 1500; // 1500 chars, should produce 3 chunks of 600
      final chunks = buildChunks(longData);

      expect(chunks.length, 3);
      expect(chunks[0], startsWith('1/3|'));
      expect(chunks[1], startsWith('2/3|'));
      expect(chunks[2], startsWith('3/3|'));

      // Reassemble and verify
      final sb = StringBuffer();
      for (final chunk in chunks) {
        final data = chunk.split('|').sublist(1).join('|');
        sb.write(data);
      }
      expect(sb.toString(), longData);
    });
  });
}
