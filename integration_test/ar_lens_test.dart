import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
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

// Locate pixels changed substantially by the overlay, independent of the face.
Offset overlayCenter(img.Image original, img.Image overlay) {
  var xTotal = 0.0, yTotal = 0.0, count = 0;
  for (var y = 0; y < original.height; y++) {
    for (var x = 0; x < original.width; x++) {
      final a = original.getPixel(x, y), b = overlay.getPixel(x, y);
      if ((a.r - b.r).abs() + (a.g - b.g).abs() + (a.b - b.b).abs() > 100) {
        xTotal += x;
        yTotal += y;
        count++;
      }
    }
  }
  expect(count, greaterThan(150), reason: 'Hearts must occupy visible pixels');
  return Offset(
    xTotal / count / original.width,
    yTotal / count / original.height,
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Heart Halo animates, tracks, mirrors and exports into photos/video',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await allowCameraAndAudio();
      final fixture = File(
        '${(await getTemporaryDirectory()).path}/ar-portrait.jpg',
      );
      await fixture.writeAsBytes(base64Decode(faceFixtureBase64));
      final files = <File>[fixture];
      final lens = BeautyLens.all.firstWhere((l) => l.heartHalo);
      img.Image? back;
      try {
        for (final front in [false, true]) {
          final session = (await channel.invokeMapMethod<String, dynamic>(
            'startFixture',
            {'path': fixture.path, 'front': front},
          ))!;
          await tester.pumpWidget(
            MaterialApp(
              home: Texture(textureId: (session['textureId'] as num).toInt()),
            ),
          );
          await waitForState(tester, (s) => s['geometryDetected'] == true);
          final geometry = (await channel.invokeMapMethod<String, dynamic>(
            'inspectFaceGeometry',
          ))!;
          files.add(File(geometry['path'] as String));
          final polygons = (geometry['polygons'] as List)
              .map(
                (p) => (p as List).map((v) => (v as num).toDouble()).toList(),
              )
              .toList();
          await channel.invokeMethod<void>(
            'setLook',
            BeautyLens.all.first.settings(1),
          );
          final original = await capture();
          final originalStill = await detectedStill();
          await channel.invokeMethod<void>('setLook', {
            ...lens.settings(1),
            'fixtureAnimationSeconds': 0.0,
          });
          final halo = await capture();
          expect(difference(original, halo), greaterThan(.15));
          final center = overlayCenter(original, halo);
          if (!front) {
            back = halo;
          } else {
            expect(difference(img.flipHorizontal(back!), halo), lessThan(.7));
          }
          final still = File(
            (await channel.invokeMethod<String>('captureStillFixture'))!,
          );
          files.add(still);
          expect(
            difference(halo, img.decodeJpg(await still.readAsBytes())!),
            lessThan(.5),
          );
          expect(
            difference(originalStill, await detectedStill()),
            greaterThan(.15),
            reason: 'AR-only photos must run fresh mesh detection',
          );
          // Translate the tracked geometry while leaving the background fixed.
          final moved = polygons
              .map(
                (p) => [
                  for (var i = 0; i < p.length; i++)
                    p[i] + (i.isEven ? .08 : .04),
                ],
              )
              .toList();
          await channel.invokeMethod<void>('setGeometryFixture', {
            'polygons': moved,
          });
          final shifted = overlayCenter(original, await capture());
          expect(shifted.dx - center.dx, closeTo(front ? -.08 : .08, .025));
          expect(shifted.dy - center.dy, closeTo(.04, .025));
          final aspect = original.width / original.height;
          Offset rotate(double x, double y) {
            final px = (x - .5) * aspect, py = y - .5;
            return Offset(
              .5 + (px * math.cos(.15) - py * math.sin(.15)) / aspect,
              .5 + px * math.sin(.15) + py * math.cos(.15),
            );
          }

          final tilted = polygons
              .map(
                (p) => [
                  for (var i = 0; i < p.length; i += 2) ...[
                    rotate(p[i], p[i + 1]).dx,
                    rotate(p[i], p[i + 1]).dy,
                  ],
                ],
              )
              .toList();
          await channel.invokeMethod<void>('setGeometryFixture', {
            'polygons': tilted,
          });
          final rotated = overlayCenter(original, await capture());
          final target = rotate(front ? 1 - center.dx : center.dx, center.dy);
          expect(rotated.dx, closeTo(front ? 1 - target.dx : target.dx, .025));
          expect(rotated.dy, closeTo(target.dy, .025));
          await channel.invokeMethod<void>('setGeometryFixture', {
            'polygons': polygons,
          });
          await channel.invokeMethod<void>('setLook', {
            ...lens.settings(1),
            'fixtureAnimationSeconds': 3.0,
          });
          expect(
            difference(halo, await capture()),
            greaterThan(.1),
            reason: 'The hearts bob over time',
          );
          await channel.invokeMethod<void>('setLook', {
            ...lens.settings(1),
            'fixtureAnimationSeconds': 0.0,
          });
          if (front) {
            const artifact = String.fromEnvironment('AR_ARTIFACT');
            if (artifact.isNotEmpty) {
              await File(
                '${fixture.parent.path}/ar-review.png',
              ).writeAsBytes(img.encodePng(halo));
            }
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
              width: halo.width,
              height: halo.height,
            );
            final error = difference(
              halo,
              resized,
              bottom: (halo.height * .55).round(),
            );
            final noEffectError = difference(
              original,
              resized,
              bottom: (halo.height * .55).round(),
            );
            debugPrint(
              'Heart Halo video error=$error, original=$noEffectError',
            );
            expect(error, lessThan(noEffectError));
            // Unfreeze time to verify the animation reaches the encoded frames.
            await channel.invokeMethod<void>('setLook', lens.settings(1));
            await channel.invokeMethod<void>('startRecording');
            await tester.pump(const Duration(seconds: 3));
            final animated = File(
              (await channel.invokeMethod<String>('stopRecording'))!,
            );
            files.add(animated);
            Future<img.Image> frameAt(int ms) async => img.decodeImage(
              (await VideoThumbnail.thumbnailData(
                video: animated.path,
                imageFormat: ImageFormat.PNG,
                timeMs: ms,
              ))!,
            )!;
            expect(
              difference(await frameAt(300), await frameAt(1800)),
              greaterThan(.03),
            );
          }
          for (final off in [
            lens.settings(0),
            lens.settings(1, original: true),
            const CustomBeautyLook().settings(),
          ]) {
            await channel.invokeMethod<void>('setLook', off);
            expect(difference(original, await capture()), lessThan(.1));
          }
          await channel.invokeMethod<void>('setLook', lens.settings(1));
          await channel.invokeMethod<void>('setGeometryFixture', {});
          expect(
            difference(original, await capture()),
            lessThan(.1),
            reason: 'Lost mesh cannot leave floating hearts behind',
          );
          await channel.invokeMethod<void>('stop');
        }
        // Exercise the fresh high-resolution exposure path and both saved ratios.
        await fixture.writeAsBytes(
          img.encodeJpg(
            img.copyResize(
              img.decodeJpg(base64Decode(faceFixtureBase64))!,
              height: 2048,
            ),
          ),
        );
        await channel.invokeMethod<void>('startFixture', {
          'path': fixture.path,
          'front': true,
        });
        await waitForState(tester, (s) => s['geometryDetected'] == true);
        for (final ratio in [9 / 16, 3 / 4]) {
          await channel.invokeMethod<void>('setLook', {
            ...BeautyLens.all.first.settings(0),
            'aspectRatio': ratio,
          });
          final plain = await detectedStill();
          await channel.invokeMethod<void>('setLook', {
            ...lens.settings(1),
            'fixtureAnimationSeconds': 0.0,
            'aspectRatio': ratio,
          });
          final photo = await detectedStill();
          expect(photo.height, 2048);
          expect(photo.width / photo.height, closeTo(ratio, .005));
          expect(difference(plain, photo), greaterThan(.15));
          final status = (await channel.invokeMapMethod<String, dynamic>(
            'status',
          ))!;
          expect((status['photoDetection'] as Map)['matched'], isTrue);
        }
      } finally {
        await channel.invokeMethod<void>('stop');
        for (final f in files) {
          if (await f.exists()) await f.delete();
        }
      }
    },
  );
}
