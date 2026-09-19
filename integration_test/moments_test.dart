import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:mooddare/core/app_theme.dart';
import 'package:mooddare/core/navigation.dart';
import 'package:mooddare/features/feed/presentation/video_sound.dart';
import 'package:mooddare/features/feed/presentation/screens/feed_screen.dart';
import 'package:mooddare/features/feed/presentation/screens/post_details_screen.dart';
import '../test/support/moments_fakes.dart' show MemoryPosts, moment;
import '../test/support/fixture_images.dart';
import 'face_fixture.dart';
import 'live_beauty_test.dart' show channel, waitForState;
import 'live_video_test.dart' show allowCameraAndAudio;

Future<void> waitForPlayer(WidgetTester tester) async {
  for (var i = 0; i < 100; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    final found = find.byType(VideoPlayer);
    if (found.evaluate().isNotEmpty &&
        tester.widget<VideoPlayer>(found).controller.value.isPlaying) {
      return;
    }
  }
  fail('The visible Moments video did not start');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'photo and native video fill feed cards and open the shared viewer',
    (tester) async {
      videoMuted.value = true;
      await allowCameraAndAudio();
      final bytes = base64Decode(faceFixtureBase64);
      final fixture = File(
        '${(await getTemporaryDirectory()).path}/moments-face.jpg',
      );
      await fixture.writeAsBytes(bytes);
      File? clip;
      final previousImages = debugNetworkImageHttpClientProvider;
      debugNetworkImageHttpClientProvider = () => FixtureImages(bytes);
      try {
        final session = await channel.invokeMapMethod<String, dynamic>(
          'startFixture',
          {'path': fixture.path, 'front': true},
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Texture(textureId: (session!['textureId'] as num).toInt()),
          ),
        );
        await waitForState(tester, (state) => state['ready'] == true);
        await channel.invokeMethod<void>('startRecording');
        await tester.pump(const Duration(seconds: 2));
        clip = File((await channel.invokeMethod<String>('stopRecording'))!);
        await channel.invokeMethod<void>('stop');
        final photo = moment('photo', url: 'https://fixture.invalid/photo.jpg');
        final video = moment('video', type: 'video', url: clip.uri.toString());
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.build(),
            navigatorObservers: [appRouteObserver],
            home: FeedScreen(repository: MemoryPosts([photo, video])),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('mooddare'), findsOneWidget);
        expect(tester.widget<Image>(find.byType(Image)).fit, BoxFit.cover);
        for (
          var i = 0;
          i < 50 && find.byType(RawImage).evaluate().isEmpty;
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
        await tester.tap(find.text(photo.dareText));
        await tester.pumpAndSettle();
        expect(find.byType(PostDetailsScreen), findsOneWidget);
        expect(tester.widget<Image>(find.byType(Image)).fit, BoxFit.contain);
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.drag(find.byType(PageView), const Offset(0, -650));
        await tester.pumpAndSettle();
        await waitForPlayer(tester);
        final feedPlayer = tester
            .widget<VideoPlayer>(find.byType(VideoPlayer))
            .controller;
        expect(feedPlayer.value.volume, 0);
        await tester.tap(find.byTooltip('Unmute video'));
        await tester.pumpAndSettle();
        expect(feedPlayer.value.volume, 1);
        final bounds = tester.getRect(
          find.byKey(const ValueKey('moment_surface_video')),
        );
        final mediaBounds = tester.getRect(find.byType(VideoPlayer));
        expect(mediaBounds.width, greaterThanOrEqualTo(bounds.width - 1));
        expect(mediaBounds.height, greaterThanOrEqualTo(bounds.height - 1));
        await tester.tap(find.text(video.dareText));
        await tester.pumpAndSettle();
        await waitForPlayer(tester);
        final detailPlayer = tester
            .widget<VideoPlayer>(find.byType(VideoPlayer))
            .controller;
        expect(identical(feedPlayer, detailPlayer), isFalse);
        expect(feedPlayer.value.isPlaying, isFalse);
        expect(detailPlayer.value.volume, 1);
        await tester.tap(find.byTooltip('Mute video'));
        await tester.pumpAndSettle();
        expect(detailPlayer.value.volume, 0);
        expect(feedPlayer.value.volume, 0);
        await tester.tap(find.byTooltip('Comments'));
        await tester.pumpAndSettle();
        expect(detailPlayer.value.isPlaying, isFalse);
        await tester.enterText(
          find.byType(TextField),
          'A native playback test',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Post comment'));
        await tester.pumpAndSettle();
        expect(find.text('A native playback test'), findsOneWidget);
        await tester.tap(find.byTooltip('Close comments'));
        await tester.pumpAndSettle();
        await waitForPlayer(tester);
        expect(find.byType(PostDetailsScreen), findsOneWidget);
        final position = detailPlayer.value.position;
        await tester.pump(const Duration(seconds: 1));
        expect(detailPlayer.value.hasError, isFalse);
        expect(detailPlayer.value.position, isNot(position));
        await tester.tapAt(tester.getCenter(find.byType(VideoPlayer)));
        await tester.pump(const Duration(milliseconds: 500));
        expect(detailPlayer.value.isPlaying, isFalse);
        await tester.pageBack();
        await tester.pumpAndSettle();
        await waitForPlayer(tester);
        expect(feedPlayer.value.isPlaying, isTrue);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const MaterialApp(home: SizedBox()));
        await tester.pump(const Duration(seconds: 1));
        debugNetworkImageHttpClientProvider = previousImages;
        PaintingBinding.instance.imageCache.clear();
        await channel.invokeMethod<void>('stop');
        if (clip != null && await clip.exists()) await clip.delete();
        await fixture.delete();
      }
    },
  );
}
