import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:mooddare/features/camera/domain/beauty_lens.dart';
import 'face_fixture.dart';
import 'live_beauty_test.dart' show channel, waitForState, capture, difference;
import 'live_video_test.dart' show allowCameraAndAudio, checkTracks;
import 'photo_makeup_regression_test.dart' show detectedStill;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('curated looks match stills and video, compare and reset', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await allowCameraAndAudio();
    final cache = (await getTemporaryDirectory()).path;
    final fixture = File('$cache/collection-fixture.jpg');
    await fixture.writeAsBytes(base64Decode(faceFixtureBase64));
    final files = <File>[fixture];
    try {
      final session = (await channel.invokeMapMethod<String, dynamic>(
        'startFixture',
        {'path': fixture.path, 'front': true},
      ))!;
      await tester.pumpWidget(
        MaterialApp(
          home: Texture(textureId: (session['textureId'] as num).toInt()),
        ),
      );
      await waitForState(tester, (s) => s['geometryDetected'] == true);
      await channel.invokeMethod<void>(
        'setLook',
        BeautyLens.all.first.settings(0),
      );
      final original = await capture();
      final originalStill = await detectedStill();
      final rendered = <img.Image>[];
      for (final lens in BeautyLens.collection) {
        await channel.invokeMethod<void>('setLook', lens.settings(.65));
        final preview = await capture();
        expect(
          difference(original, preview),
          greaterThan(.2),
          reason: lens.name,
        );
        for (final previous in rendered) {
          expect(
            difference(previous, preview),
            greaterThan(.2),
            reason: 'Looks must be visibly distinct',
          );
        }
        rendered.add(preview);
        final stillFile = File(
          (await channel.invokeMethod<String>('captureStillFixture'))!,
        );
        files.add(stillFile);
        expect(
          difference(preview, img.decodeJpg(await stillFile.readAsBytes())!),
          lessThan(.5),
        );
        expect(
          difference(originalStill, await detectedStill()),
          greaterThan(.2),
        );
        await channel.invokeMethod<void>('startRecording');
        await tester.pump(const Duration(seconds: 2));
        final video = File(
          (await channel.invokeMethod<String>('stopRecording'))!,
        );
        files.add(video);
        await checkTracks(video);
        final frame = img.decodeImage(
          (await VideoThumbnail.thumbnailData(
            video: video.path,
            imageFormat: ImageFormat.PNG,
            timeMs: 500,
          ))!,
        )!;
        final resized = img.copyResize(
          frame,
          width: preview.width,
          height: preview.height,
        );
        final expectedError = difference(preview, resized);
        final originalError = difference(original, resized);
        debugPrint(
          '${lens.name} video error=$expectedError, original=$originalError',
        );
        expect(expectedError, lessThan(6));
        expect(expectedError, lessThan(originalError));
        await channel.invokeMethod<void>(
          'setLook',
          lens.settings(.65, original: true),
        );
        expect(difference(original, await capture()), lessThan(.1));
        await channel.invokeMethod<void>('setLook', lens.settings(0));
        expect(difference(original, await capture()), lessThan(.1));
      }
      // Ensure returning to a pre-existing neutral lens clears all makeup/tone.
      await channel.invokeMethod<void>(
        'setLook',
        BeautyLens.all.first.settings(1),
      );
      expect(difference(original, await capture()), lessThan(.1));
    } finally {
      await channel.invokeMethod<void>('stop');
      for (final file in files) {
        if (await file.exists()) await file.delete();
      }
    }
  });
}
