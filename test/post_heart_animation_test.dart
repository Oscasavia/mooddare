import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/features/feed/presentation/screens/post_details_screen.dart';
import 'moments_test.dart' show openFeed, tapMedia;
import 'support/moments_fakes.dart';

Future<void> doubleTapPost(WidgetTester tester) async {
  final surface = find.byKey(const ValueKey('moment_surface_heart'));
  final point = tester.getRect(surface).topCenter + const Offset(0, 140);
  await tester.tapAt(point);
  await tester.pump(const Duration(milliseconds: 80));
  await tester.tapAt(point);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 120));
}

class DelayedHeartPosts extends MemoryPosts {
  final pending = Completer<void>();
  DelayedHeartPosts() : super([moment('heart')]);
  @override
  Future<void> toggleLike(String id, String uid) async {
    likes++;
    await pending.future;
  }
}

void main() {
  testWidgets(
    'pending double taps write once and failure clears feedback and restores like',
    (tester) async {
      final repo = DelayedHeartPosts();
      await openFeed(tester, repo);
      await doubleTapPost(tester);
      expect(find.byKey(const ValueKey('double_tap_heart')), findsOneWidget);
      await doubleTapPost(tester);
      expect(repo.likes, 1);
      repo.pending.completeError(StateError('Offline'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('double_tap_heart')), findsNothing);
      expect(find.byTooltip('Like'), findsOneWidget);
      expect(
        find.text('Could not update your like. Try again.'),
        findsOneWidget,
      );
    },
  );
  testWidgets('signed-out double tap does not show successful-like feedback', (
    tester,
  ) async {
    final repo = MemoryPosts([moment('heart')])..uid = null;
    await openFeed(tester, repo);
    await doubleTapPost(tester);
    expect(repo.likes, 0);
    expect(find.byKey(const ValueKey('double_tap_heart')), findsNothing);
  });

  for (final full in [false, true]) {
    for (final type in ['image', 'video']) {
      testWidgets(
        '$type ${full ? 'viewer' : 'feed'} double-tap shows a centered temporary heart, repeats without unliking, icon does not animate',
        (tester) async {
          final repo = MemoryPosts([moment('heart', type: type)]);
          await openFeed(tester, repo);
          if (full) await tapMedia(tester);
          expect(
            find.byType(PostDetailsScreen),
            full ? findsOneWidget : findsNothing,
          );
          await doubleTapPost(tester);
          final heart = find.byKey(const ValueKey('double_tap_heart'));
          expect(heart, findsOneWidget);
          expect(
            tester.getCenter(heart),
            tester.getCenter(
              find.byKey(const ValueKey('moment_surface_heart')),
            ),
          );
          expect(repo.likes, 1);
          await tester.pumpAndSettle();
          expect(heart, findsNothing);
          await doubleTapPost(tester);
          expect(heart, findsOneWidget);
          expect(repo.likes, 1);
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('Unlike'));
          await tester.pump();
          expect(heart, findsNothing);
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('Like'));
          await tester.pump();
          expect(heart, findsNothing);
          expect(repo.likes, 3);
          await doubleTapPost(tester);
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
