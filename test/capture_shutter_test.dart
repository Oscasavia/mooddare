import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/features/camera/presentation/capture_shutter.dart';

void main() {
  late int photos, starts, stops, swipes;
  late bool recording;
  Completer<bool>? startup;
  late StateSetter update;

  Future<void> mount(WidgetTester tester) async {
    photos = starts = stops = swipes = 0;
    recording = false;
    startup = null;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return Center(
                child: CaptureShutter(
                  enabled: true,
                  recording: recording,
                  active: true,
                  elapsedMillis: 1000,
                  lens: const Icon(Icons.camera_alt),
                  onPhoto: () async {
                    photos++;
                  },
                  onStart: (stillHeld) async {
                    starts++;
                    if (startup != null) await startup!.future;
                    update(() => recording = true);
                    return true;
                  },
                  onStop: () async {
                    stops++;
                    update(() => recording = false);
                  },
                  onSwipeLens: (delta) => swipes += delta,
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  final shutter = find.byKey(const ValueKey('capture_shutter'));
  Future<TestGesture> hold(WidgetTester tester) async {
    final finger = await tester.startGesture(tester.getCenter(shutter));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    return finger;
  }

  testWidgets('tap takes one photo; horizontal swipe only changes the lens', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(shutter);
    await tester.pump();
    expect(photos, 1);
    await tester.drag(shutter, const Offset(-90, 0));
    await tester.pump();
    expect(swipes, 1);
    expect(photos, 1);
    expect(starts, 0);
  });

  testWidgets('hold records and release stops without taking a photo', (
    tester,
  ) async {
    await mount(tester);
    final finger = await hold(tester);
    expect(starts, 1);
    expect(recording, isTrue);
    await finger.up();
    await tester.pump();
    expect(stops, 1);
    expect(photos, 0);
  });

  testWidgets('slide to lock keeps recording until the shutter is tapped', (
    tester,
  ) async {
    await mount(tester);
    final finger = await hold(tester);
    await finger.moveBy(const Offset(0, -118));
    await tester.pump();
    await finger.up();
    await tester.pump();
    expect(recording, isTrue);
    expect(stops, 0);
    expect(find.text('Tap to stop'), findsOneWidget);
    await tester.tap(shutter);
    await tester.pump();
    expect(stops, 1);
    expect(photos, 0);
  });

  testWidgets(
    'release during slow startup still stops the recorder exactly once',
    (tester) async {
      await mount(tester);
      startup = Completer<bool>();
      final finger = await hold(tester);
      await finger.up();
      await tester.pump();
      expect(stops, 0);
      startup!.complete(true);
      await tester.pump();
      expect(stops, 1);
      expect(recording, isFalse);
      expect(photos, 0);
    },
  );

  testWidgets('pointer cancellation stops an unlocked recording', (
    tester,
  ) async {
    await mount(tester);
    final finger = await hold(tester);
    await finger.cancel();
    await tester.pump();
    expect(stops, 1);
    expect(photos, 0);
  });

  testWidgets('automatic stop clears the lock for the next photo', (
    tester,
  ) async {
    await mount(tester);
    final finger = await hold(tester);
    await finger.moveBy(const Offset(0, -118));
    await finger.up();
    await tester.pump();
    update(() => recording = false);
    await tester.pump();
    expect(find.text('Tap photo · hold video'), findsOneWidget);
    await tester.tap(shutter);
    await tester.pump();
    expect(photos, 1);
    expect(stops, 0);
  });
}
