import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:mooddare/features/camera/domain/beauty_lens.dart';
import 'package:mooddare/features/camera/domain/photo_processing.dart';
import 'face_fixture.dart';
import 'live_beauty_test.dart' show channel, waitForState, difference;

Future<img.Image> detectedStill() async {
  final file = File(
    (await channel.invokeMethod<String>('captureDetectedStillFixture'))!,
  );
  try {
    return img.decodeJpg(await file.readAsBytes())!;
  } finally {
    await file.delete();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'fresh photo detection retains makeup at preview and sensor resolutions',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      final source = img.decodeJpg(base64Decode(faceFixtureBase64))!;
      final file = File(
        '${(await getTemporaryDirectory()).path}/photo-makeup.jpg',
      );
      try {
        for (final height in [600, 2048]) {
          await file.writeAsBytes(
            img.encodeJpg(img.copyResize(source, height: height), quality: 98),
          );
          for (final front in [false, true]) {
            await channel.invokeMethod<void>('startFixture', {
              'path': file.path,
              'front': front,
            });
            final state = await waitForState(
              tester,
              (s) => (s['detections'] as num? ?? 0) > 0,
            );
            expect(state['geometryDetected'], isTrue);
            await channel.invokeMethod<void>(
              'setLook',
              BeautyLens.all.first.settings(0),
            );
            final original = await detectedStill();
            await channel.invokeMethod<void>(
              'setLook',
              const BeautyLens('Lips', makeup: 1).settings(1),
            );
            final photo = await detectedStill();
            final diagnostic =
                (await channel.invokeMapMethod<String, dynamic>(
                      'status',
                    ))!['photoDetection']
                    as Map;
            debugPrint('Fresh photo $height, front=$front: $diagnostic');
            expect(diagnostic['matched'], isTrue);
            expect(diagnostic['meshSucceeded'], isTrue);
            expect(diagnostic['attempt'] as num, lessThanOrEqualTo(2));
            if (height == 2048) {
              expect(
                diagnostic['attempt'] as num,
                greaterThan(0),
                reason:
                    'This regression fixture requires the bounded mesh retry',
              );
            }
            expect(diagnostic['quality'] as num, greaterThan(.1));
            expect(
              difference(original, photo),
              greaterThan(.02),
              reason: 'Fresh still detection must retain the makeup',
            );
            expect(photo.height, height);
            final reviewed = img.decodeJpg(
              normalizePhoto(img.encodeJpg(photo, quality: 95)),
            )!;
            final reviewedOriginal = img.decodeJpg(
              normalizePhoto(img.encodeJpg(original, quality: 95)),
            )!;
            expect(
              difference(reviewedOriginal, reviewed),
              greaterThan(.02),
              reason:
                  'Opening the captured image in the editor must preserve baked makeup',
            );
            await channel.invokeMethod<void>('stop');
          }
        }
      } finally {
        await channel.invokeMethod<void>('stop');
        if (await file.exists()) await file.delete();
      }
    },
  );
}
