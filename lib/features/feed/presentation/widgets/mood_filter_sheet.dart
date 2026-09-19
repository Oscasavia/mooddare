import 'dart:math' as math;
import 'package:flutter/material.dart';

class MoodFilterSheet extends StatefulWidget {
  final List<MapEntry<String, String>> moods;
  final String? selectedId;
  const MoodFilterSheet({super.key, required this.moods, this.selectedId});
  @override
  State<MoodFilterSheet> createState() => _MoodFilterSheetState();
}

class _MoodFilterSheetState extends State<MoodFilterSheet> {
  final _search = TextEditingController();
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final matches = widget.moods
        .where((mood) => mood.value.toLowerCase().contains(query))
        .toList();
    final media = MediaQuery.of(context);
    // Grow above the keyboard, while leaving room for the sheet's drag handle.
    final height = math.min(
      media.size.height * .65,
      math.max(
        0.0,
        media.size.height - media.viewInsets.bottom - media.padding.top - 60,
      ),
    );
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: height,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                child: Text(
                  'Filter by mood',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: TextField(
                  key: const ValueKey('mood_filter_search'),
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search moods',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear mood search',
                            onPressed: () => setState(_search.clear),
                            icon: const Icon(Icons.close_rounded),
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  key: const ValueKey('mood_filter_results'),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  children: [
                    ListTile(
                      title: const Text('All moods'),
                      trailing: widget.selectedId == null
                          ? const Icon(Icons.check_rounded)
                          : null,
                      onTap: () => Navigator.pop(context, ''),
                    ),
                    if (matches.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('No matching moods. Try another name.'),
                      ),
                    for (final mood in matches)
                      ListTile(
                        title: Text(mood.value),
                        trailing: widget.selectedId == mood.key
                            ? const Icon(Icons.check_rounded)
                            : null,
                        onTap: () => Navigator.pop(context, mood.key),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
