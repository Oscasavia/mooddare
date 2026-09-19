import '../../../models/mood_model.dart';

enum MoodCollection {
  all('All'),
  free('Free'),
  daring('Daring'),
  epic('Epic'),
  seasonal('Seasonal');

  final String label;
  const MoodCollection(this.label);
}

class MoodCatalog {
  final List<MoodModel> moods;
  final bool loadFailed;
  MoodCatalog(Iterable<MoodModel> moods, {this.loadFailed = false})
    : moods = List.unmodifiable(moods);

  List<MoodModel> filter(MoodCollection collection, String query) {
    final search = query.trim().toLowerCase();
    return moods
        .where((mood) {
          final matchesCollection = switch (collection) {
            MoodCollection.all => true,
            MoodCollection.free => mood.tier == MoodTier.basic,
            MoodCollection.daring => mood.tier == MoodTier.daring,
            MoodCollection.epic => mood.tier == MoodTier.epic,
            MoodCollection.seasonal => mood.isSeasonal,
          };
          return matchesCollection &&
              '${mood.name} ${mood.description} ${mood.season ?? ''}'
                  .toLowerCase()
                  .contains(search);
        })
        .toList(growable: false);
  }
}
