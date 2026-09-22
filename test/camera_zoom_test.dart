import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/features/camera/presentation/camera_zoom_surface.dart';

void main() {
  Future<void> open(
    WidgetTester tester,
    Future<double> Function(double) send, {
    double min = 1,
    double max = 4,
    bool enabled = true,
    Key? key,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Center(
        child: SizedBox(
          width: 300,
          height: 400,
          child: CameraZoomSurface(
            key: key,
            minZoom: min,
            maxZoom: max,
            enabled: enabled,
            onZoom: send,
            child: const ColoredBox(color: Colors.black),
          ),
        ),
      ),
    ),
  );
  Future<void> pinch(WidgetTester tester, double distance) async {
    final center = tester.getCenter(
      find.byKey(const ValueKey('camera_zoom_surface')),
    );
    final a = await tester.startGesture(
      center - const Offset(25, 0),
      pointer: 1,
    );
    final b = await tester.startGesture(
      center + const Offset(25, 0),
      pointer: 2,
    );
    await b.moveTo(center + Offset(distance - 25, 0));
    await tester.pump();
    await a.up();
    await b.up();
    await tester.pump();
  }

  testWidgets(
    'pinch zooms both ways, clamps and reverses immediately at limits',
    (tester) async {
      final sent = <double>[];
      await open(tester, (z) async {
        sent.add(z);
        return z;
      }, min: .5);
      await pinch(tester, 100);
      expect(sent.last, 2);
      await pinch(tester, 25);
      expect(sent.last, 1);
      await pinch(tester, 10);
      expect(sent.last, .5);
      await pinch(tester, 1000);
      expect(sent.last, 4);
      await pinch(tester, 25);
      expect(sent.last, 2);
      await tester.pump(const Duration(seconds: 1));
      expect(
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
        0,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('single-finger drag and fixed zoom cameras do nothing', (
    tester,
  ) async {
    final sent = <double>[];
    Future<double> send(double z) async {
      sent.add(z);
      return z;
    }

    await open(tester, send);
    await tester.drag(
      find.byKey(const ValueKey('camera_zoom_surface')),
      const Offset(60, 0),
    );
    expect(sent, isEmpty);
    await open(tester, send, max: 1);
    await pinch(tester, 100);
    expect(sent, isEmpty);
    await open(tester, send, enabled: false);
    await pinch(tester, 100);
    expect(sent, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'rapid input sends only one request at a time and retains newest ratio',
    (tester) async {
      final sent = <double>[], replies = <Completer<double>>[];
      await open(tester, (z) {
        sent.add(z);
        final c = Completer<double>();
        replies.add(c);
        return c.future;
      });
      await pinch(tester, 75);
      expect(sent, [1.5]);
      await pinch(tester, 100);
      await pinch(tester, 25);
      expect(sent, [1.5]);
      replies.first.complete(1.5);
      await tester.pump();
      expect(sent, [1.5, 1.5]);
      replies.last.complete(1.5);
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'failed zoom rolls back and next pinch retries; disposed session cannot send queued work',
    (tester) async {
      var fail = true;
      final sent = <double>[];
      await open(tester, (z) async {
        sent.add(z);
        if (fail) throw StateError('closed');
        return z;
      });
      await pinch(tester, 100);
      expect(find.text('1.0×'), findsOneWidget);
      fail = false;
      await pinch(tester, 100);
      expect(sent, [2, 2]);
      final pending = Completer<double>();
      await open(tester, (z) {
        sent.add(z);
        return pending.future;
      }, key: const ValueKey('new'));
      await pinch(tester, 100);
      await pinch(tester, 75);
      final count = sent.length;
      await tester.pumpWidget(const SizedBox());
      pending.complete(2);
      await tester.pump();
      expect(sent.length, count);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'pointer cancellation and adding a third finger do not jump zoom',
    (tester) async {
      final sent = <double>[];
      await open(tester, (z) async {
        sent.add(z);
        return z;
      });
      final center = tester.getCenter(
        find.byKey(const ValueKey('camera_zoom_surface')),
      );
      final a = await tester.startGesture(
        center - const Offset(30, 0),
        pointer: 1,
      );
      final b = await tester.startGesture(
        center + const Offset(30, 0),
        pointer: 2,
      );
      final c = await tester.startGesture(center, pointer: 3);
      await b.moveBy(const Offset(30, 0));
      expect(sent, isEmpty);
      await c.cancel();
      await b.moveBy(const Offset(30, 0));
      await tester.pump();
      expect(sent.single, closeTo(120 / 90, .001));
      await a.cancel();
      await b.moveBy(const Offset(30, 0));
      expect(sent.length, 1);
      await b.up();
      await tester.pumpWidget(const SizedBox());
    },
  );
}
