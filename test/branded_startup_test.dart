import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mooddare/core/app_theme.dart';
import 'package:mooddare/core/branding/mood_wink.dart';
import 'package:mooddare/core/widgets/branded_startup.dart';
import 'package:mooddare/core/widgets/mooddare_wordmark.dart';

Future<void> mount(
  WidgetTester tester,
  Future<void> Function() initialize, {
  bool reduce = false,
  bool accessible = false,
}) => tester.pumpWidget(
  MaterialApp(
    theme: AppTheme.build(),
    home: MediaQuery(
      data: MediaQueryData(
        disableAnimations: reduce,
        accessibleNavigation: accessible,
        textScaler: const TextScaler.linear(2),
      ),
      child: BrandedStartup(
        initialize: initialize,
        child: const Scaffold(body: Text('Ready')),
      ),
    ),
  ),
);

void main() {
  for (final insets in [
    const EdgeInsets.only(top: 48, bottom: 24),
    const EdgeInsets.only(top: 24, bottom: 48),
    const EdgeInsets.only(top: 62, bottom: 34),
  ]) {
    testWidgets(
      'native-to-Flutter handoff stays centered with system insets $insets',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final ready = Completer<void>();
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.build(),
            home: MediaQuery(
              data: MediaQueryData(
                size: const Size(360, 800),
                padding: insets,
                viewPadding: insets,
              ),
              child: BrandedStartup(
                initialize: () => ready.future,
                child: const Text('Ready'),
              ),
            ),
          ),
        );
        final first = tester.getRect(find.byType(MoodWink));
        expect(first.center, const Offset(180, 400));
        expect(first.size, const Size.square(128));
        await tester.pump(const Duration(milliseconds: 270));
        expect(tester.getRect(find.byType(MoodWink)), first);
        expect(
          tester.widget<MoodWink>(find.byType(MoodWink)).wink,
          inExclusiveRange(0, 1),
        );
        ready.complete();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 629));
        expect(find.text('Ready'), findsNothing);
        // Permit the next frame after the 900ms controller boundary.
        await tester.pump(const Duration(milliseconds: 2));
        expect(find.text('Ready'), findsOneWidget);
      },
    );
  }

  testWidgets(
    'one wink completes before handoff, without reinitializing on resize',
    (tester) async {
      final ready = Completer<void>();
      var calls = 0;
      Future<void> initialize() {
        calls++;
        return ready.future;
      }

      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await mount(tester, initialize);
      expect(tester.widget<MoodWink>(find.byType(MoodWink)).wink, 0);
      expect(find.byType(MoodDareWordmark), findsNothing);
      ready.complete();
      await tester.pump();
      expect(find.text('Ready'), findsNothing);
      await tester.pump(const Duration(milliseconds: 270));
      expect(
        tester.widget<MoodWink>(find.byType(MoodWink)).wink,
        inExclusiveRange(0, 1),
      );
      await tester.pump(const Duration(milliseconds: 140));
      expect(tester.widget<MoodWink>(find.byType(MoodWink)).wink, 1);
      tester.view.physicalSize = const Size(840, 900);
      await tester.pump(const Duration(milliseconds: 210));
      expect(
        tester.widget<MoodWink>(find.byType(MoodWink)).wink,
        inExclusiveRange(0, 1),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Ready'), findsOneWidget);
      await mount(tester, initialize);
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.byType(MoodWink), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'slow startup holds a still mark and never enters before initialization',
    (tester) async {
      final ready = Completer<void>();
      await mount(tester, () => ready.future);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Ready'), findsNothing);
      expect(tester.widget<MoodWink>(find.byType(MoodWink)).wink, 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
      ready.complete();
      await tester.pump();
      await tester.pump();
      expect(find.text('Ready'), findsOneWidget);
    },
  );

  testWidgets('startup errors surface immediately and retry succeeds safely', (
    tester,
  ) async {
    final retry = Completer<void>();
    var calls = 0;
    await mount(tester, () {
      if (++calls == 1) throw StateError('offline');
      return retry.future;
    });
    await tester.pump();
    expect(find.text('Let’s try that again'), findsOneWidget);
    expect(
      tester.widget<MoodWink>(find.byType(MoodWink)).expression,
      MoodWinkExpression.error,
    );
    expect(find.text('Ready'), findsNothing);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(calls, 2);
    expect(find.text('Retry'), findsNothing);
    retry.complete();
    await tester.pumpAndSettle();
    expect(find.text('Ready'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final accessible in [false, true]) {
    testWidgets(
      'reduced motion uses a still wink and adds no delay ($accessible)',
      (tester) async {
        final ready = Completer<void>();
        await mount(
          tester,
          () => ready.future,
          reduce: !accessible,
          accessible: accessible,
        );
        expect(tester.widget<MoodWink>(find.byType(MoodWink)).wink, 1);
        expect(tester.binding.transientCallbackCount, 0);
        ready.complete();
        await tester.pump();
        await tester.pump();
        expect(find.text('Ready'), findsOneWidget);
      },
    );
  }

  testWidgets('enabling reduced motion mid-wink completes the handoff', (
    tester,
  ) async {
    Future<void> initialize() async {}
    await mount(tester, initialize);
    await tester.pump(const Duration(milliseconds: 300));
    await mount(tester, initialize, reduce: true);
    await tester.pump();
    expect(find.text('Ready'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposal during startup leaves no ticker or delayed callback', (
    tester,
  ) async {
    final ready = Completer<void>();
    await mount(tester, () => ready.future);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpWidget(const SizedBox());
    ready.complete();
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });

  test(
    'wink only changes the right eye and stays in Android adaptive safe circle',
    () {
      final open = MoodWinkGeometry.path(0);
      final wink = MoodWinkGeometry.path(1);
      var changed = 0;
      for (var y = 0; y < 100; y++) {
        for (var x = 0; x < 100; x++) {
          final point = Offset(x + .5, y + .5);
          final a = open.contains(point), b = wink.contains(point);
          if (a != b) {
            changed++;
            expect(x, inInclusiveRange(53, 84));
            expect(y, inInclusiveRange(28, 57));
          }
          if (b) {
            final dx =
                MoodWinkGeometry.adaptiveOffset +
                point.dx * MoodWinkGeometry.adaptiveScale -
                54;
            final dy =
                MoodWinkGeometry.adaptiveOffset +
                point.dy * MoodWinkGeometry.adaptiveScale -
                54;
            expect(dx * dx + dy * dy, lessThanOrEqualTo(33 * 33));
          }
        }
      }
      expect(changed, greaterThan(100));
      expect(
        const MoodWinkPainter(
          wink: 1,
          color: AppTheme.accent,
        ).shouldRepaint(const MoodWinkPainter(wink: 1, color: AppTheme.accent)),
        isFalse,
      );
      expect(
        const MoodWinkPainter(
          wink: 0,
          color: AppTheme.accent,
        ).shouldRepaint(const MoodWinkPainter(wink: 1, color: AppTheme.accent)),
        isTrue,
      );
    },
  );

  test('iOS launcher catalog is correctly sized and has no alpha channel', () {
    const folder = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
    final catalog =
        jsonDecode(File('$folder/Contents.json').readAsStringSync()) as Map;
    for (final entry in catalog['images'] as List) {
      final points = double.parse((entry['size'] as String).split('x').first);
      final scale = int.parse((entry['scale'] as String).replaceAll('x', ''));
      final image = img.decodePng(
        File('$folder/${entry['filename']}').readAsBytesSync(),
      )!;
      expect(image.width, (points * scale).round());
      expect(image.height, image.width);
      expect(image.numChannels, 3);
      expect(image.getPixel(0, 0).r, 197);
    }
  });
}
