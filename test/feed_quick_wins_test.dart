import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/core/comment_time.dart';
import 'package:mooddare/models/comment_model.dart';
import 'moments_test.dart' show openFeed;
import 'support/moments_fakes.dart';

class TimestampPosts extends MemoryPosts {
  TimestampPosts() : super([moment('p')]);
  @override
  Stream<List<CommentModel>> getReplies(String postId, String parentId) =>
      Stream.value([
        CommentModel(
          id: 'reply',
          authorId: 'other',
          text: 'A reply',
          parentId: parentId,
          createdAt: DateTime.now().subtract(const Duration(minutes: 10)),
        ),
      ]);
}

void main() {
  test(
    'comment ages handle minute/hour boundaries, local days and future clocks',
    () {
      final now = DateTime(2026, 1, 1, 14);
      for (final entry in <Duration, String>{
        const Duration(seconds: -5): 'Just now',
        const Duration(seconds: 59): 'Just now',
        const Duration(minutes: 1): '1m',
        const Duration(minutes: 59): '59m',
        const Duration(hours: 1): '1h',
        const Duration(hours: 13): '13h',
        const Duration(hours: 15): 'Yesterday',
        const Duration(days: 2): '12/30/2025',
      }.entries) {
        expect(commentTime(now.subtract(entry.key), now), entry.value);
      }
      expect(
        commentTime(DateTime(2026, 2, 28, 23), DateTime(2026, 3, 1, 2)),
        'Yesterday',
      );
    },
  );

  testWidgets(
    'timestamps appear for comments and replies, preserve Edited and omit missing dates',
    (tester) async {
      final repo = TimestampPosts();
      repo.comments.addAll([
        CommentModel(
          id: 'root',
          authorId: 'other',
          text: 'Root text',
          createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
          editedAt: DateTime.now(),
        ),
        const CommentModel(
          id: 'legacy',
          authorId: 'other',
          text: 'Legacy text',
        ),
      ]);
      addTearDown(repo.commentChanges.close);
      await openFeed(tester, repo, size: const Size(320, 700), textScale: 2);
      await tester.tap(find.byTooltip('Comments'));
      await tester.pumpAndSettle();
      expect(find.text('5m'), findsOneWidget);
      expect(find.text('Edited'), findsOneWidget);
      expect(find.byKey(const ValueKey('comment_time_legacy')), findsNothing);
      await tester.ensureVisible(find.textContaining('View replies').first);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('View replies').first);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('comment_time_reply')), findsOneWidget);
      expect(find.text('10m'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'active mood chip is absent initially, opens chooser and clears filter',
    (tester) async {
      final repo = MemoryPosts([
        moment('p', moodId: 'happy', moodName: 'Happy'),
      ]);
      await openFeed(tester, repo, size: const Size(320, 700), textScale: 2);
      final chip = find.byKey(const ValueKey('active_mood_filter'));
      expect(chip, findsNothing);
      expect(find.byTooltip('Find people'), findsOneWidget);
      await tester.tap(find.byTooltip('Filter by mood'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('mood_filter_search')),
        'Happy',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Happy'));
      await tester.pumpAndSettle();
      expect(chip, findsOneWidget);
      expect(repo.selectedMood, 'happy');
      expect(find.byIcon(Icons.filter_list_rounded), findsOneWidget);
      await tester.tap(find.descendant(of: chip, matching: find.text('Happy')));
      await tester.pumpAndSettle();
      expect(find.text('Filter by mood'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Clear mood filter'));
      await tester.pumpAndSettle();
      expect(chip, findsNothing);
      expect(repo.selectedMood, isNull);
      expect(tester.takeException(), isNull);
    },
  );
}
