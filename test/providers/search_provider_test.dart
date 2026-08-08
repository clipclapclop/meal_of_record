import 'package:flutter_test/flutter_test.dart' hide isNotNull;
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:meal_of_record/providers/search_provider.dart';
import 'package:meal_of_record/services/database_service.dart';
import 'package:meal_of_record/services/open_food_facts_service.dart';
import 'package:meal_of_record/services/search_service.dart';
import 'package:meal_of_record/models/food.dart' as model;

import 'package:meal_of_record/models/search_mode.dart';
import 'search_provider_test.mocks.dart';

@GenerateMocks([DatabaseService, OffApiService, SearchService])
void main() {
  late SearchProvider searchProvider;
  late MockDatabaseService mockDatabaseService;
  late MockOffApiService mockOffApiService;
  late MockSearchService mockSearchService;

  setUp(() {
    mockDatabaseService = MockDatabaseService();
    mockOffApiService = MockOffApiService();
    mockSearchService = MockSearchService();
    searchProvider = SearchProvider(
      databaseService: mockDatabaseService,
      offApiService: mockOffApiService,
      searchService: mockSearchService,
    );
  });

  group('textSearch', () {
    test('should always call local search and update current query', () async {
      // Arrange
      final mockFoods = [
        model.Food(
          id: 1,
          name: 'Apple',
          emoji: '',
          calories: 52,
          protein: 0.3,
          fat: 0.2,
          carbs: 14,
          fiber: 2.4,
          source: 'test',
        ),
      ];
      when(mockSearchService.searchLocal('apple')).thenAnswer(
        (_) async => SearchResults(foods: mockFoods, displayNotes: {}),
      );

      // Act
      await searchProvider.textSearch('apple');

      // Assert
      expect(searchProvider.searchResults, mockFoods);
      verify(mockSearchService.searchLocal('apple')).called(1);
      verifyNever(mockSearchService.searchOff(any));
    });

    test(
      'should call getAllRecipesAsFoods when query is empty and mode is recipe',
      () async {
        // Arrange
        final mockRecipes = [
          model.Food(
            id: 2,
            name: 'Lasagna',
            emoji: '',
            calories: 300,
            protein: 20,
            fat: 15,
            carbs: 30,
            fiber: 2,
            source: 'recipe',
          ),
        ];

        when(mockSearchService.getAllRecipesAsFoods()).thenAnswer(
          (_) async => SearchResults(foods: mockRecipes, displayNotes: {}),
        );

        searchProvider.setSearchMode(SearchMode.recipe);

        // Act
        await searchProvider.textSearch('');

        // Assert
        expect(searchProvider.searchResults, mockRecipes);
        // Called once by setSearchMode (re-triggers search) and once by textSearch
        verify(mockSearchService.getAllRecipesAsFoods()).called(2);
        verifyNever(mockSearchService.searchLocal(any));
      },
    );

    test(
      'should call searchRecipesOnly when query is NOT empty and mode is recipe',
      () async {
        // Arrange
        final mockRecipes = [
          model.Food(
            id: 2,
            name: 'Lasagna',
            emoji: '',
            calories: 300,
            protein: 20,
            fat: 15,
            carbs: 30,
            fiber: 2,
            source: 'recipe',
          ),
        ];

        when(
          mockSearchService.searchRecipesOnly(
            'Lasagna',
            categoryId: anyNamed('categoryId'),
          ),
        ).thenAnswer(
          (_) async => SearchResults(foods: mockRecipes, displayNotes: {}),
        );

        // Stub getAllRecipesAsFoods since setSearchMode re-triggers search with empty query
        when(
          mockSearchService.getAllRecipesAsFoods(
            categoryId: anyNamed('categoryId'),
          ),
        ).thenAnswer((_) async => SearchResults(foods: [], displayNotes: {}));

        searchProvider.setSearchMode(SearchMode.recipe);

        // Act
        await searchProvider.textSearch('Lasagna');

        // Assert
        expect(searchProvider.searchResults, mockRecipes);
        verify(
          mockSearchService.searchRecipesOnly(
            'Lasagna',
            categoryId: anyNamed('categoryId'),
          ),
        ).called(1);
        verifyNever(
          mockSearchService.searchLocal(
            any,
            categoryId: anyNamed('categoryId'),
          ),
        );
      },
    );

    test('should set errorMessage on local search error', () async {
      // Arrange
      when(
        mockSearchService.searchLocal(any),
      ).thenThrow(Exception('Local DB error'));

      // Act
      await searchProvider.textSearch('error_query');

      // Assert
      expect(searchProvider.errorMessage, contains('Something went wrong'));
      expect(searchProvider.searchResults, isEmpty);
    });
  });

  group('performOffSearch', () {
    test('should do nothing if current query is empty', () async {
      // Act
      await searchProvider.performOffSearch();

      // Assert
      verifyZeroInteractions(mockSearchService);
    });

    test(
      'should call OFF search with the current query from the last textSearch',
      () async {
        // Arrange
        const query = 'skippy';
        final mockOffFoods = [
          model.Food(
            id: 2,
            name: 'Skippy Peanut Butter',
            emoji: '',
            calories: 588,
            protein: 25,
            fat: 50,
            carbs: 20,
            fiber: 2.0,
            source: 'off',
          ),
        ];
        // First, perform a text search to set the current query
        when(mockSearchService.searchLocal(query)).thenAnswer(
          (_) async => const SearchResults(foods: [], displayNotes: {}),
        );
        await searchProvider.textSearch(query);

        // Now, stub the OFF search
        when(mockSearchService.searchOff(query)).thenAnswer(
          (_) async => SearchResults(foods: mockOffFoods, displayNotes: {}),
        );

        // Act
        await searchProvider.performOffSearch();

        // Assert
        expect(searchProvider.searchResults, mockOffFoods);
        verify(mockSearchService.searchOff(query)).called(1);
      },
    );

    test('should set errorMessage on OFF search error', () async {
      // Arrange
      const query = 'error_query';
      // Set the current query
      when(mockSearchService.searchLocal(query)).thenAnswer(
        (_) async => const SearchResults(foods: [], displayNotes: {}),
      );
      await searchProvider.textSearch(query);

      // Stub the OFF search to throw an error
      when(
        mockSearchService.searchOff(query),
      ).thenThrow(Exception('OFF API error'));

      // Act
      await searchProvider.performOffSearch();

      // Assert
      expect(
        searchProvider.errorMessage,
        contains('Could not reach Open Food Facts'),
      );
      expect(searchProvider.searchResults, isEmpty);
    });
  });

  // Barcode search and other groups remain unchanged as their logic was not affected.
  group('barcodeSearch', () {
    test('should NOT query OffApiService if not found in database', () async {
      // Arrange
      when(
        mockDatabaseService.getFoodsByBarcode(any),
      ).thenAnswer((_) async => []);

      // Act
      await searchProvider.barcodeSearch('12345');

      // Assert
      expect(searchProvider.searchResults, isEmpty);
      expect(searchProvider.isBarcodeSearch, isTrue);
      expect(searchProvider.lastScannedBarcode, '12345');
      verify(mockDatabaseService.getFoodsByBarcode('12345')).called(1);
      verifyNever(mockOffApiService.fetchFoodByBarcode(any));
    });

    test('should return local food if found in database', () async {
      // Arrange
      final localFood = model.Food(
        id: 1,
        name: 'Local Food',
        emoji: '',
        calories: 100,
        protein: 10,
        fat: 5,
        carbs: 15,
        fiber: 0.0,
        source: 'live',
      );
      when(
        mockDatabaseService.getFoodsByBarcode(any),
      ).thenAnswer((_) async => [localFood]);

      // Act
      await searchProvider.barcodeSearch('12345');

      // Assert
      expect(searchProvider.searchResults, [localFood]);
      expect(searchProvider.isBarcodeSearch, isTrue);
      verify(mockDatabaseService.getFoodsByBarcode('12345')).called(1);
      verifyNever(mockOffApiService.fetchFoodByBarcode(any));
    });

    test('should clear barcode search state', () async {
      // Arrange
      when(
        mockDatabaseService.getFoodsByBarcode(any),
      ).thenAnswer((_) async => []);
      when(
        mockOffApiService.fetchFoodByBarcode(any),
      ).thenAnswer((_) async => null);

      // Act
      await searchProvider.barcodeSearch('12345');
      expect(searchProvider.isBarcodeSearch, isTrue);

      searchProvider.clearBarcodeSearchState();

      // Assert
      expect(searchProvider.isBarcodeSearch, isFalse);
      expect(searchProvider.lastScannedBarcode, isNull);
    });
  });

  group('barcodeOffSearch', () {
    test('should query OffApiService', () async {
      // Arrange
      final mockFood = model.Food(
        id: 0,
        name: 'OFF Food',
        emoji: '',
        calories: 200,
        protein: 20,
        fat: 10,
        carbs: 30,
        fiber: 0.0,
        source: 'off',
        sourceBarcode: '12345',
      );
      when(
        mockOffApiService.fetchFoodByBarcode('12345'),
      ).thenAnswer((_) async => mockFood);

      // Act
      await searchProvider.barcodeOffSearch('12345');

      // Assert
      expect(searchProvider.searchResults, [mockFood]);
      expect(searchProvider.isBarcodeSearch, isTrue);
      expect(searchProvider.lastScannedBarcode, '12345');
      verify(mockOffApiService.fetchFoodByBarcode('12345')).called(1);
    });

    test('should set errorMessage on error', () async {
      // Arrange
      when(
        mockOffApiService.fetchFoodByBarcode(any),
      ).thenThrow(Exception('Network error'));

      // Act
      await searchProvider.barcodeOffSearch('12345');

      // Assert
      expect(
        searchProvider.errorMessage,
        contains('Could not reach Open Food Facts'),
      );
      expect(searchProvider.searchResults, isEmpty);
    });
  });
  group('searchMode', () {
    test('should default to text', () {
      expect(searchProvider.searchMode, SearchMode.text);
    });

    test('should update searchMode and notify listeners', () {
      bool notified = false;
      searchProvider.addListener(() {
        notified = true;
      });

      searchProvider.setSearchMode(SearchMode.scan);

      expect(searchProvider.searchMode, SearchMode.scan);
      expect(notified, isTrue);
    });
  });
}
