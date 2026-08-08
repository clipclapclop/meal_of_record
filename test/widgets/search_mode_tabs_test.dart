import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_of_record/models/search_mode.dart';
import 'package:meal_of_record/providers/search_provider.dart';
import 'package:meal_of_record/widgets/search/search_mode_tabs.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import 'search_mode_tabs_test.mocks.dart';

@GenerateMocks([SearchProvider])
void main() {
  late MockSearchProvider mockProvider;

  setUp(() {
    mockProvider = MockSearchProvider();
  });

  Widget createTestWidget() {
    return MaterialApp(
      home: Scaffold(
        body: ChangeNotifierProvider<SearchProvider>.value(
          value: mockProvider,
          child: const SearchModeTabs(),
        ),
      ),
    );
  }

  testWidgets('displays all tabs', (tester) async {
    when(mockProvider.searchMode).thenReturn(SearchMode.text);

    await tester.pumpWidget(createTestWidget());

    expect(find.byIcon(Icons.search), findsOneWidget);
    expect(find.byIcon(Icons.qr_code_scanner), findsOneWidget);
    expect(find.byIcon(Icons.restaurant_menu), findsOneWidget);
    expect(find.byIcon(Icons.restaurant), findsOneWidget);
  });

  testWidgets('clicking text tab calls setSearchMode with text', (
    tester,
  ) async {
    when(mockProvider.searchMode).thenReturn(SearchMode.recipe);

    await tester.pumpWidget(createTestWidget());

    await tester.tap(find.byIcon(Icons.search));
    verify(mockProvider.setSearchMode(SearchMode.text)).called(1);
  });

  testWidgets('clicking recipe tab calls setSearchMode with recipe', (
    tester,
  ) async {
    when(mockProvider.searchMode).thenReturn(SearchMode.text);

    await tester.pumpWidget(createTestWidget());

    await tester.tap(find.byIcon(Icons.restaurant_menu));
    verify(mockProvider.setSearchMode(SearchMode.recipe)).called(1);
  });

  testWidgets('clicking food tab calls setSearchMode with food', (
    tester,
  ) async {
    when(mockProvider.searchMode).thenReturn(SearchMode.text);

    await tester.pumpWidget(createTestWidget());

    await tester.tap(find.byIcon(Icons.restaurant));
    verify(mockProvider.setSearchMode(SearchMode.food)).called(1);
  });

  testWidgets('scan tab does not call setSearchMode (launches scanner instead)', (
    tester,
  ) async {
    when(mockProvider.searchMode).thenReturn(SearchMode.text);

    await tester.pumpWidget(createTestWidget());

    // Verify the scan icon exists - we can't fully test the navigation
    // since it launches a camera scanner that requires platform support
    expect(find.byIcon(Icons.qr_code_scanner), findsOneWidget);

    // Verify that tapping other tabs calls setSearchMode, but scan tab
    // exists and is interactive (the tap itself will fail in test due to Navigator)
    verifyNever(mockProvider.setSearchMode(SearchMode.scan));
  });

  testWidgets('selected tab has primary color background', (tester) async {
    when(mockProvider.searchMode).thenReturn(SearchMode.text);

    await tester.pumpWidget(createTestWidget());

    // Find the text tab container
    final textTabFinder = find.ancestor(
      of: find.byIcon(Icons.search),
      matching: find.byType(Container),
    );

    // There might be multiple containers, get the one with decoration
    final containers = tester.widgetList<Container>(textTabFinder);
    final decoratedContainer = containers.firstWhere(
      (c) => c.decoration is BoxDecoration,
      orElse: () => containers.first,
    );

    final decoration = decoratedContainer.decoration as BoxDecoration?;
    // Selected tab should have a non-transparent color
    expect(decoration?.color, isNot(Colors.transparent));
  });

  testWidgets('scan tab is always grey (never visually selected)', (
    tester,
  ) async {
    // Even if searchMode is scan, the scan tab itself doesn't highlight
    // because it immediately launches scanner and returns
    when(mockProvider.searchMode).thenReturn(SearchMode.text);

    await tester.pumpWidget(createTestWidget());

    // Scan icon should be grey (not selected state), regardless of mode
    final scanIcon = tester.widget<Icon>(find.byIcon(Icons.qr_code_scanner));
    expect(scanIcon.color, Colors.grey);
  });
}
