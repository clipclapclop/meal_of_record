import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_of_record/services/database_service.dart';
import 'package:meal_of_record/services/live_database.dart';
import 'package:meal_of_record/services/reference_database.dart' as ref;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  late DatabaseService svc;
  late LiveDatabase live;
  late ref.ReferenceDatabase reference;

  setUp(() {
    live = LiveDatabase(connection: NativeDatabase.memory());
    reference = ref.ReferenceDatabase(connection: NativeDatabase.memory());
    svc = DatabaseService.forTesting(live, reference);
  });

  tearDown(() async {
    await live.close();
    await reference.close();
  });

  Future<int> insertFood({
    required String name,
    required double cal,
    double protein = 0.1,
    double fat = 0.05,
    double carbs = 0.08,
    double fiber = 0.02,
    bool hidden = false,
    int? parentId,
  }) {
    return live
        .into(live.foods)
        .insert(
          FoodsCompanion.insert(
            name: name,
            source: 'live',
            caloriesPerGram: cal,
            proteinPerGram: protein,
            fatPerGram: fat,
            carbsPerGram: carbs,
            fiberPerGram: fiber,
            hidden: Value(hidden),
            parentId: Value(parentId),
          ),
        );
  }

  group('findDuplicateFoodGroups', () {
    test('groups two foods with macros within threshold', () async {
      await insertFood(name: 'Apple A', cal: 0.520);
      await insertFood(name: 'Apple B', cal: 0.523);
      final groups = await svc.findDuplicateFoodGroups(thresholdPct: 1.0);
      expect(groups.length, 1);
      expect(groups.first.length, 2);
    });

    test('does NOT group foods outside threshold', () async {
      await insertFood(name: 'Apple', cal: 0.52);
      await insertFood(name: 'Banana', cal: 0.40);
      final groups = await svc.findDuplicateFoodGroups(thresholdPct: 1.0);
      expect(groups, isEmpty);
    });

    test('threshold widens group membership', () async {
      await insertFood(name: 'X', cal: 0.50, protein: 0.100);
      await insertFood(name: 'Y', cal: 0.50, protein: 0.102); // 2% off protein
      final strict = await svc.findDuplicateFoodGroups(thresholdPct: 1.0);
      expect(strict, isEmpty);
      final loose = await svc.findDuplicateFoodGroups(thresholdPct: 5.0);
      expect(loose.length, 1);
    });

    test('transitively groups via union-find', () async {
      await insertFood(name: 'A', cal: 0.500);
      await insertFood(name: 'B', cal: 0.503);
      await insertFood(name: 'C', cal: 0.506);
      // A-B within 1%, B-C within 1%, A-C just outside 1%
      // Union-find should still cluster all three.
      final groups = await svc.findDuplicateFoodGroups(thresholdPct: 1.0);
      expect(groups.length, 1);
      expect(groups.first.length, 3);
    });

    test('includes hidden (soft-deleted) foods', () async {
      await insertFood(name: 'Apple', cal: 0.52);
      await insertFood(name: 'Apple', cal: 0.52, hidden: true);
      final groups = await svc.findDuplicateFoodGroups(thresholdPct: 1.0);
      expect(groups.length, 1);
      expect(groups.first.any((f) => f.hidden), isTrue);
    });

    test(
      'excludes system pseudo-foods but includes off/FOUNDATION imports',
      () async {
        // A user-created food.
        await insertFood(name: 'Apple A', cal: 0.5);
        // A food imported from OpenFoodFacts (still in live DB, just different
        // provenance). Same macros.
        await live
            .into(live.foods)
            .insert(
              FoodsCompanion.insert(
                name: 'Some OFF Apple',
                source: 'off',
                caloriesPerGram: 0.5,
                proteinPerGram: 0.1,
                fatPerGram: 0.05,
                carbsPerGram: 0.08,
                fiberPerGram: 0.02,
              ),
            );
        // A system pseudo-food with matching macros — must be excluded.
        await live
            .into(live.foods)
            .insert(
              FoodsCompanion.insert(
                name: 'Quick Add',
                source: 'system',
                caloriesPerGram: 0.5,
                proteinPerGram: 0.1,
                fatPerGram: 0.05,
                carbsPerGram: 0.08,
                fiberPerGram: 0.02,
              ),
            );
        final groups = await svc.findDuplicateFoodGroups(thresholdPct: 1.0);
        expect(groups.length, 1);
        expect(groups.first.length, 2);
        expect(
          groups.first.any((f) => f.source == 'system'),
          isFalse,
          reason: 'system pseudo-foods must never appear in a duplicate group',
        );
      },
    );
  });

  group('findVersionChainGroups', () {
    test('finds a 2-row chain', () async {
      final old = await insertFood(name: 'Apple old', cal: 0.52);
      await insertFood(name: 'Apple new', cal: 0.52, parentId: old);
      final chains = await svc.findVersionChainGroups();
      expect(chains.length, 1);
      expect(chains.first.length, 2);
    });

    test('finds a multi-step chain via transitive parentId', () async {
      final a = await insertFood(name: 'A v1', cal: 0.5);
      final b = await insertFood(name: 'A v2', cal: 0.5, parentId: a);
      await insertFood(name: 'A v3', cal: 0.5, parentId: b);
      final chains = await svc.findVersionChainGroups();
      expect(chains.length, 1);
      expect(chains.first.length, 3);
    });

    test('does NOT return singletons (no parent edges)', () async {
      await insertFood(name: 'Alone A', cal: 0.5);
      await insertFood(name: 'Alone B', cal: 0.6);
      final chains = await svc.findVersionChainGroups();
      expect(chains, isEmpty);
    });

    test('finds chains even when macros diverge', () async {
      // The "rev on rename" bug created chains; macros may or may not match.
      // findVersionChainGroups must surface them regardless.
      final old = await insertFood(name: 'Renamed old', cal: 0.5);
      await insertFood(name: 'Renamed new', cal: 0.9, parentId: old);
      final chains = await svc.findVersionChainGroups();
      expect(chains.length, 1);
      expect(chains.first.length, 2);
    });

    test('excludes system source', () async {
      // A system food can't have a real parent chain but defensively assert.
      final a = await insertFood(name: 'A', cal: 0.5);
      await live
          .into(live.foods)
          .insert(
            FoodsCompanion.insert(
              name: 'System B',
              source: 'system',
              caloriesPerGram: 0.5,
              proteinPerGram: 0.1,
              fatPerGram: 0.05,
              carbsPerGram: 0.08,
              fiberPerGram: 0.02,
              parentId: Value(a),
            ),
          );
      final chains = await svc.findVersionChainGroups();
      expect(
        chains,
        isEmpty,
        reason: 'a chain with only one non-system row is not a chain',
      );
    });
  });

  group('mergeFoods', () {
    test(
      'repoints logs, recipe items, parent chains, drops portions/barcodes',
      () async {
        final keeper = await insertFood(name: 'Apple', cal: 0.52);
        final loser = await insertFood(name: 'Apple', cal: 0.522);

        // Loser has a portion.
        await live
            .into(live.foodPortions)
            .insert(
              FoodPortionsCompanion.insert(
                foodId: loser,
                unit: 'small',
                grams: 120.0,
                quantity: 1.0,
              ),
            );

        // Loser has a barcode.
        await live
            .into(live.foodBarcodes)
            .insert(
              FoodBarcodesCompanion.insert(foodId: loser, barcode: '1234'),
            );

        // Two logs pointing at the loser.
        final now = DateTime.now().millisecondsSinceEpoch;
        await live
            .into(live.loggedPortions)
            .insert(
              LoggedPortionsCompanion.insert(
                foodId: Value(loser),
                logTimestamp: now,
                grams: 100.0,
                unit: 'g',
                quantity: 100.0,
              ),
            );
        await live
            .into(live.loggedPortions)
            .insert(
              LoggedPortionsCompanion.insert(
                foodId: Value(loser),
                logTimestamp: now + 1,
                grams: 50.0,
                unit: 'g',
                quantity: 50.0,
              ),
            );

        // A recipe item referencing the loser.
        final recipeId = await live
            .into(live.recipes)
            .insert(
              RecipesCompanion.insert(name: 'Snack', createdTimestamp: now),
            );
        await live
            .into(live.recipeItems)
            .insert(
              RecipeItemsCompanion.insert(
                recipeId: recipeId,
                ingredientFoodId: Value(loser),
                grams: 50.0,
                unit: 'g',
              ),
            );

        // A version-chain heir whose parent is the loser.
        final heir = await insertFood(
          name: 'Apple v2',
          cal: 0.55,
          parentId: loser,
        );

        final result = await svc.mergeFoods(keeperId: keeper, loserId: loser);

        expect(result.loggedRepointed, 2);
        expect(result.recipeRepointed, 1);
        expect(result.parentChainsRepointed, 1);
        expect(result.portionsDropped, 1);
        expect(result.barcodesDropped, 1);
        expect(result.sampleLoggedTimestamps.length, 2);

        // Loser is gone.
        final loserRow = await (live.select(
          live.foods,
        )..where((t) => t.id.equals(loser))).getSingleOrNull();
        expect(loserRow, isNull);

        // Logs now point at keeper.
        final keeperLogs = await (live.select(
          live.loggedPortions,
        )..where((t) => t.foodId.equals(keeper))).get();
        expect(keeperLogs.length, 2);

        // Recipe item now points at keeper.
        final keeperRecipeItems = await (live.select(
          live.recipeItems,
        )..where((t) => t.ingredientFoodId.equals(keeper))).get();
        expect(keeperRecipeItems.length, 1);

        // Heir's parentId is repointed.
        final heirRow = await (live.select(
          live.foods,
        )..where((t) => t.id.equals(heir))).getSingle();
        expect(heirRow.parentId, keeper);

        // Loser's portions and barcodes are gone.
        final loserPortions = await (live.select(
          live.foodPortions,
        )..where((t) => t.foodId.equals(loser))).get();
        expect(loserPortions, isEmpty);
        final loserBarcodes = await (live.select(
          live.foodBarcodes,
        )..where((t) => t.foodId.equals(loser))).get();
        expect(loserBarcodes, isEmpty);
      },
    );

    test('rejects self-merge', () async {
      final id = await insertFood(name: 'Apple', cal: 0.5);
      expect(
        () => svc.mergeFoods(keeperId: id, loserId: id),
        throwsArgumentError,
      );
    });

    test('rejects missing food', () async {
      final id = await insertFood(name: 'Apple', cal: 0.5);
      expect(
        () => svc.mergeFoods(keeperId: id, loserId: 99999),
        throwsArgumentError,
      );
    });
  });

  group('getMergePredictedCounts', () {
    test('reports the exact rows the merge will touch', () async {
      final keeper = await insertFood(name: 'Apple', cal: 0.52);
      final loser = await insertFood(name: 'Apple', cal: 0.522);
      final now = DateTime.now().millisecondsSinceEpoch;

      await live
          .into(live.loggedPortions)
          .insert(
            LoggedPortionsCompanion.insert(
              foodId: Value(loser),
              logTimestamp: now,
              grams: 10.0,
              unit: 'g',
              quantity: 10.0,
            ),
          );
      await live
          .into(live.foodPortions)
          .insert(
            FoodPortionsCompanion.insert(
              foodId: loser,
              unit: 'piece',
              grams: 50.0,
              quantity: 1.0,
            ),
          );

      final predicted = await svc.getMergePredictedCounts(loserId: loser);
      expect(predicted.loggedToRepoint, 1);
      expect(predicted.portionsToDrop, 1);
      expect(predicted.recipeToRepoint, 0);
      expect(predicted.parentChainsToRepoint, 0);
      expect(predicted.barcodesToDrop, 0);

      // Sanity: counts hold after a real merge.
      final result = await svc.mergeFoods(keeperId: keeper, loserId: loser);
      expect(result.loggedRepointed, predicted.loggedToRepoint);
      expect(result.portionsDropped, predicted.portionsToDrop);
    });
  });
}
