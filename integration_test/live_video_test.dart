import 'dart:convert';
import 'dart:io';
import 'package:camera/camera.dart' hide ImageFormat;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:mooddare/core/app_theme.dart';
import 'package:mooddare/features/camera/domain/beauty_lens.dart';
import 'package:mooddare/features/camera/presentation/live_beauty_screen.dart';
import 'face_fixture.dart';
import 'live_beauty_test.dart' show channel, waitForState, capture, difference;

Future<void> allowCameraAndAudio() async {
  final camera = CameraController(
    (await availableCameras()).first,
    ResolutionPreset.low,
    enableAudio: true,
  );
  await camera.initialize();
  await camera.dispose();
}

Future<void> checkTracks(File file, {double minimumSeconds = 1}) async {
  final tracks = (await channel.invokeListMethod<dynamic>('inspectVideo', {
    'path': file.path,
  }))!;
  final video = tracks.singleWhere((track) => track['mime'] == 'video/avc');
  final audio = tracks.singleWhere(
    (track) => track['mime'] == 'audio/mp4a-latm',
  );
  final videoSeconds = (video['durationUs'] as num) / 1000000;
  final audioSeconds = (audio['durationUs'] as num) / 1000000;
  debugPrint('Recorded video: ${videoSeconds}s, audio: ${audioSeconds}s');
  expect(videoSeconds, greaterThan(minimumSeconds));
  expect(audioSeconds, greaterThan(minimumSeconds));
  expect((videoSeconds - audioSeconds).abs(), lessThan(.5));
  expect(await file.length(), lessThan(30 * 1024 * 1024));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('live video bakes GPU effects, encodes audio and stops at 30s', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await allowCameraAndAudio();
    final fixture = File(
      '${(await getTemporaryDirectory()).path}/video-face.jpg',
    );
    await fixture.writeAsBytes(base64Decode(faceFixtureBase64));
    final clips = <File>[];
    try {
      final session = await channel.invokeMapMethod<String, dynamic>(
        'startFixture',
        {'path': fixture.path, 'front': true},
      );
      // Consume the preview surface just as the live camera screen does.
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: Texture(textureId: (session!['textureId'] as num).toInt()),
          ),
        ),
      );
      await waitForState(tester, (state) => state['faceDetected'] == true);
      await channel.invokeMethod<void>(
        'setLook',
        BeautyLens.all.first.settings(0),
      );
      final original = await capture();
      await channel.invokeMethod<void>(
        'setLook',
        const BeautyLens(
          'Test',
          smooth: 1,
          light: .8,
          warmth: .8,
          eyeSize: 1,
          faceSlim: 1,
        ).settings(1),
      );
      final filtered = await capture();
      await channel.invokeMethod<void>('startRecording');
      await tester.pump(const Duration(seconds: 2));
      // A duplicate start must fail without damaging the recording in progress.
      await expectLater(
        channel.invokeMethod<void>('startRecording'),
        throwsA(isA<PlatformException>()),
      );
      final clip = File((await channel.invokeMethod<String>('stopRecording'))!);
      clips.add(clip);
      await checkTracks(clip);
      final player = VideoPlayerController.file(clip);
      try {
        await player.initialize();
        expect(
          player.value.size.aspectRatio,
          closeTo(filtered.width / filtered.height, .01),
        );
        await player.play();
        await tester.pump(const Duration(milliseconds: 400));
        expect(player.value.hasError, isFalse);
      } finally {
        await player.dispose();
      }
      final bytes = (await VideoThumbnail.thumbnailData(
        video: clip.path,
        imageFormat: ImageFormat.PNG,
        timeMs: 1000,
      ))!;
      final frame = img.decodePng(bytes)!;
      final expected = img.copyResize(
        filtered,
        width: frame.width,
        height: frame.height,
      );
      final unfiltered = img.copyResize(
        original,
        width: frame.width,
        height: frame.height,
      );
      final actualDifference = difference(frame, expected);
      debugPrint('MP4 vs GPU capture pixel difference: $actualDifference');
      expect(
        actualDifference,
        lessThan(12),
        reason:
            'Video must preserve lens pixels, upright orientation and selfie mirroring',
      );
      expect(
        actualDifference,
        lessThan(difference(frame, unfiltered) / 2),
        reason: 'The exported MP4 must contain the applied effect',
      );

      await channel.invokeMethod<void>('startRecording');
      Map<String, dynamic> state = {};
      for (var i = 0; i < 140; i++) {
        await tester.pump(const Duration(milliseconds: 250));
        state = (await channel.invokeMapMethod<String, dynamic>('status'))!;
        if (state['videoReady'] == true) break;
      }
      expect(state['recording'], isFalse);
      expect(state['videoReady'], isTrue);
      final limited = File(
        (await channel.invokeMethod<String>('stopRecording'))!,
      );
      clips.add(limited);
      await checkTracks(limited, minimumSeconds: 28);
      final limitedPlayer = VideoPlayerController.file(limited);
      try {
        await limitedPlayer.initialize();
        expect(
          limitedPlayer.value.duration.inMilliseconds,
          lessThanOrEqualTo(31000),
        );
      } finally {
        await limitedPlayer.dispose();
      }

      await channel.invokeMethod<void>('startRecording');
      await tester.pump(const Duration(seconds: 2));
      await channel.invokeMethod<void>('stop');
      final interrupted = File(
        (await channel.invokeMethod<String>('takePendingVideo'))!,
      );
      clips.add(interrupted);
      await checkTracks(interrupted);
      expect(await channel.invokeMethod<String>('takePendingVideo'), isNull);
    } finally {
      await channel.invokeMethod<void>('stop');
      for (final file in [fixture, ...clips]) {
        if (await file.exists()) await file.delete();
      }
    }
  });

  testWidgets('live video UI records, plays, retakes and recovers on resume', (
    tester,
  ) async {
    await allowCameraAndAudio();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        home: const LiveBeautyScreen(dareText: 'Video test'),
      ),
    );
    await waitForState(tester, (state) => state['ready'] == true);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Video'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byTooltip('Record live video'));
    await waitForState(tester, (state) => state['recording'] == true);
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.byTooltip('Stop live recording'));
    for (
      var i = 0;
      i < 100 && find.byType(VideoPlayer).evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 150));
    }
    expect(find.byType(VideoPlayer), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pageBack();
    await waitForState(tester, (state) => state['ready'] == true);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byTooltip('Record live video'));
    await waitForState(tester, (state) => state['recording'] == true);
    await tester.pump(const Duration(seconds: 2));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    for (
      var i = 0;
      i < 100 && find.byType(VideoPlayer).evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 150));
    }
    expect(find.byType(VideoPlayer), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pageBack();
    await waitForState(tester, (state) => state['ready'] == true);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump(const Duration(seconds: 1));
    await channel.invokeMethod<void>('stop');
  });
}
