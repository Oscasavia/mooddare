import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// A device-local display preference, independent of weekly participation.
/// Only the last collapsed week is retained, so a new week opens expanded.
class WeeklyDarePreferences {
  static final instance = WeeklyDarePreferences();
  final Future<Directory> Function() directory;
  Future<void> _pending = Future.value();
  WeeklyDarePreferences({Future<Directory> Function()? directory})
    : directory = directory ?? getApplicationSupportDirectory;

  Future<File> _file() async =>
      File('${(await directory()).path}/weekly-dare-collapsed.txt');

  Future<String?> load() async {
    await _pending;
    final file = await _file();
    if (!await file.exists()) return null;
    final value = (await file.readAsString()).trim();
    return RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) ? value : null;
  }

  Future<void> save(String? week) {
    final operation = _pending.then((_) async {
      final file = await _file();
      await file.parent.create(recursive: true);
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(week ?? '', flush: true);
      await temporary.rename(file.path);
    });
    _pending = operation.catchError((Object _) {});
    return operation;
  }
}
