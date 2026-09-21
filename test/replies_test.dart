import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/features/feed/presentation/widgets/comments_sheet.dart';
import 'package:mooddare/models/comment_model.dart';
import 'package:mooddare/models/user_model.dart';
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
    yield* changes.stream.map(
      (items) => items.where((r) => r.parentId == parentId).toList(),
    );
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
    repo.authors['author'] = UserModel(
      id: 'author',
      name: 'Parent',
      username: 'parent',
      createdAt: Timestamp.now(),
    );
    repo.authors['viewer'] = UserModel(
      id: 'viewer',
      name: 'Viewer',
      username: 'viewer',
      createdAt: Timestamp.now(),
    );
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
    'empty threads stay hidden and reply retries preserve text and IDs',
    (tester) async {
      await open(tester);
      expect(find.text('View replies'), findsNothing);
      expect(find.text('Hide replies'), findsNothing);
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
      expect(find.text('@parent A reply'), findsOneWidget);
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
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Child reply',
      );
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
      expect(find.text('@parent Edited child'), findsOneWidget);
      expect(find.textContaining('Could not delete'), findsOneWidget);
      repo.failDelete = false;
      await remove();
      expect(find.text('@parent Edited child'), findsNothing);
      expect(find.text('Parent comment'), findsOneWidget);
      expect(find.text('View replies'), findsNothing);
      expect(find.text('Hide replies'), findsNothing);
    },
  );
  testWidgets(
    'reply controls follow live data, chevrons and aligned compact avatars',
    (tester) async {
      await open(tester);
      expect(find.byKey(const ValueKey('replies_root')), findsNothing);
      const reply = CommentModel(
        id: 'child',
        parentId: 'root',
        authorId: 'viewer',
        text: 'Thanks for the idea!',
      );
      repo.replies.add(reply);
      repo.changes.add(List.of(repo.replies));
      await tester.pumpAndSettle();
      final control = find.byKey(const ValueKey('replies_root'));
      expect(find.text('View replies'), findsOneWidget);
      expect(find.text('@parent Thanks for the idea!'), findsNothing);
      expect(
        find.descendant(
          of: control,
          matching: find.byIcon(Icons.keyboard_arrow_down),
        ),
        findsOneWidget,
      );
      expect(
        tester.getCenter(find.byIcon(Icons.keyboard_arrow_down)).dx,
        greaterThan(tester.getTopRight(find.text('View replies')).dx),
      );
      await tester.tap(control);
      await tester.pumpAndSettle();
      expect(find.text('Hide replies'), findsOneWidget);
      expect(
        find.descendant(
          of: control,
          matching: find.byIcon(Icons.keyboard_arrow_up),
        ),
        findsOneWidget,
      );
      expect(
        tester.getCenter(find.byIcon(Icons.keyboard_arrow_up)).dx,
        greaterThan(tester.getTopRight(find.text('Hide replies')).dx),
      );
      expect(find.text('@parent Thanks for the idea!'), findsOneWidget);
      for (final id in ['root', 'child']) {
        final name = find.byKey(ValueKey('comment_author_$id'));
        final text = find.byKey(ValueKey('comment_text_$id'));
        expect(
          tester.getTopLeft(text).dx,
          closeTo(tester.getTopLeft(name).dx, .1),
        );
        final avatar = find.descendant(
          of: find.byKey(ValueKey('comment_avatar_$id')),
          matching: find.byType(CircleAvatar),
        );
        expect(tester.getSize(avatar), const Size(28, 28));
      }
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('comment_text_child'))).dx,
        greaterThan(
          tester.getTopLeft(find.byKey(const ValueKey('comment_text_root'))).dx,
        ),
      );
      await tester.tap(control);
      await tester.pumpAndSettle();
      expect(find.text('@parent Thanks for the idea!'), findsNothing);
      await tester.tap(control);
      await tester.pumpAndSettle();
      expect(find.text('@parent Thanks for the idea!'), findsOneWidget);
      expect(repo.replyReads, 1);
      repo.changes.add([]);
      await tester.pumpAndSettle();
      expect(control, findsNothing);
      expect(find.text('@parent Thanks for the idea!'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('threads containing only blocked replies have no toggle', (
    tester,
  ) async {
    repo.blocked = {'hidden'};
    repo.replies.add(
      const CommentModel(
        id: 'hidden-reply',
        parentId: 'root',
        authorId: 'hidden',
        text: 'Hidden',
      ),
    );
    await open(tester);
    expect(find.text('View replies'), findsNothing);
    expect(find.text('Hide replies'), findsNothing);
    expect(find.textContaining('Hidden'), findsNothing);
  });

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
