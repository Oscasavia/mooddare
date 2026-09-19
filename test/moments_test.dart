import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'dart:async';
import 'package:image/image.dart' as img;
import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/core/app_theme.dart';
import 'package:mooddare/core/navigation.dart';
import 'package:mooddare/features/feed/presentation/screens/feed_screen.dart';
import 'package:mooddare/features/feed/presentation/screens/post_details_screen.dart';
import 'package:mooddare/features/feed/presentation/widgets/dare_proof_card.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'support/moments_fakes.dart';
import 'support/fixture_images.dart';

Future<void> openFeed(
  WidgetTester tester,
  MemoryPosts repository, {
  MemoryVideo? video,
  Size size = const Size(390, 844),
}) async {
  final previous = VideoPlayerPlatform.instance;
  VideoPlayerPlatform.instance = video ?? MemoryVideo();
  addTearDown(() {
    VideoPlayerPlatform.instance = previous;
  });
  final previousImages = debugNetworkImageHttpClientProvider;
  final bytes = Uint8List.fromList(
    img.encodePng(img.Image(width: 40, height: 30)),
  );
  debugNetworkImageHttpClientProvider = () => FixtureImages(bytes);
  addTearDown(() {
    debugNetworkImageHttpClientProvider = previousImages;
    PaintingBinding.instance.imageCache.clear();
  });
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.runAsync(() async {
    for (final post in repository.posts.where(
      (post) => post.mediaType == 'image',
    )) {
      final done = Completer<void>();
      final stream = NetworkImage(
        post.mediaUrl,
      ).resolve(ImageConfiguration.empty);
      final listener = ImageStreamListener(
        (_, _) => done.complete(),
        onError: (Object error, StackTrace? trace) =>
            done.completeError(error, trace),
      );
      stream.addListener(listener);
      await done.future;
      stream.removeListener(listener);
    }
  });
  debugNetworkImageHttpClientProvider = previousImages;
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.build(),
      navigatorObservers: [appRouteObserver],
      home: FeedScreen(repository: repository),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> tapMedia(WidgetTester tester) async {
  // Tap above the caption and action buttons, inside the card's media surface.
  final bounds = tester.getRect(find.byType(DareProofCard).last);
  await tester.tapAt(
    Offset(bounds.center.dx, bounds.top + bounds.height * .35),
  );
  // A media tap waits briefly so the gesture recognizer can rule out double-tap like.
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'mooddare branding and a photo card open the profile viewer on one tap',
    (tester) async {
      final post = moment('photo');
      await openFeed(tester, MemoryPosts([post]));
      expect(find.text('mooddare'), findsOneWidget);
      expect(find.text('Little moments'), findsNothing);
      expect(tester.widget<Image>(find.byType(Image)).fit, BoxFit.cover);
      await tapMedia(tester);
      expect(find.byType(PostDetailsScreen), findsOneWidget);
      expect(
        tester.widget<PostDetailsScreen>(find.byType(PostDetailsScreen)).post,
        same(post),
      );
      expect(tester.widget<Image>(find.byType(Image)).fit, BoxFit.contain);
      await tapMedia(tester);
      expect(
        find.byType(PostDetailsScreen),
        findsOneWidget,
        reason: 'A viewer tap must not stack another viewer',
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('mooddare'), findsOneWidget);
      expect(find.byType(PostDetailsScreen), findsNothing);
    },
  );

  testWidgets('caption taps open the viewer; like and menu actions do not', (
    tester,
  ) async {
    final post = moment('caption');
    final repository = MemoryPosts([post]);
    await openFeed(tester, repository);
    await tester.tap(find.byTooltip('Like'));
    await tester.pumpAndSettle();
    expect(repository.likes, 1);
    expect(find.byType(PostDetailsScreen), findsNothing);
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Report moment'));
    await tester.pumpAndSettle();
    expect(repository.reports, 1);
    expect(find.byType(PostDetailsScreen), findsNothing);
    await tester.tap(find.text(post.dareText));
    await tester.pumpAndSettle();
    expect(find.byType(PostDetailsScreen), findsOneWidget);
  });

  testWidgets('double tap likes once without opening the viewer', (
    tester,
  ) async {
    final repository = MemoryPosts([moment('double')]);
    await openFeed(tester, repository);
    final surface = find.byKey(const ValueKey('moment_surface_double'));
    final point = tester.getRect(surface).topCenter + const Offset(0, 120);
    await tester.tapAt(point);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(point);
    await tester.pumpAndSettle();
    expect(repository.likes, 1);
    expect(find.byType(PostDetailsScreen), findsNothing);
  });

  testWidgets('vertical swipe changes moments without opening a viewer', (
    tester,
  ) async {
    await openFeed(tester, MemoryPosts([moment('first'), moment('second')]));
    await tester.drag(find.byType(PageView), const Offset(0, -650));
    await tester.pumpAndSettle();
    expect(find.byType(PostDetailsScreen), findsNothing);
    expect(
      find.text('A moment worth sharing: second').hitTestable(),
      findsOneWidget,
    );
  });

  testWidgets('hiding from the viewer closes it and removes that feed card', (
    tester,
  ) async {
    await openFeed(tester, MemoryPosts([moment('hide')]));
    await tapMedia(tester);
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hide for now'));
    await tester.pumpAndSettle();
    expect(find.byType(PostDetailsScreen), findsNothing);
    expect(find.text('The first moment could be yours'), findsOneWidget);
  });

  for (final dimensions in [
    const Size(720, 1280),
    const Size(1280, 720),
    const Size(900, 1200),
  ]) {
    testWidgets(
      'video $dimensions fills the card and transfers playback to the viewer',
      (tester) async {
        final video = MemoryVideo(size: dimensions);
        await openFeed(
          tester,
          MemoryPosts([moment('video', type: 'video')]),
          video: video,
        );
        expect(video.playing[1], isTrue);
        final card = tester.getRect(
          find.byKey(const ValueKey('moment_surface_video')),
        );
        final media = tester.getRect(find.byType(VideoPlayer));
        expect(media.width, greaterThanOrEqualTo(card.width - .01));
        expect(media.height, greaterThanOrEqualTo(card.height - .01));
        expect(media.center.dx, closeTo(card.center.dx, .01));
        expect(media.center.dy, closeTo(card.center.dy, .01));
        expect(
          media.width / media.height,
          closeTo(dimensions.aspectRatio, .001),
        );
        await tapMedia(tester);
        expect(video.created, 2);
        expect(video.playing[1], isFalse);
        expect(video.playing[2], isTrue);
        expect(
          tester.widget<FittedBox>(find.byType(FittedBox)).fit,
          BoxFit.contain,
        );
        await tapMedia(tester);
        expect(video.playing[2], isFalse);
        expect(find.byIcon(Icons.play_circle_outline), findsOneWidget);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(
          video.playing[2],
          isFalse,
          reason: 'A manually paused video stays paused after an interruption',
        );
        await tapMedia(tester);
        expect(video.playing[2], isTrue);
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.byType(PostDetailsScreen), findsNothing);
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
        expect(video.playing.containsKey(2), isFalse, reason: '${video.calls}');
        expect(video.playing[1], isTrue);
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pumpAndSettle();
        expect(video.playing, isEmpty);
      },
    );
  }
}
