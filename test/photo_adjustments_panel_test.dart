import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/core/app_theme.dart';
import 'package:mooddare/features/camera/domain/photo_processing.dart';
import 'package:mooddare/features/camera/presentation/photo_adjustments_panel.dart';

void main() {
  for (final width in [320.0, 768.0]) {
    testWidgets('adjustments stay independent at width $width', (tester) async {
      tester.view.physicalSize = Size(width, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var settings = const PhotoAdjustments();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(),
          home: Scaffold(
            body: MediaQuery(
              data: MediaQueryData(textScaler: const TextScaler.linear(1.5)),
              child: StatefulBuilder(
                builder: (context, setState) => PhotoAdjustmentsPanel(
                  settings: settings,
                  faceDetected: true,
                  enabled: true,
                  onChanged: (value) => setState(() => settings = value),
                  onReset: () =>
                      setState(() => settings = const PhotoAdjustments()),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.byType(Slider), findsOneWidget);
      await tester.drag(find.byType(Slider), const Offset(50, 0));
      await tester.pump();
      final smooth = settings.smoothing;
      expect(smooth, greaterThan(0));
      final wheel = find.byKey(const ValueKey('photo_adjustment_wheel'));
      await tester.drag(wheel, const Offset(-100, 0));
      await tester.pumpAndSettle();
      expect(find.text('Light'), findsOneWidget);
      expect(tester.widget<Slider>(find.byType(Slider)).min, -1);
      await tester.drag(find.byType(Slider), const Offset(-40, 0));
      await tester.pump();
      final brightness = settings.brightness;
      expect(brightness, lessThan(0));
      expect(settings.smoothing, smooth);
      await tester.tap(find.byTooltip('Select Warmth').hitTestable());
      await tester.pumpAndSettle();
      expect(find.text('Warmth'), findsOneWidget);
      await tester.drag(find.byType(Slider), const Offset(40, 0));
      await tester.pump();
      expect(settings.warmth, greaterThan(0));
      expect(settings.brightness, brightness);
      expect(settings.smoothing, smooth);
      await tester.drag(wheel, const Offset(-100, 0));
      await tester.pumpAndSettle();
      expect(find.text('Smooth'), findsOneWidget);
      expect(tester.widget<Slider>(find.byType(Slider)).value, smooth);
      expect(
        tester.getCenter(find.byTooltip('Select Smooth').hitTestable()).dx,
        closeTo(tester.getCenter(wheel).dx, .1),
      );
      await tester.tap(find.byTooltip('Reset adjustments'));
      await tester.pump();
      expect(settings.smoothing, 0);
      expect(settings.brightness, 0);
      expect(settings.warmth, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('no-face captures can change color but cannot smooth', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        home: Scaffold(
          body: PhotoAdjustmentsPanel(
            settings: const PhotoAdjustments(),
            faceDetected: false,
            enabled: true,
            notice: 'No front-facing face found.',
            onChanged: (_) {},
            onReset: () {},
          ),
        ),
      ),
    );
    expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNotNull);
    await tester.tap(find.byTooltip('Select Smooth').hitTestable());
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
    expect(find.text('No front-facing face found.'), findsOneWidget);
    await tester.tap(find.byTooltip('Select Warmth').hitTestable());
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNotNull);
    expect(find.text('No front-facing face found.'), findsNothing);
  });
}
