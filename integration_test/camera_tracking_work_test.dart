import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mooddare/features/camera/domain/beauty_lens.dart';
import 'live_beauty_test.dart' show channel, waitForState;
import 'live_video_test.dart' show allowCameraAndAudio;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Original and compare stop detection; active lenses resume it', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await allowCameraAndAudio();
    try {
      final session = (await channel.invokeMapMethod<String, dynamic>('start', {
        'front': true,
      }))!;
      await tester.pumpWidget(
        MaterialApp(
          home: Texture(textureId: (session['textureId'] as num).toInt()),
        ),
      );
      await waitForState(tester, (s) => s['ready'] == true);
      final golden = BeautyLens.all.firstWhere((l) => l.id == 'golden_hour');
      for (final look in [
        BeautyLens.all.first.settings(1),
        {...golden.settings(.65), 'original': true},
        golden.settings(0),
      ]) {
        await channel.invokeMethod<void>('setLook', look);
        // Let any already submitted detector task finish before comparing counts.
        await tester.pump(const Duration(seconds: 2));
        final before = (await channel.invokeMapMethod<String, dynamic>(
          'status',
        ))!;
        await tester.pump(const Duration(seconds: 2));
        final after = (await channel.invokeMapMethod<String, dynamic>(
          'status',
        ))!;
        expect(after['detections'], before['detections']);
        expect(after['frames'] as num, greaterThan(before['frames'] as num));
        expect(after['faceDetected'], isFalse);
        expect(after['geometryDetected'], isFalse);
        await channel.invokeMethod<void>('setLook', golden.settings(.65));
        await waitForState(
          tester,
          (s) => (s['detections'] as num) > (after['detections'] as num),
        );
      }
      await channel.invokeMethod<void>(
        'setLook',
        BeautyLens.all.first.settings(1),
      );
      await tester.pump(const Duration(seconds: 2));
      final beforeAr = (await channel.invokeMapMethod<String, dynamic>(
        'status',
      ))!;
      await channel.invokeMethod<void>(
        'setLook',
        BeautyLens.all.firstWhere((l) => l.heartHalo).settings(1),
      );
      await waitForState(
        tester,
        (s) => (s['detections'] as num) > (beforeAr['detections'] as num) + 1,
      );
      final state = await waitForState(
        tester,
        (s) => (s['performance'] as Map).isNotEmpty,
      );
      final performance = state['performance'] as Map;
      expect(performance['fps'] as num, greaterThan(0));
      expect(performance['frames'] as num, greaterThan(1));
      expect(performance['averageFrameMs'] as num, greaterThan(0));
      debugPrint('Emulator processing sample: $performance');
    } finally {
      await channel.invokeMethod<void>('stop');
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    }
  });
}
