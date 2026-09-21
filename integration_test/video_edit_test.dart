import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:image/image.dart' as img;
import 'package:mooddare/features/camera/data/video_editor.dart';
import 'package:mooddare/features/camera/presentation/video_adjustments_panel.dart';
import 'package:mooddare/core/app_theme.dart';
import 'package:mooddare/features/feed/presentation/screens/preview_screen.dart';
import 'face_fixture.dart';
import 'live_beauty_test.dart' show channel, waitForState, difference;
import 'live_video_test.dart' show allowCameraAndAudio;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native trim removes excluded footage and mute removes audio while retaining lens pixels',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await allowCameraAndAudio();
      final directory = await (await getTemporaryDirectory()).createTemp(
        'edit-fixture-',
      );
      final fixture = await File(
        '${directory.path}/face.jpg',
      ).writeAsBytes(base64Decode(faceFixtureBase64));
      File? original;
      VideoEditor? editor;
      try {
        final session = await channel.invokeMapMethod<String, dynamic>(
          'startFixture',
          {'path': fixture.path, 'front': true},
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Texture(textureId: (session!['textureId'] as num).toInt()),
          ),
        );
        await waitForState(tester, (s) => s['ready'] == true);
        await channel.invokeMethod<void>('setLook', {
          'smooth': 0.0,
          'light': 0.0,
          'warmth': 0.0,
          'eyeSize': 0.0,
          'faceSlim': 0.0,
          'makeup': 0.0,
          'aspectRatio': 9 / 16,
        });
        await channel.invokeMethod<void>('startRecording');
        await tester.pump(const Duration(seconds: 1));
        await channel.invokeMethod<void>('setLook', {
          'smooth': 1.0,
          'light': 0.8,
          'warmth': 0.9,
          'eyeSize': 0.0,
          'faceSlim': 0.0,
          'makeup': 1.0,
          'aspectRatio': 9 / 16,
        });
        await tester.pump(const Duration(seconds: 3));
        original = File((await channel.invokeMethod<String>('stopRecording'))!);
        await channel.invokeMethod<void>('stop');
        final player = VideoPlayerController.file(original);
        await player.initialize();
        final duration = player.value.duration.inMilliseconds;
        final size = player.value.size;
        await player.dispose();
        expect(duration, greaterThan(3000));
        editor = VideoEditor(original, duration);
        final thumbnails = editor.thumbnails();
        final frames = await thumbnails;
        expect(frames, hasLength(8));
        for (final bytes in frames) {
          expect(bytes, isNotNull);
          final decoded = img.decodeJpg(bytes!);
          expect(decoded, isNotNull);
          expect(decoded!.height, 96);
        }
        var selection = VideoEdits(startMs: 0, endMs: duration);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.build(),
            home: Scaffold(
              body: Center(
                child: StatefulBuilder(
                  builder: (_, set) => VideoAdjustmentsPanel(
                    edits: selection,
                    durationMs: duration,
                    thumbnails: thumbnails,
                    onChanged: (value) => set(() => selection = value),
                    onDone: () {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(Image), findsNWidgets(8));
        final timeline = tester.getRect(
          find.byKey(const ValueKey('video_trim_timeline')),
        );
        await tester.dragFrom(
          Offset(timeline.left + 24, timeline.center.dy),
          Offset((timeline.width - 48) * .2, 0),
        );
        await tester.pumpAndSettle();
        expect(selection.startMs, greaterThan(0));
        expect(selection.endMs, duration);
        await tester.tap(find.byTooltip('Remove audio'));
        await tester.pumpAndSettle();
        expect(selection.muted, isTrue);
        expect(tester.takeException(), isNull);
        Future<List<dynamic>> tracks(File file) async => (await channel
            .invokeListMethod<dynamic>('inspectVideo', {'path': file.path}))!;
        expect(
          (await tracks(
            original,
          )).where((t) => (t['mime'] as String).startsWith('audio/')),
          hasLength(1),
        );
        final edited = await editor.export(
          const VideoEdits(startMs: 1700, endMs: 2900, muted: true),
        );
        final actualTracks = await tracks(edited);
        expect(
          actualTracks.where((t) => (t['mime'] as String).startsWith('audio/')),
          isEmpty,
        );
        final playback = VideoPlayerController.file(edited);
        await playback.initialize();
        expect(playback.value.duration.inMilliseconds, closeTo(1200, 150));
        expect(playback.value.size, size);
        await playback.play();
        await tester.pump(const Duration(milliseconds: 300));
        expect(playback.value.hasError, false);
        await playback.dispose();
        Future<img.Image> frame(File file, int ms) async => img.decodePng(
          (await VideoThumbnail.thumbnailData(
            video: file.path,
            imageFormat: ImageFormat.PNG,
            timeMs: ms,
          ))!,
        )!;
        final actual = await frame(edited, 100);
        final expected = await frame(original, 2000);
        final excluded = await frame(original, 200);
        expect(difference(actual, expected), lessThan(8));
        expect(
          difference(actual, expected),
          lessThan(difference(actual, excluded)),
        );
        final audible = await editor.export(
          const VideoEdits(startMs: 1700, endMs: 2900),
        );
        expect(
          (await tracks(
            audible,
          )).where((t) => (t['mime'] as String).startsWith('audio/')),
          hasLength(1),
        );
        expect(
          await editor.export(VideoEdits(startMs: 0, endMs: duration)),
          original,
        );
        await expectLater(
          VideoEditor.channel.invokeMethod<void>('export', {
            'input': original.path,
            'output': '${directory.path}/invalid.mp4',
            'startMs': 3000,
            'endMs': 1000,
            'muted': true,
          }),
          throwsA(isA<PlatformException>()),
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.build(),
            home: PreviewScreen(
              mediaFile: original,
              mediaType: 'video',
              dareText: 'Preview seeking test',
            ),
          ),
        );
        for (
          var i = 0;
          i < 40 && find.byType(VideoPlayer).evaluate().isEmpty;
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 250));
        }
        expect(find.byType(VideoPlayer), findsOneWidget);
        await tester.tap(find.byTooltip('Edit video'));
        await tester.pumpAndSettle();
        tester.widget<RangeSlider>(find.byType(RangeSlider)).onChanged!(
          const RangeValues(1000, 3000),
        );
        await tester.pump(const Duration(milliseconds: 300));
        final selected = tester
            .widget<VideoAdjustmentsPanel>(find.byType(VideoAdjustmentsPanel))
            .edits;
        final strip = tester.getRect(
          find.byKey(const ValueKey('video_trim_timeline')),
        );
        await tester.tapAt(strip.center);
        await tester.pump(const Duration(milliseconds: 500));
        final previewController = tester
            .widget<VideoPlayer>(find.byType(VideoPlayer))
            .controller;
        expect(previewController.value.isPlaying, isFalse);
        expect(
          previewController.value.position.inMilliseconds,
          closeTo(duration / 2, 100),
        );
        expect(
          tester
              .widget<VideoAdjustmentsPanel>(find.byType(VideoAdjustmentsPanel))
              .edits
              .sameAs(selected),
          isTrue,
        );
        expect(
          find.byKey(const ValueKey('video_trim_playhead')),
          findsOneWidget,
        );
        await previewController.play();
        await tester.pump(const Duration(milliseconds: 500));
        expect(previewController.value.isPlaying, isTrue);
        expect(previewController.value.hasError, isFalse);
        await tester.pumpWidget(const MaterialApp(home: SizedBox()));
        await tester.pump(const Duration(seconds: 1));
        expect(await original.exists(), true);
      } finally {
        await channel.invokeMethod<void>('stop');
        await editor?.dispose();
        if (original != null && await original.exists()) {
          await original.delete();
        }
        await directory.delete(recursive: true);
      }
    },
  );
}
