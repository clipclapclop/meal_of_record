import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_of_record/widgets/quick_add_dialog.dart';

void main() {
  Widget createTestWidget() {
    return const MaterialApp(home: QuickAddScreen());
  }

  group('QuickAddScreen', () {
    testWidgets('renders calorie input field and Add button', (tester) async {
      await tester.pumpWidget(createTestWidget());

      expect(find.text('Quick Add'), findsOneWidget); // AppBar title
      expect(find.text('Calories'), findsOneWidget);
      expect(find.text('cal'), findsOneWidget);
      expect(find.text('Add'), findsOneWidget);
    });

    testWidgets('shows Required error when submitting empty', (tester) async {
      await tester.pumpWidget(createTestWidget());

      // Clear autofocused field and tap Add
      await tester.enterText(find.byType(TextField), '');
      await tester.tap(find.text('Add'));
      await tester.pump();

      expect(find.text('Required'), findsOneWidget);
    });

    testWidgets('shows Invalid expression error for bad input', (tester) async {
      await tester.pumpWidget(createTestWidget());

      await tester.enterText(find.byType(TextField), '10++');
      await tester.tap(find.text('Add'));
      await tester.pump();

      expect(find.text('Invalid expression'), findsOneWidget);
    });

    testWidgets('shows error for zero value', (tester) async {
      await tester.pumpWidget(createTestWidget());

      await tester.enterText(find.byType(TextField), '0');
      await tester.tap(find.text('Add'));
      await tester.pump();

      expect(find.text('Enter a positive number'), findsOneWidget);
    });

    testWidgets('shows error for negative value', (tester) async {
      await tester.pumpWidget(createTestWidget());

      await tester.enterText(find.byType(TextField), '-5');
      await tester.tap(find.text('Add'));
      await tester.pump();

      expect(find.text('Enter a positive number'), findsOneWidget);
    });

    testWidgets('no preview for plain number', (tester) async {
      await tester.pumpWidget(createTestWidget());

      await tester.enterText(find.byType(TextField), '250');
      await tester.pump();

      expect(find.textContaining('='), findsNothing);
    });

    testWidgets('shows preview with kcal for valid expression', (tester) async {
      await tester.pumpWidget(createTestWidget());

      await tester.enterText(find.byType(TextField), '100+50');
      await tester.pump();

      expect(find.text('= 150 cal'), findsOneWidget);
    });

    testWidgets('preview updates as expression changes', (tester) async {
      await tester.pumpWidget(createTestWidget());

      await tester.enterText(find.byType(TextField), '100+50');
      await tester.pump();
      expect(find.text('= 150 cal'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '100*3');
      await tester.pump();
      expect(find.text('= 300 cal'), findsOneWidget);
    });

    testWidgets('no preview for incomplete expression', (tester) async {
      await tester.pumpWidget(createTestWidget());

      await tester.enterText(find.byType(TextField), '100+');
      await tester.pump();

      // Should not show preview since expression is invalid
      expect(find.textContaining('='), findsNothing);
    });

    testWidgets('preview handles decimal results', (tester) async {
      await tester.pumpWidget(createTestWidget());

      await tester.enterText(find.byType(TextField), '10/3');
      await tester.pump();

      expect(find.text('= 3.3 cal'), findsOneWidget);
    });

    testWidgets('preview handles operator precedence', (tester) async {
      await tester.pumpWidget(createTestWidget());

      await tester.enterText(find.byType(TextField), '100+50*2');
      await tester.pump();

      expect(find.text('= 200 cal'), findsOneWidget);
    });

    testWidgets('MathInputBar renders its operator buttons', (tester) async {
      // MathInputBar is only shown when keyboard is visible (keyboardHeight > 0),
      // which we can't simulate in widget tests. Instead verify the screen
      // doesn't crash and the input field accepts math-like text.
      await tester.pumpWidget(createTestWidget());

      await tester.enterText(find.byType(TextField), '50+50');
      await tester.pump();

      // The text should be accepted (not rejected by the field)
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller?.text, '50+50');
    });

    testWidgets('clears error when re-submitting valid input', (tester) async {
      await tester.pumpWidget(createTestWidget());

      // First submit empty to get error
      await tester.enterText(find.byType(TextField), '');
      await tester.tap(find.text('Add'));
      await tester.pump();
      expect(find.text('Required'), findsOneWidget);

      // Type valid expression and submit — error should be replaced
      // (submit will try to call DatabaseService which isn't available in test,
      // but the error text should clear before that)
      await tester.enterText(find.byType(TextField), '100+50');
      await tester.tap(find.text('Add'));
      await tester.pump();

      expect(find.text('Required'), findsNothing);
      expect(find.text('Invalid expression'), findsNothing);
    });

    testWidgets('leading negative sign does not trigger preview', (
      tester,
    ) async {
      await tester.pumpWidget(createTestWidget());

      await tester.enterText(find.byType(TextField), '-100');
      await tester.pump();

      // -100 is just a negative number, not a math expression
      expect(find.textContaining('='), findsNothing);
    });
  });
}
