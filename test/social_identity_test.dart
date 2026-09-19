import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/core/app_routes.dart';
import 'package:mooddare/models/comment_model.dart';
import 'package:mooddare/models/user_model.dart';
import 'package:mooddare/features/feed/presentation/widgets/post_likes_sheet.dart';
import 'package:mooddare/features/feed/presentation/widgets/comments_sheet.dart';
import 'package:mooddare/features/feed/presentation/screens/post_details_screen.dart';
import 'moments_test.dart' show openFeed, tapMedia;
import 'support/moments_fakes.dart';

UserModel user(String id) =>
    UserModel(id: id, username: id, createdAt: moment('time').createdAt);
Route<dynamic> profileStub(RouteSettings settings) {
  expect(settings.name, profileRoute);
  return MaterialPageRoute<void>(
    builder: (_) => Scaffold(
      appBar: AppBar(),
      body: Text('Profile: ${settings.arguments}'),
    ),
  );
}

void main() {
  testWidgets(
    'post avatar and username have an eight-pixel visual gap in both views',
    (tester) async {
      final repo = MemoryPosts([moment('identity')]);
      repo.authors['author'] = user('author');
      await openFeed(tester, repo);
      for (final fullscreen in [false, true]) {
        if (fullscreen) await tapMedia(tester);
        final avatar = tester.getRect(
          find.descendant(
            of: find.byKey(const ValueKey('moment_author_avatar')),
            matching: find.byType(CircleAvatar),
          ),
        );
        final name = tester.getRect(find.text('@author'));
        expect(name.left - avatar.right, closeTo(8, .1));
      }
    },
  );

  testWidgets(
    'long press opens fresh liker profiles without liking, pauses and resumes both video views',
    (tester) async {
      final repo = MemoryPosts([moment('likers', type: 'video')])
        ..likerIds = ['alice', 'bob'];
      repo.authors.addAll({'alice': user('alice'), 'bob': user('bob')});
      final video = MemoryVideo();
      await openFeed(tester, repo, video: video, onGenerateRoute: profileStub);
      for (final fullscreen in [false, true]) {
        if (fullscreen) await tapMedia(tester);
        final current = video.created;
        expect(video.playing[current], isTrue);
        await tester.longPress(find.byTooltip('Like'));
        await tester.pumpAndSettle();
        expect(find.byType(PostLikesSheet), findsOneWidget);
        expect(find.text('@alice'), findsOneWidget);
        expect(find.text('@bob'), findsOneWidget);
        expect(repo.likes, 0);
        expect(video.playing.values.any((playing) => playing), isFalse);
        if (!fullscreen) expect(find.byType(PostDetailsScreen), findsNothing);
        for (final key in ['liker_avatar_alice', 'liker_name_alice']) {
          await tester.tap(find.byKey(ValueKey(key)));
          await tester.pumpAndSettle();
          expect(find.text('Profile: alice'), findsOneWidget);
          await tester.pageBack();
          await tester.pumpAndSettle();
          expect(find.byType(PostLikesSheet), findsOneWidget);
          expect(video.playing[current], isFalse);
        }
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(video.playing[current], isTrue);
      }
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pumpAndSettle();
      expect(video.playing, isEmpty);
    },
  );

  testWidgets(
    'liker sheet can retry, hide blocked accounts and handle deleted profiles',
    (tester) async {
      final repo = MemoryPosts([moment('retry-likes')])
        ..failLikers = true
        ..likerIds = ['alice', 'alice', 'blocked', 'deleted']
        ..blocked = {'blocked'};
      repo.authors['alice'] = user('alice');
      await openFeed(tester, repo);
      await tester.longPress(find.byTooltip('Like'));
      await tester.pumpAndSettle();
      expect(find.text('Could not load likes. Retry'), findsOneWidget);
      repo.failLikers = false;
      await tester.tap(find.text('Could not load likes. Retry'));
      await tester.pumpAndSettle();
      expect(find.text('@alice'), findsOneWidget);
      expect(find.text('Account unavailable'), findsOneWidget);
      expect(repo.authorReads.where((id) => id == 'blocked'), isEmpty);
      expect(repo.authorReads.where((id) => id == 'alice').length, 1);
      final deleted = tester.widget<TextButton>(
        find.byKey(const ValueKey('liker_name_deleted')),
      );
      expect(deleted.onPressed, isNull);
    },
  );

  testWidgets('liker sheet is empty when no users liked the post', (
    tester,
  ) async {
    await openFeed(tester, MemoryPosts([moment('empty-likes')]));
    await tester.longPress(find.byTooltip('Like'));
    await tester.pumpAndSettle();
    expect(find.text('No likes to show yet.'), findsOneWidget);
  });

  testWidgets('liker profiles load lazily rather than fetching every account', (
    tester,
  ) async {
    final ids = List.generate(150, (i) => 'user$i');
    final repo = MemoryPosts([moment('many-likes')])..likerIds = ids;
    repo.authors.addEntries(ids.map((id) => MapEntry(id, user(id))));
    await openFeed(tester, repo);
    await tester.longPress(find.byTooltip('Like'));
    await tester.pumpAndSettle();
    expect(repo.authorReads.length, lessThan(30));
    await tester.drag(find.byType(ListView), const Offset(0, -1000));
    await tester.pumpAndSettle();
    expect(repo.authorReads.any((id) => id == 'user25'), isTrue);
    expect(repo.authorReads.length, lessThan(70));
  });

  testWidgets(
    'comments have no close icon and identities open profiles without losing the draft',
    (tester) async {
      final repo = MemoryPosts([moment('comment-profiles')]);
      repo.comments.add(
        const CommentModel(id: 'c', authorId: 'alice', text: 'Hello there'),
      );
      repo.authors['alice'] = user('alice');
      addTearDown(repo.commentChanges.close);
      await openFeed(tester, repo, onGenerateRoute: profileStub);
      await tester.tap(find.byTooltip('Comments'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Close comments'), findsNothing);
      expect(find.byIcon(Icons.close), findsNothing);
      expect(find.text('@alice'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('comment_avatar_c')),
          matching: find.byType(CircleAvatar),
        ),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField), 'Keep this draft');
      await tester.pump();
      for (final key in ['comment_avatar_c', 'comment_author_c']) {
        await tester.ensureVisible(find.byKey(ValueKey(key)));
        await tester.tap(find.byKey(ValueKey(key)));
        await tester.pumpAndSettle();
        expect(find.text('Profile: alice'), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'Keep this draft',
        );
      }
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(CommentsSheet), findsNothing);
    },
  );

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'comment text uses full width and the like count stays beside its heart at scale $scale',
      (tester) async {
        final repo = MemoryPosts([moment('wide-comments')]);
        repo.comments.add(
          CommentModel(
            id: 'c',
            authorId: 'viewer',
            text: List.filled(
              10,
              'A longer comment with room to read.',
            ).join(' '),
            likedBy: const ['alice'],
          ),
        );
        repo.authors['viewer'] = user('viewer');
        addTearDown(repo.commentChanges.close);
        await openFeed(
          tester,
          repo,
          size: const Size(320, 700),
          textScale: scale,
        );
        await tester.tap(find.byTooltip('Comments'));
        await tester.pumpAndSettle();
        expect(
          tester.getSize(find.byKey(const ValueKey('comment_text_c'))).width,
          closeTo(288, .1),
        );
        expect(
          tester.getRect(find.byKey(const ValueKey('comment_menu_c'))).right,
          closeTo(316, .1),
        );
        final like = find.byKey(const ValueKey('comment_like_c'));
        final heart = tester.getRect(
          find.descendant(of: like, matching: find.byType(Icon)),
        );
        final count = tester.getRect(
          find.byKey(const ValueKey('comment_count_c')),
        );
        expect(heart.center.dy, closeTo(count.center.dy, .1));
        expect(count.left - heart.right, lessThanOrEqualTo(8.1));
        expect(tester.takeException(), isNull);
        await tester.drag(find.text('Comments'), const Offset(0, 650));
        await tester.pumpAndSettle();
        expect(find.byType(CommentsSheet), findsNothing);
      },
    );
  }
}
