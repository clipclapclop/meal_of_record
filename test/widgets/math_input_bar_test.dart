import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_of_record/widgets/math_input_bar.dart';

void main() {
  late TextEditingController controller;

  setUp(() {
    controller = TextEditingController();
  });

  tearDown(() {
    controller.dispose();
  });

  Widget createTestWidget(TextEditingController ctrl) {
    return MaterialApp(
      home: Scaffold(body: MathInputBar(controller: ctrl)),
    );
  }

  testWidgets('renders all 6 buttons', (tester) async {
    await tester.pumpWidget(createTestWidget(controller));

    expect(find.text('<'), findsOneWidget);
    expect(find.text('>'), findsOneWidget);
    expect(find.text('+'), findsOneWidget);
    expect(find.text('-'), findsOneWidget);
    expect(find.text('*'), findsOneWidget);
    expect(find.text('/'), findsOneWidget);
  });

  testWidgets('inserts operator at cursor position', (tester) async {
    controller.text = '100';
    controller.selection = TextSelection.collapsed(offset: 3);

    await tester.pumpWidget(createTestWidget(controller));

    await tester.tap(find.text('+'));
    await tester.pump();

    expect(controller.text, '100+');
    expect(controller.selection.baseOffset, 4);
  });

  testWidgets('inserts operator in middle of text', (tester) async {
    controller.text = '10050';
    controller.selection = TextSelection.collapsed(offset: 3);

    await tester.pumpWidget(createTestWidget(controller));

    await tester.tap(find.text('*'));
    await tester.pump();

    expect(controller.text, '100*50');
    expect(controller.selection.baseOffset, 4);
  });

  testWidgets('moves cursor left', (tester) async {
    controller.text = '100+50';
    controller.selection = TextSelection.collapsed(offset: 4);

    await tester.pumpWidget(createTestWidget(controller));

    await tester.tap(find.text('<'));
    await tester.pump();

    expect(controller.selection.baseOffset, 3);
  });

  testWidgets('moves cursor right', (tester) async {
    controller.text = '100+50';
    controller.selection = TextSelection.collapsed(offset: 3);

    await tester.pumpWidget(createTestWidget(controller));

    await tester.tap(find.text('>'));
    await tester.pump();

    expect(controller.selection.baseOffset, 4);
  });

  testWidgets('cursor does not go below 0', (tester) async {
    controller.text = '100';
    controller.selection = TextSelection.collapsed(offset: 0);

    await tester.pumpWidget(createTestWidget(controller));

    await tester.tap(find.text('<'));
    await tester.pump();

    expect(controller.selection.baseOffset, 0);
  });

  testWidgets('cursor does not go past text length', (tester) async {
    controller.text = '100';
    controller.selection = TextSelection.collapsed(offset: 3);

    await tester.pumpWidget(createTestWidget(controller));

    await tester.tap(find.text('>'));
    await tester.pump();

    expect(controller.selection.baseOffset, 3);
  });

  testWidgets('collapses range selection on left cursor move', (tester) async {
    controller.text = '100+50';
    controller.selection = const TextSelection(baseOffset: 1, extentOffset: 4);

    await tester.pumpWidget(createTestWidget(controller));

    await tester.tap(find.text('<'));
    await tester.pump();

    expect(controller.selection.isCollapsed, true);
    expect(controller.selection.baseOffset, 1);
  });

  testWidgets('collapses range selection on right cursor move', (tester) async {
    controller.text = '100+50';
    controller.selection = const TextSelection(baseOffset: 1, extentOffset: 4);

    await tester.pumpWidget(createTestWidget(controller));

    await tester.tap(find.text('>'));
    await tester.pump();

    expect(controller.selection.isCollapsed, true);
    expect(controller.selection.baseOffset, 4);
  });
}
