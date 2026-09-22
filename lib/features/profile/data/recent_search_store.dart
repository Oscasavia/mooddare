import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Device-local history, separated by account. Writes remain ordered even when
/// a screen closes and reopens while a disk operation is still in flight.
class RecentSearchStore {
  static final instance = RecentSearchStore();
  static const limit = 10;
  final Future<Directory> Function() directory;
  Future<void> _pending = Future.value();
  RecentSearchStore({Future<Directory> Function()? directory})
    : directory = directory ?? getApplicationSupportDirectory;

  Future<File> _file(String uid) async {
    final root = await directory();
    return File('${root.path}/people-search-${Uri.encodeComponent(uid)}.json');
  }

  static List<String> clean(Iterable<String> values) {
    final result = <String>{};
    for (final value in values) {
      final text = value.trim().toLowerCase().replaceFirst(RegExp(r'^@'), '');
      if (text.isNotEmpty && text.length <= 64) result.add(text);
      if (result.length == limit) break;
    }
    return result.toList();
  }

  Future<List<String>> load(String uid) async {
    await _pending;
    final file = await _file(uid);
    if (!await file.exists()) return [];
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! List) throw const FormatException('Invalid search history');
    return clean(decoded.whereType<String>());
  }

  Future<void> save(String uid, List<String> searches) {
    final snapshot = clean(searches);
    final operation = _pending.then((_) async {
      final file = await _file(uid);
      await file.parent.create(recursive: true);
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(jsonEncode(snapshot), flush: true);
      await temporary.rename(file.path);
    });
    _pending = operation.catchError((Object _) {});
    return operation;
  }
}
