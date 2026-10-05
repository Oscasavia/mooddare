import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// A bounded seven-day queue. Ownership is checked again before every delivery.
class AnalyticsQueue {
  final Future<Directory> Function() directory;
  Future<void> _pending = Future.value();
  AnalyticsQueue({Future<Directory> Function()? directory})
    : directory = directory ?? getApplicationSupportDirectory;
  Future<File> _file() async =>
      File('${(await directory()).path}/product-events.json');
  Future<List<Map<String, dynamic>>> _read() async {
    try {
      final value = jsonDecode(await (await _file()).readAsString());
      if (value is! List) return [];
      final cutoff = DateTime.now()
          .subtract(const Duration(days: 7))
          .millisecondsSinceEpoch;
      return value
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .where((e) => e['at'] is int && e['at'] >= cutoff)
          .take(200)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _write(List<Map<String, dynamic>> events) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(events), flush: true);
    await temp.rename(file.path);
  }

  Future<void> _change(Future<void> Function() operation) {
    final next = _pending.then((_) => operation());
    _pending = next.catchError((Object _) {});
    return next;
  }

  Future<void> add(Map<String, dynamic> event) => _change(() async {
    final events = await _read();
    events.add(event);
    await _write(
      events.length > 200 ? events.sublist(events.length - 200) : events,
    );
  });
  Future<List<Map<String, dynamic>>> pending(String? uid) async {
    await _pending;
    return (await _read())
        .where((e) => e['owner'] == uid || e['owner'] == null)
        .toList();
  }

  Future<void> acknowledge(List<String> ids) => _change(
    () async =>
        _write((await _read()).where((e) => !ids.contains(e['id'])).toList()),
  );
  Future<void> clear(String uid) => _change(
    () async =>
        _write((await _read()).where((e) => e['owner'] != uid).toList()),
  );
}
