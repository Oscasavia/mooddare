import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/features/feed/presentation/widgets/comments_sheet.dart';
import 'package:mooddare/models/comment_model.dart';
import 'support/moments_fakes.dart';

class ReplyPosts extends MemoryPosts {
  ReplyPosts() : super([moment('post')]);
  final replies = <CommentModel>[];
  final changes = StreamController<List<CommentModel>>.broadcast();
  int replyReads = 0, replyLikes = 0;
  final parents = <String>[];
  @override
  Stream<List<CommentModel>> getReplies(String postId, String parentId) async* {
    replyReads++;
    yield List.of(replies.where((r) => r.parentId == parentId));
    yield* changes.stream;
  }

  @override
  Future<void> addReply(
    String postId,
    String parentId,
    String replyId,
    String text,
  ) async {
    submissions.add(replyId);
    if (failSending) throw StateError('Offline');
    parents.add(parentId);
    replies.add(
      CommentModel(id: replyId, parentId: parentId, authorId: uid!, text: text),
    );
    changes.add(List.of(replies));
  }

  @override
  Future<void> editReply(String postId, String replyId, String text) async {
    if (failEdit) throw StateError('Offline');
    final index = replies.indexWhere((r) => r.id == replyId);
    final old = replies[index];
    replies[index] = CommentModel(
      id: replyId,
      parentId: old.parentId,
      authorId: old.authorId,
      text: text,
      editedAt: DateTime.now(),
    );
    changes.add(List.of(replies));
  }

  @override
  Future<void> toggleReplyLike(String postId, String replyId) async {
    replyLikes++;
  }

  @override
  Future<void> deleteReply(String postId, String replyId) async {
    if (failDelete) throw StateError('Offline');
    replies.removeWhere((r) => r.id == replyId);
    changes.add(List.of(replies));
  }
}

void main() {
  late ReplyPosts repo;
  setUp(() {
    repo = ReplyPosts();
    repo.comments.add(
      const CommentModel(
        id: 'root',
        authorId: 'author',
        text: 'Parent comment',
      ),
    );
  });
  tearDown(() async {
    await repo.changes.close();
    await repo.commentChanges.close();
  });
  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CommentsSheet(post: repo.posts.first, repository: repo),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'replies load on expansion, collapse, and retry sends without duplicate IDs',
    (tester) async {
      await open(tester);
      expect(repo.replyReads, 0);
      await tester.tap(find.text('View replies'));
      await tester.pumpAndSettle();
      expect(find.text('No replies yet'), findsOneWidget);
      await tester.tap(find.text('Hide replies'));
      await tester.pumpAndSettle();
      expect(find.text('No replies yet'), findsNothing);
      await tester.tap(find.text('Reply'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Replying to'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'A reply');
      await tester.pump();
      repo.failSending = true;
      await tester.tap(find.byTooltip('Post comment'));
      await tester.pumpAndSettle();
      expect(find.text('A reply'), findsOneWidget);
      expect(find.textContaining('Your draft is saved'), findsOneWidget);
      repo.failSending = false;
      await tester.tap(find.byTooltip('Post comment'));
      await tester.pumpAndSettle();
      expect(repo.submissions[0], repo.submissions[1]);
      expect(repo.parents, ['root']);
      expect(find.text('A reply'), findsOneWidget);
      expect(find.text('Hide replies'), findsOneWidget);
      expect(find.textContaining('Replying to'), findsNothing);
    },
  );
  testWidgets(
    'reply edit, like, failed delete and successful delete use reply methods',
    (tester) async {
      repo.replies.add(
        const CommentModel(
          id: 'child',
          parentId: 'root',
          authorId: 'viewer',
          text: 'Child reply',
        ),
      );
      await open(tester);
      await tester.tap(find.text('View replies'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('comment_like_child')));
      await tester.pumpAndSettle();
      expect(repo.replyLikes, 1);
      expect(repo.commentLikes, 0);
      await tester.tap(find.byKey(const ValueKey('comment_menu_child')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit comment'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Edited child');
      await tester.tap(find.byTooltip('Save comment'));
      await tester.pumpAndSettle();
      expect(repo.replies.single.text, 'Edited child');
      repo.failDelete = true;
      Future<void> remove() async {
        await tester.tap(find.byKey(const ValueKey('comment_menu_child')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete comment'));
        await tester.pumpAndSettle();
      }

      await remove();
      expect(find.text('Edited child'), findsOneWidget);
      expect(find.textContaining('Could not delete'), findsOneWidget);
      repo.failDelete = false;
      await remove();
      expect(find.text('Edited child'), findsNothing);
      expect(find.text('Parent comment'), findsOneWidget);
    },
  );
  testWidgets(
    'cancel reply preserves typed text and deleting threads cannot receive replies',
    (tester) async {
      await open(tester);
      await tester.tap(find.text('Reply'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Keep my draft');
      await tester.tap(find.byTooltip('Cancel reply'));
      await tester.pumpAndSettle();
      expect(find.text('Keep my draft'), findsOneWidget);
      expect(find.textContaining('Replying to'), findsNothing);
      repo.commentChanges.add([
        const CommentModel(
          id: 'root',
          authorId: 'author',
          text: 'Parent comment',
          deleting: true,
        ),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Reply'), findsNothing);
      expect(find.text('View replies'), findsNothing);
      expect(
        find.textContaining('Thread deletion interrupted'),
        findsOneWidget,
      );
    },
  );
}
