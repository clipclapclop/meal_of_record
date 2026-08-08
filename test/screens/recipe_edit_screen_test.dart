import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:meal_of_record/providers/goals_provider.dart';
import 'package:meal_of_record/providers/recipe_provider.dart';
import 'package:meal_of_record/screens/recipe_edit_screen.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:meal_of_record/services/database_service.dart';

import 'package:meal_of_record/services/live_database.dart' as live_db;
import 'package:meal_of_record/services/reference_database.dart' as ref_db;
import 'package:drift/native.dart';

import 'recipe_edit_screen_test.mocks.dart';

@GenerateMocks([DatabaseService, GoalsProvider])
void main() {
  late MockGoalsProvider mockGoalsProvider;

  setUpAll(() {
    final liveDb = live_db.LiveDatabase(connection: NativeDatabase.memory());
    final refDb = ref_db.ReferenceDatabase(connection: NativeDatabase.memory());
    DatabaseService.initSingletonForTesting(liveDb, refDb);
  });

  setUp(() {
    mockGoalsProvider = MockGoalsProvider();
    when(mockGoalsProvider.useNetCarbs).thenReturn(false);
  });

  testWidgets(
    'RecipeEditScreen should show portion unit name field and dual macro rows',
    (tester) async {
      final provider = RecipeProvider();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<RecipeProvider>.value(value: provider),
            ChangeNotifierProvider<GoalsProvider>.value(
              value: mockGoalsProvider,
            ),
          ],
          child: const MaterialApp(home: RecipeEditScreen()),
        ),
      );

      // Verify fields exist
      expect(find.text('Portions Count'), findsOneWidget);
      expect(find.text('Portion Unit Name'), findsOneWidget);
      expect(find.text('Total Recipe Macros'), findsOneWidget);
      expect(find.text('Macros per serving'), findsOneWidget);
      expect(find.text('Categories'), findsOneWidget);

      // Enter portion unit name
      // Enter portion unit name
      // Open dropdown
      await tester.tap(find.text('serving')); // Initial value
      await tester.pumpAndSettle();

      // Select Custom...
      await tester.tap(find.text('Custom...'));
      await tester.pumpAndSettle();

      // Now enter text in the custom field
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Portion Unit Name'),
        'Muffin',
      );

      // Verify provider updated
      expect(provider.portionName, 'Muffin');

      await tester.pump();
      expect(find.text('Macros per Muffin'), findsOneWidget);
    },
  );
}
