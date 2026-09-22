import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/features/profile/data/recent_search_store.dart';

void main() {
  late Directory directory;
  late RecentSearchStore store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('mooddare-search-test-');
    store = RecentSearchStore(directory: () async => directory);
  });
  tearDown(() => directory.delete(recursive: true));
  test(
    'history persists across instances, isolates accounts and clears',
    () async {
      expect(await store.load('alice'), isEmpty);
      await store.save('alice', [' @BOB ', 'bob', 'charlie']);
      final reopened = RecentSearchStore(directory: () async => directory);
      expect(await reopened.load('alice'), ['bob', 'charlie']);
      expect(await reopened.load('other'), isEmpty);
      await store.save('other', ['alice']);
      await store.save('alice', []);
      expect(await reopened.load('alice'), isEmpty);
      expect(await reopened.load('other'), ['alice']);
    },
  );
  test('bounds and normalizes entries and orders overlapping writes', () async {
    final values = List.generate(15, (i) => 'user$i');
    await Future.wait([
      store.save('a', values),
      store.save('a', ['last', ...values]),
    ]);
    expect(await store.load('a'), ['last', ...values.take(9)]);
    expect(
      RecentSearchStore.clean(['', ' @ ', 'x' * 65, ' @ALICE ', 'alice']),
      ['alice'],
    );
  });
  test('corrupt history reports failure and a later save repairs it', () async {
    await File(
      '${directory.path}/people-search-a.json',
    ).writeAsString('broken');
    await expectLater(store.load('a'), throwsFormatException);
    await store.save('a', ['bob']);
    expect(await store.load('a'), ['bob']);
  });
  test('a failed write does not poison the queue for later saves', () async {
    var fail = true;
    final flaky = RecentSearchStore(
      directory: () async {
        if (fail) throw const FileSystemException('unavailable');
        return directory;
      },
    );
    await expectLater(
      flaky.save('a', ['lost']),
      throwsA(isA<FileSystemException>()),
    );
    fail = false;
    await flaky.save('a', ['saved']);
    expect(await flaky.load('a'), ['saved']);
  });
}
