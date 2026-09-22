import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/core/widgets/mooddare_wordmark.dart';

void main() {
  testWidgets('wordmark loads, announces the brand and removes the dark panel', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: boundaryKey,
              child: const ColoredBox(
                color: Color(0xFF205040),
                child: MoodDareWordmark(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      await precacheImage(
        const AssetImage('assets/branding/mooddare-wordmark.png'),
        tester.element(find.byType(MoodDareWordmark)),
      );
    });
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('MoodDare'), findsOneWidget);
    semantics.dispose();
    expect(tester.takeException(), isNull);
    final boundary =
        boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final data = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      // The source PNG is opaque: its corners must nevertheless reveal the
      // surrounding surface, while the lettering remains lavender and visible.
      expect(data.getUint8(0), 32);
      expect(data.getUint8(1), 80);
      expect(data.getUint8(2), 64);
      var lavenderPixels = 0;
      var leftInk = image.width;
      var rightInk = -1;
      for (var offset = 0; offset < data.lengthInBytes; offset += 4) {
        if ((data.getUint8(offset) - 197).abs() <= 2 &&
            (data.getUint8(offset + 1) - 180).abs() <= 2 &&
            data.getUint8(offset + 2) >= 253) {
          lavenderPixels++;
          final x = (offset ~/ 4) % image.width;
          if (x < leftInk) leftInk = x;
          if (x > rightInk) rightInk = x;
        }
      }
      expect(lavenderPixels, greaterThan(500));
      // Layout edges match visible lettering, rather than the original PNG's
      // 200px side margins. This is what makes the Welcome heading align.
      expect(leftInk, lessThanOrEqualTo(1));
      expect(rightInk, greaterThanOrEqualTo(image.width - 2));
      image.dispose();
    });
  });
}
