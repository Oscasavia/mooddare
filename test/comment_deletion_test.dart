import 'package:mooddare/core/widgets/stable_popup_menu.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/models/comment_model.dart';
import 'moments_test.dart' show openFeed, tapMedia;
import 'support/moments_fakes.dart';

Future<void> deleteMenu(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Comment options'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Delete comment'));
  await tester.pumpAndSettle();
}

void main() {
  for (final uid in ['viewer', 'author']) {
    for (final fullscreen in [false, true]) {
      testWidgets(
        '$uid deletes from ${fullscreen ? 'viewer' : 'feed'} and refreshes total',
        (tester) async {
          final repo = MemoryPosts([moment('delete')])..uid = uid;
          repo.comments.add(
            const CommentModel(
              id: 'c',
              authorId: 'viewer',
              text: 'Remove this',
              likedBy: ['other'],
            ),
          );
          addTearDown(repo.commentChanges.close);
          await openFeed(tester, repo);
          if (fullscreen) await tapMedia(tester);
          expect(
            tester
                .widget<Text>(
                  find.byKey(const ValueKey('moment_comment_count')),
                )
                .data,
            '1',
          );
          await tester.tap(find.byTooltip('Comments'));
          await tester.pumpAndSettle();
          await deleteMenu(tester);
          expect(repo.comments, isEmpty);
          expect(find.text('Remove this'), findsNothing);
          expect(find.text('Start the conversation ✨'), findsOneWidget);
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<Text>(
                  find.byKey(const ValueKey('moment_comment_count')),
                )
                .data,
            '0',
          );
        },
      );
    }
  }
  testWidgets(
    'failed deletion preserves comment, likes and draft; retry clears error',
    (tester) async {
      final repo = MemoryPosts([moment('retry')])..failDelete = true;
      repo.comments.add(
        const CommentModel(
          id: 'c',
          authorId: 'viewer',
          text: 'Keep on failure',
          likedBy: ['alice'],
        ),
      );
      addTearDown(repo.commentChanges.close);
      await openFeed(tester, repo);
      await tester.tap(find.byTooltip('Comments'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'My new draft');
      await deleteMenu(tester);
      expect(
        find.text('Could not delete this comment. Try again.'),
        findsOneWidget,
      );
      expect(repo.comments.single.likedBy, ['alice']);
      expect(find.text('Keep on failure'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'My new draft',
      );
      repo.failDelete = false;
      await deleteMenu(tester);
      expect(
        find.text('Could not delete this comment. Try again.'),
        findsNothing,
      );
      expect(repo.deletions, 2);
      expect(repo.comments, isEmpty);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'My new draft',
      );
    },
  );
  testWidgets(
    'deleting during edit prevents duplicate requests and restores original draft',
    (tester) async {
      final gate = Completer<void>();
      final repo = MemoryPosts([moment('editing')])..deleteGate = gate.future;
      repo.comments.add(
        const CommentModel(id: 'c', authorId: 'viewer', text: 'Original'),
      );
      addTearDown(repo.commentChanges.close);
      await openFeed(tester, repo);
      await tester.tap(find.byTooltip('Comments'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Unsent draft');
      await tester.tap(find.byTooltip('Comment options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit comment'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Unsent edit');
      await deleteMenu(tester);
      expect(
        tester
            .widget<StablePopupMenu<String>>(
              find.byKey(const ValueKey('comment_menu_c')),
            )
            .enabled,
        isFalse,
      );
      expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.check))
            .onPressed,
        isNull,
      );
      expect(repo.deletions, 1);
      gate.complete();
      await tester.pumpAndSettle();
      expect(repo.comments, isEmpty);
      expect(find.byTooltip('Save comment'), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Unsent draft',
      );
    },
  );
  testWidgets('dismissing the panel during a deletion is safe', (tester) async {
    final gate = Completer<void>();
    final repo = MemoryPosts([moment('dismiss')])..deleteGate = gate.future;
    repo.comments.add(
      const CommentModel(id: 'c', authorId: 'viewer', text: 'Delete later'),
    );
    addTearDown(repo.commentChanges.close);
    await openFeed(tester, repo);
    await tester.tap(find.byTooltip('Comments'));
    await tester.pumpAndSettle();
    await deleteMenu(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    gate.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(repo.comments, isEmpty);
  });
}
