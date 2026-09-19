import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:mooddare/features/camera/domain/beauty_lens.dart';
import 'package:mooddare/features/camera/domain/photo_processing.dart';
import 'live_beauty_test.dart' show channel, waitForState, capture, difference;
import 'live_video_test.dart' show allowCameraAndAudio;

Future<img.Image> stillFixture() async {
  final file = File(
    (await channel.invokeMethod<String>('captureStillFixture'))!,
  );
  try {
    return img.decodeJpg(await file.readAsBytes())!;
  } finally {
    await file.delete();
  }
}

double detail(img.Image image) {
  var result = 0.0;
  for (var y = 64; y < 128; y++) {
    for (var x = 64; x < 128; x++) {
      result += (image.getPixel(x, y).r - image.getPixel(x + 1, y).r).abs();
    }
  }
  return result / (64 * 64);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'larger still keeps real detail, framing and mirroring without altering preview',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      final source = img.Image(width: 1536, height: 2048);
      for (var y = 0; y < source.height; y++) {
        for (var x = 0; x < source.width; x++) {
          final stripe = x < 256 && y < 256 ? (x.isEven ? 220 : 30) : null;
          source.setPixelRgb(
            x,
            y,
            stripe ?? x * 255 ~/ source.width,
            stripe ?? y * 255 ~/ source.height,
            stripe ?? 100,
          );
        }
      }
      final file = File(
        '${(await getTemporaryDirectory()).path}/detail-fixture.png',
      );
      await file.writeAsBytes(img.encodePng(source));
      try {
        for (final front in [false, true]) {
          await channel.invokeMethod<void>('startFixture', {
            'path': file.path,
            'front': front,
          });
          final state = await waitForState(
            tester,
            (s) => (s['detections'] as num? ?? 0) > 0,
          );
          expect(state['height'], 1280);
          await channel.invokeMethod<void>(
            'setLook',
            BeautyLens.all.first.settings(0),
          );
          final preview = await capture();
          final full = await stillFixture();
          expect(full.width, 1536);
          expect(full.height, 2048);
          expect(
            difference(
              full,
              front ? img.flipHorizontal(img.Image.from(source)) : source,
            ),
            lessThan(6),
          );
          if (!front) {
            final enlargedPreview = img.copyResize(
              preview,
              width: full.width,
              height: full.height,
              interpolation: img.Interpolation.linear,
            );
            expect(
              detail(full),
              greaterThan(detail(enlargedPreview) + 40),
              reason:
                  'Higher resolution must retain source detail, not enlarge preview pixels',
            );
            final normalized = img.decodeJpg(
              normalizePhoto(img.encodeJpg(full, quality: 95)),
            )!;
            expect(
              normalized.height,
              2048,
              reason: 'The editor must retain the improved capture size',
            );
          }
          expect(
            difference(preview, await capture()),
            lessThan(.1),
            reason: 'Offscreen rendering must not replace the preview texture',
          );
          for (final ratio in [9 / 16, 3 / 4]) {
            await channel.invokeMethod<void>('setLook', {
              ...BeautyLens.all.first.settings(0),
              'aspectRatio': ratio,
            });
            final photo = await stillFixture();
            final width = (2048 * ratio).toInt();
            expect(photo.width, width);
            expect(photo.height, 2048);
            final oriented = front
                ? img.flipHorizontal(img.Image.from(source))
                : source;
            final expected = img.copyCrop(
              oriented,
              x: (source.width - width) ~/ 2,
              y: 0,
              width: width,
              height: 2048,
            );
            expect(difference(photo, expected), lessThan(6));
          }
          await channel.invokeMethod<void>('stop');
        }
      } finally {
        await channel.invokeMethod<void>('stop');
        await file.delete();
      }
    },
  );

  testWidgets(
    'front and rear CameraX still capture stay upright and recover after cancellation',
    (tester) async {
      await allowCameraAndAudio();
      var capturedExtraDetail = false;
      try {
        for (final front in [true, false]) {
          final session = await channel.invokeMapMethod<String, dynamic>(
            'start',
            {'front': front},
          );
          await tester.pumpWidget(
            MaterialApp(
              home: Texture(textureId: (session!['textureId'] as num).toInt()),
            ),
          );
          final state = await waitForState(
            tester,
            (s) => s['ready'] == true && (s['frames'] as num) > 5,
          );
          expect(state['highQualityPhotos'], isTrue);
          await channel.invokeMethod<void>('setLook', {
            ...BeautyLens.all.first.settings(0),
            'aspectRatio': 3 / 4,
          });
          final photo = await capture();
          debugPrint(
            'Sensor photo ${front ? "front" : "rear"}: ${photo.width}x${photo.height}; preview ${state['width']}x${state['height']}',
          );
          // The emulator's rear sensor is limited to the preview resolution.
          expect(photo.height, greaterThanOrEqualTo(state['height'] as num));
          capturedExtraDetail |= photo.height > (state['height'] as num);
          expect(photo.height, lessThanOrEqualTo(2048));
          expect(photo.width / photo.height, closeTo(3 / 4, .002));
          await waitForState(
            tester,
            (s) => (s['frames'] as num) > (state['frames'] as num) + 5,
          );
          // Subscribe to the error before closing; no late result may reach a new session.
          final pending = channel.invokeMethod<String>('capture');
          final settled = pending.then(
            (path) async {
              if (path != null) await File(path).delete();
            },
            onError: (Object e) {
              expect(e, isA<PlatformException>());
            },
          );
          await channel.invokeMethod<void>('stop');
          await settled;
        }
        expect(capturedExtraDetail, isTrue);
      } finally {
        await channel.invokeMethod<void>('stop');
      }
    },
  );
}
