import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:mooddare/features/camera/domain/beauty_lens.dart';
import 'face_fixture.dart';
import 'live_beauty_test.dart' show channel, waitForState, capture, difference;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'mesh shaping mirrors, protects the center and stops on closed eyes or lost mesh',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      final cache = (await getTemporaryDirectory()).path;
      final fixture = File('$cache/shape-portrait.jpg');
      await fixture.writeAsBytes(base64Decode(faceFixtureBase64));
      img.Image? unmirrored;
      try {
        for (final front in [false, true]) {
          await channel.invokeMethod<void>('startFixture', {
            'path': fixture.path,
            'front': front,
          });
          await waitForState(tester, (s) => (s['detections'] as num? ?? 0) > 0);
          final inspected = (await channel.invokeMapMethod<String, dynamic>(
            'inspectFaceGeometry',
          ))!;
          await File(inspected['path'] as String).delete();
          final polygons = (inspected['polygons'] as List)
              .map(
                (p) => (p as List).map((v) => (v as num).toDouble()).toList(),
              )
              .toList();
          await channel.invokeMethod<void>(
            'setLook',
            BeautyLens.all.first.settings(0),
          );
          final original = await capture();
          await channel.invokeMethod<void>(
            'setLook',
            const BeautyLens('Eyes', eyeSize: 1).settings(1),
          );
          final eyes = await capture();
          expect(difference(original, eyes), greaterThan(.02));
          // Close both eye contours in their own physical eye-line frame. The
          // portrait stays identical, isolating blink handling in the GPU shader.
          final closed = polygons.map((p) => [...p]).toList();
          final aspect = original.width / original.height;
          List<double> center(List<double> p) => [
            [
                  for (var i = 0; i < p.length; i += 2) p[i] * aspect,
                ].reduce((a, b) => a + b) /
                (p.length / 2),
            [
                  for (var i = 1; i < p.length; i += 2) p[i],
                ].reduce((a, b) => a + b) /
                (p.length / 2),
          ];
          final a = center(polygons[1]), b = center(polygons[2]);
          final length = math.sqrt(
            math.pow(b[0] - a[0], 2) + math.pow(b[1] - a[1], 2),
          );
          final ux = (b[0] - a[0]) / length, uy = (b[1] - a[1]) / length;
          for (final index in [1, 2]) {
            final c = center(polygons[index]);
            for (var i = 0; i < closed[index].length; i += 2) {
              final x = polygons[index][i] * aspect - c[0],
                  y = polygons[index][i + 1] - c[1];
              final along = x * ux + y * uy, across = (-x * uy + y * ux) * .04;
              closed[index][i] = (c[0] + along * ux - across * uy) / aspect;
              closed[index][i + 1] = c[1] + along * uy + across * ux;
            }
          }
          await channel.invokeMethod<void>('setGeometryFixture', {
            'polygons': closed,
          });
          expect(
            difference(original, await capture()),
            lessThan(.15),
            reason: 'Closed eyelids must not be enlarged',
          );
          await channel.invokeMethod<void>('setGeometryFixture', {
            'polygons': polygons,
          });
          await channel.invokeMethod<void>(
            'setLook',
            const BeautyLens('Jaw', faceSlim: 1).settings(1),
          );
          final jaw = await capture();
          expect(difference(original, jaw), greaterThan(.02));
          final mouth = polygons[5];
          final mx = center(mouth)[0] / aspect;
          final my =
              [
                for (var i = 1; i < mouth.length; i += 2) mouth[i],
              ].reduce((a, b) => a + b) /
              (mouth.length / 2);
          // Small central mouth region must not be pulled sideways by slimming.
          final centerX = ((front ? 1 - mx : mx) * original.width).round();
          final centerY = (my * original.height).round();
          final originalMouth = img.copyCrop(
            original,
            x: centerX - 5,
            y: centerY - 3,
            width: 10,
            height: 6,
          );
          final shapedMouth = img.copyCrop(
            jaw,
            x: centerX - 5,
            y: centerY - 3,
            width: 10,
            height: 6,
          );
          expect(difference(originalMouth, shapedMouth), lessThan(1));
          await channel.invokeMethod<void>(
            'setLook',
            const BeautyLens('Shape', eyeSize: 1, faceSlim: 1).settings(1),
          );
          final shaped = await capture();
          expect(
            difference(
              original,
              shaped,
              right: original.width ~/ 5,
              bottom: original.height ~/ 5,
            ),
            lessThan(.01),
            reason: 'Distant pixels retain exact source coordinates',
          );
          if (front) {
            expect(
              difference(img.flipHorizontal(unmirrored!), shaped),
              lessThan(1),
              reason: 'Shape must mirror with the face',
            );
          } else {
            unmirrored = shaped;
            await File(
              '$cache/shape-original.jpg',
            ).writeAsBytes(img.encodeJpg(original, quality: 95));
            await File(
              '$cache/shape-result.jpg',
            ).writeAsBytes(img.encodeJpg(shaped, quality: 95));
            await tester.pump(const Duration(seconds: 6));
          }
          final still = File(
            (await channel.invokeMethod<String>('captureStillFixture'))!,
          );
          expect(
            difference(shaped, img.decodeJpg(await still.readAsBytes())!),
            lessThan(.5),
          );
          await still.delete();
          await channel.invokeMethod<void>('setGeometryFixture');
          expect(
            difference(original, await capture()),
            lessThan(.1),
            reason: 'Missing mesh must not reuse old shape guides',
          );
          await channel.invokeMethod<void>('stop');
        }
      } finally {
        await channel.invokeMethod<void>('stop');
        await fixture.delete();
      }
    },
  );
}
