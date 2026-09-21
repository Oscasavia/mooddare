import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/core/app_theme.dart';
import 'package:mooddare/features/feed/presentation/widgets/comments_sheet.dart';
import 'package:mooddare/models/comment_model.dart';
import 'replies_test.dart' show ReplyPosts;

class DelayedLikes extends ReplyPosts {
  Completer<void> gate = Completer<void>();
  final requests = <({bool reply, String id, bool? liked})>[];

  @override
  Future<void> toggleCommentLike(
    String postId,
    String commentId, {
    bool? liked,
  }) {
    requests.add((reply: false, id: commentId, liked: liked));
    return gate.future;
  }

  @override
  Future<void> toggleReplyLike(String postId, String replyId, {bool? liked}) {
    requests.add((reply: true, id: replyId, liked: liked));
    return gate.future;
  }

  void emit(bool reply, List<String> likes) {
    final model = CommentModel(
      id: reply ? 'child' : 'root',
      parentId: reply ? 'root' : null,
      authorId: 'author',
      text: 'A comment',
      likedBy: likes,
    );
    if (reply) {
      replies.clear();
      replies.add(model);
      changes.add(List.of(replies));
    } else {
      comments.clear();
      comments.add(model);
      commentChanges.add(List.of(comments));
    }
  }
}

void main() {
  for (final reply in [false, true]) {
    final id = reply ? 'child' : 'root';
    late DelayedLikes repo;
    setUp(() {
      repo = DelayedLikes();
      repo.comments.add(
        const CommentModel(id: 'root', authorId: 'author', text: 'Root'),
      );
      repo.emit(reply, ['other']);
    });
    tearDown(() async {
      await repo.commentChanges.close();
      await repo.changes.close();
    });
    Future<void> mount(WidgetTester tester) async {
      repo.gate = Completer<void>();
      tester.view.physicalSize = const Size(430, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(),
          home: Scaffold(
            body: CommentsSheet(post: repo.posts.first, repository: repo),
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (reply) {
        await tester.tap(find.text('View replies'));
        await tester.pumpAndSettle();
      }
    }

    final button = find.byKey(ValueKey('comment_like_$id'));
    final count = find.byKey(ValueKey('comment_count_$id'));
    void check(WidgetTester tester, {required bool liked, required int likes}) {
      final icon = tester.widget<Icon>(
        find.descendant(of: button, matching: find.byType(Icon)),
      );
      expect(icon.icon, liked ? Icons.favorite : Icons.favorite_outline);
      expect(icon.color, liked ? AppTheme.likedHeart : null);
      expect(tester.widget<Text>(count).data, '$likes');
      expect(tester.widget<Text>(count).semanticsLabel, '$likes likes');
      expect(
        DefaultTextStyle.of(tester.element(count)).style.color,
        Colors.white,
      );
    }

    testWidgets(
      '$id likes and unlikes update before Firebase and reconcile both response orders',
      (tester) async {
        await mount(tester);
        check(tester, liked: false, likes: 1);
        await tester.tap(button);
        await tester.pump();
        check(tester, liked: true, likes: 2);
        expect(tester.widget<TextButton>(button).onPressed, isNull);
        await tester.tap(button);
        await tester.pump();
        expect(repo.requests, [(reply: reply, id: id, liked: true)]);
        // Other people's likes remain live while our write is outstanding.
        repo.emit(reply, ['other', 'second']);
        await tester.pump();
        check(tester, liked: true, likes: 3);
        // The write response may arrive before its snapshot: no flicker backward.
        repo.gate.complete();
        await tester.pumpAndSettle();
        check(tester, liked: true, likes: 3);
        repo.emit(reply, ['other', 'second', 'viewer']);
        await tester.pumpAndSettle();
        check(tester, liked: true, likes: 3);
        repo.gate = Completer<void>();
        await tester.tap(button);
        await tester.pump();
        check(tester, liked: false, likes: 2);
        // This time the snapshot arrives before the write response.
        repo.emit(reply, ['other', 'second']);
        await tester.pump();
        check(tester, liked: false, likes: 2);
        repo.gate.complete();
        await tester.pumpAndSettle();
        check(tester, liked: false, likes: 2);
        expect(repo.requests.last, (reply: reply, id: id, liked: false));
        expect(tester.widget<TextButton>(button).onPressed, isNotNull);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '$id failed unlike rolls back without discarding other users likes and can retry',
      (tester) async {
        repo.emit(reply, ['other', 'viewer']);
        await mount(tester);
        await tester.tap(button);
        await tester.pump();
        check(tester, liked: false, likes: 1);
        repo.emit(reply, ['other', 'viewer', 'second']);
        await tester.pump();
        check(tester, liked: false, likes: 2);
        repo.gate.completeError(StateError('Offline'));
        await tester.pumpAndSettle();
        check(tester, liked: true, likes: 3);
        expect(
          find.text('Could not update your like. Try again.'),
          findsOneWidget,
        );
        repo.gate = Completer<void>();
        await tester.tap(button);
        await tester.pump();
        check(tester, liked: false, likes: 2);
        repo.gate.complete();
        await tester.pumpAndSettle();
        check(tester, liked: false, likes: 2);
        repo.emit(reply, ['other', 'second']);
        await tester.pumpAndSettle();
        check(tester, liked: false, likes: 2);
        expect(
          find.text('Could not update your like. Try again.'),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '$id failed undo preserves a saved like while its snapshot is delayed',
      (tester) async {
        await mount(tester);
        await tester.tap(button);
        await tester.pump();
        repo.gate.complete();
        await tester.pumpAndSettle();
        check(tester, liked: true, likes: 2);
        // Undo before the first write's live snapshot is delivered.
        repo.gate = Completer<void>();
        await tester.tap(button);
        await tester.pump();
        check(tester, liked: false, likes: 1);
        expect(repo.requests.last.liked, false);
        repo.gate.completeError(StateError('Offline'));
        await tester.pumpAndSettle();
        check(tester, liked: true, likes: 2);
        repo.emit(reply, ['other', 'viewer']);
        await tester.pumpAndSettle();
        check(tester, liked: true, likes: 2);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('$id can be dismissed while a delayed like fails', (
      tester,
    ) async {
      await mount(tester);
      await tester.tap(button);
      await tester.pump();
      check(tester, liked: true, likes: 2);
      await tester.pumpWidget(const SizedBox());
      repo.gate.completeError(StateError('Offline'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
