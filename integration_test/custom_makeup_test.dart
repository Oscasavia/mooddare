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
import 'mesh_makeup_test.dart' as mesh show contains;

/// Compare only pixels within the tracked outer lip, excluding the mouth opening.
double lipDifference(
  img.Image a,
  img.Image b,
  List<List<double>> polygons,
  bool front,
) {
  var total = 0.0, count = 0;
  for (var y = 0; y < a.height; y++) {
    for (var x = 0; x < a.width; x++) {
      final u = front ? 1 - (x + .5) / a.width : (x + .5) / a.width;
      final v = (y + .5) / a.height;
      if (!mesh.contains(polygons[5], u, v) ||
          mesh.contains(polygons[6], u, v)) {
        continue;
      }
      final p = a.getPixel(x, y), q = b.getPixel(x, y);
      total += (p.r - q.r).abs() + (p.g - q.g).abs() + (p.b - q.b).abs();
      count += 3;
    }
  }
  expect(count, greaterThan(30));
  return total / count;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('independent makeup shades survive GPU stills and encoded video', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await allowCameraAndAudio();
    final fixture = File(
      '${(await getTemporaryDirectory()).path}/custom-makeup.jpg',
    );
    await fixture.writeAsBytes(base64Decode(faceFixtureBase64));
    final files = <File>[fixture];
    try {
      for (final front in [false, true]) {
        final session = await channel.invokeMapMethod<String, dynamic>(
          'startFixture',
          {'path': fixture.path, 'front': front},
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Texture(textureId: (session!['textureId'] as num).toInt()),
          ),
        );
        await waitForState(tester, (s) => s['geometryDetected'] == true);
        final geometry = (await channel.invokeMapMethod<String, dynamic>(
          'inspectFaceGeometry',
        ))!;
        files.add(File(geometry['path'] as String));
        final polygons = (geometry['polygons'] as List)
            .map((p) => (p as List).map((v) => (v as num).toDouble()).toList())
            .toList();
        await channel.invokeMethod<void>(
          'setLook',
          const CustomBeautyLook().settings(),
        );
        final original = await capture();
        final shades = <img.Image>[];
        for (final shade in LipShade.values) {
          final look = CustomBeautyLook(lips: 1, lipShade: shade);
          await channel.invokeMethod<void>('setLook', look.settings());
          final tinted = await capture();
          expect(
            lipDifference(original, tinted, polygons, front),
            greaterThan(3),
            reason: shade.name,
          );
          for (final previous in shades) {
            expect(
              lipDifference(previous, tinted, polygons, front),
              greaterThan(1),
              reason: 'Each shade must have a distinct lip color',
            );
          }
          shades.add(tinted);
          expect(
            difference(
              original,
              tinted,
              right: original.width ~/ 5,
              bottom: original.height ~/ 5,
            ),
            lessThan(.5),
          );
          final still = File(
            (await channel.invokeMethod<String>('captureStillFixture'))!,
          );
          files.add(still);
          expect(
            difference(tinted, img.decodeJpg(await still.readAsBytes())!),
            lessThan(.5),
          );
          if (front) {
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
              width: tinted.width,
              height: tinted.height,
            );
            final encodedDifference = lipDifference(
              tinted,
              resized,
              polygons,
              front,
            );
            final originalDifference = lipDifference(
              original,
              resized,
              polygons,
              front,
            );
            debugPrint(
              '${shade.label} encoded lip error=$encodedDifference vs original=$originalDifference',
            );
            expect(
              encodedDifference,
              lessThan(originalDifference),
              reason: 'Video must bake ${shade.label}, not the original lips',
            );
          }
          await channel.invokeMethod<void>(
            'setLook',
            look.withAmount(BeautyAdjustment.blush, 1).settings(),
          );
          final both = await capture();
          expect(difference(tinted, both), greaterThan(.02));
          expect(
            lipDifference(tinted, both, polygons, front),
            lessThan(1),
            reason: 'Blush must not recolor lips',
          );
          await channel.invokeMethod<void>(
            'setLook',
            look.settings(original: true),
          );
          expect(difference(original, await capture()), lessThan(.1));
        }
        // A blush-only look must render without lip tint or shaping enabled.
        await channel.invokeMethod<void>(
          'setLook',
          const CustomBeautyLook(blush: 1).settings(),
        );
        final blush = await capture();
        expect(difference(original, blush), greaterThan(.02));
        expect(lipDifference(original, blush, polygons, front), lessThan(1));
        // Legacy presets clear all custom color/intensity values.
        await channel.invokeMethod<void>(
          'setLook',
          BeautyLens.all.first.settings(0),
        );
        expect(difference(original, await capture()), lessThan(.1));
        await channel.invokeMethod<void>('stop');
      }
      final empty = img.Image(width: 240, height: 320);
      for (var y = 0; y < empty.height; y++) {
        for (var x = 0; x < empty.width; x++) {
          empty.setPixelRgb(x, y, x, y % 256, (x * 7 + y * 3) % 256);
        }
      }
      await fixture.writeAsBytes(img.encodeJpg(empty));
      await channel.invokeMethod<void>('startFixture', {
        'path': fixture.path,
        'front': false,
      });
      final state = await waitForState(
        tester,
        (s) => (s['detections'] as num? ?? 0) > 0,
      );
      expect(state['faceDetected'], isFalse);
      await channel.invokeMethod<void>(
        'setLook',
        const CustomBeautyLook().settings(),
      );
      final blank = await capture();
      for (final shade in LipShade.values) {
        await channel.invokeMethod<void>(
          'setLook',
          CustomBeautyLook(lips: 1, blush: 1, lipShade: shade).settings(),
        );
        expect(
          difference(blank, await capture()),
          lessThan(.1),
          reason: 'No face must mean no makeup',
        );
      }
    } finally {
      await channel.invokeMethod<void>('stop');
      for (final file in files) {
        if (await file.exists()) await file.delete();
      }
    }
  });
}
