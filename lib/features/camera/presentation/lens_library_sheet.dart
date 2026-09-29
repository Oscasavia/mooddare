import 'package:flutter/material.dart';
import '../../../core/branding/mood_wink.dart';
import '../domain/beauty_lens.dart';
import 'beauty_lens_disc.dart';

class LensLibrarySheet extends StatefulWidget {
  final BeautyLens selected;
  final Set<String> favorites;
  final ValueChanged<BeautyLens> onToggleFavorite;
  const LensLibrarySheet({
    super.key,
    required this.selected,
    required this.favorites,
    required this.onToggleFavorite,
  });

  @override
  State<LensLibrarySheet> createState() => _LensLibrarySheetState();
}

class _LensLibrarySheetState extends State<LensLibrarySheet> {
  late final Set<String> _favorites = {...widget.favorites};
  bool _favoritesOnly = false;

  @override
  Widget build(BuildContext context) {
    final lenses = BeautyLens.all
        .where((lens) => !_favoritesOnly || _favorites.contains(lens.id))
        .toList();
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Your lenses',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              runSpacing: 8,
              children: [
                for (final favorite in [false, true])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(favorite ? 'Favorites' : 'All lenses'),
                      selected: _favoritesOnly == favorite,
                      onSelected: (_) =>
                          setState(() => _favoritesOnly = favorite),
                      side: BorderSide.none,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Flexible(
              child: lenses.isEmpty
                  ? const SingleChildScrollView(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Column(
                          children: [
                            MoodWink(size: 64),
                            SizedBox(height: 16),
                            Text(
                              'Keep your favorites close',
                              textAlign: TextAlign.center,
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Tap the star on a lens to find it here.',
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: lenses.length,
                      itemBuilder: (context, index) {
                        final lens = lenses[index];
                        final favorite = _favorites.contains(lens.id);
                        return ListTile(
                          key: ValueKey('library_lens_${lens.id}'),
                          contentPadding: EdgeInsets.zero,
                          leading: SizedBox.square(
                            dimension: 44,
                            child: BeautyLensDisc(lens: lens),
                          ),
                          title: Text(lens.name),
                          selected: lens == widget.selected,
                          onTap: () => Navigator.pop(context, lens),
                          trailing: lens.id == 'original'
                              ? null
                              : IconButton(
                                  tooltip: favorite
                                      ? 'Unfavorite ${lens.name}'
                                      : 'Favorite ${lens.name}',
                                  isSelected: favorite,
                                  icon: Icon(
                                    favorite
                                        ? Icons.star_rounded
                                        : Icons.star_outline_rounded,
                                  ),
                                  onPressed: () {
                                    setState(
                                      () => favorite
                                          ? _favorites.remove(lens.id)
                                          : _favorites.add(lens.id),
                                    );
                                    widget.onToggleFavorite(lens);
                                  },
                                ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
