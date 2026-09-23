import 'dare_library_screen.dart';
import 'package:flutter/material.dart';
import 'package:mooddare/core/widgets/app_empty_state.dart';
import 'package:mooddare/models/mood_model.dart';
import '../../data/repositories/dares_repository.dart';
import '../../domain/mood_catalog.dart';
import '../widgets/mood_card.dart';
import '../widgets/mood_preview.dart';
import 'dare_generation_screen.dart';

class DaresScreen extends StatefulWidget {
  final DaresRepository? repository;
  const DaresScreen({super.key, this.repository});
  @override
  State<DaresScreen> createState() => _DaresScreenState();
}

class _DaresScreenState extends State<DaresScreen> {
  final _search = TextEditingController();
  late final DaresRepository _repository;
  late Future<MoodCatalog> _catalog;
  MoodCollection _collection = MoodCollection.all;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? DaresRepository();
    _catalog = _repository.getCatalog();
  }

  Future<void> _refresh() async {
    final next = _repository.getCatalog();
    setState(() {
      _catalog = next;
    });
    await next;
  }

  void _select(MoodCollection collection) {
    FocusScope.of(context).unfocus();
    setState(() => _collection = collection);
  }

  void _open(MoodModel mood) {
    FocusScope.of(context).unfocus();
    if (!mood.isAvailable) {
      showMoodPreview(context, mood);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DareDisplayScreen(mood: mood, isProofRequired: false),
      ),
    );
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: FutureBuilder<MoodCatalog>(
        future: _catalog,
        builder: (context, snapshot) {
          final waiting = snapshot.connectionState == ConnectionState.waiting;
          final catalog = snapshot.data;
          final moods =
              catalog?.filter(_collection, _search.text) ?? <MoodModel>[];
          final premium =
              _collection == MoodCollection.daring ||
              _collection == MoodCollection.epic;
          return RefreshIndicator(
            onRefresh: _refresh,
            child: CustomScrollView(
              key: const PageStorageKey('mood_catalog_scroll'),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Expanded(
                              child: Text(
                                'Find your mood.',
                                style: TextStyle(
                                  fontSize: 32,
                                  height: 1.15,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -1,
                                ),
                              ),
                            ),
                            const DareInboxButton(),
                            IconButton(
                              tooltip: 'About collections',
                              onPressed: () => showMoodCollections(context),
                              icon: const Icon(
                                Icons.layers_outlined,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'A little dare for every kind of day.',
                          style: TextStyle(color: Colors.white60, height: 1.5),
                        ),
                        const SizedBox(height: 24),
                        TextField(
                          controller: _search,
                          onChanged: (_) => setState(() {}),
                          textInputAction: TextInputAction.search,
                          onSubmitted: (_) => FocusScope.of(context).unfocus(),
                          decoration: InputDecoration(
                            hintText: 'Search moods',
                            prefixIcon: const Icon(Icons.search_rounded),
                            suffixIcon: _search.text.isEmpty
                                ? null
                                : IconButton(
                                    tooltip: 'Clear search',
                                    onPressed: () => setState(_search.clear),
                                    icon: const Icon(Icons.close),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: MoodCollection.values
                          .map(
                            (collection) => Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                key: ValueKey('collection_${collection.name}'),
                                showCheckmark: false,
                                label: Text(collection.label),
                                selected: _collection == collection,
                                onSelected: (_) => _select(collection),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
                if (catalog?.loadFailed ?? false)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                    sliver: SliverToBoxAdapter(
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Couldn’t refresh. Starter moods are ready.',
                              style: TextStyle(
                                color: Colors.white60,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: waiting ? null : _refresh,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (waiting && catalog != null)
                  const SliverToBoxAdapter(child: LinearProgressIndicator()),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 18),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                switch (_collection) {
                                  MoodCollection.all => 'Pick your energy',
                                  MoodCollection.free => 'Yours to explore',
                                  MoodCollection.daring =>
                                    'A little more daring',
                                  MoodCollection.epic => 'Make it memorable',
                                  MoodCollection.seasonal => 'Seasonal moments',
                                },
                                style: const TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (catalog != null) ...[
                              const SizedBox(width: 12),
                              Text(
                                '${moods.length}',
                                style: const TextStyle(color: Colors.white54),
                              ),
                            ],
                          ],
                        ),
                        if (premium ||
                            _collection == MoodCollection.seasonal) ...[
                          const SizedBox(height: 8),
                          Text(
                            premium
                                ? '${_collection.label} · Coming soon. Tap a mood for a preview.'
                                : 'Christmas, New Year, and moments worth celebrating. Available year-round.',
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 13,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (catalog == null)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: CircularProgressIndicator(
                        semanticsLabel: 'Loading moods',
                      ),
                    ),
                  )
                else if (moods.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: AppEmptyState(
                      icon: Icons.search_off_rounded,
                      title: 'No matching moods',
                      message: 'Try another word or collection.',
                      actionLabel: 'Show all moods',
                      onAction: () {
                        FocusScope.of(context).unfocus();
                        setState(() {
                          _search.clear();
                          _collection = MoodCollection.all;
                        });
                      },
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    sliver: SliverLayoutBuilder(
                      builder: (context, constraints) {
                        final scale =
                            MediaQuery.textScalerOf(context).scale(20) / 20;
                        // Keep two cards on narrow phones, including cover screens.
                        // Larger text grows the cards vertically instead of dropping a column.
                        final columns = (constraints.crossAxisExtent / 220)
                            .floor()
                            .clamp(2, 4);
                        return SliverGrid(
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: columns,
                                mainAxisExtent: 132 + 64 * scale,
                                mainAxisSpacing: 12,
                                crossAxisSpacing: 12,
                              ),
                          delegate: SliverChildBuilderDelegate(
                            (context, index) => MoodCard(
                              key: ValueKey('mood_${moods[index].id}'),
                              mood: moods[index],
                              onTap: () => _open(moods[index]),
                            ),
                            childCount: moods.length,
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    ),
  );
}
