import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:mooddare/firebase_options.dart';
import 'package:mooddare/core/app_theme.dart';
import 'package:mooddare/core/app_routes.dart';
import 'package:mooddare/features/profile/data/account_repository.dart';
import 'package:mooddare/features/profile/data/social_repository.dart';
import 'package:mooddare/features/feed/data/repositories/post_repository.dart';
import 'package:mooddare/features/dares/data/repositories/dare_library_repository.dart';
import 'package:mooddare/features/drafts/data/draft_repository.dart';
import 'package:mooddare/features/drafts/data/capture_draft.dart';
import 'package:mooddare/features/links/moment_links.dart';
import 'package:mooddare/features/notifications/data/notification_repository.dart';
import 'package:mooddare/features/notifications/presentation/notification_inbox.dart';

/// Explicit opt-in, TEST EMULATOR ONLY: creates two disposable live accounts.
/// Never run a Flutter integration runner on a personal device (it reinstalls).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'two isolated accounts: drafts, links, social activity, inbox navigation and server deletion',
    (tester) async {
      final primary = await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      final secondary = await Firebase.initializeApp(
        name: 'qa-second-account',
        options: DefaultFirebaseOptions.currentPlatform,
      );
      final apps = [primary, secondary];
      final auth = apps.map((a) => FirebaseAuth.instanceFor(app: a)).toList();
      final db = apps
          .map((a) => FirebaseFirestore.instanceFor(app: a))
          .toList();
      final storage = apps
          .map((a) => FirebaseStorage.instanceFor(app: a))
          .toList();
      final run = const Uuid().v4().replaceAll('-', '');
      final accounts = <String>[];
      final draftFolder = Directory(
        '${(await getTemporaryDirectory()).path}/lifecycle-$run',
      );
      await draftFolder.create(recursive: true);
      final drafts = DraftRepository(
        currentUserId: () => auth[0].currentUser?.uid,
        directory: () async => draftFolder,
      );
      Future<void> erase(int i) async {
        final uid = auth[i].currentUser?.uid;
        if (uid == null) return;
        await AccountRepository(
          auth: auth[i],
          detachPush: () async {},
          deleteLocalDrafts: (owner) async {
            if (i == 0) await drafts.clear(owner);
          },
          requestDeletion: (owner) async {
            final response =
                await FirebaseFunctions.instanceFor(
                  app: apps[i],
                  region: 'us-central1',
                ).httpsCallable('requestAccountDeletion').call({
                  'confirm': 'DELETE',
                  'expectedUid': owner,
                });
            expect(response.data['accepted'], true);
          },
        ).deleteAccount();
      }

      Future<void> until(Future<bool> Function() condition) async {
        final deadline = DateTime.now().add(const Duration(seconds: 90));
        while (!await condition()) {
          if (DateTime.now().isAfter(deadline)) {
            fail('Timed out waiting for backend state.');
          }
          await Future<void>.delayed(const Duration(seconds: 1));
        }
      }

      try {
        for (var i = 0; i < 2; i++) {
          final result = await auth[i].createUserWithEmailAndPassword(
            email: 'mooddare-qa-$run-$i@example.com',
            password: '${const Uuid().v4()}Aa9!',
          );
          final uid = result.user!.uid;
          accounts.add(uid);
          // Only synthetic IDs are logged, to allow cleanup if the emulator stops.
          debugPrint('ACCOUNT_LIFECYCLE_QA_UID=$uid');
          final name = 'qatest${run.substring(0, 8)}$i';
          final batch = db[i].batch();
          batch.set(db[i].doc('users/$uid'), {
            'id': uid,
            'name': 'Automated QA',
            'username': name,
            'username_lower': name,
            'createdAt': FieldValue.serverTimestamp(),
          });
          batch.set(db[i].doc('usernames/$name'), {'uid': uid});
          await batch.commit();
        }
        final alice = accounts[0], bob = accounts[1];
        final social = List.generate(
          2,
          (i) => SocialRepository(firestore: db[i], auth: auth[i]),
        );
        final posts = List.generate(
          2,
          (i) => PostRepository(
            firestore: db[i],
            auth: auth[i],
            storage: storage[i],
          ),
        );
        final libraries = List.generate(
          2,
          (i) => DareLibraryRepository(firestore: db[i], auth: auth[i]),
        );
        await social[0].setFollowing(bob, true);
        await social[1].setFollowing(alice, true);
        final picture = await File(
          '${draftFolder.path}/photo.jpg',
        ).writeAsBytes(image.encodeJpg(image.Image(width: 80, height: 80)));
        final postId = 'qa-$run';
        final draft = CaptureDraft(
          id: postId,
          ownerId: alice,
          mediaType: 'image',
          dareText: 'Automated QA: take a quiet moment.',
          mediaFile: picture,
          updatedAt: DateTime.now(),
          moodId: 'relaxed',
          moodName: 'Relaxed',
        );
        await drafts.save(draft);
        final reopened = DraftRepository(
          currentUserId: () => alice,
          directory: () async => draftFolder,
        );
        expect((await reopened.list(alice)).single.dareText, draft.dareText);
        await expectLater(reopened.list(bob), throwsStateError);
        await posts[0].createPost(
          dareText: draft.dareText,
          mediaFile: draft.mediaFile,
          mediaType: 'image',
          postId: postId,
          moodId: draft.moodId,
          moodName: draft.moodName,
        );
        await posts[0].createPost(
          dareText: draft.dareText,
          mediaFile: draft.mediaFile,
          mediaType: 'image',
          postId: postId,
          moodId: draft.moodId,
          moodName: draft.moodName,
        );
        final shared = await posts[1].getSharedPost(
          MomentLinks.parse(MomentLinks.url(postId))!,
        );
        expect(shared?.authorId, alice);
        expect(shared?.moodId, 'relaxed');
        await posts[1].toggleLike(postId, bob);
        await posts[1].addComment(postId, 'root', 'QA comment');
        await posts[0].addReply(postId, 'root', 'first', 'QA reply');
        await posts[1].addReply(
          postId,
          'root',
          'answer',
          'QA nested reply',
          replyToId: 'first',
        );
        expect(
          (await db[1].doc('posts/$postId/replies/answer').get())
              .data()?['replyToAuthorId'],
          alice,
        );
        await posts[0].toggleCommentLike(postId, 'root', liked: true);
        final prompt = DarePrompt.fromPost(shared!);
        await libraries[0].save(prompt);
        expect(await libraries[0].send(prompt, bob), true);
        expect(await libraries[0].send(prompt, bob), false);
        final invite = (await libraries[1].inbox().first).single;
        expect(invite.prompt.text, draft.dareText);
        await libraries[1].markOpened(invite.id);
        final notifications = NotificationRepository(
          firestore: db[0],
          auth: auth[0],
        );
        await until(() async {
          final all =
              (await db[0].collection('users/$alice/notifications').get()).docs;
          return all.any((d) => d.data()['kind'] == 'follow') &&
              all.any((d) => d.data()['kind'] == 'comment') &&
              all.any((d) => d.data()['kind'] == 'reply');
        });
        final follow = (await notifications.watch().first).firstWhere(
          (n) => n.kind == 'follow',
        );
        BuildContext? screen;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.build(),
            onGenerateRoute: (settings) {
              if (settings.name == profileRoute) {
                return MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    body: Text('Profile target: ${settings.arguments}'),
                  ),
                );
              }
              return null;
            },
            home: Builder(
              builder: (context) {
                screen = context;
                return const Scaffold(body: Text('Inbox QA'));
              },
            ),
          ),
        );
        final opening = openActivity(screen!, notifications, follow);
        await until(
          () async =>
              (await db[0].doc('users/$alice/notifications/${follow.id}').get())
                  .data()?['read'] ==
              true,
        );
        await tester.pumpAndSettle();
        expect(find.text('Profile target: $bob'), findsOneWidget);
        Navigator.of(tester.element(find.text('Profile target: $bob'))).pop();
        await tester.pumpAndSettle();
        await opening;
        await tester.pumpWidget(const SizedBox());
        await erase(0);
        expect(auth[0].currentUser, null);
        await until(
          () async =>
              !(await db[1]
                      .doc('posts/$postId')
                      .get(const GetOptions(source: Source.server)))
                  .exists,
        );
        expect(await posts[1].getSharedPost(postId), null);
        await until(
          () async =>
              !(await db[1]
                      .doc('users/$alice')
                      .get(const GetOptions(source: Source.server)))
                  .exists,
        );
        expect((await db[1].doc('users/$bob').get()).exists, true);
        await until(
          () async =>
              (await db[1]
                      .collection('dareInvites')
                      .where('recipientId', isEqualTo: bob)
                      .get(const GetOptions(source: Source.server)))
                  .docs
                  .isEmpty,
        );
        expect(
          (await db[1].collection('users/$bob/following').get()).docs,
          isEmpty,
        );
        await until(() async {
          try {
            await storage[1].ref('posts/$alice/$postId.jpg').getDownloadURL();
            return false;
          } on FirebaseException catch (error) {
            if (error.code == 'object-not-found') return true;
            rethrow;
          }
        });
        debugPrint('ACCOUNT_LIFECYCLE_QA_SOCIAL_AND_DELETION_PASSED');
      } finally {
        await tester.pumpWidget(const SizedBox());
        for (var i = 0; i < accounts.length; i++) {
          try {
            await erase(i);
          } catch (error) {
            debugPrint(
              'ACCOUNT_LIFECYCLE_QA_CLEANUP_NEEDED=${accounts[i]} ${error.runtimeType}',
            );
          }
        }
        if (await draftFolder.exists()) {
          await draftFolder.delete(recursive: true);
        }
      }
    },
    skip: !const bool.fromEnvironment('RUN_LIVE_ACCOUNT_QA'),
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
