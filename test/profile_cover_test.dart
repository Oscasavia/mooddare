import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/core/branding/profile_cover_color.dart';
import 'package:mooddare/features/profile/presentation/screens/profile_screen.dart';
import 'package:mooddare/features/profile/presentation/screens/edit_profile_screen.dart';
import 'package:mooddare/features/user/data/repositories/user_repository.dart';
import 'package:mooddare/models/user_model.dart';
import 'entry_polish_test.dart' show mount, ProfileMemory;
import 'entry_polish_test.dart' as entry;
import 'profile_updates_test.dart' show ProfileChanges, ProfilePosts, profile;
import 'support/social_fakes.dart';

Color coverColor(WidgetTester tester) =>
    (tester
                .widget<DecoratedBox>(
                  find.byKey(const ValueKey('profile_cover_background')),
                )
                .decoration
            as BoxDecoration)
        .color!;

void main() {
  test(
    'legacy/unknown colors fall back safely and all supported colors round-trip',
    () async {
      final db = FakeFirebaseFirestore();
      for (final value in [
        null,
        'invalid',
        42,
        ...ProfileCoverColor.values.map((c) => c.name),
      ]) {
        await db.doc('users/alice').set({
          'id': 'alice',
          if (value != null) 'coverColor': value,
        });
        final model = UserModel.fromFirestore(
          await db.doc('users/alice').get(),
        );
        expect(model.coverColor, ProfileCoverColor.fromId(value));
        expect(model.toFirestore()['coverColor'], model.coverColor.name);
      }
    },
  );
  test(
    'color saves preserve profile fields, stream immediately, survive reopening and remain unchanged on errors',
    () async {
      final db = FakeFirebaseFirestore(),
          auth = MockFirebaseAuth(
            mockUser: MockUser(uid: 'alice'),
            signedIn: true,
          );
      final repo = UserRepository(
        firestore: db,
        auth: auth,
        storage: MockFirebaseStorage(),
      );
      await db.doc('users/alice').set({
        'id': 'alice',
        'username': 'alice',
        'username_lower': 'alice',
        'name': 'Alice',
        'bio': 'Hello',
        'photoUrl': 'https://fixture.invalid/avatar.jpg',
      });
      await db.doc('usernames/alice').set({'uid': 'alice'});
      for (final color in ProfileCoverColor.values) {
        final changed = repo
            .watchUserModel('alice')
            .firstWhere((u) => u?.coverColor == color);
        await repo.saveProfile(username: 'alice', coverColor: color.name);
        await changed;
        final reopened = UserRepository(
          firestore: db,
          auth: auth,
          storage: MockFirebaseStorage(),
        );
        final result = (await reopened.getUserModel('alice'))!;
        expect(result.coverColor, color);
        expect(result.bio, 'Hello');
        expect(result.name, 'Alice');
        expect(result.photoUrl, 'https://fixture.invalid/avatar.jpg');
      }
      await repo.saveProfile(username: 'alice', name: 'Still Alice');
      expect(
        (await repo.getUserModel('alice'))!.coverColor,
        ProfileCoverColor.sunset,
      );
      await expectLater(
        repo.saveProfile(username: 'alice', coverColor: '#123456'),
        throwsFormatException,
      );
      await db.doc('usernames/taken').set({'uid': 'bob'});
      await expectLater(
        repo.saveProfile(username: 'taken', coverColor: 'sage'),
        throwsFormatException,
      );
      expect(
        (await repo.getUserModel('alice'))!.coverColor,
        ProfileCoverColor.sunset,
      );
      await auth.signOut();
      await expectLater(
        repo.saveProfile(username: 'alice', coverColor: 'sage'),
        throwsStateError,
      );
    },
  );

  test(
    'new profiles accept a cover and username changes/sign-in preserve it',
    () async {
      final db = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'fresh'),
        signedIn: true,
      );
      final repo = UserRepository(
        firestore: db,
        auth: auth,
        storage: MockFirebaseStorage(),
      );
      await repo.saveProfile(
        username: 'fresh',
        name: 'Fresh',
        coverColor: 'rose',
      );
      final created = (await db.doc('users/fresh').get()).data()!;
      expect(created['id'], 'fresh');
      expect(created['createdAt'], isA<Timestamp>());
      expect((await db.doc('usernames/fresh').get()).data()!['uid'], 'fresh');
      await repo.updateUsername('fresh', 'freshname');
      await repo.upsertUser(auth.currentUser!, name: 'Provider name');
      final result = (await repo.getUserModel('fresh'))!;
      expect(result.coverColor, ProfileCoverColor.rose);
      expect(result.name, 'Fresh');
      expect(result.username, 'freshname');
      expect((await db.doc('usernames/fresh').get()).exists, false);
      expect(
        (await db.doc('usernames/freshname').get()).data()!['uid'],
        'fresh',
      );
    },
  );

  Future<ProfileChanges> open(
    WidgetTester tester, {
    double width = 390,
    double scale = 1,
    bool other = false,
  }) async {
    final repo = ProfileChanges()
      ..current = profile(coverColor: ProfileCoverColor.ocean);
    final social = MemorySocial();
    addTearDown(repo.updates.close);
    addTearDown(social.changed.close);
    await mount(
      tester,
      ProfileScreen(
        isGuest: false,
        userId: other ? 'other' : null,
        repository: repo,
        postRepository: ProfilePosts(),
        socialRepository: social,
      ),
      size: Size(width, 900),
      scale: scale,
    );
    return repo;
  }

  testWidgets(
    'cover previews locally, cancellation preserves original, failed saves can retry and success updates the open profile',
    (tester) async {
      final repo = await open(tester);
      expect(coverColor(tester), ProfileCoverColor.ocean.color);
      final background = tester.getRect(
        find.byKey(const ValueKey('profile_cover_background')),
      );
      final avatar = tester.getRect(
        find.byKey(const ValueKey('profile_photo')),
      );
      expect(avatar.center.dy, closeTo(background.bottom, .1));
      await tester.tap(find.byTooltip('Edit Profile'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cover color'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ChoiceChip>(find.byKey(const ValueKey('cover_color_ocean')))
            .selected,
        true,
      );
      await tester.tap(find.byKey(const ValueKey('cover_color_rose')));
      await tester.pumpAndSettle();
      expect(coverColor(tester), ProfileCoverColor.rose.color);
      expect(repo.current.coverColor, ProfileCoverColor.ocean);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(coverColor(tester), ProfileCoverColor.ocean.color);
      await tester.tap(find.byTooltip('Edit Profile'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cover color'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('cover_color_sage')));
      await tester.pumpAndSettle();
      repo.failSave = true;
      await tester.tap(find.byKey(const ValueKey('profile_save')));
      await tester.pumpAndSettle();
      expect(find.byType(EditProfileScreen), findsOneWidget);
      expect(coverColor(tester), ProfileCoverColor.sage.color);
      expect(repo.current.coverColor, ProfileCoverColor.ocean);
      repo.failSave = false;
      await tester.tap(find.byKey(const ValueKey('profile_save')));
      await tester.pumpAndSettle();
      expect(find.byType(EditProfileScreen), findsNothing);
      expect(coverColor(tester), ProfileCoverColor.sage.color);
      expect(repo.watches, 1);
    },
  );

  for (final width in [320.0, 390.0, 768.0]) {
    testWidgets(
      'cover and color picker fit $width at large text size, and dismissal does not change color',
      (tester) async {
        await open(tester, width: width, scale: 2);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('Edit Profile'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Cover color'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cover color'));
        await tester.pumpAndSettle();
        for (final tone in ProfileCoverColor.values) {
          expect(
            find.byKey(ValueKey('cover_color_${tone.name}')),
            findsOneWidget,
          );
        }
        expect(tester.takeException(), isNull);
        Navigator.of(
          tester.element(find.byKey(const ValueKey('cover_color_sage'))),
        ).pop();
        await tester.pumpAndSettle();
        expect(coverColor(tester), ProfileCoverColor.ocean.color);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'other profiles show their chosen cover and receive live color updates',
    (tester) async {
      final repo = await open(tester, other: true);
      expect(find.byTooltip('Edit Profile'), findsNothing);
      expect(coverColor(tester), ProfileCoverColor.ocean.color);
      repo.publish(profile(coverColor: ProfileCoverColor.rose));
      await tester.pumpAndSettle();
      expect(coverColor(tester), ProfileCoverColor.rose.color);
    },
  );
  testWidgets('color picker is disabled while saving', (tester) async {
    final gate = Completer<void>();
    final repo = ProfileMemory()..saveGate = gate.future;
    await entry.profile(tester, repo);
    await tester.tap(find.byKey(const ValueKey('profile_save')));
    await tester.pump();
    expect(
      tester
          .widget<TextButton>(
            find.ancestor(
              of: find.text('Cover color'),
              matching: find.byWidgetPredicate(
                (widget) => widget is TextButton,
              ),
            ),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(
            find.ancestor(
              of: find.text('Change photo'),
              matching: find.byWidgetPredicate(
                (widget) => widget is TextButton,
              ),
            ),
          )
          .onPressed,
      isNull,
    );
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Saved profile'), findsOneWidget);
  });
  testWidgets(
    'failed profile load cannot expose controls that replace a saved cover',
    (tester) async {
      final repo = ProfileMemory()..failLoad = true;
      await mount(
        tester,
        EditProfileScreen(repository: repo, userId: 'viewer'),
      );
      expect(find.text('Cover color'), findsNothing);
      expect(find.text('Retry'), findsOneWidget);
    },
  );
}
