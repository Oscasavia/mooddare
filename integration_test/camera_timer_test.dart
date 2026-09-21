import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mooddare/core/app_theme.dart';
import 'package:mooddare/features/camera/presentation/live_beauty_screen.dart';
import 'package:mooddare/features/feed/presentation/screens/camera_screen.dart';
import 'package:mooddare/features/feed/presentation/screens/preview_screen.dart';
import 'live_beauty_test.dart' show channel, waitForState;
import 'live_video_test.dart' show allowCameraAndAudio, checkTracks;

Future<void> selectTimer(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('camera_timer')));
  await tester.pumpAndSettle();
  await tester.tap(
    find.ancestor(
      of: find.text('3 seconds'),
      matching: find.byType(CheckedPopupMenuItem<int>),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> waitForPreview(WidgetTester tester) async {
  for (
    var i = 0;
    i < 80 && find.byType(PreviewScreen).evaluate().isEmpty;
    i++
  ) {
    await tester.pump(const Duration(milliseconds: 250));
  }
  expect(find.byType(PreviewScreen), findsOneWidget);
  expect(tester.takeException(), isNull);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'live camera timer cancels a photo, then captures a photo and hands-free video',
    (tester) async {
      await allowCameraAndAudio();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(),
          home: const LiveBeautyScreen(dareText: 'Timer acceptance'),
        ),
      );
      await waitForState(tester, (s) => s['ready'] == true);
      await tester.pump(const Duration(milliseconds: 500));
      await selectTimer(tester);
      final shutter = find.byKey(const ValueKey('capture_shutter'));
      await tester.tap(shutter);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('Cancel timer'));
      await tester.pump(const Duration(seconds: 4));
      expect(find.byType(PreviewScreen), findsNothing);
      expect(find.byKey(const ValueKey('capture_countdown')), findsNothing);
      await tester.tap(shutter);
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const ValueKey('capture_countdown')), findsOneWidget);
      expect(find.byType(PreviewScreen), findsNothing);
      await waitForPreview(tester);
      expect(
        tester.widget<PreviewScreen>(find.byType(PreviewScreen)).mediaType,
        'image',
      );
      await tester.pageBack();
      await tester.pump(const Duration(seconds: 2));
      await waitForState(tester, (s) => s['ready'] == true);
      await tester.pump(const Duration(milliseconds: 500));
      final finger = await tester.startGesture(tester.getCenter(shutter));
      await tester.pump(const Duration(milliseconds: 650));
      await finger.up();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const ValueKey('capture_countdown')), findsOneWidget);
      expect(
        (await channel.invokeMapMethod<String, dynamic>(
          'status',
        ))!['recording'],
        isFalse,
      );
      await waitForState(tester, (s) => s['recording'] == true);
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(shutter);
      await waitForPreview(tester);
      final preview = tester.widget<PreviewScreen>(find.byType(PreviewScreen));
      expect(preview.mediaType, 'video');
      await checkTracks(preview.mediaFile);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump(const Duration(seconds: 1));
    },
  );
  testWidgets('fallback camera timer captures only after the countdown', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        home: const BasicCameraScreen(dareText: 'Fallback timer'),
      ),
    );
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 250));
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
    }
    await selectTimer(tester);
    await tester.tap(find.bySemanticsLabel('Take photo'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const ValueKey('capture_countdown')), findsOneWidget);
    expect(find.byType(PreviewScreen), findsNothing);
    await waitForPreview(tester);
    expect(
      tester.widget<PreviewScreen>(find.byType(PreviewScreen)).mediaType,
      'image',
    );
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump(const Duration(seconds: 1));
  });
}
