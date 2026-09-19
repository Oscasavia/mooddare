import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/core/app_theme.dart';
import 'package:mooddare/features/camera/presentation/live_beauty_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('mooddare/live_beauty');
  double? sentAspect;
  setUp(() {
    sentAspect = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'setLook') {
            sentAspect = (call.arguments['aspectRatio'] as num).toDouble();
          }
          return switch (call.method) {
            'requestCamera' => true,
            'start' => {'textureId': 1},
            'status' => {
              'ready': true,
              'width': 960,
              'height': 1280,
              'faceDetected': true,
            },
            _ => null,
          };
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  for (final size in [const Size(320, 640), const Size(768, 1024)]) {
    testWidgets(
      'camera framing stays consistent at $size with floating controls',
      (tester) async {
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
        final frame = find.byKey(const ValueKey('camera_frame'));
        expect(tester.getSize(frame).aspectRatio, closeTo(9 / 16, .0001));
        expect(tester.getCenter(frame), size.center(Offset.zero));
        expect(sentAspect, 9 / 16);
        for (final entry in {
          '3:4': 3 / 4,
          'Full': size.aspectRatio,
          '9:16': 9 / 16,
        }.entries) {
          await tester.tap(find.byKey(const ValueKey('camera_ratio')));
          await tester.pumpAndSettle();
          await tester.tap(
            find.ancestor(
              of: find.text(entry.key).last,
              matching: find.byWidgetPredicate(
                (widget) => widget is PopupMenuItem,
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            tester.getSize(frame).aspectRatio,
            closeTo(entry.value, .0001),
          );
          expect(
            sentAspect,
            entry.value,
            reason:
                'The native export must use the same ratio as the viewfinder',
          );
          expect(tester.getRect(frame).left, greaterThanOrEqualTo(0));
          expect(tester.getRect(frame).right, lessThanOrEqualTo(size.width));
          expect(tester.getRect(frame).bottom, lessThanOrEqualTo(size.height));
          expect(tester.getCenter(frame), size.center(Offset.zero));
        }
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
      },
    );
  }
}
