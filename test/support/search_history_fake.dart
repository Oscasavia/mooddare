import 'package:mooddare/features/profile/data/recent_search_store.dart';

class MemorySearchHistory extends RecentSearchStore {
  final values = <String, List<String>>{};
  bool failLoad = false, failSave = false;
  @override
  Future<List<String>> load(String uid) async {
    if (failLoad) throw StateError('unavailable');
    return List.of(values[uid] ?? []);
  }

  @override
  Future<void> save(String uid, List<String> searches) async {
    if (failSave) throw StateError('unavailable');
    values[uid] = List.of(searches);
  }
}
