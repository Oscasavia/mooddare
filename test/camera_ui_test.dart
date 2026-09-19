import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/core/app_theme.dart';
import 'package:mooddare/features/camera/presentation/live_beauty_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('mooddare/live_beauty');
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async => switch (call.method) {
            'requestCamera' => true,
            'start' => {'textureId': 1},
            'status' => {
              'ready': true,
              'width': 960,
              'height': 1280,
              'faceDetected': true,
            },
            _ => null,
          },
        );
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  for (final size in [const Size(320, 640), const Size(768, 1024)]) {
    testWidgets('camera fills $size with readable floating controls', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: const LiveBeautyScreen(
            dareText:
                'A longer dare that stays out of the way while you capture your moment.',
          ),
        ),
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      final preview = tester.getRect(find.byType(Texture));
      expect(preview.width, greaterThanOrEqualTo(size.width));
      expect(preview.height, greaterThanOrEqualTo(size.height));
      expect(tester.getSize(find.byType(PageView)).width, size.width);
      expect(tester.getRect(find.byType(TextButton)).bottom, lessThan(100));
      expect(find.byType(SegmentedButton<bool>), findsNothing);
      expect(find.byType(Slider), findsNothing);
      await tester.drag(
        find.byKey(const ValueKey('capture_shutter')),
        const Offset(-80, 0),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Adjust lens'));
      await tester.pump();
      expect(find.byType(Slider), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  }
}
