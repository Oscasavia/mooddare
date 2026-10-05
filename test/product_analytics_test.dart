import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/core/analytics/product_analytics.dart';

void main() {
  test(
    'sends only a mood ID and unique event ID for an explicit selection',
    () async {
      final events = <Map<String, String>>[];
      var id = 0;
      final analytics = ProductAnalytics(
        signedIn: () => true,
        eventId: () => 'selection-${++id}',
        send: (d) async => events.add(d),
      );
      await analytics.moodSelected('happy');
      await analytics.moodSelected('chill');
      expect(events, [
        {'eventId': 'selection-1', 'moodId': 'happy'},
        {'eventId': 'selection-2', 'moodId': 'chill'},
      ]);
    },
  );
  test(
    'guests are not tracked and network errors never reach navigation',
    () async {
      var sent = 0;
      Future<void> send(Map<String, String> _) async {
        sent++;
        throw StateError('offline');
      }

      await ProductAnalytics(
        signedIn: () => false,
        send: send,
      ).moodSelected('happy');
      expect(sent, 0);
      await ProductAnalytics(
        signedIn: () => true,
        send: send,
      ).moodSelected('happy');
      expect(sent, 1);
    },
  );
}
