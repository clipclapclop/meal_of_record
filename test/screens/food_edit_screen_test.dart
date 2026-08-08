import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_of_record/models/food.dart' as model;
import 'package:meal_of_record/models/food_serving.dart';
import 'package:meal_of_record/screens/food_edit_screen.dart';
import 'package:meal_of_record/services/database_service.dart';
import 'package:meal_of_record/services/live_database.dart' as live_db;
import 'package:meal_of_record/services/reference_database.dart' as ref_db;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late live_db.LiveDatabase liveDb;
  late ref_db.ReferenceDatabase refDb;

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
  });

  setUp(() {
    liveDb = live_db.LiveDatabase(connection: NativeDatabase.memory());
    refDb = ref_db.ReferenceDatabase(connection: NativeDatabase.memory());
    DatabaseService.initSingletonForTesting(liveDb, refDb);
  });

  tearDown(() async {
    await liveDb.close();
    await refDb.close();
  });

  testWidgets('renders create food form', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: FoodEditScreen()));

    expect(find.text('Create Food'), findsOneWidget);
    expect(find.text('Food Name'), findsOneWidget);

    // Scroll down to see Nutrition section (pushed down by barcode section)
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();

    expect(find.text('Nutrition'), findsOneWidget);

    // Scroll down more to see bottom elements
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();

    expect(find.text('Additional Servings'), findsOneWidget);
  });

  testWidgets('validates required fields', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: FoodEditScreen()));

    // Tap save without entering name
    await tester.tap(find.byIcon(Icons.check));
    await tester.pumpAndSettle();

    expect(find.text('Required'), findsOneWidget);
  });

  testWidgets('saves new food correctly', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: FoodEditScreen()));

    // New foods default to per-serving mode, switch to 100g mode for this test
    await tester.tap(find.text('Serving'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('100g').last);
    await tester.pumpAndSettle();

    // Enter details
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Food Name'),
      'Test Banana',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Notes (Optional)'),
      'Yummy',
    );

    Finder findMacroField(String label) {
      return find.descendant(
        of: find.widgetWithText(Row, label),
        matching: find.byType(TextFormField),
      );
    }

    await tester.enterText(findMacroField('Calories'), '89');
    await tester.enterText(findMacroField('Protein'), '1.1');
    await tester.enterText(findMacroField('Fat'), '0.3');
    await tester.enterText(findMacroField('Carbs'), '22.8');
    await tester.enterText(findMacroField('Fiber'), '2.6');

    // Tap save
    await tester.ensureVisible(find.byIcon(Icons.check));
    await tester.tap(find.byIcon(Icons.check));

    // Wait for async save
    await tester.pumpAndSettle();

    // Verify it popped
    expect(find.byType(FoodEditScreen), findsNothing);

    // Verify DB
    final savedFood = await liveDb.select(liveDb.foods).getSingle();
    expect(savedFood.name, 'Test Banana');
    expect(savedFood.usageNote, 'Yummy');
    expect(savedFood.caloriesPerGram, closeTo(0.89, 0.001));
  });

  testWidgets('calculates per serving correctly', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: FoodEditScreen()));

    // New foods now default to per-serving mode
    // The primary serving section should be visible with Qty, Unit, and Grams fields

    // Fill in the primary serving: 1 Slice = 30g
    // First, select a unit - tap on the unit dropdown
    await tester.tap(find.text('serving'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom...').last);
    await tester.pumpAndSettle();

    // Enter custom unit name
    await tester.enterText(find.widgetWithText(TextFormField, 'Unit'), 'Slice');

    // Enter grams for the serving
    await tester.enterText(find.widgetWithText(TextFormField, 'Grams'), '30');

    // Scroll down to see Calories field (pushed down by barcode section)
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();

    // Enter 100 calories per Slice (30g)
    // So per gram: 100 / 30 = 3.333
    Finder findMacroField(String label) {
      return find.descendant(
        of: find.widgetWithText(Row, label),
        matching: find.byType(TextFormField),
      );
    }

    await tester.enterText(findMacroField('Calories'), '100');

    // Fill metadata - scroll up to find Food Name
    await tester.drag(find.byType(ListView), const Offset(0, 500));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Food Name'),
      'Test Bread',
    );

    // Save
    await tester.tap(find.byIcon(Icons.check));
    await tester.pumpAndSettle();

    // Verify DB
    final savedFood = await liveDb.select(liveDb.foods).getSingle();
    expect(savedFood.name, 'Test Bread');
    expect(savedFood.caloriesPerGram, closeTo(3.333, 0.001));
  });

  group('Barcode Management', () {
    Future<void> scrollToBarcodes(WidgetTester tester) async {
      // Scroll down to find barcode section - use ensureVisible
      final barcodeLabel = find.text('Barcodes');
      await tester.scrollUntilVisible(
        barcodeLabel,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
    }

    testWidgets('displays barcode section', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: FoodEditScreen()));
      await scrollToBarcodes(tester);

      expect(find.text('Barcodes'), findsOneWidget);
    });

    testWidgets('shows initial barcode when provided', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: FoodEditScreen(initialBarcode: '1234567890123'),
        ),
      );
      await scrollToBarcodes(tester);

      expect(find.text('1234567890123'), findsOneWidget);
    });

    testWidgets('can add barcode via text field', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: FoodEditScreen()));
      await scrollToBarcodes(tester);

      // Find the barcode text field by hint text
      final barcodeField = find.widgetWithText(TextField, 'Type barcode...');
      await tester.ensureVisible(barcodeField);
      await tester.pumpAndSettle();

      // Enter barcode
      await tester.enterText(barcodeField, '9876543210');

      // Tap the add button (Icons.add)
      final addButton = find.byIcon(Icons.add);
      await tester.ensureVisible(addButton);
      await tester.tap(addButton);
      await tester.pumpAndSettle();

      // Barcode should now be in the list
      expect(find.text('9876543210'), findsOneWidget);
    });

    testWidgets('can remove barcode', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: FoodEditScreen(initialBarcode: '1234567890123'),
        ),
      );
      await scrollToBarcodes(tester);

      // Find the barcode text
      expect(find.text('1234567890123'), findsOneWidget);

      // Find and tap the delete icon (close button in ListTile)
      final closeButtons = find.byIcon(Icons.close);
      await tester.tap(closeButtons.first);
      await tester.pumpAndSettle();

      // Barcode should be removed
      expect(find.text('1234567890123'), findsNothing);
    });

    testWidgets('saves food with barcodes', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: FoodEditScreen(initialBarcode: '1234567890123'),
        ),
      );

      // New foods default to per-serving mode, switch to 100g mode for simplicity
      await tester.tap(find.text('Serving'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('100g').last);
      await tester.pumpAndSettle();

      // Enter food name
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Food Name'),
        'Barcode Test Food',
      );

      // Enter calories
      Finder findMacroField(String label) {
        return find.descendant(
          of: find.widgetWithText(Row, label),
          matching: find.byType(TextFormField),
        );
      }

      await tester.enterText(findMacroField('Calories'), '100');

      // Save
      await tester.tap(find.byIcon(Icons.check));
      await tester.pumpAndSettle();

      // Verify food was saved
      final savedFood = await liveDb.select(liveDb.foods).getSingle();
      expect(savedFood.name, 'Barcode Test Food');

      // Verify barcode was saved
      final barcodes = await DatabaseService.instance.getBarcodesByFoodId(
        savedFood.id,
      );
      expect(barcodes, contains('1234567890123'));
    });

    testWidgets('loads existing barcodes when editing food', (tester) async {
      // First create a food with barcodes
      final foodId = await liveDb
          .into(liveDb.foods)
          .insert(
            live_db.FoodsCompanion.insert(
              name: 'Existing Food',
              source: 'user_created',
              caloriesPerGram: 1.0,
              proteinPerGram: 0.0,
              fatPerGram: 0.0,
              carbsPerGram: 0.0,
              fiberPerGram: 0.0,
            ),
          );

      // Add barcodes to it
      await DatabaseService.instance.addBarcodeToFood(foodId, '1111111111');
      await DatabaseService.instance.addBarcodeToFood(foodId, '2222222222');

      // Create the food model
      final food = model.Food(
        id: foodId,
        name: 'Existing Food',
        source: 'live',
        calories: 1.0,
        protein: 0.0,
        fat: 0.0,
        carbs: 0.0,
        fiber: 0.0,
        servings: [
          const FoodServing(foodId: 0, unit: 'g', grams: 1.0, quantity: 1.0),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: FoodEditScreen(
            originalFood: food,
            contextType: FoodEditContext.search,
            isCopy: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await scrollToBarcodes(tester);

      // Both barcodes should be visible
      expect(find.text('1111111111'), findsOneWidget);
      expect(find.text('2222222222'), findsOneWidget);
    });

    testWidgets('empty barcode is not added', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: FoodEditScreen()));
      await scrollToBarcodes(tester);

      // Count ListTiles before (should be 0 for barcodes)
      final listTileCountBefore = tester
          .widgetList(find.byType(ListTile))
          .length;

      // Find and tap Add button without entering anything
      final addButton = find.byIcon(Icons.add);
      await tester.ensureVisible(addButton);
      await tester.tap(addButton);
      await tester.pumpAndSettle();

      // No new ListTile should be added (no barcode added)
      final listTileCountAfter = tester
          .widgetList(find.byType(ListTile))
          .length;
      expect(listTileCountAfter, listTileCountBefore);
    });

    testWidgets('duplicate barcode is not added', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: FoodEditScreen(initialBarcode: '1234567890')),
      );
      await scrollToBarcodes(tester);

      // Verify barcode is there
      expect(find.text('1234567890'), findsOneWidget);

      // Find the barcode text field and try to add the same barcode
      final barcodeField = find.widgetWithText(TextField, 'Type barcode...');
      await tester.ensureVisible(barcodeField);
      await tester.enterText(barcodeField, '1234567890');

      final addButton = find.byIcon(Icons.add);
      await tester.ensureVisible(addButton);
      await tester.tap(addButton);
      await tester.pumpAndSettle();

      // Should still only have one instance of the barcode
      expect(find.text('1234567890'), findsOneWidget);
    });
  });

  group('Math expression support', () {
    testWidgets('evaluates expression in Calories field on blur', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: FoodEditScreen()));

      // Switch to 100g mode for simplicity
      await tester.tap(find.text('Serving'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('100g').last);
      await tester.pumpAndSettle();

      // Scroll down to see Calories field
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();

      // Find the Calories field
      Finder findMacroField(String label) {
        return find.descendant(
          of: find.widgetWithText(Row, label),
          matching: find.byType(TextFormField),
        );
      }

      // Enter expression
      await tester.enterText(findMacroField('Calories'), '100+50');
      await tester.pumpAndSettle();

      // Tap another field to blur Calories
      await tester.enterText(findMacroField('Protein'), '10');
      await tester.pumpAndSettle();

      // Verify the Calories field was evaluated
      final caloriesField = tester.widget<TextFormField>(
        findMacroField('Calories'),
      );
      expect(caloriesField.controller!.text, '150');
    });

    testWidgets('_parse handles expressions on save', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: FoodEditScreen()));

      // Switch to 100g mode
      await tester.tap(find.text('Serving'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('100g').last);
      await tester.pumpAndSettle();

      // Enter food name
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Food Name'),
        'Math Test Food',
      );

      // Scroll to see macro fields
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();

      Finder findMacroField(String label) {
        return find.descendant(
          of: find.widgetWithText(Row, label),
          matching: find.byType(TextFormField),
        );
      }

      // Enter expression in Calories (don't blur - test that _parse handles it)
      await tester.enterText(findMacroField('Calories'), '10*3');

      // Save
      await tester.ensureVisible(find.byIcon(Icons.check));
      await tester.tap(find.byIcon(Icons.check));
      await tester.pumpAndSettle();

      // Verify it popped (save succeeded)
      expect(find.byType(FoodEditScreen), findsNothing);

      // Verify DB - 10*3 = 30 per 100g = 0.3 per gram
      final savedFood = await liveDb.select(liveDb.foods).getSingle();
      expect(savedFood.name, 'Math Test Food');
      expect(savedFood.caloriesPerGram, closeTo(0.3, 0.001));
    });
  });
}
