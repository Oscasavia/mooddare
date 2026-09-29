import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/features/dares/domain/curated_dares.dart';
import 'package:mooddare/features/dares/data/repositories/dares_repository.dart';

void main() {
  test('bundled dares match reviewed source, including fallback aliases', () {
    final source =
        jsonDecode(File('content/dares.json').readAsStringSync()) as Map;
    final moods = source['moods'] as Map;
    final expected = <String, List<dynamic>>{};
    for (final name in moods.keys) {
      final entry = moods[name] as Map;
      expect((entry['dares'] as List).length, greaterThanOrEqualTo(10));
      if (entry['pack'] == 'basic') {
        expected[(name as String).toLowerCase()] = entry['dares'] as List;
      }
    }
    expected['chill'] = expected['relaxed']!;
    expected['energized'] = expected['energetic']!;
    expect(curatedDares, expected);
  });
  test(
    'offline playable cards have twelve distinct dares and paid previews stay locked',
    () {
      final catalog = DaresRepository.assemble([]);
      for (final mood in catalog.moods) {
        if (mood.isAvailable) {
          expect(mood.dareList, hasLength(12));
          expect(mood.dareList.toSet(), hasLength(12));
        } else {
          expect(mood.isLocked, isTrue);
          expect(mood.dareList, isEmpty);
        }
      }
    },
  );
}
