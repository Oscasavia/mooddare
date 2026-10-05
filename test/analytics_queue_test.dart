import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/core/analytics/event_queue.dart';

void main() {
  late Directory dir;
  late AnalyticsQueue queue;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('metrics-test-');
    queue = AnalyticsQueue(directory: () async => dir);
  });
  tearDown(() async => dir.delete(recursive: true));
  Map<String, dynamic> event(String id, String? owner) => {
    'id': id,
    'owner': owner,
    'at': DateTime.now().millisecondsSinceEpoch,
    'version': '1_0',
    'session': 'original',
    'environment': 'development',
  };
  test(
    'queue persists original IDs and metadata across restart and isolates accounts',
    () async {
      await queue.add(event('one', 'alice'));
      await queue.add(event('two', 'bob'));
      await queue.add(event('public', null));
      final restarted = AnalyticsQueue(directory: () async => dir);
      final events = await restarted.pending('alice');
      expect(events.map((e) => e['id']), ['one', 'public']);
      expect(events.first['session'], 'original');
      await restarted.acknowledge(['one']);
      expect((await restarted.pending('alice')).length, 1);
      expect((await restarted.pending('bob')).map((e) => e['id']), [
        'two',
        'public',
      ]);
    },
  );
  test(
    'concurrent enqueue and acknowledgement preserve other events; deletion clears only owner',
    () async {
      await Future.wait(
        List.generate(
          25,
          (i) => queue.add(event('$i', i.isEven ? 'alice' : 'bob')),
        ),
      );
      await queue.acknowledge(['0']);
      await queue.clear('alice');
      expect(await queue.pending('alice'), isEmpty);
      expect((await queue.pending('bob')).length, 12);
    },
  );
  test('expiry and capacity bound storage; corrupted file recovers', () async {
    final old = event('old', 'alice')
      ..['at'] = DateTime.now()
          .subtract(const Duration(days: 8))
          .millisecondsSinceEpoch;
    await queue.add(old);
    expect(await queue.pending('alice'), isEmpty);
    for (var i = 0; i < 205; i++) {
      await queue.add(event('$i', 'alice'));
    }
    expect((await queue.pending('alice')).length, 200);
    expect((await queue.pending('alice')).first['id'], '5');
    await File('${dir.path}/product-events.json').writeAsString('broken');
    await queue.add(event('recovered', 'alice'));
    expect((await queue.pending('alice')).single['id'], 'recovered');
  });
}
