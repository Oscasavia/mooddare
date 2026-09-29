import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/features/camera/data/beauty_preferences.dart';
import 'package:mooddare/features/camera/domain/beauty_lens.dart';

class MemoryBeautyPreferences extends BeautyPreferences {
  BeautyPreferencesData value = const BeautyPreferencesData();
  bool failRead = false, failWrite = false;
  int writes = 0;
  Completer<BeautyPreferencesData>? pendingRead;
  @override
  Future<BeautyPreferencesData> load() async {
    if (failRead) throw FileSystemException('Unavailable');
    return pendingRead == null ? value : await pendingRead!.future;
  }

  @override
  Future<void> save(BeautyPreferencesData data) async {
    writes++;
    if (failWrite) throw FileSystemException('Full');
    value = data;
  }
}

void main() {
  test('stored IDs are unique and independent of carousel positions', () {
    expect(
      BeautyLens.all.map((l) => l.id).toSet().length,
      BeautyLens.all.length,
    );
    expect(BeautyLens.all.every((l) => l.id.isNotEmpty), isTrue);
    expect(BeautyLens.collection.last.id, 'golden_hour');
    expect(BeautyLens.custom.id, 'custom');
  });

  test('all custom settings, strength and favorites survive serialization', () {
    for (final shade in LipShade.values) {
      final original = BeautyPreferencesData(
        look: CustomBeautyLook(
          smooth: .1,
          eyes: .2,
          face: .3,
          lips: .4,
          blush: .5,
          lipShade: shade,
        ),
        strength: .7,
        favorites: {'golden_hour', 'custom'},
      );
      final restored = BeautyPreferencesData.fromJson(original.toJson());
      expect(restored.look.settings(), original.look.settings());
      expect(restored.strength, .7);
      expect(restored.favorites, {'golden_hour', 'custom'});
      expect(restored.toJson(), original.toJson());
    }
  });

  test('malformed values are bounded and unknown favorites are discarded', () {
    for (final invalid in [
      null,
      [],
      'bad',
      {'version': 2},
    ]) {
      expect(BeautyPreferencesData.fromJson(invalid).look.isOriginal, isTrue);
    }
    final parsed = BeautyPreferencesData.fromJson({
      'version': 1,
      'strength': double.nan,
      'look': {
        'smooth': 4,
        'eyes': -1,
        'face': '1',
        'lips': double.infinity,
        'blush': .6,
        'lipShade': 'missing',
      },
      'favorites': ['original', 'missing', 'golden_hour', 'golden_hour', 1],
    });
    expect(parsed.look.smooth, 1);
    expect(parsed.look.eyes, 0);
    expect(parsed.look.face, 0);
    expect(parsed.look.lips, 0);
    expect(parsed.look.blush, .6);
    expect(parsed.look.lipShade, LipShade.rose);
    expect(parsed.strength, .65);
    expect(parsed.favorites, {'golden_hour'});
    expect(
      BeautyPreferencesData.fromJson({
        'version': 1,
        'look': [],
        'favorites': true,
      }).favorites,
      isEmpty,
    );
  });

  test(
    'ordered atomic writes survive a new store and snapshot mutable input',
    () async {
      final temp = await Directory.systemTemp.createTemp('beauty-prefs-');
      try {
        final store = BeautyPreferences(directory: () async => temp);
        expect((await store.load()).look.isOriginal, isTrue);
        final favorites = {'golden_hour'};
        final first = store.save(BeautyPreferencesData(favorites: favorites));
        favorites.clear();
        await first;
        expect((await store.load()).favorites, {'golden_hour'});
        final writes = [
          store.save(
            const BeautyPreferencesData(look: CustomBeautyLook(lips: .8)),
          ),
          store.save(
            const BeautyPreferencesData(
              look: CustomBeautyLook(blush: .4),
              favorites: {'peach'},
            ),
          ),
        ];
        expect((await store.load()).favorites, {'peach'});
        await Future.wait(writes);
        final reopened = BeautyPreferences(directory: () async => temp);
        expect((await reopened.load()).look.blush, .4);
        // An interrupted replacement leaves the last complete JSON authoritative.
        await File(
          '${temp.path}/beauty-preferences.json.tmp',
        ).writeAsString('{');
        expect((await reopened.load()).favorites, {'peach'});
        await reopened.save(const BeautyPreferencesData());
        expect((await store.load()).look.isOriginal, isTrue);
        expect((await store.load()).favorites, isEmpty);
      } finally {
        await temp.delete(recursive: true);
      }
    },
  );

  test(
    'corrupt or oversized files default safely; saving repairs them',
    () async {
      final temp = await Directory.systemTemp.createTemp('beauty-prefs-');
      try {
        final file = File('${temp.path}/beauty-preferences.json');
        final store = BeautyPreferences(directory: () async => temp);
        for (final bad in ['{', '[]', 'x' * 65537]) {
          await file.writeAsString(bad);
          expect((await store.load()).strength, .65);
        }
        await store.save(const BeautyPreferencesData(favorites: {'rosy'}));
        expect((await store.load()).favorites, {'rosy'});
      } finally {
        await temp.delete(recursive: true);
      }
    },
  );

  test(
    'unavailable storage reports failure and later writes recover',
    () async {
      final temp = await Directory.systemTemp.createTemp('beauty-prefs-');
      var fails = true;
      final store = BeautyPreferences(
        directory: () async {
          if (fails) throw FileSystemException('Unavailable');
          return temp;
        },
      );
      try {
        await expectLater(store.load(), throwsA(isA<FileSystemException>()));
        await expectLater(
          store.save(const BeautyPreferencesData()),
          throwsA(isA<FileSystemException>()),
        );
        fails = false;
        await store.save(
          const BeautyPreferencesData(favorites: {'golden_hour'}),
        );
        expect((await store.load()).favorites, {'golden_hour'});
      } finally {
        await temp.delete(recursive: true);
      }
    },
  );
}
