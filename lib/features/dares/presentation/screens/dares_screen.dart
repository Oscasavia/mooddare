import 'package:flutter/material.dart';
import 'package:mooddare/core/widgets/app_empty_state.dart';
import 'package:mooddare/models/mood_model.dart';
import '../../data/repositories/dares_repository.dart';
import '../widgets/mood_card.dart';
import 'dare_generation_screen.dart';

class DaresScreen extends StatefulWidget {
  const DaresScreen({super.key});
  @override
  State<DaresScreen> createState() => _DaresScreenState();
}

class _DaresScreenState extends State<DaresScreen> {
  final _search = TextEditingController();
  late Future<Map<String, List<MoodModel>>> _packs;
  @override
  void initState() {
    super.initState();
    _packs = DaresRepository().getDarePacks();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: FutureBuilder<Map<String, List<MoodModel>>>(
        future: _packs,
        builder: (context, snapshot) {
          final local = snapshot.hasError;
          final moods =
              (local
                      ? DaresRepository.starterMoods
                      : snapshot.data?.values.expand((m) => m).toList() ??
                            <MoodModel>[])
                  .where(
                    (m) => m.name.toLowerCase().contains(
                      _search.text.trim().toLowerCase(),
                    ),
                  )
                  .toList();
          return CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'MAKE TODAY A STORY',
                        style: TextStyle(
                          fontSize: 11,
                          letterSpacing: 2.5,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'What’s your\nmood?',
                        style: TextStyle(
                          fontSize: 42,
                          height: 1.1,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'A small challenge. A new perspective.',
                        style: TextStyle(color: Colors.white60, fontSize: 15),
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        controller: _search,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: 'Find your mood',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _search.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Clear search',
                                  onPressed: () => setState(_search.clear),
                                  icon: const Icon(Icons.close),
                                ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Pick your energy',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Text(
                            '${moods.length} moods',
                            style: const TextStyle(color: Colors.white54),
                          ),
                        ],
                      ),
                      if (local)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'Offline? Explore our starter dares.',
                                  style: TextStyle(color: Colors.white60),
                                ),
                              ),
                              TextButton(
                                onPressed: () => setState(
                                  () =>
                                      _packs = DaresRepository().getDarePacks(),
                                ),
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (snapshot.connectionState == ConnectionState.waiting)
                const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (moods.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: AppEmptyState(
                    icon: Icons.search_off,
                    title: 'No matching moods',
                    message: 'Try a different word.',
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  sliver: SliverLayoutBuilder(
                    builder: (context, constraints) => SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: constraints.crossAxisExtent > 600
                            ? 3
                            : 2,
                        mainAxisExtent: 174,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => MoodCard(
                          mood: moods[i],
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => DareDisplayScreen(
                                mood: moods[i],
                                isProofRequired: false,
                              ),
                            ),
                          ),
                        ),
                        childCount: moods.length,
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );
}
