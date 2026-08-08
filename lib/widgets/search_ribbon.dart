import 'package:flutter/material.dart';
import 'package:meal_of_record/config/app_router.dart';
import 'package:provider/provider.dart';
import 'package:meal_of_record/providers/navigation_provider.dart';
import 'package:meal_of_record/providers/log_provider.dart';
import 'package:meal_of_record/providers/search_provider.dart';
import 'package:meal_of_record/models/search_mode.dart';

class SearchRibbon extends StatefulWidget {
  final bool isSearchActive;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onOffSearch;

  const SearchRibbon({
    super.key,
    this.isSearchActive = false,
    this.focusNode,
    this.onChanged,
    this.onOffSearch,
  });

  @override
  State<SearchRibbon> createState() => _SearchRibbonState();
}

class _SearchRibbonState extends State<SearchRibbon> {
  late TextEditingController _controller;
  SearchProvider? _searchProvider;
  bool _clearing = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.isSearchActive) {
      final provider = Provider.of<SearchProvider>(context, listen: false);
      if (_searchProvider != provider) {
        _searchProvider?.removeListener(_onSearchProviderChanged);
        _searchProvider = provider;
        _searchProvider!.addListener(_onSearchProviderChanged);
      }
    }
  }

  void _onSearchProviderChanged() {
    if (_searchProvider != null &&
        _searchProvider!.currentQuery.isEmpty &&
        _controller.text.isNotEmpty) {
      _clearing = true;
      _controller.clear();
      _clearing = false;
    }
  }

  @override
  void dispose() {
    _searchProvider?.removeListener(_onSearchProviderChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 4.0),
      child: Row(
        children: [
          Expanded(
            child: widget.isSearchActive
                ? TextField(
                    focusNode: widget.focusNode,
                    controller: _controller,
                    decoration: InputDecoration(
                      hintText: 'Search food...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12.0,
                      ),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _controller.clear();
                          widget.onChanged?.call('');
                        },
                      ),
                    ),
                    onChanged: (value) {
                      if (!_clearing) {
                        // Call onChanged first to set the query in SearchProvider
                        widget.onChanged?.call(value);

                        // Then auto-switch from food tab to text tab if needed
                        // This order is important: the query must be set before switching modes
                        // to prevent the _onSearchProviderChanged listener from clearing the text
                        final searchProvider = Provider.of<SearchProvider>(
                          context,
                          listen: false,
                        );
                        if (searchProvider.searchMode == SearchMode.food &&
                            value.isNotEmpty) {
                          searchProvider.setSearchMode(SearchMode.text);
                        }
                      }
                    },
                  )
                : GestureDetector(
                    key: const Key('food_search_text_field'),
                    onTap: () {
                      Provider.of<NavigationProvider>(
                        context,
                        listen: false,
                      ).goToSearch();
                      Navigator.pushNamed(context, AppRouter.searchRoute);
                    },
                    child: AbsorbPointer(
                      child: TextField(
                        controller: _controller,
                        decoration: InputDecoration(
                          hintText: 'Search food...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8.0),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12.0,
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 8.0),
          ElevatedButton(
            onPressed: widget.onOffSearch,
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.all(Colors.grey[800]),
            ),
            child: const Icon(Icons.language), // Globe icon
          ),
          const SizedBox(width: 8.0),
          ElevatedButton(
            onPressed: () async {
              final logProvider = Provider.of<LogProvider>(
                context,
                listen: false,
              );
              final navProvider = Provider.of<NavigationProvider>(
                context,
                listen: false,
              );

              await logProvider.logQueueToDatabase();

              if (context.mounted) {
                navProvider.changeTab(0); // Go to Overview
                Navigator.popUntil(context, (route) => route.isFirst);
              }
            },
            child: const Text('Log'),
          ),
        ],
      ),
    );
  }
}
