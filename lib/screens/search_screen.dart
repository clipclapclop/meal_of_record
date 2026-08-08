import 'package:flutter/material.dart';
import 'package:meal_of_record/config/app_router.dart';
import 'package:meal_of_record/widgets/discard_dialog.dart';
import 'package:meal_of_record/widgets/log_queue_top_ribbon.dart';
import 'package:provider/provider.dart';
import 'package:meal_of_record/providers/search_provider.dart';
import 'package:meal_of_record/providers/log_provider.dart';
import 'package:meal_of_record/providers/navigation_provider.dart';
import 'package:meal_of_record/widgets/search_ribbon.dart';
import 'package:meal_of_record/models/search_mode.dart';
import 'package:meal_of_record/widgets/search/search_mode_tabs.dart';
import 'package:meal_of_record/widgets/search/text_search_view.dart';
import 'package:meal_of_record/widgets/search/recipe_search_view.dart';
import 'package:meal_of_record/widgets/search/food_search_view.dart';
import 'package:meal_of_record/models/search_config.dart';

class SearchScreen extends StatefulWidget {
  final SearchConfig config;

  const SearchScreen({super.key, required this.config});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navProvider = Provider.of<NavigationProvider>(
        context,
        listen: false,
      );

      if (navProvider.shouldFocusSearch) {
        _focusNode.requestFocus();
        navProvider.resetSearchFocus();
      }

      // Ensure logged portions are fresh so bar charts show correct values
      Provider.of<LogProvider>(
        context,
        listen: false,
      ).loadLoggedPortionsForDate(DateTime.now());

      // Load solo food suggestions for empty-query state
      Provider.of<SearchProvider>(context, listen: false).loadSuggestions();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !widget.config.showQueueStats,
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: widget.config.showQueueStats ? 180 : null,
          automaticallyImplyLeading: !widget.config.showQueueStats,
          title: widget.config.showQueueStats
              ? Consumer<LogProvider>(
                  builder: (context, logProvider, child) {
                    return LogQueueTopRibbon(
                      leading: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () async {
                          final logProvider = Provider.of<LogProvider>(
                            context,
                            listen: false,
                          );
                          final navProvider = Provider.of<NavigationProvider>(
                            context,
                            listen: false,
                          );

                          bool shouldPop = false;
                          if (logProvider.logQueue.isNotEmpty) {
                            final discard = await showDiscardDialog(context);
                            if (discard == true) {
                              logProvider.clearQueue();
                              navProvider.goBack();
                              shouldPop = true;
                            }
                          } else {
                            navProvider.goBack();
                            shouldPop = true;
                          }

                          if (shouldPop) {
                            // Defer the pop operation to the next frame
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) {
                                Navigator.pop(context);
                              }
                            });
                          }
                        },
                      ),
                      arrowDirection: Icons.arrow_drop_down,
                      onArrowPressed: () {
                        Navigator.pushNamed(context, AppRouter.logQueueRoute);
                      },
                      logProvider: logProvider,
                    );
                  },
                )
              : Text(widget.config.title),
        ),
        body: Column(
          children: [
            const SearchModeTabs(),
            Expanded(
              child: Consumer<SearchProvider>(
                builder: (context, searchProvider, child) {
                  return _buildBody(searchProvider.searchMode);
                },
              ),
            ),
            SearchRibbon(
              isSearchActive: true,
              focusNode: _focusNode,
              onChanged: (query) {
                Provider.of<SearchProvider>(
                  context,
                  listen: false,
                ).textSearch(query);
              },
              onOffSearch: () {
                Provider.of<SearchProvider>(
                  context,
                  listen: false,
                ).performOffSearch();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(SearchMode searchMode) {
    switch (searchMode) {
      case SearchMode.text:
      case SearchMode.scan:
        // Scan mode now immediately launches scanner and returns to text mode
        // with results, so both cases show the text search view
        return TextSearchView(config: widget.config);
      case SearchMode.recipe:
        return RecipeSearchView(config: widget.config);
      case SearchMode.food:
        return FoodSearchView(config: widget.config);
    }
  }
}
