import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:mooddare/core/app_routes.dart';
import 'package:mooddare/core/app_theme.dart';
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
    String text, {
    String? replyToId,
  }) async {
    submissions.add(replyId);
    if (failSending) throw StateError('Offline');
    parents.add(parentId);
    replies.add(
      CommentModel(
        id: replyId,
        parentId: parentId,
        authorId: uid!,
        text: text,
        replyToId: replyToId,
        replyToAuthorId: replyToId == null
            ? comments.firstWhere((c) => c.id == parentId).authorId
            : replies.firstWhere((r) => r.id == replyToId).authorId,
      ),
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
      replyToId: old.replyToId,
      replyToAuthorId: old.replyToAuthorId,
      authorId: old.authorId,
      text: text,
      editedAt: DateTime.now(),
    );
    changes.add(List.of(replies));
  }

  @override
  Future<void> toggleReplyLike(
    String postId,
    String replyId, {
    bool? liked,
  }) async {
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
  Future<void> open(
    WidgetTester tester, {
    Size size = const Size(430, 1000),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        onGenerateRoute: (settings) {
          expect(settings.name, profileRoute);
          return MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              appBar: AppBar(),
              body: Text('Profile: ${settings.arguments}'),
            ),
          );
        },
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
      expect(find.text('@parent A reply', findRichText: true), findsOneWidget);
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
      expect(
        find.text('@parent Edited child', findRichText: true),
        findsOneWidget,
      );
      expect(find.textContaining('Could not delete'), findsOneWidget);
      repo.failDelete = false;
      await remove();
      expect(
        find.text('@parent Edited child', findRichText: true),
        findsNothing,
      );
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
        likedBy: ['viewer'],
      );
      repo.replies.add(reply);
      repo.changes.add(List.of(repo.replies));
      await tester.pumpAndSettle();
      final control = find.byKey(const ValueKey('replies_root'));
      expect(find.text('View replies'), findsOneWidget);
      expect(
        find.text('@parent Thanks for the idea!', findRichText: true),
        findsNothing,
      );
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
      expect(
        find.text('@parent Thanks for the idea!', findRichText: true),
        findsOneWidget,
      );
      final replyHeart = find.descendant(
        of: find.byKey(const ValueKey('comment_like_child')),
        matching: find.byIcon(Icons.favorite),
      );
      expect(tester.widget<Icon>(replyHeart).color, AppTheme.likedHeart);
      expect(
        DefaultTextStyle.of(
          tester.element(find.byKey(const ValueKey('comment_count_child'))),
        ).style.color,
        Colors.white,
      );
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
        if (id == 'child') {
          expect(
            tester.getTopLeft(avatar).dx,
            closeTo(tester.getTopLeft(find.text('Hide replies')).dx, .1),
          );
        }
        expect(
          tester.getTopLeft(name).dx - tester.getTopRight(avatar).dx,
          closeTo(6, .1),
        );
        expect(
          tester.getTopLeft(find.byKey(ValueKey('comment_actions_$id'))).dx,
          closeTo(tester.getTopLeft(text).dx, .1),
        );
      }
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('comment_text_child'))).dx,
        greaterThan(
          tester.getTopLeft(find.byKey(const ValueKey('comment_text_root'))).dx,
        ),
      );
      await tester.tap(control);
      await tester.pumpAndSettle();
      expect(
        find.text('@parent Thanks for the idea!', findRichText: true),
        findsNothing,
      );
      await tester.tap(control);
      await tester.pumpAndSettle();
      expect(
        find.text('@parent Thanks for the idea!', findRichText: true),
        findsOneWidget,
      );
      expect(repo.replyReads, 1);
      repo.changes.add([]);
      await tester.pumpAndSettle();
      expect(control, findsNothing);
      expect(
        find.text('@parent Thanks for the idea!', findRichText: true),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'replying to a reply targets that author, stays flat, and links only the purple mention',
    (tester) async {
      repo.authors['other'] = UserModel(
        id: 'other',
        username: 'friend',
        createdAt: Timestamp.now(),
      );
      repo.replies.add(
        const CommentModel(
          id: 'child',
          parentId: 'root',
          authorId: 'other',
          text: 'First reply',
        ),
      );
      await open(tester);
      await tester.tap(find.text('View replies'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('comment_reply_child')));
      await tester.pumpAndSettle();
      expect(find.text('Replying to @friend'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Agreed!');
      await tester.pump();
      repo.failSending = true;
      await tester.tap(find.byTooltip('Post comment'));
      await tester.pumpAndSettle();
      expect(find.text('Replying to @friend'), findsOneWidget);
      repo.failSending = false;
      await tester.tap(find.byTooltip('Post comment'));
      await tester.pumpAndSettle();
      final sent = repo.replies.last;
      expect(repo.submissions[0], repo.submissions[1]);
      expect(sent.parentId, 'root');
      expect(sent.replyToId, 'child');
      expect(sent.replyToAuthorId, 'other');
      final text = find.byKey(ValueKey('comment_text_${sent.id}'));
      final rich = tester.widget<Text>(text).textSpan! as TextSpan;
      expect(rich.toPlainText(), '@friend Agreed!');
      final mention = rich.children!.first as TextSpan;
      expect(
        mention.style!.color,
        Theme.of(tester.element(text)).colorScheme.primary,
      );
      expect((rich.children!.last as TextSpan).recognizer, isNull);
      expect(
        tester.getTopLeft(text).dx,
        tester.getTopLeft(find.byKey(const ValueKey('comment_text_child'))).dx,
      );
      await tester.tapAt(tester.getTopLeft(text) + const Offset(8, 8));
      await tester.pumpAndSettle();
      expect(find.text('Profile: other'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      // Editing changes only the body; the selected recipient survives.
      await tester.tap(find.byKey(ValueKey('comment_menu_${sent.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit comment'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Agreed!',
      );
      await tester.enterText(find.byType(TextField), 'Absolutely!');
      await tester.tap(find.byTooltip('Save comment'));
      await tester.pumpAndSettle();
      expect(
        find.text('@friend Absolutely!', findRichText: true),
        findsOneWidget,
      );
      // The original target can disappear without losing the saved recipient.
      await repo.deleteReply('post', 'child');
      await tester.pumpAndSettle();
      expect(
        find.text('@friend Absolutely!', findRichText: true),
        findsOneWidget,
      );
      await tester.tap(find.byKey(ValueKey('comment_reply_${sent.id}')));
      await tester.pumpAndSettle();
      expect(find.text('Replying to @viewer'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'root and reply actions align and wrap with large text on a narrow phone',
    (tester) async {
      repo.comments[0] = CommentModel(
        id: 'root',
        authorId: 'author',
        text: 'Parent comment',
        editedAt: DateTime.now(),
      );
      repo.replies.add(
        CommentModel(
          id: 'child',
          parentId: 'root',
          authorId: 'viewer',
          text: 'A longer reply that wraps onto several lines.',
          editedAt: DateTime.now(),
        ),
      );
      await open(tester, size: const Size(320, 900), textScale: 2);
      await tester.ensureVisible(find.text('View replies'));
      await tester.tap(find.text('View replies'));
      await tester.pumpAndSettle();
      for (final id in ['root', 'child']) {
        final body = tester.getRect(find.byKey(ValueKey('comment_text_$id')));
        final actions = tester.getRect(
          find.byKey(ValueKey('comment_actions_$id')),
        );
        expect(actions.left, closeTo(body.left, .1));
        for (final item in ['like', 'reply', 'edited']) {
          final rect = tester.getRect(
            find.byKey(ValueKey('comment_${item}_$id')),
          );
          expect(rect.left, greaterThanOrEqualTo(actions.left));
          expect(rect.right, lessThanOrEqualTo(actions.right + .1));
        }
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'comment avatars align with the heading and spacing stays compact',
    (tester) async {
      repo.comments.add(
        const CommentModel(
          id: 'older',
          authorId: 'author',
          text: 'Older comment',
        ),
      );
      repo.replies.add(
        const CommentModel(
          id: 'child',
          parentId: 'root',
          authorId: 'viewer',
          text: 'Reply',
        ),
      );
      await open(tester);
      final avatar = find.descendant(
        of: find.byKey(const ValueKey('comment_avatar_root')),
        matching: find.byType(CircleAvatar),
      );
      expect(
        tester.getTopLeft(avatar).dx,
        closeTo(tester.getTopLeft(find.text('Comments')).dx, .1),
      );
      final toggle = find.byKey(const ValueKey('replies_root'));
      expect(tester.getSize(toggle).height, 32);
      expect(
        tester.getTopLeft(toggle).dy,
        closeTo(
          tester
              .getBottomLeft(find.byKey(const ValueKey('comment_actions_root')))
              .dy,
          .1,
        ),
      );
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('older'))).dy -
            tester.getBottomLeft(toggle).dy,
        closeTo(8, .1),
      );
      // Keep the body, actions and toggle aligned with the username.
      final nameX = tester
          .getTopLeft(find.byKey(const ValueKey('comment_author_root')))
          .dx;
      for (final key in [
        'comment_text_root',
        'comment_actions_root',
        'replies_root',
      ]) {
        expect(
          tester.getTopLeft(find.byKey(ValueKey(key))).dx,
          closeTo(nameX, .1),
        );
      }
    },
  );

  for (final precedingComments in [0, 8]) {
    testWidgets(
      'expanding a long thread keeps its parent in place after $precedingComments comments',
      (tester) async {
        repo.comments.insertAll(
          0,
          List.generate(
            precedingComments,
            (i) => CommentModel(
              id: 'recent$i',
              authorId: 'author',
              text: 'Recent comment $i',
            ),
          ),
        );
        repo.replies.addAll(
          List.generate(
            10,
            (i) => CommentModel(
              id: 'child$i',
              parentId: 'root',
              authorId: 'viewer',
              text: "Reply $i: ${'A longer response. ' * 12}",
            ),
          ),
        );
        await open(tester);
        final toggle = find.byKey(const ValueKey('replies_root'));
        final scrollable = find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first;
        await tester.scrollUntilVisible(toggle, 180, scrollable: scrollable);
        await tester.pumpAndSettle();
        final before = tester.getTopLeft(toggle);
        final parent = find.byKey(const ValueKey('comment_author_root'));
        final parentBefore = tester.getTopLeft(parent);
        final scroll = tester.state<ScrollableState>(scrollable).position;
        final offset = scroll.pixels;
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(toggle).dy, closeTo(before.dy, .1));
        expect(tester.getTopLeft(parent).dy, closeTo(parentBefore.dy, .1));
        expect(scroll.pixels, closeTo(offset, .1));
        expect(
          tester
              .getTopLeft(find.byKey(const ValueKey('comment_author_child0')))
              .dy,
          greaterThanOrEqualTo(tester.getBottomLeft(toggle).dy),
        );
        final viewport = tester.getRect(find.byType(ListView));
        expect(
          tester
              .getTopLeft(find.byKey(const ValueKey('comment_text_child4')))
              .dy,
          greaterThan(viewport.bottom),
        );
        // Collapsing without scrolling also keeps the parent in the same place.
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(parent).dy, closeTo(parentBefore.dy, .1));
        expect(tester.takeException(), isNull);
      },
    );
  }

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
