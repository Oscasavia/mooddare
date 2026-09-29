import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../domain/beauty_lens.dart';

/// Device-local camera preferences; contains no photos or account information.
class BeautyPreferencesData {
  final CustomBeautyLook look;
  final double strength;
  final Set<String> favorites;
  const BeautyPreferencesData({
    this.look = const CustomBeautyLook(),
    this.strength = .65,
    this.favorites = const {},
  });

  static final _favoriteIds = BeautyLens.all
      .where((lens) => lens.id != 'original')
      .map((lens) => lens.id)
      .toSet();
  static double _amount(Object? value, [double fallback = 0]) =>
      value is num && value.isFinite ? value.toDouble().clamp(0, 1) : fallback;

  factory BeautyPreferencesData.fromJson(Object? value) {
    if (value is! Map || value['version'] != 1) {
      return const BeautyPreferencesData();
    }
    final custom = value['look'] is Map ? value['look'] as Map : const {};
    final shade = LipShade.values
        .where((s) => s.name == custom['lipShade'])
        .firstOrNull;
    final favorites = value['favorites'];
    return BeautyPreferencesData(
      look: CustomBeautyLook(
        smooth: _amount(custom['smooth']),
        eyes: _amount(custom['eyes']),
        face: _amount(custom['face']),
        lips: _amount(custom['lips']),
        blush: _amount(custom['blush']),
        lipShade: shade ?? LipShade.rose,
      ),
      strength: _amount(value['strength'], .65),
      favorites: Set.unmodifiable(
        favorites is List
            ? favorites.whereType<String>().where(_favoriteIds.contains).toSet()
            : <String>{},
      ),
    );
  }

  Map<String, Object> toJson() => {
    'version': 1,
    'look': {
      for (final adjustment in BeautyAdjustment.values)
        adjustment.name: look.amount(adjustment),
      'lipShade': look.lipShade.name,
    },
    'strength': _amount(strength, .65),
    'favorites': favorites.where(_favoriteIds.contains).toList()..sort(),
  };
}

class BeautyPreferences {
  static final instance = BeautyPreferences();
  final Future<Directory> Function() directory;
  Future<void> _pending = Future.value();
  BeautyPreferences({Future<Directory> Function()? directory})
    : directory = directory ?? getApplicationSupportDirectory;

  Future<File> _file() async =>
      File('${(await directory()).path}/beauty-preferences.json');

  Future<BeautyPreferencesData> load() async {
    await _pending;
    final file = await _file();
    if (!await file.exists() || await file.length() > 65536) {
      return const BeautyPreferencesData();
    }
    try {
      return BeautyPreferencesData.fromJson(
        jsonDecode(await file.readAsString()),
      );
    } on FormatException {
      return const BeautyPreferencesData();
    }
  }

  Future<void> save(BeautyPreferencesData value) {
    // Snapshot before enqueueing: later edits must not mutate this write.
    final json = jsonEncode(value.toJson());
    final operation = _pending.then((_) async {
      final file = await _file();
      await file.parent.create(recursive: true);
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(json, flush: true);
      await temporary.rename(file.path);
    });
    _pending = operation.catchError((Object _) {});
    return operation;
  }
}
