import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:mooddare/core/app_theme.dart';
import 'package:mooddare/features/camera/presentation/live_beauty_screen.dart';
import 'package:mooddare/features/feed/presentation/screens/camera_screen.dart';
import 'package:mooddare/features/feed/presentation/screens/preview_screen.dart';
import 'live_beauty_test.dart' show channel, waitForState, capture, difference;
import 'live_video_test.dart' show allowCameraAndAudio, checkTracks;
import 'camera_timer_test.dart' show waitForPreview;

Future<void> pinch(WidgetTester tester, double factor) async {
  final center = tester.getCenter(
    find.byKey(const ValueKey('camera_zoom_surface')),
  );
  final a = await tester.startGesture(
    center - const Offset(30, 0),
    pointer: 20,
  );
  final b = await tester.startGesture(
    center + const Offset(30, 0),
    pointer: 21,
  );
  for (var i = 1; i <= 5; i++) {
    await b.moveTo(center + Offset(30 + 60 * (factor - 1) * i / 5, 0));
    await tester.pump(const Duration(milliseconds: 80));
  }
  await a.up();
  await b.up();
  await tester.pump(const Duration(milliseconds: 800));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native camera zoom changes saved photos, works during held/locked video, and resets on switch',
    (tester) async {
      await allowCameraAndAudio();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(),
          home: const LiveBeautyScreen(dareText: 'Zoom acceptance'),
        ),
      );
      await waitForState(tester, (s) => s['ready'] == true);
      await tester.pump(const Duration(milliseconds: 500));
      final state = await waitForState(
        tester,
        (s) => s['ready'] == true && s['front'] == true,
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect((state['maxZoom'] as num).toDouble(), greaterThanOrEqualTo(2));
      final original = await capture();
      await pinch(tester, 2);
      await waitForState(
        tester,
        (s) => ((s['zoom'] as num).toDouble() - 2).abs() < .02,
      );
      final zoomed = await capture();
      expect(zoomed.width, original.width);
      expect(zoomed.height, original.height);
      expect(
        difference(original, zoomed),
        greaterThan(1),
        reason:
            'Zoom must reach the saved pixels, not just scale the preview widget',
      );
      final shutter = find.byKey(const ValueKey('capture_shutter'));
      final finger = await tester.startGesture(
        tester.getCenter(shutter),
        pointer: 1,
      );
      await tester.pump(const Duration(milliseconds: 700));
      await waitForState(tester, (s) => s['recording'] == true);
      await pinch(tester, .75);
      await waitForState(
        tester,
        (s) =>
            s['recording'] == true &&
            ((s['zoom'] as num).toDouble() - 1.5).abs() < .03,
      );
      await finger.moveBy(const Offset(0, -110));
      await tester.pump();
      await finger.up();
      await tester.pump(const Duration(milliseconds: 250));
      await pinch(tester, 1.5);
      await waitForState(
        tester,
        (s) =>
            s['recording'] == true &&
            ((s['zoom'] as num).toDouble() - 2.25).abs() < .04,
      );
      await tester.tap(shutter);
      await waitForPreview(tester);
      final preview = tester.widget<PreviewScreen>(find.byType(PreviewScreen));
      expect(preview.mediaType, 'video');
      await checkTracks(preview.mediaFile);
      await tester.pageBack();
      await waitForState(tester, (s) => s['ready'] == true);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.byTooltip('Switch camera'));
      await waitForState(
        tester,
        (s) => s['ready'] == true && s['front'] == false && s['zoom'] == 1.0,
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(shutter);
      await waitForPreview(tester);
      expect(
        tester.widget<PreviewScreen>(find.byType(PreviewScreen)).mediaType,
        'image',
      );
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'native zoom rejects stale sessions and invalid input and clamps to camera limits',
    (tester) async {
      final start = (await channel.invokeMapMethod<String, dynamic>('start', {
        'front': false,
      }))!;
      try {
        await waitForState(tester, (s) => s['ready'] == true);
        final texture = start['textureId'];
        for (final ratio in [double.nan, double.infinity]) {
          await expectLater(
            channel.invokeMethod<double>('setZoom', {
              'ratio': ratio,
              'textureId': texture,
            }),
            throwsA(isA<PlatformException>()),
          );
        }
        await expectLater(
          channel.invokeMethod<double>('setZoom', {
            'ratio': 2.0,
            'textureId': -1,
          }),
          throwsA(isA<PlatformException>()),
        );
        expect(
          await channel.invokeMethod<double>('setZoom', {
            'ratio': 100000.0,
            'textureId': texture,
          }),
          start['maxZoom'],
        );
        expect(
          await channel.invokeMethod<double>('setZoom', {
            'ratio': 0.0,
            'textureId': texture,
          }),
          start['minZoom'],
        );
      } finally {
        await channel.invokeMethod<void>('stop');
      }
    },
  );

  testWidgets('fallback camera pinch preserves photos and recording', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        home: const BasicCameraScreen(dareText: 'Fallback zoom'),
      ),
    );
    Future<void> ready() async {
      for (var i = 0; i < 80; i++) {
        await tester.pump(const Duration(milliseconds: 250));
        if (find
            .byKey(const ValueKey('camera_zoom_surface'))
            .evaluate()
            .isNotEmpty) {
          return;
        }
      }
      fail('Fallback camera did not initialize');
    }

    await ready();
    await pinch(tester, 2);
    expect(find.text('2.0×'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Take photo'));
    await waitForPreview(tester);
    final photo = tester.widget<PreviewScreen>(find.byType(PreviewScreen));
    expect(
      img.decodeImage(await File(photo.mediaFile.path).readAsBytes()),
      isNotNull,
    );
    await tester.pageBack();
    await ready();
    await tester.tap(find.text('Video'));
    await tester.pump();
    await ready();
    await tester.tap(find.bySemanticsLabel('Record video'));
    await tester.pump(const Duration(seconds: 2));
    await pinch(tester, 2);
    expect(find.text('2.0×'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Stop recording'));
    await waitForPreview(tester);
    final video = tester.widget<PreviewScreen>(find.byType(PreviewScreen));
    expect(video.mediaType, 'video');
    final tracks = (await channel.invokeListMethod<dynamic>('inspectVideo', {
      'path': video.mediaFile.path,
    }))!;
    expect(
      tracks.any((t) => (t['mime'] as String).startsWith('video/')),
      isTrue,
    );
    expect(
      tracks.any((t) => (t['mime'] as String).startsWith('audio/')),
      isTrue,
    );
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });
}
