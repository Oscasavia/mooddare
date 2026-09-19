import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/core/app_routes.dart';
import 'package:mooddare/core/compact_count.dart';
import 'package:mooddare/models/comment_model.dart';
import 'package:mooddare/features/feed/presentation/video_sound.dart';
import 'package:mooddare/features/profile/presentation/screens/profile_screen.dart';
import 'moments_test.dart' show openFeed, tapMedia;
import 'support/moments_fakes.dart';

void main() {
  setUp(() => videoMuted.value = true);

  test('compact counts retain one decimal without rounding milestones up', () {
    for (final entry in <int, String>{
      -1: '0',
      0: '0',
      999: '999',
      1000: '1k',
      1200: '1.2k',
      1299: '1.2k',
      10000: '10k',
      10500: '10.5k',
      999999: '999.9k',
      1000000: '1m',
      1200000: '1.2m',
      1000000000: '1b',
    }.entries) {
      expect(compactCount(entry.key), entry.value);
    }
  });

  testWidgets('fullscreen top controls align with Back and mute has no fill', (
    tester,
  ) async {
    tester.view.padding = const FakeViewPadding(top: 60);
    addTearDown(tester.view.resetPadding);
    await openFeed(tester, MemoryPosts([moment('video', type: 'video')]));
    void checkNoFill() {
      final mute = find.byIcon(Icons.volume_off_rounded);
      final material = tester.widget<Material>(
        find.ancestor(of: mute, matching: find.byType(Material)).first,
      );
      expect(material.color, Colors.transparent);
    }

    checkNoFill();
    await tapMedia(tester);
    final backY = tester.getCenter(find.byType(BackButton)).dy;
    expect(
      tester.getCenter(find.byTooltip('Unmute video')).dy,
      closeTo(backY, .1),
    );
    expect(
      tester.getCenter(find.byTooltip('Moment options')).dy,
      closeTo(backY, .1),
    );
    expect(backY, closeTo(60 + kToolbarHeight / 2, .1));
    checkNoFill();
    await tester.tap(find.byTooltip('Unmute video'));
    await tester.pumpAndSettle();
    expect(videoMuted.value, isFalse);
    await tester.pageBack();
    await tester.pumpAndSettle();
  });

  testWidgets(
    'author avatar and name route to the same profile from both views',
    (tester) async {
      final targets = <Object?>[];
      await openFeed(
        tester,
        MemoryPosts([moment('profile')]),
        onGenerateRoute: (settings) {
          expect(settings.name, profileRoute);
          targets.add(settings.arguments);
          final realRoute =
              appRouteFactory(settings)! as MaterialPageRoute<void>;
          final realScreen =
              realRoute.builder(tester.element(find.byType(Scaffold).last))
                  as ProfileScreen;
          expect(realScreen.userId, 'author');
          return MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              appBar: AppBar(),
              body: const Text('Profile destination'),
            ),
          );
        },
      );
      for (final fullScreen in [false, true]) {
        if (fullScreen) await tapMedia(tester);
        for (final key in ['moment_author_avatar', 'moment_author_name']) {
          await tester.tap(find.byKey(ValueKey(key)));
          await tester.pumpAndSettle();
          expect(find.text('Profile destination'), findsOneWidget);
          await tester.pageBack();
          await tester.pumpAndSettle();
        }
      }
      expect(targets, ['author', 'author', 'author', 'author']);
    },
  );

  testWidgets(
    'post icons match and aggregate comments use compact accessible counts',
    (tester) async {
      final repo = MemoryPosts([moment('counts')])..commentCount = 1250;
      await openFeed(tester, repo, size: const Size(320, 700), textScale: 2);
      for (final fullScreen in [false, true]) {
        if (fullScreen) await tapMedia(tester);
        for (final tooltip in ['Like', 'Comments', 'Share moment']) {
          final icon = tester.widget<Icon>(
            find
                .descendant(
                  of: find.byTooltip(tooltip),
                  matching: find.byType(Icon),
                )
                .first,
          );
          expect(icon.size, 22);
          expect(icon.color, Colors.white);
        }
        expect(find.byIcon(Icons.send_outlined), findsOneWidget);
        final count = tester.widget<Text>(
          find.byKey(const ValueKey('moment_comment_count')),
        );
        expect(count.data, '1.2k');
        expect(count.semanticsLabel, '1250 comments');
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'comment count refreshes after posting and deleting in either view',
    (tester) async {
      final repo = MemoryPosts([moment('count-updates')]);
      addTearDown(repo.commentChanges.close);
      await openFeed(tester, repo);
      await tester.tap(find.byTooltip('Comments'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'First comment');
      await tester.pump();
      await tester.tap(find.byTooltip('Post comment'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('moment_comment_count')))
            .data,
        '1',
      );
      await tapMedia(tester);
      await tester.tap(find.byTooltip('Comments'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Comment options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete comment'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('moment_comment_count')))
            .data,
        '0',
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('moment_comment_count')))
            .data,
        '0',
      );
    },
  );

  testWidgets(
    'editing retries preserve likes, show Edited and restore the unsent draft',
    (tester) async {
      final repo = MemoryPosts([moment('edit')])..failEdit = true;
      repo.comments.add(
        const CommentModel(
          id: 'mine',
          authorId: 'viewer',
          text: 'Original',
          likedBy: ['other'],
        ),
      );
      addTearDown(repo.commentChanges.close);
      await openFeed(tester, repo);
      await tester.tap(find.byTooltip('Comments'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Unsent new comment');
      await tester.pump();
      await tester.tap(find.byTooltip('Comment options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit comment'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Original',
      );
      await tester.enterText(find.byType(TextField), 'Updated comment');
      await tester.pump();
      await tester.tap(find.byTooltip('Save comment'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not save changes'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Updated comment',
      );
      repo.failEdit = false;
      await tester.tap(find.byTooltip('Save comment'));
      await tester.pumpAndSettle();
      expect(repo.comments.single.text, 'Updated comment');
      expect(repo.comments.single.likedBy, ['other']);
      expect(find.text('Edited'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Unsent new comment',
      );
      expect(repo.submissions, isEmpty);
    },
  );

  testWidgets('post owners may delete but cannot edit someone else’s comment', (
    tester,
  ) async {
    final repo = MemoryPosts([moment('moderate')])..uid = 'author';
    repo.comments.add(
      const CommentModel(id: 'other', authorId: 'viewer', text: 'Hello'),
    );
    addTearDown(repo.commentChanges.close);
    await openFeed(tester, repo);
    await tester.tap(find.byTooltip('Comments'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Comment options'));
    await tester.pumpAndSettle();
    expect(find.text('Delete comment'), findsOneWidget);
    expect(find.text('Edit comment'), findsNothing);
  });

  testWidgets(
    'cancel edit restores draft and fits large text above the keyboard',
    (tester) async {
      final repo = MemoryPosts([moment('cancel-edit')]);
      repo.comments.add(
        const CommentModel(
          id: 'mine',
          authorId: 'viewer',
          text: 'Before editing',
        ),
      );
      addTearDown(repo.commentChanges.close);
      await openFeed(tester, repo, size: const Size(320, 700), textScale: 2);
      await tester.tap(find.byTooltip('Comments'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'My new draft');
      await tester.pump();
      await tester.ensureVisible(find.byTooltip('Comment options'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Comment options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit comment'));
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump();
      final save = tester.widget<IconButton>(
        find.byWidgetPredicate(
          (w) => w is IconButton && w.tooltip == 'Save comment',
        ),
      );
      expect(save.onPressed, isNull);
      await tester.tap(find.byTooltip('Cancel edit'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'My new draft',
      );
      expect(repo.comments.single.text, 'Before editing');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'comment likes toggle and failed likes leave the count unchanged',
    (tester) async {
      final repo = MemoryPosts([moment('comment-likes')])
        ..failCommentLike = true;
      repo.comments.add(
        const CommentModel(id: 'other', authorId: 'other', text: 'Hello'),
      );
      addTearDown(repo.commentChanges.close);
      await openFeed(tester, repo);
      await tester.tap(find.byTooltip('Comments'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Like comment'));
      await tester.pumpAndSettle();
      expect(repo.comments.single.likedBy, isEmpty);
      expect(
        find.text('Could not update your like. Try again.'),
        findsOneWidget,
      );
      repo.failCommentLike = false;
      await tester.tap(find.byTooltip('Like comment'));
      await tester.pumpAndSettle();
      expect(repo.comments.single.likedBy, ['viewer']);
      expect(find.byTooltip('Unlike comment'), findsOneWidget);
      await tester.tap(find.byTooltip('Unlike comment'));
      await tester.pumpAndSettle();
      expect(repo.comments.single.likedBy, isEmpty);
      expect(repo.commentLikes, 3);
    },
  );
}
