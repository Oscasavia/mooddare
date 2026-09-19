import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/core/app_theme.dart';
import 'package:mooddare/features/camera/domain/photo_processing.dart';
import 'package:mooddare/features/camera/presentation/photo_adjustments_panel.dart';
import 'package:mooddare/features/camera/presentation/photo_review_frame.dart';

void main() {
  for (final size in [const Size(320, 640), const Size(768, 1024)]) {
    testWidgets('floating controls preserve photo bounds and corners at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var open = false;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(),
          home: Scaffold(
            body: MediaQuery(
              data: MediaQueryData(
                size: size,
                textScaler: const TextScaler.linear(1.5),
              ),
              child: StatefulBuilder(
                builder: (context, setState) {
                  update = setState;
                  return Column(
                    children: [
                      Expanded(
                        child: PhotoReviewFrame(
                          photo: const AspectRatio(
                            key: ValueKey('test_photo'),
                            aspectRatio: 3 / 4,
                            child: ColoredBox(color: Colors.blue),
                          ),
                          controls: open
                              ? PhotoAdjustmentsPanel(
                                  settings: const PhotoAdjustments(),
                                  faceDetected: false,
                                  enabled: true,
                                  notice:
                                      'No front-facing face found. Try a well-lit selfie for smoothing.',
                                  onChanged: (_) {},
                                  onReset: () {},
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(height: 112),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );
      final photo = find.byKey(const ValueKey('test_photo'));
      final frame = find.byKey(const ValueKey('photo_review_frame'));
      final bounds = tester.getRect(photo);
      expect(tester.getRect(frame), bounds);
      update(() => open = true);
      await tester.pumpAndSettle();
      expect(tester.getRect(photo), bounds);
      expect(tester.getRect(frame), bounds);
      expect(
        tester.widget<ClipRRect>(frame).borderRadius,
        BorderRadius.circular(24),
      );
      final overlay = tester.getRect(
        find.byKey(const ValueKey('photo_controls_overlay')),
      );
      expect(overlay.intersect(bounds), overlay);
      await tester.tap(find.byTooltip('Select Smooth').hitTestable());
      await tester.pumpAndSettle();
      expect(find.textContaining('No front-facing face'), findsOneWidget);
      expect(tester.getRect(photo), bounds);
      expect(tester.getRect(frame), bounds);
      update(() => open = false);
      await tester.pumpAndSettle();
      expect(tester.getRect(photo), bounds);
      expect(tester.takeException(), isNull);
    });
  }
}
