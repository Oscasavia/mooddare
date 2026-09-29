import 'dart:convert';
import 'dart:ui' as ui;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mooddare/core/app_theme.dart';
import 'package:mooddare/features/dares/data/repositories/dares_repository.dart';
import 'package:mooddare/features/dares/data/repositories/weekly_dare_repository.dart';
import 'package:mooddare/features/dares/presentation/screens/dares_screen.dart';
import 'package:mooddare/features/feed/presentation/screens/camera_screen.dart';
import 'package:mooddare/features/feed/presentation/screens/preview_screen.dart';
import '../test/weekly_dare_test.dart' show schedule;
import 'live_beauty_test.dart' show waitForState;
import 'live_video_test.dart' show allowCameraAndAudio;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Discover weekly challenge carries its identity through photo and video capture',
    (tester) async {
      await allowCameraAndAudio();
      final db = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'alice'),
        signedIn: true,
      );
      final now = DateTime.now().toUtc(),
          id = WeeklyDare.weekId(DateTime.now());
      await db.doc('weeklyDares/$id').set(schedule(now));
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            theme: AppTheme.build(),
            home: DaresScreen(
              repository: DaresRepository(loadMoods: () async => []),
              weeklyRepository: WeeklyDareRepository(firestore: db, auth: auth),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final image =
          await (boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      // Synthetic fixture only; allows reviewing the screen after the runner removes its app.
      debugPrint(
        'WEEKLY_CARD_SCREENSHOT:${base64Encode(bytes!.buffer.asUint8List())}',
        wrapWidth: 1000000,
      );
      image.dispose();
      await tester.tap(find.text('Join this week'));
      await waitForState(tester, (state) => state['ready'] == true);
      await tester.pump(const Duration(milliseconds: 500));
      final camera = tester.widget<CameraScreen>(find.byType(CameraScreen));
      expect(camera.weeklyDareId, id);
      expect(camera.moodId, 'happy');
      for (final type in ['image', 'video']) {
        if (type == 'image') {
          await tester.tap(find.byKey(const ValueKey('capture_shutter')));
        } else {
          final hold = await tester.startGesture(
            tester.getCenter(find.byKey(const ValueKey('capture_shutter'))),
          );
          await tester.pump(const Duration(milliseconds: 600));
          await tester.pump(const Duration(seconds: 3));
          await hold.up();
        }
        for (
          var i = 0;
          i < 150 && find.byType(PreviewScreen).evaluate().isEmpty;
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(find.byType(PreviewScreen), findsOneWidget);
        final preview = tester.widget<PreviewScreen>(
          find.byType(PreviewScreen),
        );
        expect(preview.weeklyDareId, id);
        expect(preview.mediaType, type);
        expect(preview.dareText, schedule(now)['dareText']);
        expect(preview.moodName, 'Happy');
        expect(await preview.mediaFile.exists(), true);
        Navigator.of(tester.element(find.byType(PreviewScreen))).pop();
        await tester.pump(const Duration(milliseconds: 500));
        await waitForState(tester, (state) => state['ready'] == true);
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect((await db.collection('posts').get()).docs, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
