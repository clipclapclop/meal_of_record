import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_of_record/screens/food_edit_screen.dart';
import 'package:meal_of_record/services/database_service.dart';
import 'package:meal_of_record/services/live_database.dart' as live_db;
import 'package:meal_of_record/services/reference_database.dart' as ref_db;
import 'package:meal_of_record/widgets/unit_select_field.dart';
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

  testWidgets('serving dialog uses UnitSelectField and saves correctly', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: FoodEditScreen()));

    // Scroll down to Additional Servings section
    await tester.drag(find.byType(ListView), const Offset(0, -800));
    await tester.pumpAndSettle();

    expect(find.text('Additional Servings'), findsOneWidget);

    // Tap Add button
    await tester.tap(find.widgetWithIcon(IconButton, Icons.add_circle).last);
    await tester.pumpAndSettle();

    // Verify dialog is open
    expect(find.text('Add Serving'), findsOneWidget);

    // The screen also has a primary-serving UnitSelectField. Verify and use the
    // separate field inside this dialog rather than relying on a global count.
    final dialog = find.byType(AlertDialog);
    final dialogUnitField = find.descendant(
      of: dialog,
      matching: find.byType(UnitSelectField),
    );
    final dialogServingOption = find.descendant(
      of: dialog,
      matching: find.text('serving'),
    );
    expect(dialogUnitField, findsOneWidget);
    expect(dialogServingOption, findsOneWidget);

    // Change to custom unit
    await tester.tap(dialogServingOption); // Open dropdown
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom...').last); // Select Custom
    await tester.pumpAndSettle();

    // Verify it's now a text field
    expect(find.widgetWithText(TextFormField, 'Unit Name (e.g. cup, slice)'), findsOneWidget);

    // Enter details
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Unit Name (e.g. cup, slice)'),
      'Bowl',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Quantity (e.g. 1.0)'),
      '1.5',
    );
     await tester.enterText(
      find.widgetWithText(TextFormField, 'Weight for Quantity (g)'),
      '250',
    );

    // Save
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // Verify dialog closed
    expect(find.text('Add Serving'), findsNothing);

    // Verify serving is added to the list
    expect(find.text('1.5 Bowl'), findsOneWidget);
    expect(find.text('= 250g'), findsOneWidget);
  });

  testWidgets('editing existing serving uses UnitSelectField with correct value', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: FoodEditScreen()));

      // Add a serving first (programmatically or via UI, UI is safer here to rely on prev test)
      // Actually let's just use the UI flow quickly
      await tester.drag(find.byType(ListView), const Offset(0, -800));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithIcon(IconButton, Icons.add_circle).last);
      await tester.pumpAndSettle();
      
      await tester.tap(find.text('serving').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Custom...').last);
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, 'Unit Name (e.g. cup, slice)'), 'Bowl');
      await tester.enterText(find.widgetWithText(TextFormField, 'Weight for Quantity (g)'), '100');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // Now Edit it
      await tester.tap(find.byIcon(Icons.edit).last);
      await tester.pumpAndSettle();

      expect(find.text('Edit Serving'), findsOneWidget);
      
      // "Bowl" is custom, so UnitSelectField should show as text field
      expect(find.widgetWithText(TextFormField, 'Unit Name (e.g. cup, slice)'), findsOneWidget);
      expect(find.text('Bowl'), findsOneWidget);
  });
}
