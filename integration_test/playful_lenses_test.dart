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
import 'ar_lens_test.dart' show overlayCenter;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'new AR lenses track, react independently and export without leaking into other looks',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await allowCameraAndAudio();
      final cache = (await getTemporaryDirectory()).path;
      final fixture = File('$cache/playful-fixture.jpg');
      await fixture.writeAsBytes(base64Decode(faceFixtureBase64));
      final files = <File>[fixture];
      final back = <String, img.Image>{};
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
          final info = (await channel.invokeMapMethod<String, dynamic>(
            'inspectFaceGeometry',
          ))!;
          files.add(File(info['path'] as String));
          final polygons = (info['polygons'] as List)
              .map(
                (p) => (p as List).map((v) => (v as num).toDouble()).toList(),
              )
              .toList();
          await channel.invokeMethod<void>(
            'setLook',
            BeautyLens.all.first.settings(0),
          );
          final original = await capture();
          final originalStill = await detectedStill();
          for (final lens in BeautyLens.playful) {
            await channel.invokeMethod<void>('setGeometryFixture', {
              'polygons': polygons,
            });
            await channel.invokeMethod<void>('setLook', {
              ...lens.settings(1),
              'fixtureAnimationSeconds': 0.0,
            });
            final rendered = await capture();
            expect(
              difference(original, rendered),
              greaterThan(.12),
              reason: lens.name,
            );
            final center = overlayCenter(original, rendered);
            if (!front) {
              back[lens.id] = rendered;
            } else {
              expect(
                difference(img.flipHorizontal(back[lens.id]!), rendered),
                lessThan(.8),
              );
            }
            final still = File(
              (await channel.invokeMethod<String>('captureStillFixture'))!,
            );
            files.add(still);
            expect(
              difference(rendered, img.decodeJpg(await still.readAsBytes())!),
              lessThan(.5),
            );
            expect(
              difference(originalStill, await detectedStill()),
              greaterThan(.12),
            );
            final moved = polygons
                .map(
                  (p) => [
                    for (var i = 0; i < p.length; i++)
                      p[i] + (i.isEven ? .04 : .03),
                  ],
                )
                .toList();
            await channel.invokeMethod<void>('setGeometryFixture', {
              'polygons': moved,
            });
            final translated = overlayCenter(original, await capture());
            expect(translated.dx - center.dx, closeTo(front ? -.04 : .04, .03));
            expect(translated.dy - center.dy, closeTo(.03, .03));
            // Deliberately open the inner lip contour without moving the head.
            final opened = polygons.map((p) => [...p]).toList();
            final mouth = polygons[6];
            final cx =
                [
                  for (var i = 0; i < mouth.length; i += 2) mouth[i],
                ].reduce((a, b) => a + b) /
                (mouth.length / 2);
            final cy =
                [
                  for (var i = 1; i < mouth.length; i += 2) mouth[i],
                ].reduce((a, b) => a + b) /
                (mouth.length / 2);
            opened[6] = [
              for (var i = 0; i < 32; i++) ...[
                cx + math.cos(i * math.pi / 16) * .045,
                cy + math.sin(i * math.pi / 16) * .05,
              ],
            ];
            await channel.invokeMethod<void>('setGeometryFixture', {
              'polygons': opened,
            });
            final reacting = await capture();
            if (lens.arEffect == ArEffect.moodCompanion) {
              expect(
                difference(rendered, reacting),
                greaterThan(.1),
                reason: 'Mouth opening must change the mascot',
              );
            } else {
              expect(
                difference(rendered, reacting),
                lessThan(.1),
                reason: 'Mouth changes must not affect the other lenses',
              );
            }
            await channel.invokeMethod<void>('setGeometryFixture', {
              'polygons': polygons,
            });
            await channel.invokeMethod<void>('setLook', {
              ...lens.settings(1),
              'fixtureAnimationSeconds': 1.3,
            });
            final later = await capture();
            if (lens.arEffect == ArEffect.purpleShades) {
              expect(difference(rendered, later), lessThan(.1));
            } else {
              expect(difference(rendered, later), greaterThan(.03));
            }
            await channel.invokeMethod<void>('setLook', {
              ...lens.settings(1),
              'fixtureAnimationSeconds': 0.0,
            });
            if (front) {
              const artifact = bool.fromEnvironment('AR_REVIEW');
              if (artifact) {
                await File(
                  '$cache/${lens.id}-review.png',
                ).writeAsBytes(img.encodePng(rendered));
                if (lens.arEffect == ArEffect.moodCompanion) {
                  await File(
                    '$cache/companion-open-review.png',
                  ).writeAsBytes(img.encodePng(reacting));
                }
              }
              await channel.invokeMethod<void>('startRecording');
              await tester.pump(const Duration(seconds: 2));
              final clip = File(
                (await channel.invokeMethod<String>('stopRecording'))!,
              );
              files.add(clip);
              await checkTracks(clip);
              final frame = img.decodeImage(
                (await VideoThumbnail.thumbnailData(
                  video: clip.path,
                  imageFormat: ImageFormat.PNG,
                  timeMs: 500,
                ))!,
              )!;
              final resized = img.copyResize(
                frame,
                width: rendered.width,
                height: rendered.height,
              );
              final error = difference(
                rendered,
                resized,
                bottom: (rendered.height * .55).round(),
              );
              final plainError = difference(
                original,
                resized,
                bottom: (rendered.height * .55).round(),
              );
              debugPrint('${lens.name}: video=$error original=$plainError');
              expect(error, lessThan(plainError));
              if (lens.arEffect != ArEffect.purpleShades) {
                final reacts = lens.arEffect == ArEffect.moodCompanion;
                await channel.invokeMethod<void>('setLook', {
                  ...lens.settings(1),
                  if (reacts) 'fixtureAnimationSeconds': 0.0,
                });
                await channel.invokeMethod<void>('startRecording');
                if (reacts) {
                  await tester.pump(const Duration(seconds: 1));
                  await channel.invokeMethod<void>('setGeometryFixture', {
                    'polygons': opened,
                  });
                  await tester.pump(const Duration(seconds: 2));
                } else {
                  await tester.pump(const Duration(seconds: 3));
                }
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
                  greaterThan(.01),
                );
              }
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
            expect(difference(original, await capture()), lessThan(.1));
          }
          await channel.invokeMethod<void>('stop');
        }
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
          for (final lens in BeautyLens.playful) {
            await channel.invokeMethod<void>('setLook', {
              ...lens.settings(1),
              'aspectRatio': ratio,
              'fixtureAnimationSeconds': 0.0,
            });
            final photo = await detectedStill();
            expect(photo.height, 2048);
            expect(photo.width / photo.height, closeTo(ratio, .005));
            expect(difference(plain, photo), greaterThan(.12));
          }
        }
        if (const bool.fromEnvironment('AR_REVIEW')) {
          debugPrint('AR review renders ready in app cache');
          await tester.pump(const Duration(seconds: 45));
        }
      } finally {
        await channel.invokeMethod<void>('stop');
        for (final file in files) {
          if (await file.exists()) await file.delete();
        }
      }
    },
  );
}
