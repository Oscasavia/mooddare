import 'package:camera/camera.dart';
import 'package:mooddare/features/feed/presentation/screens/preview_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mooddare/core/app_theme.dart';
import 'package:mooddare/features/camera/presentation/capture_shutter.dart';
import 'package:mooddare/features/dares/data/repositories/dares_repository.dart';
import 'package:mooddare/features/dares/presentation/screens/dares_screen.dart';
import 'package:mooddare/features/dares/presentation/screens/dare_generation_screen.dart';
import 'package:mooddare/features/dares/presentation/widgets/mood_preview.dart';
import 'live_beauty_test.dart' show waitForState;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'offline catalog to seasonal dare, live capture, review and back',
    (tester) async {
      final permissionCamera = CameraController(
        (await availableCameras()).first,
        ResolutionPreset.low,
        enableAudio: false,
      );
      await permissionCamera.initialize();
      await permissionCamera.dispose();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(),
          home: DaresScreen(
            repository: DaresRepository(
              loadMoods: () async => throw StateError('offline test'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Couldn’t refresh. Starter moods are ready.'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField), 'Brave');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('mood_preview-daring-brave')));
      await tester.pumpAndSettle();
      expect(find.byType(MoodPreviewContent), findsOneWidget);
      expect(find.text('Daring · Coming soon'), findsOneWidget);
      expect(find.text('Open camera'), findsNothing);
      await tester.tap(find.text('Back to moods'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      final seasonal = find.byKey(const ValueKey('collection_seasonal'));
      await tester.ensureVisible(seasonal);
      await tester.tap(seasonal);
      await tester.pumpAndSettle();
      final christmas = find.byKey(const ValueKey('mood_season-christmas'));
      await tester.scrollUntilVisible(
        christmas,
        160,
        scrollable: find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(christmas);
      await tester.pumpAndSettle();
      final dare = DaresRepository.seasonalMoods.first.dareList.singleWhere(
        (d) => find.text(d).evaluate().isNotEmpty,
      );
      await tester.tap(find.text('Open camera'));
      await waitForState(
        tester,
        (state) => state['ready'] == true && (state['frames'] as num) > 5,
      );
      expect(find.text(dare), findsOneWidget);
      // Native frames can arrive before the Flutter status poll enables capture.
      for (
        var i = 0;
        i < 30 &&
            !tester.widget<CaptureShutter>(find.byType(CaptureShutter)).enabled;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        tester.widget<CaptureShutter>(find.byType(CaptureShutter)).enabled,
        isTrue,
      );
      await tester.tap(find.byKey(const ValueKey('capture_shutter')));
      final photo = find.byKey(const ValueKey('capture_preview'));
      for (var i = 0; i < 100 && photo.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(photo, findsOneWidget);
      final review = tester.widget<PreviewScreen>(find.byType(PreviewScreen));
      expect(review.moodId, 'season-christmas');
      expect(review.moodName, 'Christmas');
      await tester.pumpAndSettle();
      final bounds = tester.getRect(photo);
      await tester.tap(find.byTooltip('Adjust photo'));
      await tester.pumpAndSettle();
      expect(find.byType(Slider), findsOneWidget);
      expect(tester.getRect(photo), bounds);
      await tester.pageBack();
      await waitForState(
        tester,
        (state) => state['ready'] == true && (state['frames'] as num) > 2,
      );
      await tester.tap(find.byTooltip('Close camera'));
      await tester.pumpAndSettle();
      expect(find.byType(DareDisplayScreen), findsOneWidget);
      expect(find.text(dare), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(tester.widget<ChoiceChip>(seasonal).selected, isTrue);
      expect(christmas, findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump(const Duration(seconds: 1));
    },
  );
}
