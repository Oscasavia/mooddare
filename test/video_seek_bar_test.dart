import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/features/feed/presentation/video_sound.dart';
import 'moments_test.dart' show openFeed, tapMedia;
import 'support/moments_fakes.dart';

class SeekVideo extends MemoryVideo {
  final positions = <int, Duration>{};
  final seeks = <Duration>[];
  Completer<void>? gate;
  bool fail = false;
  @override
  Future<void> seekTo(int playerId, Duration position) async {
    seeks.add(position);
    await gate?.future;
    if (fail) throw StateError('Seek failed');
    positions[playerId] = position;
  }

  @override
  Future<Duration> getPosition(int playerId) async =>
      positions[playerId] ?? Duration.zero;
}

void main() {
  final bar = find.byKey(const ValueKey('video_progress'));
  late SeekVideo video;
  setUp(() {
    video = SeekVideo();
    videoMuted.value = true;
  });
  Future<void> open(WidgetTester tester) async {
    await openFeed(
      tester,
      MemoryPosts([moment('video', type: 'video')]),
      video: video,
    );
    expect(bar, findsNothing);
    await tapMedia(tester);
    expect(bar, findsOneWidget);
  }

  Future<void> seek(WidgetTester tester, double value) async {
    final slider = tester.widget<Slider>(bar);
    slider.onChangeStart!(value);
    slider.onChanged!(value);
    slider.onChangeEnd!(value);
    await tester.pump();
  }

  testWidgets(
    'thin full-screen progress track seeks by touch and preserves mute/playback',
    (tester) async {
      await open(tester);
      final theme = SliderTheme.of(tester.element(bar));
      expect(theme.trackHeight, 2);
      final bounds = tester.getRect(bar);
      expect(bounds.height, greaterThanOrEqualTo(48));
      await tester.tapAt(
        Offset(bounds.left + bounds.width * .75, bounds.center.dy),
      );
      await tester.pumpAndSettle();
      expect(video.seeks.last.inMilliseconds, closeTo(7500, 400));
      expect(video.playing[1], isFalse);
      expect(video.playing[2], isTrue);
      expect(video.volumes[2], 0);
      await tester.drag(bar, const Offset(-100, 0));
      await tester.pumpAndSettle();
      expect(video.seeks.last.inMilliseconds, lessThan(7500));
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(bar, findsNothing);
      expect(video.playing[1], isTrue);
    },
  );
  testWidgets(
    'seeking a user-paused video stays paused and errors can be retried',
    (tester) async {
      await open(tester);
      await tapMedia(tester);
      expect(video.playing[2], isFalse);
      await seek(tester, 4000);
      await tester.pumpAndSettle();
      expect(video.playing[2], isFalse);
      video.fail = true;
      await seek(tester, 6000);
      await tester.pumpAndSettle();
      expect(
        find.text('Could not seek this video. Try again.'),
        findsOneWidget,
      );
      video.fail = false;
      await seek(tester, 8000);
      await tester.pumpAndSettle();
      expect(video.positions[2], const Duration(seconds: 8));
      expect(video.playing[2], isFalse);
    },
  );
  testWidgets(
    'rapid seeks serialize and do not resume behind comments or in background',
    (tester) async {
      await open(tester);
      video.gate = Completer<void>();
      await seek(tester, 2000);
      await seek(tester, 4000);
      await seek(tester, 7000);
      expect(video.seeks, [const Duration(seconds: 2)]);
      expect(video.playing[2], isFalse);
      await tester.tap(find.byTooltip('Comments'));
      await tester.pumpAndSettle();
      video.gate!.complete();
      await tester.pumpAndSettle();
      expect(video.seeks, [
        const Duration(seconds: 2),
        const Duration(seconds: 7),
      ]);
      expect(video.playing[2], isFalse);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(video.playing[2], isTrue);
      video.gate = Completer<void>();
      await seek(tester, 5000);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      video.gate!.complete();
      await tester.pumpAndSettle();
      expect(video.playing[2], isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(video.playing[2], isTrue);
    },
  );
  testWidgets('leaving during seek never restarts the disposed player', (
    tester,
  ) async {
    await open(tester);
    video.gate = Completer<void>();
    await seek(tester, 5000);
    await tester.pageBack();
    await tester.pumpAndSettle();
    final lastPlay = video.calls.where((c) => c == 'play 2').length;
    video.gate!.complete();
    await tester.pumpAndSettle();
    expect(video.calls.where((c) => c == 'play 2').length, lastPlay);
    expect(tester.takeException(), isNull);
  });
  testWidgets('photos and failed videos do not show a seek track', (
    tester,
  ) async {
    await openFeed(tester, MemoryPosts([moment('photo')]));
    await tapMedia(tester);
    expect(bar, findsNothing);
    await tester.pumpWidget(const SizedBox());
    await openFeed(
      tester,
      MemoryPosts([moment('bad', type: 'video')]),
      video: MemoryVideo(failToLoad: true),
    );
    await tapMedia(tester);
    expect(bar, findsNothing);
  });
}
