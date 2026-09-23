import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import '../test/support/fixture_images.dart';
import 'face_fixture.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mooddare/core/app_theme.dart';
import 'package:mooddare/core/navigation.dart';
import 'package:mooddare/features/dares/data/repositories/dare_library_repository.dart';
import 'package:mooddare/features/dares/data/repositories/dares_repository.dart';
import 'package:mooddare/features/dares/presentation/screens/dare_generation_screen.dart';
import 'package:mooddare/features/dares/presentation/screens/dare_library_screen.dart';
import 'package:mooddare/features/feed/presentation/screens/camera_screen.dart';
import 'package:mooddare/features/feed/presentation/screens/preview_screen.dart';
import 'package:mooddare/features/feed/presentation/widgets/dare_proof_card.dart';
import 'package:mooddare/features/profile/data/social_repository.dart';
import '../test/support/moments_fakes.dart';
import 'live_beauty_test.dart' show waitForState;
import 'live_video_test.dart' show allowCameraAndAudio;

final _shotKey = GlobalKey();
Future<void> screenshot(String name) async {
  final image =
      await (_shotKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary)
          .toImage(pixelRatio: 1.5);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  await File(
    '${(await getTemporaryDirectory()).path}/$name.png',
  ).writeAsBytes(data!.buffer.asUint8List());
  image.dispose();
}

Future<void> mountDare(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(
    RepaintBoundary(
      key: _shotKey,
      child: MaterialApp(
        theme: AppTheme.build(),
        navigatorObservers: [appRouteObserver],
        home: child,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'saved and sent dares arrive intact and open the real camera and photo editor',
    (tester) async {
      await allowCameraAndAudio();
      final db = FakeFirebaseFirestore();
      final aliceAuth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'alice'),
        signedIn: true,
      );
      final bobAuth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'bob'),
        signedIn: true,
      );
      final alice = DareLibraryRepository(firestore: db, auth: aliceAuth);
      final bob = DareLibraryRepository(firestore: db, auth: bobAuth);
      final social = SocialRepository(firestore: db, auth: aliceAuth);
      final bobSocial = SocialRepository(firestore: db, auth: bobAuth);
      for (final id in ['alice', 'bob']) {
        await db.doc('users/$id').set({
          'id': id,
          'username': id,
          'createdAt': Timestamp.now(),
        });
      }
      await social.setFollowing('bob', true);
      await bobSocial.setFollowing('alice', true);
      final mood = DaresRepository.starterMoods.first;
      await mountDare(
        tester,
        DareDisplayScreen(
          mood: mood,
          isProofRequired: false,
          library: alice,
          social: social,
        ),
      );
      await screenshot('dare-selected');
      await tester.tap(find.byTooltip('Save dare'));
      await tester.pumpAndSettle();
      final saved = (await alice.saved().first).single.prompt;
      await tester.tap(find.text('Send dare'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'bob');
      await tester.pumpAndSettle();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await screenshot('dare-send');
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      expect(find.text('Sent'), findsOneWidget);
      expect((await bob.inbox().first).single.prompt.toMap(), saved.toMap());
      await mountDare(
        tester,
        Scaffold(
          body: DareLibraryList(
            inbox: true,
            repository: bob,
            social: bobSocial,
            catalog: DaresRepository(loadMoods: () async => []),
          ),
        ),
      );
      expect(find.text('From @alice'), findsOneWidget);
      await screenshot('dare-inbox');
      await tester.tap(find.text('Try it'));
      await waitForState(tester, (s) => s['ready'] == true);
      await tester.pump(const Duration(milliseconds: 500));
      final camera = tester.widget<CameraScreen>(find.byType(CameraScreen));
      expect(camera.dareText, saved.text);
      expect(camera.moodId, mood.id);
      expect(camera.moodName, mood.name);
      await tester.tap(find.byKey(const ValueKey('capture_shutter')));
      for (
        var i = 0;
        i < 150 && find.byType(PreviewScreen).evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final preview = tester.widget<PreviewScreen>(find.byType(PreviewScreen));
      expect(preview.dareText, saved.text);
      expect(preview.moodId, mood.id);
      expect(preview.mediaType, 'image');
      expect(await preview.mediaFile.exists(), isTrue);
      expect(await bob.hasUnread().first, isFalse);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'Try this dare on a moment opens native capture without changing the source post',
    (tester) async {
      await allowCameraAndAudio();
      final previousImages = debugNetworkImageHttpClientProvider;
      debugNetworkImageHttpClientProvider = () =>
          FixtureImages(base64Decode(faceFixtureBase64));
      try {
        final post = moment('retry', moodId: 'happy', moodName: 'Happy');
        final posts = MemoryPosts([post]);
        addTearDown(posts.commentChanges.close);
        await mountDare(
          tester,
          Scaffold(
            body: DareProofCard(
              post: post,
              repository: posts,
              isFullScreen: true,
            ),
          ),
        );
        await tester.tap(find.text('Try this dare'));
        await waitForState(tester, (s) => s['ready'] == true);
        await tester.pump(const Duration(milliseconds: 500));
        final camera = tester.widget<CameraScreen>(find.byType(CameraScreen));
        expect(camera.dareText, post.dareText);
        expect(camera.moodId, post.moodId);
        expect(camera.moodName, post.moodName);
        await tester.tap(find.byTooltip('Close camera'));
        await tester.pumpAndSettle();
        expect(find.byType(DareProofCard), findsOneWidget);
        expect(posts.posts.single.authorId, 'author');
        expect(posts.likes, 0);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      } finally {
        debugNetworkImageHttpClientProvider = previousImages;
      }
    },
  );
}
