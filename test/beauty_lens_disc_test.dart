import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/core/app_theme.dart';
import 'package:mooddare/features/camera/domain/beauty_lens.dart';
import 'package:mooddare/features/camera/presentation/beauty_lens_disc.dart';

void main() {
  testWidgets(
    'collection thumbnails render distinctly and repaint when a lens changes',
    (tester) async {
      final key = GlobalKey();
      Future<List<int>> render(BeautyLens lens) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.build(),
            home: Center(
              child: RepaintBoundary(
                key: key,
                child: SizedBox.square(
                  dimension: 64,
                  child: BeautyLensDisc(lens: lens),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        return (await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage();
          try {
            final bytes = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!.buffer.asUint8List();
            // The round disc should not paint an opaque rectangular background.
            expect(bytes[3], 0);
            expect(bytes[(32 * 64 + 32) * 4 + 3], 255);
            return bytes.toList();
          } finally {
            image.dispose();
          }
        }))!;
      }

      final images = <List<int>>[];
      for (final lens in [
        ...BeautyLens.collection,
        ...BeautyLens.playful,
        BeautyLens.all.firstWhere((l) => l.heartHalo),
      ]) {
        final image = await render(lens);
        for (final prior in images) {
          expect(image, isNot(orderedEquals(prior)));
        }
        images.add(image);
        expect(tester.takeException(), isNull);
      }
      expect(
        await render(BeautyLens.collection.first),
        orderedEquals(images.first),
      );
    },
  );

  testWidgets('collection thumbnail strip remains compact', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        home: Center(
          child: RepaintBoundary(
            key: key,
            child: ColoredBox(
              color: const Color(0xFF16131D),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final lens in [
                      BeautyLens.all.first,
                      ...BeautyLens.collection,
                      BeautyLens.all.firstWhere((l) => l.heartHalo),
                    ])
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: SizedBox.square(
                          dimension: 64,
                          child: BeautyLensDisc(lens: lens),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    const artifact = String.fromEnvironment('LENS_ARTIFACT');
    if (artifact.isNotEmpty) {
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 3);
        try {
          await File(artifact).writeAsBytes(
            (await image.toByteData(
              format: ui.ImageByteFormat.png,
            ))!.buffer.asUint8List(),
          );
        } finally {
          image.dispose();
        }
      });
    }
  });
}
