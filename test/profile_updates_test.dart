import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mooddare/features/feed/data/repositories/post_repository.dart';
import 'package:mooddare/features/profile/presentation/screens/edit_profile_screen.dart';
import 'package:mooddare/features/profile/presentation/screens/profile_screen.dart';
import 'package:mooddare/features/user/data/repositories/user_repository.dart';
import 'package:mooddare/models/post_model.dart';
import 'package:mooddare/models/user_model.dart';

import 'entry_polish_test.dart' show mount;
import 'support/fixture_images.dart';

UserModel profile({
  String? photo,
  String name = 'Before',
  String bio = 'Old bio',
  String username = 'before',
}) => UserModel(
  id: 'viewer',
  name: name,
  username: username,
  bio: bio,
  photoUrl: photo,
  createdAt: Timestamp.fromMillisecondsSinceEpoch(0),
);

class ProfileChanges implements UserRepository {
  UserModel current = profile();
  final updates = StreamController<UserModel?>.broadcast();
  int watches = 0;
  bool failSave = false;
  @override
  String get currentUserId => 'viewer';
  @override
  Future<UserModel?> getUserModel(String uid) async => current;
  @override
  Stream<UserModel?> watchUserModel(String uid) async* {
    watches++;
    yield current;
    yield* updates.stream;
  }

  void publish(UserModel value) {
    current = value;
    updates.add(value);
  }

  @override
  Future<void> saveProfile({
    required String username,
    String? name,
    String? bio,
    File? imageFile,
  }) async {
    if (failSave) {
      throw const FormatException('That username is already taken.');
    }
    publish(profile(username: username, name: name!, bio: bio!));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ProfilePosts implements PostRepository {
  int statsReads = 0;
  @override
  Future<Map<String, int>> getUserStats(String uid) async {
    statsReads++;
    return {'daresCompleted': 2, 'totalLikes': 3};
  }

  @override
  Stream<List<PostModel>> getUserPosts(String uid) => Stream.value([]);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late ProfileChanges repo;
  late ProfilePosts posts;
  setUp(() {
    repo = ProfileChanges();
    posts = ProfilePosts();
  });
  tearDown(() => repo.updates.close());
  Future<void> open(WidgetTester tester) => mount(
    tester,
    ProfileScreen(isGuest: false, repository: repo, postRepository: posts),
    size: const Size(390, 844),
  );

  testWidgets(
    'Save returns to the same profile with updated name, username and bio',
    (tester) async {
      await open(tester);
      expect(find.text('@before'), findsOneWidget);
      await tester.tap(find.byTooltip('Edit Profile'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Display name'),
        'After',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Username'),
        'after',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'A little about you'),
        'New bio',
      );
      repo.failSave = true;
      await tester.tap(find.byKey(const ValueKey('profile_save')));
      await tester.pumpAndSettle();
      expect(find.byType(EditProfileScreen), findsOneWidget);
      expect(repo.current.username, 'before');
      repo.failSave = false;
      await tester.tap(find.byKey(const ValueKey('profile_save')));
      await tester.pumpAndSettle();
      expect(find.byType(EditProfileScreen), findsNothing);
      expect(find.text('After'), findsOneWidget);
      expect(find.text('@after'), findsOneWidget);
      expect(find.text('New bio'), findsOneWidget);
      expect(find.text('@before'), findsNothing);
      expect(repo.watches, 1);
      expect(posts.statsReads, 1);
    },
  );

  testWidgets(
    'live updates appear without reopening and stream errors can retry',
    (tester) async {
      await open(tester);
      repo.publish(
        profile(name: 'Changed elsewhere', username: 'newname', bio: ''),
      );
      await tester.pumpAndSettle();
      expect(find.text('Changed elsewhere'), findsOneWidget);
      expect(find.text('@newname'), findsOneWidget);
      expect(find.text('Old bio'), findsNothing);
      repo.updates.addError(StateError('Offline'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Could not load your profile. Tap to retry.'));
      await tester.pumpAndSettle();
      expect(find.text('@newname'), findsOneWidget);
      expect(repo.watches, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'profile avatar replaces the previously cached photo on a live update',
    (tester) async {
      const first = 'https://fixture.invalid/first-avatar.jpg';
      const next = 'https://fixture.invalid/new-avatar.jpg';
      final previous = debugNetworkImageHttpClientProvider;
      debugNetworkImageHttpClientProvider = () => FixtureImages(
        Uint8List.fromList(img.encodePng(img.Image(width: 30, height: 30))),
      );
      addTearDown(() {
        debugNetworkImageHttpClientProvider = previous;
        PaintingBinding.instance.imageCache.clear();
      });
      for (final url in [first, next]) {
        await tester.runAsync(() async {
          final loaded = Completer<void>();
          final stream = NetworkImage(url).resolve(ImageConfiguration.empty);
          final listener = ImageStreamListener(
            (_, _) => loaded.complete(),
            onError: (Object e, StackTrace? s) => loaded.completeError(e, s),
          );
          stream.addListener(listener);
          await loaded.future;
          stream.removeListener(listener);
        });
      }
      debugNetworkImageHttpClientProvider = previous;
      repo.current = profile(photo: first);
      await open(tester);
      expect(
        (tester.widget<CircleAvatar>(find.byType(CircleAvatar)).backgroundImage
                as NetworkImage)
            .url,
        first,
      );
      repo.publish(profile(photo: next));
      await tester.pumpAndSettle();
      expect(
        (tester.widget<CircleAvatar>(find.byType(CircleAvatar)).backgroundImage
                as NetworkImage)
            .url,
        next,
      );
      repo.publish(profile());
      await tester.pumpAndSettle();
      expect(
        tester.widget<CircleAvatar>(find.byType(CircleAvatar)).backgroundImage,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
