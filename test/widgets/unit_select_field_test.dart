import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_of_record/widgets/unit_select_field.dart';

void main() {
  group('UnitSelectField', () {
    testWidgets('shows dropdown with initial known value', (tester) async {
      String currentValue = 'cup';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return UnitSelectField(
                  label: 'Unit',
                  value: currentValue,
                  availableUnits: const ['cup', 'oz', 'gram'],
                  onChanged: (val) {
                    setState(() {
                      currentValue = val;
                    });
                  },
                );
              },
            ),
          ),
        ),
      );

      // Should show dropdown
      expect(find.byType(DropdownButton<String>), findsOneWidget);
      expect(find.text('cup'), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing);
    });

    testWidgets('shows text field with initial custom value', (tester) async {
      String currentValue = 'bowl';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return UnitSelectField(
                  label: 'Unit',
                  value: currentValue,
                  availableUnits: const ['cup', 'oz', 'gram'],
                  onChanged: (val) {
                    setState(() {
                      currentValue = val;
                    });
                  },
                );
              },
            ),
          ),
        ),
      );

      // Should show text field
      expect(find.byType(TextFormField), findsOneWidget);
      expect(find.text('bowl'), findsOneWidget);
      expect(find.byType(DropdownButton<String>), findsNothing);
    });

    testWidgets('switches to custom mode when "Custom..." is selected', (
      tester,
    ) async {
      String currentValue = 'cup';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return UnitSelectField(
                  label: 'Unit',
                  value: currentValue,
                  availableUnits: const ['cup', 'oz'],
                  onChanged: (val) {
                    setState(() {
                      currentValue = val;
                    });
                  },
                );
              },
            ),
          ),
        ),
      );

      // Open dropdown
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();

      // Select Custom...
      await tester.tap(find.text('Custom...'));
      await tester.pumpAndSettle();

      // Should now be text field
      expect(find.byType(TextFormField), findsOneWidget);
      expect(find.byType(DropdownButton<String>), findsNothing);
    });

    testWidgets('switches back to dropdown mode when close icon is tapped', (
      tester,
    ) async {
      String currentValue = 'bowl'; // Custom

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return UnitSelectField(
                  label: 'Unit',
                  value: currentValue,
                  availableUnits: const ['cup', 'oz'],
                  onChanged: (val) {
                    setState(() {
                      currentValue = val;
                    });
                  },
                );
              },
            ),
          ),
        ),
      );

      // Verify custom mode
      expect(find.byType(TextFormField), findsOneWidget);

      // Tap close icon
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      // Should be dropdown mode defaulting to 'serving' (as per implementation)
      expect(find.byType(DropdownButton<String>), findsOneWidget);
      expect(find.text('serving'), findsOneWidget);
    });

    testWidgets(
      'updates text field when external value changes in custom mode',
      (tester) async {
        String currentValue = 'bowl';

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  return Column(
                    children: [
                      UnitSelectField(
                        label: 'Unit',
                        value: currentValue,
                        availableUnits: const ['cup'],
                        onChanged: (val) {
                          setState(() {
                            currentValue = val;
                          });
                        },
                      ),
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            currentValue = 'plate';
                          });
                        },
                        child: const Text('Change Value'),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );

        expect(find.text('bowl'), findsOneWidget);

        await tester.tap(find.text('Change Value'));
        await tester.pumpAndSettle();

        expect(find.text('plate'), findsOneWidget);
      },
    );

    testWidgets(
      'does not switch to dropdown while typing custom value that matches existing unit',
      (tester) async {
        String currentValue = 'c';

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  return UnitSelectField(
                    label: 'Unit',
                    value: currentValue,
                    availableUnits: const ['cup'],
                    onChanged: (val) {
                      setState(() {
                        currentValue = val;
                      });
                    },
                  );
                },
              ),
            ),
          ),
        );

        // Initial state: 'c' is not in ['cup'], so it should be custom (text field)
        expect(find.byType(TextFormField), findsOneWidget);

        // Type 'u' -> 'cu'
        await tester.enterText(find.byType(TextFormField), 'cu');
        await tester.pumpAndSettle();
        expect(find.byType(TextFormField), findsOneWidget); // Still custom

        // Type 'p' -> 'cup'
        // 'cup' IS in availableUnits. Logic might force it to dropdown.
        await tester.enterText(find.byType(TextFormField), 'cup');
        await tester.pumpAndSettle();

        // If checks pass, it means the widget stayed as TextFormField.
        // If it fails (finds DropdownButton), the bug is confirmed.
        expect(
          find.byType(TextFormField),
          findsOneWidget,
          reason: 'Should remain text field to allow further typing',
        );
      },
    );

    testWidgets('shows Custom option when allowCustom is true', (tester) async {
      String currentValue = 'cup';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return UnitSelectField(
                  label: 'Unit',
                  value: currentValue,
                  availableUnits: const ['cup', 'oz'],
                  allowCustom: true,
                  onChanged: (val) {
                    setState(() {
                      currentValue = val;
                    });
                  },
                );
              },
            ),
          ),
        ),
      );

      // Open dropdown
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();

      // Should show Custom... option
      expect(find.text('Custom...'), findsOneWidget);
    });

    testWidgets('hides Custom option when allowCustom is false', (
      tester,
    ) async {
      String currentValue = 'cup';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return UnitSelectField(
                  label: 'Unit',
                  value: currentValue,
                  availableUnits: const ['cup', 'oz'],
                  allowCustom: false,
                  onChanged: (val) {
                    setState(() {
                      currentValue = val;
                    });
                  },
                );
              },
            ),
          ),
        ),
      );

      // Open dropdown
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();

      // Should NOT show Custom... option
      expect(find.text('Custom...'), findsNothing);

      // Should still show the available units
      expect(find.text('cup'), findsWidgets);
      expect(find.text('oz'), findsOneWidget);
    });
  });
}
