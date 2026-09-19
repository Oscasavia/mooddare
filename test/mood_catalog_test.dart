import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/models/mood_model.dart';
import 'package:mooddare/features/dares/data/repositories/dares_repository.dart';
import 'package:mooddare/features/dares/domain/mood_catalog.dart';

MoodModel mood(
  String id, {
  String? name,
  String pack = 'basic',
  bool locked = false,
  List<String> dares = const ['A real dare.'],
  String? season,
}) => MoodModel(
  id: id,
  name: name ?? id,
  icon: '✨',
  pack: pack,
  color: Colors.teal,
  isLocked: locked,
  dareList: dares,
  season: season,
);

void main() {
  test('legacy packs map to tiers and never unlock premium dares', () {
    for (final entry in {
      'basic': MoodTier.basic,
      'Daring': MoodTier.gold,
      'premium': MoodTier.gold,
      'gold': MoodTier.gold,
      ' Epic ': MoodTier.diamond,
      'diamond': MoodTier.diamond,
    }.entries) {
      final parsed = MoodModel.fromFirestore({
        'pack': entry.key,
        'isLocked': false,
        'dareList': ['Capture something.'],
      }, 'id');
      expect(parsed.tier, entry.value);
      expect(parsed.isAvailable, entry.value == MoodTier.basic);
    }
    expect(mood('locked', locked: true).isAvailable, isFalse);
    expect(mood('empty', dares: []).isAvailable, isFalse);
  });

  test('explicit tiers override packs and unknown tiers fail closed', () {
    for (final entry in <Object, MoodTier>{
      'free': MoodTier.basic,
      'diamond': MoodTier.diamond,
      'gold': MoodTier.gold,
      'future-tier': MoodTier.gold,
      42: MoodTier.gold,
    }.entries) {
      final parsed = MoodModel.fromFirestore({
        'pack': 'daring',
        'tier': entry.key,
        'dareList': ['Hi'],
      }, 'id');
      expect(parsed.tier, entry.value);
      expect(parsed.isAvailable, entry.value == MoodTier.basic);
    }
    expect(
      MoodModel.fromFirestore({
        'isLocked': 'false',
        'dareList': ['Hi'],
      }, 'id').isAvailable,
      isFalse,
    );
  });

  test('malformed Firestore fields are safe and dares are normalized', () {
    final parsed = MoodModel.fromFirestore({
      'moodName': 12,
      'moodIcon': null,
      'colorHex': '#not-a-color',
      'dareList': [false, null, '  ', ' Hello ', 'Hello', 'World'],
      'season': ' New Year ',
    }, 'remote');
    expect(parsed.name, 'Unnamed mood');
    expect(parsed.icon, '✨');
    expect(parsed.color, const Color(0xFFC5B4FF));
    expect(parsed.dareList, ['Hello', 'World']);
    expect(parsed.season, 'New Year');
    expect(parsed.isSeasonal, isTrue);
    expect(() => parsed.dareList.add('mutate'), throwsUnsupportedError);
    expect(
      MoodModel.fromFirestore({
        'colorHex': '#ABCDEF',
        'dareList': 'bad',
      }, 'id').color,
      const Color(0xFFABCDEF),
    );
    expect(
      MoodModel.fromFirestore({'colorHex': 'FFAABBCC'}, 'id').color,
      const Color(0xFFAABBCC),
    );
    expect(
      MoodModel.fromFirestore({
        'dareList': 'bad',
        'season': ' ',
      }, 'id').dareList,
      isEmpty,
    );
    expect(MoodModel.fromFirestore({'season': ' '}, 'id').isSeasonal, isFalse);
  });

  test(
    'remote catalog wins by ID and normalized name without hiding premium',
    () async {
      final remoteBrave = mood('server-brave', name: ' BRAVE ', pack: 'daring');
      final remote = [
        remoteBrave,
        mood('server-free'),
        mood('duplicate-name', name: 'brave', pack: 'daring'),
        mood('server-free', name: 'Duplicate ID'),
        mood('empty', dares: []),
      ];
      final catalog = await DaresRepository(
        loadMoods: () async => remote,
      ).getCatalog();
      expect(catalog.loadFailed, isFalse);
      expect(
        catalog.moods.where((m) => m.name.trim().toLowerCase() == 'brave'),
        [remoteBrave],
      );
      expect(catalog.moods.where((m) => m.id == 'server-free'), hasLength(1));
      expect(catalog.moods.any((m) => m.id == 'empty'), isFalse);
      expect(catalog.moods.any((m) => m.id == 'creative'), isFalse);
      expect(catalog.filter(MoodCollection.gold, ''), hasLength(8));
      expect(catalog.filter(MoodCollection.diamond, ''), hasLength(7));
      expect(remoteBrave.isAvailable, isFalse);
    },
  );

  test(
    'empty, locked-only and failed sources preserve usable free moods',
    () async {
      for (final source in <List<MoodModel>>[
        [],
        [mood('paid', pack: 'epic')],
        [mood('empty', dares: [])],
      ]) {
        final catalog = DaresRepository.assemble(source);
        expect(
          catalog.moods.where((m) => m.isAvailable && !m.isSeasonal),
          hasLength(6),
        );
        expect(catalog.loadFailed, isFalse);
      }
      final catalog = await DaresRepository(
        loadMoods: () async => throw StateError('offline'),
      ).getCatalog();
      expect(catalog.loadFailed, isTrue);
      expect(catalog.moods.where((m) => m.isAvailable), hasLength(8));
      expect(() => catalog.moods.clear(), throwsUnsupportedError);
    },
  );

  testWidgets('a stalled source times out to starter moods', (tester) async {
    final pending = Completer<List<MoodModel>>();
    final future = DaresRepository(
      loadMoods: () => pending.future,
    ).getCatalog();
    await tester.pump(const Duration(seconds: 11));
    final catalog = await future;
    expect(catalog.loadFailed, isTrue);
    expect(catalog.moods.any((m) => m.isAvailable), isTrue);
    pending.complete([]);
    await tester.pump();
  });

  test(
    'built-in previews contain no paid dares and seasonal moods are playable',
    () {
      expect(DaresRepository.premiumPreviews, hasLength(15));
      for (final preview in DaresRepository.premiumPreviews) {
        expect(preview.isAvailable, isFalse);
        expect(preview.isLocked, isTrue);
        expect(preview.dareList, isEmpty);
      }
      expect(DaresRepository.seasonalMoods.map((m) => m.season), [
        'Christmas',
        'New Year',
      ]);
      for (final seasonal in DaresRepository.seasonalMoods) {
        expect(seasonal.isAvailable, isTrue);
        expect(seasonal.dareList, hasLength(3));
      }
    },
  );

  test(
    'search intersects collection, ignores case and includes descriptions and seasons',
    () {
      final catalog = DaresRepository.assemble([]);
      expect(
        catalog.filter(MoodCollection.gold, ' bRaVe ').single.name,
        'Brave',
      );
      expect(catalog.filter(MoodCollection.diamond, 'brave'), isEmpty);
      expect(
        catalog.filter(MoodCollection.free, 'festive').single.name,
        'Christmas',
      );
      expect(
        catalog.filter(MoodCollection.seasonal, 'NEW YEAR').single.name,
        'New Year',
      );
      expect(catalog.filter(MoodCollection.all, 'nonexistent'), isEmpty);
      final premiumSeasonal = mood(
        'holiday',
        pack: 'diamond',
        season: 'Test holiday',
      );
      final future = MoodCatalog([premiumSeasonal]);
      expect(future.filter(MoodCollection.seasonal, ''), [premiumSeasonal]);
      expect(future.filter(MoodCollection.free, ''), isEmpty);
      expect(premiumSeasonal.isAvailable, isFalse);
    },
  );
}
