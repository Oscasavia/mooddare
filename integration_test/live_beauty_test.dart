import 'dart:convert';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:mooddare/core/app_theme.dart';
import 'package:mooddare/features/camera/domain/beauty_lens.dart';
import 'package:mooddare/features/feed/presentation/screens/camera_screen.dart';
import 'face_fixture.dart';

const channel = MethodChannel('mooddare/live_beauty');

Future<Map<String, dynamic>> waitForState(
  WidgetTester tester,
  bool Function(Map<String, dynamic>) matches,
) async {
  Map<String, dynamic> state = {};
  for (var i = 0; i < 100; i++) {
    await tester.pump(const Duration(milliseconds: 150));
    state = (await channel.invokeMapMethod<String, dynamic>('status'))!;
    if (state['error'] != null) fail('Native camera error: ${state['error']}');
    if (matches(state)) return state;
  }
  fail('Camera did not reach the expected state: $state');
}

Future<img.Image> capture() async {
  final file = File((await channel.invokeMethod<String>('capture'))!);
  final decoded = img.decodeJpg(await file.readAsBytes())!;
  await file.delete();
  return decoded;
}

double difference(img.Image a, img.Image b, {int? right, int? bottom}) {
  var total = 0.0, count = 0;
  for (var y = 0; y < (bottom ?? a.height); y += 2) {
    for (var x = 0; x < (right ?? a.width); x += 2) {
      final p = a.getPixel(x, y), q = b.getPixel(x, y);
      total += (p.r - q.r).abs() + (p.g - q.g).abs() + (p.b - q.b).abs();
      count += 3;
    }
  }
  return total / count;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'GPU lens capture preserves orientation, applies shapes and resets',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      final file = File(
        '${(await getTemporaryDirectory()).path}/live-fixture.jpg',
      );
      await file.writeAsBytes(base64Decode(faceFixtureBase64));
      final source = img.decodeJpg(await file.readAsBytes())!;
      try {
        await channel.invokeMethod<void>('startFixture', {
          'path': file.path,
          'front': false,
        });
        await waitForState(
          tester,
          (state) => state['ready'] == true && state['faceDetected'] == true,
        );
        await channel.invokeMethod<void>(
          'setLook',
          BeautyLens.all.first.settings(0),
        );
        final original = await capture();
        expect(original.width, source.width);
        expect(original.height, source.height);
        expect(
          difference(original, source),
          lessThan(6),
          reason: 'RGBA color order and upright output must match the input',
        );

        await channel.invokeMethod<void>('setLook', {
          ...BeautyLens.all.first.settings(0),
          'aspectRatio': 9 / 16,
        });
        final cropped = await capture();
        final cropWidth = (source.height * 9 / 16).toInt();
        expect(cropped.width, cropWidth);
        expect(cropped.height, source.height);
        expect(
          difference(
            cropped,
            img.copyCrop(
              source,
              x: (source.width - cropWidth) ~/ 2,
              y: 0,
              width: cropWidth,
              height: source.height,
            ),
          ),
          lessThan(6),
          reason:
              'The saved photo must match the centered full-screen preview crop',
        );
        await channel.invokeMethod<void>('setLook', {
          ...BeautyLens.all.first.settings(0),
          'aspectRatio': null,
        });

        await channel.invokeMethod<void>(
          'setLook',
          const BeautyLens('Shape', eyeSize: 1, faceSlim: 1).settings(1),
        );
        final shaped = await capture();
        expect(
          difference(original, shaped),
          greaterThan(.15),
          reason: 'Eye and jaw geometry must actually change pixels',
        );
        expect(
          difference(
            original,
            shaped,
            right: source.width ~/ 5,
            bottom: source.height ~/ 5,
          ),
          lessThan(.5),
          reason: 'The background outside the face must stay unchanged',
        );

        for (final lens in const [
          BeautyLens('Eyes', eyeSize: 1),
          BeautyLens('Jaw', faceSlim: 1),
          BeautyLens('Skin', smooth: 1),
        ]) {
          await channel.invokeMethod<void>('setLook', lens.settings(1));
          expect(
            difference(original, await capture()),
            greaterThan(.02),
            reason: '${lens.name} must independently change the output',
          );
        }

        await channel.invokeMethod<void>(
          'setLook',
          BeautyLens.all.last.settings(1, original: true),
        );
        expect(
          difference(original, await capture()),
          lessThan(.1),
          reason: 'Original bypasses every effect',
        );
        await channel.invokeMethod<void>('stop');

        await channel.invokeMethod<void>('startFixture', {
          'path': file.path,
          'front': true,
        });
        await waitForState(
          tester,
          (state) => state['ready'] == true && state['faceDetected'] == true,
        );
        await channel.invokeMethod<void>(
          'setLook',
          BeautyLens.all.first.settings(0),
        );
        expect(
          difference(await capture(), img.flipHorizontal(source)),
          lessThan(6),
          reason: 'Selfie preview and export use the same horizontal mirror',
        );
        await channel.invokeMethod<void>('stop');
        final empty = img.Image(width: 256, height: 256);
        for (var y = 0; y < 256; y++) {
          for (var x = 0; x < 256; x++) {
            empty.setPixelRgb(x, y, x, y, (x * 7 + y * 3) % 256);
          }
        }
        await file.writeAsBytes(img.encodeJpg(empty));
        await channel.invokeMethod<void>('startFixture', {
          'path': file.path,
          'front': false,
        });
        final noFace = await waitForState(
          tester,
          (state) => (state['detections'] as num? ?? 0) > 0,
        );
        expect(noFace['faceDetected'], isFalse);
        await channel.invokeMethod<void>(
          'setLook',
          BeautyLens.all.first.settings(0),
        );
        final unchanged = await capture();
        await channel.invokeMethod<void>(
          'setLook',
          const BeautyLens(
            'Face',
            smooth: 1,
            eyeSize: 1,
            faceSlim: 1,
          ).settings(1),
        );
        expect(
          difference(unchanged, await capture()),
          lessThan(.1),
          reason: 'Without a face, skin and geometry effects must be bypassed',
        );
      } finally {
        await channel.invokeMethod<void>('stop');
        await file.delete();
      }
    },
  );

  testWidgets(
    'live camera streams, switches lens, captures and resumes for retake',
    (tester) async {
      // Grant emulator permission before exercising the default camera route.
      final permissionCamera = CameraController(
        (await availableCameras()).first,
        ResolutionPreset.low,
        enableAudio: false,
      );
      await permissionCamera.initialize();
      await permissionCamera.dispose();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(),
          home: const CameraScreen(dareText: 'Live lens test'),
        ),
      );
      final first = await waitForState(
        tester,
        (state) => state['ready'] == true && (state['frames'] as num) > 5,
      );
      expect(
        first['height'],
        greaterThan(first['width']),
        reason: 'Camera must be portrait upright',
      );
      await tester.pump(const Duration(seconds: 2));
      final later = (await channel.invokeMapMethod<String, dynamic>('status'))!;
      expect(
        later['frames'] as num,
        greaterThan((first['frames'] as num) + 8),
        reason: 'Preview must keep producing frames',
      );
      debugPrint(
        'Live camera: ${later['width']}x${later['height']}, ${later['fps']} fps',
      );
      await tester.dragFrom(
        tester.getCenter(find.byType(PageView)) + const Offset(103, 0),
        const Offset(-103, 0),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Original'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('capture_shutter')));
      for (
        var i = 0;
        i < 100 && find.textContaining('· Photo studio').evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(find.textContaining('· Photo studio'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pageBack();
      await waitForState(
        tester,
        (state) => state['ready'] == true && (state['frames'] as num) > 2,
      );
      await tester.tap(find.byTooltip('Switch camera'));
      await waitForState(
        tester,
        (state) => state['ready'] == true && (state['frames'] as num) > 2,
      );
      expect(tester.takeException(), isNull);
      // Rapid background/resume must not allow an old stop to close a new camera.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(seconds: 1));
      await waitForState(
        tester,
        (state) => state['ready'] == true && (state['frames'] as num) > 2,
      );
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump(const Duration(seconds: 1));
      await channel.invokeMethod<void>('stop');
    },
  );
}
