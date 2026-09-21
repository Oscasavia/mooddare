import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mooddare/core/app_theme.dart';
import 'package:mooddare/features/camera/data/video_editor.dart';
import 'package:mooddare/features/camera/presentation/video_adjustments_panel.dart';

void main() {
  const thumbnailChannel = MethodChannel(
    'plugins.justsoft.xyz/video_thumbnail',
  );
  final frames = Uint8List.fromList(
    img.encodePng(img.Image(width: 16, height: 24)),
  );
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(thumbnailChannel, null),
  );

  test(
    'thumbnails sample the entire original clip once, with bounded image size and per-frame fallback',
    () async {
      final calls = <Map>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(thumbnailChannel, (call) async {
            expect(call.method, 'data');
            calls.add(call.arguments as Map);
            if (calls.length == 3) throw PlatformException(code: 'unavailable');
            return frames;
          });
      final editor = VideoEditor(File('/tmp/filmstrip.mp4'), 10000);
      final loading = editor.thumbnails();
      expect(identical(loading, editor.thumbnails()), isTrue);
      final result = await loading;
      expect(calls, hasLength(8));
      expect(result.whereType<Uint8List>(), hasLength(7));
      expect(result[2], isNull);
      expect(calls.first['timeMs'], 0);
      expect(calls.last['timeMs'], 9999);
      expect(calls.map((c) => c['timeMs']).toSet(), hasLength(8));
      for (final call in calls) {
        expect(call['video'], '/tmp/filmstrip.mp4');
        expect(call['maxh'], 96);
        expect(call['quality'], 65);
      }
      await editor.thumbnails();
      expect(calls, hasLength(8));
      await editor.dispose();
    },
  );
  test(
    'leaving review stops scheduling additional frames and empty videos do not request frames',
    () async {
      final pending = Completer<Uint8List>();
      var calls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(thumbnailChannel, (call) async {
            calls++;
            return pending.future;
          });
      final editor = VideoEditor(File('/tmp/filmstrip.mp4'), 10000);
      final loading = editor.thumbnails();
      await Future<void>.delayed(Duration.zero);
      await editor.dispose();
      pending.complete(frames);
      await loading;
      expect(calls, 1);
      final empty = VideoEditor(File('/tmp/empty.mp4'), 0);
      expect(
        (await empty.thumbnails()).every((frame) => frame == null),
        isTrue,
      );
      expect(calls, 1);
      await empty.dispose();
    },
  );

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'filmstrip handles drag independently, retain sound and fit a narrow phone at scale $scale',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var edits = const VideoEdits(startMs: 0, endMs: 10000, muted: true);
        var enabled = true;
        var position = 0;
        final seeks = <int>[];
        late StateSetter update;
        final thumbnails = Future.value(List<Uint8List?>.filled(8, frames));
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.build(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: Center(
                child: StatefulBuilder(
                  builder: (_, set) {
                    update = set;
                    return VideoAdjustmentsPanel(
                      edits: edits,
                      durationMs: 10000,
                      thumbnails: thumbnails,
                      positionMs: position,
                      onSeek: (value) => set(() {
                        position = value;
                        seeks.add(value);
                      }),
                      enabled: enabled,
                      onChanged: (value) => set(() => edits = value),
                      onDone: () {},
                    );
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(Image), findsNWidgets(8));
        final strip = tester.getRect(
          find.byKey(const ValueKey('video_trim_timeline')),
        );
        final trackWidth = strip.width - 48;
        await tester.dragFrom(
          Offset(strip.left + 24, strip.center.dy),
          Offset(trackWidth * .2, 0),
        );
        await tester.pumpAndSettle();
        expect(edits.startMs, closeTo(2000, 100));
        expect(edits.endMs, 10000);
        expect(edits.muted, isTrue);
        expect(seeks, isEmpty);
        await tester.dragFrom(
          Offset(strip.right - 24, strip.center.dy),
          Offset(-trackWidth * .2, 0),
        );
        await tester.pumpAndSettle();
        expect(edits.endMs, closeTo(8000, 100));
        expect(find.text('6.0s selected'), findsOneWidget);
        expect(seeks, isEmpty);
        final selected = edits;
        await tester.tapAt(
          Offset(strip.left + 24 + trackWidth * .5, strip.center.dy),
        );
        await tester.pumpAndSettle();
        expect(seeks, [5000]);
        expect(edits.sameAs(selected), isTrue);
        expect(
          tester
              .getCenter(find.byKey(const ValueKey('video_trim_playhead')))
              .dx,
          closeTo(strip.left + 24 + trackWidth * .5, .1),
        );
        final before = edits;
        update(() => enabled = false);
        await tester.pumpAndSettle();
        await tester.dragFrom(
          Offset(strip.left + 24 + trackWidth * .2, strip.center.dy),
          Offset(trackWidth * .2, 0),
        );
        await tester.pumpAndSettle();
        expect(edits.sameAs(before), isTrue);
        await tester.tapAt(
          Offset(strip.left + 24 + trackWidth * .5, strip.center.dy),
        );
        await tester.pumpAndSettle();
        expect(seeks, [5000]);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'trimming stays usable before frames arrive and when frame extraction fails',
    (tester) async {
      final pending = Completer<List<Uint8List?>>();
      var edits = const VideoEdits(startMs: 0, endMs: 1000);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (_, set) => VideoAdjustmentsPanel(
                edits: edits,
                durationMs: 1000,
                thumbnails: pending.future,
                onChanged: (value) => set(() => edits = value),
                onDone: () {},
              ),
            ),
          ),
        ),
      );
      expect(find.byType(Image), findsNothing);
      final slider = tester.widget<RangeSlider>(find.byType(RangeSlider));
      slider.onChanged!(const RangeValues(0, 500));
      await tester.pump();
      expect(edits.endMs, 500);
      pending.completeError(StateError('No frames'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<RangeSlider>(find.byType(RangeSlider)).onChanged,
        isNotNull,
      );
      expect(find.text('0.5s selected'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
