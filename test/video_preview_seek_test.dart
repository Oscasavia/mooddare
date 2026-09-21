import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:mooddare/features/feed/presentation/screens/preview_screen.dart';
import 'package:mooddare/features/camera/presentation/video_adjustments_panel.dart';
import 'support/moments_fakes.dart';

class SeekVideo extends MemoryVideo {
  final seeks = <int>[];
  int position = 0;
  bool fail = false;
  Completer<void>? gate;
  @override
  Future<void> seekTo(int playerId, Duration target) async {
    seeks.add(target.inMilliseconds);
    final pending = gate;
    gate = null;
    if (pending != null) await pending.future;
    if (fail) throw PlatformException(code: 'seek');
    position = target.inMilliseconds;
  }

  @override
  Future<Duration> getPosition(int playerId) async =>
      Duration(milliseconds: position);
}

void main() {
  late SeekVideo video;
  setUp(() {
    final previous = VideoPlayerPlatform.instance;
    video = SeekVideo();
    VideoPlayerPlatform.instance = video;
    addTearDown(() => VideoPlayerPlatform.instance = previous);
  });
  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PreviewScreen(
          mediaFile: File('/tmp/seek.mp4'),
          mediaType: 'video',
          dareText: 'Seek test',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit video'));
    await tester.pumpAndSettle();
  }

  Future<void> tapTime(WidgetTester tester, double fraction) async {
    final rect = tester.getRect(
      find.byKey(const ValueKey('video_trim_timeline')),
    );
    await tester.tapAt(
      Offset(rect.left + 24 + (rect.width - 48) * fraction, rect.center.dy),
    );
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  }

  testWidgets(
    'thumbnail taps pause on the requested frame without changing trim or mute, and playhead follows playback',
    (tester) async {
      await open(tester);
      tester.widget<RangeSlider>(find.byType(RangeSlider)).onChanged!(
        const RangeValues(2000, 8000),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Remove audio'));
      await tester.pumpAndSettle();
      final selected = tester
          .widget<VideoAdjustmentsPanel>(find.byType(VideoAdjustmentsPanel))
          .edits;
      await tapTime(tester, .5);
      expect(video.position, 5000);
      expect(video.playing[1], isFalse);
      expect(video.volumes[1], 0);
      expect(
        tester
            .widget<VideoAdjustmentsPanel>(find.byType(VideoAdjustmentsPanel))
            .edits
            .sameAs(selected),
        isTrue,
      );
      await tapTime(tester, .98);
      expect(video.position, 9800);
      final controller = tester
          .widget<VideoPlayer>(find.byType(VideoPlayer))
          .controller;
      expect(controller.value.position.inMilliseconds, 9800);
      await controller.play();
      await tester.pumpAndSettle();
      expect(
        video.position,
        2000,
        reason:
            'Playback returns to the selected clip after inspecting excluded footage',
      );
      video.position = 4500;
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(
        tester
            .widget<VideoAdjustmentsPanel>(find.byType(VideoAdjustmentsPanel))
            .positionMs,
        4500,
      );
      await close(tester);
    },
  );
  testWidgets(
    'rapid thumbnail taps keep the latest request while a decoder seek is pending',
    (tester) async {
      await open(tester);
      final pending = Completer<void>();
      video.gate = pending;
      await tapTime(tester, .3);
      await tapTime(tester, .5);
      await tapTime(tester, .7);
      expect(video.seeks, [3000]);
      pending.complete();
      await tester.pumpAndSettle();
      expect(video.seeks, [3000, 7000]);
      expect(video.position, 7000);
      await close(tester);
    },
  );
  testWidgets(
    'changing trim while a thumbnail seek is pending finishes at the new trim start',
    (tester) async {
      await open(tester);
      final pending = Completer<void>();
      video.gate = pending;
      await tapTime(tester, .7);
      tester.widget<RangeSlider>(find.byType(RangeSlider)).onChanged!(
        const RangeValues(1000, 4000),
      );
      await tester.pump();
      pending.complete();
      await tester.pumpAndSettle();
      expect(video.seeks, [7000, 1000]);
      expect(video.position, 1000);
      await close(tester);
    },
  );
  testWidgets(
    'failed preview seek can be retried and dismissal during a seek is safe',
    (tester) async {
      await open(tester);
      video.fail = true;
      await tapTime(tester, .5);
      expect(
        find.text('Could not preview that moment. Try again.'),
        findsOneWidget,
      );
      video.fail = false;
      await tapTime(tester, .7);
      expect(video.position, 7000);
      final pending = Completer<void>();
      video.gate = pending;
      await tapTime(tester, .4);
      await close(tester);
      pending.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
