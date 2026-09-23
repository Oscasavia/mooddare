import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/features/dares/data/repositories/dare_library_repository.dart';
import 'package:mooddare/features/dares/data/repositories/dares_repository.dart';
import 'package:mooddare/features/dares/presentation/screens/dare_generation_screen.dart';
import 'package:mooddare/features/dares/presentation/screens/dare_library_screen.dart';
import 'package:mooddare/features/dares/presentation/widgets/dare_actions.dart';
import 'package:mooddare/features/dares/presentation/widgets/send_dare_sheet.dart';
import 'package:mooddare/features/feed/presentation/widgets/dare_proof_card.dart';
import 'package:mooddare/features/profile/data/social_repository.dart';
import 'package:mooddare/features/profile/presentation/screens/profile_screen.dart';
import 'dare_library_repository_test.dart' show prompt;
import 'entry_polish_test.dart' show mount;
import 'profile_updates_test.dart' show ProfileChanges, ProfilePosts;
import 'support/moments_fakes.dart';
import 'support/social_fakes.dart';

class ControlledLibrary extends DareLibraryRepository {
  bool failSave = false,
      failSend = false,
      failDismiss = false,
      failLoad = false;
  Completer<void>? saveGate, sendGate;
  int saves = 0, sends = 0;
  ControlledLibrary({required super.firestore, required super.auth});
  @override
  Future<void> save(DarePrompt prompt) async {
    saves++;
    if (saveGate != null) await saveGate!.future;
    if (failSave) throw StateError('offline');
    return super.save(prompt);
  }

  @override
  Future<bool> send(DarePrompt prompt, String recipient) async {
    sends++;
    if (sendGate != null) await sendGate!.future;
    if (failSend) throw StateError('offline');
    return super.send(prompt, recipient);
  }

  @override
  Future<void> dismiss(String id) {
    if (failDismiss) return Future.error(StateError('offline'));
    return super.dismiss(id);
  }

  @override
  Stream<List<DareEntry>> saved({int limit = 40}) => failLoad
      ? Stream.error(StateError('offline'))
      : super.saved(limit: limit);
}

void main() {
  late FakeFirebaseFirestore db;
  late MockFirebaseAuth auth;
  late ControlledLibrary library;
  late SocialRepository social;
  final catalog = DaresRepository(loadMoods: () async => []);
  setUp(() async {
    db = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(mockUser: MockUser(uid: 'alice'), signedIn: true);
    library = ControlledLibrary(firestore: db, auth: auth);
    social = SocialRepository(firestore: db, auth: auth);
    for (final id in ['alice', 'bob', 'charlie']) {
      await db.doc('users/$id').set({
        'id': id,
        'username': id,
        'createdAt': Timestamp.now(),
      });
    }
    await social.setFollowing('bob', true);
    await SocialRepository(
      firestore: db,
      auth: MockFirebaseAuth(mockUser: MockUser(uid: 'bob'), signedIn: true),
    ).setFollowing('alice', true);
    await social.setFollowing('charlie', true); // One-way; must never appear.
  });
  Widget camera(DarePrompt p) => Scaffold(
    appBar: AppBar(),
    body: Text('Camera: ${p.moodId} / ${p.moodName} / ${p.text}'),
  );
  testWidgets(
    'bookmark saves once while pending, survives rebuild, and unsaves',
    (tester) async {
      library.saveGate = Completer<void>();
      await mount(
        tester,
        Scaffold(
          body: SaveDareButton(prompt: prompt, repository: library),
        ),
      );
      await tester.tap(find.byTooltip('Save dare'));
      await tester.pump();
      await tester.tap(find.byTooltip('Save dare'));
      await tester.pump();
      expect(library.saves, 1);
      library.saveGate!.complete();
      await tester.pumpAndSettle();
      expect(find.byTooltip('Unsave dare'), findsOneWidget);
      await tester.tap(find.byTooltip('Unsave dare'));
      await tester.pumpAndSettle();
      expect(
        await tester.runAsync(() => library.isSaved(prompt).first),
        isFalse,
      );
    },
  );
  testWidgets('failed save keeps bookmark unsaved and permits retry', (
    tester,
  ) async {
    library.failSave = true;
    await mount(
      tester,
      Scaffold(
        body: SaveDareButton(prompt: prompt, repository: library),
      ),
    );
    await tester.tap(find.byTooltip('Save dare'));
    await tester.pumpAndSettle();
    expect(
      find.text('Could not update saved dares. Please try again.'),
      findsOneWidget,
    );
    expect(find.byTooltip('Save dare'), findsOneWidget);
    library.failSave = false;
    await tester.tap(find.byTooltip('Save dare'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Unsave dare'), findsOneWidget);
  });
  testWidgets(
    'selected mood exposes bookmark and secondary Send dare without changing camera',
    (tester) async {
      await mount(
        tester,
        DareDisplayScreen(
          mood: DaresRepository.starterMoods.first,
          isProofRequired: false,
          library: library,
        ),
        size: const Size(320, 700),
        scale: 1.5,
      );
      expect(find.text('Open camera'), findsOneWidget);
      expect(find.text('Send dare'), findsOneWidget);
      await tester.ensureVisible(find.byTooltip('Save dare'));
      await tester.tap(find.byTooltip('Save dare'));
      await tester.pumpAndSettle();
      expect(await tester.runAsync(() => library.saved().first), hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'saved empty, load failure retry, and two-column cards at narrow width',
    (tester) async {
      library.failLoad = true;
      await mount(tester, Scaffold(body: DareLibraryList(repository: library)));
      expect(find.text('Couldn’t load dares'), findsOneWidget);
      library.failLoad = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Keep a little inspiration'), findsOneWidget);
      await library.save(prompt);
      await library.save(
        const DarePrompt(
          text: 'A second dare',
          moodId: 'happy',
          moodName: 'Happy',
        ),
      );
      await mount(
        tester,
        Scaffold(body: DareLibraryList(repository: library)),
        size: const Size(360, 700),
        scale: 2,
      );
      expect(find.text('Try it'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      final a = tester.getTopLeft(find.text(prompt.text)),
          b = tester.getTopLeft(find.text('A second dare'));
      expect(a.dy, b.dy);
      expect(a.dx, isNot(b.dx));
    },
  );
  testWidgets(
    'saved dare opens camera with exact mood and text; backing out keeps save',
    (tester) async {
      await library.save(prompt);
      await mount(
        tester,
        Scaffold(
          body: DareLibraryList(
            repository: library,
            catalog: catalog,
            cameraBuilder: camera,
          ),
        ),
      );
      await tester.tap(find.text('Try it'));
      await tester.pumpAndSettle();
      expect(
        find.text('Camera: happy / Happy / ${prompt.text}'),
        findsOneWidget,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(await tester.runAsync(() => library.saved().first), hasLength(1));
    },
  );
  testWidgets(
    'premium and removed moods cannot enter the camera, legacy prompts can',
    (tester) async {
      for (final p in [
        const DarePrompt(
          text: 'Mismatched name',
          moodId: 'preview-epic-spicy',
          moodName: 'Happy',
        ),
        const DarePrompt(
          text: 'Locked dare',
          moodId: 'preview-epic-spicy',
          moodName: 'Spicy',
        ),
        const DarePrompt(
          text: 'Removed dare',
          moodId: 'removed',
          moodName: 'Removed',
        ),
      ]) {
        await mount(
          tester,
          Scaffold(
            body: TryDareButton(
              prompt: p,
              catalog: catalog,
              cameraBuilder: camera,
            ),
          ),
        );
        await tester.tap(find.text('Try this dare'));
        await tester.pumpAndSettle();
        expect(
          find.text('This mood is not available to try right now.'),
          findsOneWidget,
        );
      }
      await mount(
        tester,
        Scaffold(
          body: TryDareButton(
            prompt: const DarePrompt(text: 'Old prompt'),
            catalog: catalog,
            cameraBuilder: camera,
          ),
        ),
      );
      await tester.tap(find.text('Try this dare'));
      await tester.pumpAndSettle();
      expect(find.text('Camera: null / null / Old prompt'), findsOneWidget);
    },
  );
  testWidgets(
    'recipient search contains only mutuals and updates after unfollow',
    (tester) async {
      await mount(
        tester,
        Scaffold(
          body: SendDareSheet(
            prompt: prompt,
            repository: library,
            social: social,
          ),
        ),
      );
      expect(find.text('@bob'), findsOneWidget);
      expect(find.text('@charlie'), findsNothing);
      expect(find.text('@alice'), findsNothing);
      await tester.enterText(find.byType(TextField), '@nobody');
      await tester.pumpAndSettle();
      expect(find.text('No matching people'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '@BO');
      await tester.pumpAndSettle();
      expect(find.text('@bob'), findsOneWidget);
      await social.setFollowing('bob', false);
      await tester.pumpAndSettle();
      expect(find.text('@bob'), findsNothing);
      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();
      expect(find.text('Better with a friend'), findsOneWidget);
    },
  );
  testWidgets(
    'send failure retries, duplicate taps are disabled and delivery is visible to recipient',
    (tester) async {
      library.failSend = true;
      await mount(
        tester,
        Scaffold(
          body: SendDareSheet(
            prompt: prompt,
            repository: library,
            social: social,
          ),
        ),
        scale: 2,
      );
      await tester.scrollUntilVisible(
        find.text('Send'),
        160,
        scrollable: find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await Scrollable.ensureVisible(
        tester.element(find.text('Send')),
        alignment: .5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not send.'), findsOneWidget);
      library.failSend = false;
      library.sendGate = Completer<void>();
      await Scrollable.ensureVisible(
        tester.element(find.text('Send')),
        alignment: .5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send'));
      await tester.pump();
      expect(find.text('Sending…'), findsOneWidget);
      library.sendGate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Sent'), findsOneWidget);
      expect(library.sends, 2);
      final bob = DareLibraryRepository(
        firestore: db,
        auth: MockFirebaseAuth(mockUser: MockUser(uid: 'bob'), signedIn: true),
      );
      expect(
        (await tester.runAsync(() => bob.inbox().first))!.single.prompt.text,
        prompt.text,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'inbox badge opens recipient list, Try passes prompt, marks opened and dismiss can retry',
    (tester) async {
      final bobAuth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'bob'),
        signedIn: true,
      );
      final bob = ControlledLibrary(firestore: db, auth: bobAuth);
      final bobSocial = SocialRepository(firestore: db, auth: bobAuth);
      await library.send(prompt, 'bob');
      await mount(
        tester,
        Scaffold(
          body: DareInboxButton(repository: bob, social: bobSocial),
        ),
      );
      expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isTrue);
      await tester.tap(find.byTooltip('Dare inbox'));
      await tester.pumpAndSettle();
      expect(find.text('From @alice'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await mount(
        tester,
        Scaffold(
          body: DareLibraryList(
            inbox: true,
            repository: bob,
            social: bobSocial,
            catalog: catalog,
            cameraBuilder: camera,
          ),
        ),
      );
      await tester.tap(find.text('Try it'));
      await tester.pumpAndSettle();
      expect(
        find.text('Camera: happy / Happy / ${prompt.text}'),
        findsOneWidget,
      );
      expect(await tester.runAsync(() => bob.hasUnread().first), isFalse);
      await tester.pageBack();
      await tester.pumpAndSettle();
      bob.failDismiss = true;
      await tester.tap(find.byTooltip('Dismiss dare'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not dismiss'), findsOneWidget);
      bob.failDismiss = false;
      await tester.tap(find.byTooltip('Dismiss dare'));
      await tester.pumpAndSettle();
      expect(find.text('A dare could be on its way'), findsOneWidget);
    },
  );
  testWidgets('inbox hides blocked senders immediately', (tester) async {
    await DareLibraryRepository(
      firestore: db,
      auth: MockFirebaseAuth(mockUser: MockUser(uid: 'bob'), signedIn: true),
    ).send(prompt, 'alice');
    await mount(
      tester,
      Scaffold(
        body: DareLibraryList(inbox: true, repository: library, social: social),
      ),
    );
    expect(find.text(prompt.text), findsOneWidget);
    await social.block('bob');
    await tester.pumpAndSettle();
    expect(find.text(prompt.text), findsNothing);
  });
  for (final full in [false, true]) {
    testWidgets(
      'post ${full ? 'viewer' : 'card'} has Try and saves only its dare, not media',
      (tester) async {
        final post = moment('saved', moodId: 'happy', moodName: 'Happy');
        final posts = MemoryPosts([post]);
        addTearDown(posts.commentChanges.close);
        await mount(
          tester,
          Scaffold(
            body: DareProofCard(
              post: post,
              isFullScreen: full,
              repository: posts,
              dareLibrary: library,
            ),
          ),
          size: const Size(390, 800),
        );
        expect(find.text('Try this dare'), findsOneWidget);
        await tester.tap(find.byTooltip('Moment options'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save dare'));
        await tester.pumpAndSettle();
        expect(
          (await tester.runAsync(
            () => library.saved().first,
          ))!.single.prompt.text,
          post.dareText,
        );
        final data = (await db.collection('users/alice/savedDares').get())
            .docs
            .single
            .data();
        expect(data.containsKey('mediaUrl'), isFalse);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets('Saved tab is visible on own profile only', (tester) async {
    final users = ProfileChanges(), friends = MemorySocial();
    addTearDown(users.updates.close);
    addTearDown(friends.changed.close);
    await mount(
      tester,
      ProfileScreen(
        isGuest: false,
        repository: users,
        postRepository: ProfilePosts(),
        socialRepository: friends,
        dareLibrary: library,
      ),
    );
    expect(find.text('Saved'), findsOneWidget);
    await tester.tap(find.text('Saved'));
    await tester.pumpAndSettle();
    expect(find.text('Keep a little inspiration'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await mount(
      tester,
      ProfileScreen(
        isGuest: false,
        userId: 'other',
        repository: users,
        postRepository: ProfilePosts(),
        socialRepository: friends,
        dareLibrary: library,
      ),
    );
    expect(find.text('Saved'), findsNothing);
  });
}
