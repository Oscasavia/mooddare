import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mooddare/features/feed/presentation/video_sound.dart';
import 'package:mooddare/features/feed/presentation/widgets/comments_sheet.dart';
import 'package:mooddare/models/comment_model.dart';
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
  double textScale = 1,
  RouteFactory? onGenerateRoute,
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
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      navigatorObservers: [appRouteObserver],
      onGenerateRoute: onGenerateRoute,
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
  setUp(() => videoMuted.value = true);

  testWidgets('comments slide up from both surfaces, submit and delete', (
    tester,
  ) async {
    final repo = MemoryPosts([moment('comments')]);
    addTearDown(repo.commentChanges.close);
    await openFeed(tester, repo, size: const Size(344, 800));
    await tester.tap(find.byTooltip('Comments'));
    await tester.pumpAndSettle();
    expect(find.byType(CommentsSheet), findsOneWidget);
    expect(find.byType(PostDetailsScreen), findsNothing);
    expect(find.text('Start the conversation ✨'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (w) => w is IconButton && w.tooltip == 'Post comment',
            ),
          )
          .onPressed,
      isNull,
    );
    await tester.enterText(find.byType(TextField), '  Love this moment!  ');
    await tester.pump();
    await tester.tap(find.byTooltip('Post comment'));
    await tester.pumpAndSettle();
    expect(repo.comments.single.text, 'Love this moment!');
    expect(find.text('Love this moment!'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tapMedia(tester);
    await tester.tap(find.byTooltip('Comments'));
    await tester.pumpAndSettle();
    expect(find.text('Love this moment!'), findsOneWidget);
    await tester.tap(find.byTooltip('Comment options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete comment'));
    await tester.pumpAndSettle();
    expect(repo.comments, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed comment retains its draft and retry ID; load can retry', (
    tester,
  ) async {
    final repo = MemoryPosts([moment('retry')])..failComments = true;
    addTearDown(repo.commentChanges.close);
    await openFeed(tester, repo);
    await tester.tap(find.byTooltip('Comments'));
    await tester.pumpAndSettle();
    expect(find.text('Could not load comments. Retry'), findsOneWidget);
    repo.failComments = false;
    await tester.tap(find.text('Could not load comments. Retry'));
    await tester.pumpAndSettle();
    repo.failSending = true;
    await tester.enterText(find.byType(TextField), 'Keep my draft');
    await tester.pump();
    await tester.tap(find.byTooltip('Post comment'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Your draft is saved'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Keep my draft',
    );
    repo.failSending = false;
    await tester.tap(find.byTooltip('Post comment'));
    await tester.pumpAndSettle();
    expect(repo.submissions.length, 2);
    expect(repo.submissions[0], repo.submissions[1]);
    expect(repo.comments.length, 1);
  });

  testWidgets(
    'comments handle keyboard space and no delete option for other authors',
    (tester) async {
      final repo = MemoryPosts([moment('keyboard')]);
      repo.comments.add(
        const CommentModel(id: 'other', authorId: 'other', text: 'Hello!'),
      );
      addTearDown(repo.commentChanges.close);
      await openFeed(tester, repo, size: const Size(320, 700));
      await tester.tap(find.byTooltip('Comments'));
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'A reply');
      await tester.pump();
      expect(find.byTooltip('Comment options'), findsNothing);
      expect(
        tester.getBottomRight(find.byTooltip('Post comment')).dy,
        lessThanOrEqualTo(420),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'share invokes the native sheet in feed and viewer; errors recover',
    (tester) async {
      final calls = <MethodCall>[];
      const channel = MethodChannel('dev.fluttercommunity.plus/share');
      var failShare = false;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        if (failShare) throw PlatformException(code: 'unavailable');
        return 'dev.fluttercommunity.plus/share/dismissed';
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      final post = moment('share');
      await openFeed(tester, MemoryPosts([post]));
      await tester.tap(find.byTooltip('Share moment'));
      await tester.pumpAndSettle();
      expect(calls.single.arguments['text'], contains(post.mediaUrl));
      expect(calls.single.arguments['text'], contains(post.dareText));
      expect(find.byType(PostDetailsScreen), findsNothing);
      await tapMedia(tester);
      await tester.tap(find.byTooltip('Share moment'));
      await tester.pumpAndSettle();
      expect(calls.length, 2);
      failShare = true;
      await tester.tap(find.byTooltip('Share moment'));
      await tester.pumpAndSettle();
      expect(
        find.text('Could not open sharing. Please try again.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'mood filter queries chosen mood, excludes legacy posts and resets',
    (tester) async {
      final repo = MemoryPosts([
        moment('legacy'),
        moment('happy', moodId: 'happy', moodName: 'Happy'),
        moment('calm', moodId: 'calm', moodName: 'Calm'),
      ]);
      await openFeed(tester, repo);
      expect(find.byTooltip('Refresh feed'), findsNothing);
      await tester.tap(find.byTooltip('Filter by mood'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Happy'));
      await tester.pumpAndSettle();
      expect(repo.selectedMood, 'happy');
      expect(find.text('A moment worth sharing: happy'), findsOneWidget);
      expect(find.text('A moment worth sharing: legacy'), findsNothing);
      await tester.tap(find.byTooltip('Filter by mood'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('All moods'));
      await tester.pumpAndSettle();
      expect(repo.selectedMood, isNull);
      expect(find.text('A moment worth sharing: legacy'), findsOneWidget);
    },
  );

  testWidgets(
    'back refreshes to top, then exits even after waiting or a system swipe',
    (tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          calls.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final repo = MemoryPosts([moment('first'), moment('second')]);
      await openFeed(tester, repo);
      await tester.drag(find.byType(PageView), const Offset(0, -650));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(repo.reads, 2);
      expect(
        find.text('A moment worth sharing: first').hitTestable(),
        findsOneWidget,
      );
      expect(calls.where((c) => c.method == 'SystemNavigator.pop'), isEmpty);
      await tester.pump(const Duration(seconds: 5));
      // Android cancels the app pointer when it takes over an edge back swipe.
      final backSwipe = await tester.startGesture(const Offset(1, 300));
      await backSwipe.moveBy(const Offset(70, 0));
      await backSwipe.cancel();
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(repo.reads, 2);
      expect(calls.where((c) => c.method == 'SystemNavigator.pop').length, 1);

      // Reopening the app starts a fresh two-press sequence.
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(repo.reads, 3);
      await tester.tap(find.byTooltip('Filter by mood'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('All moods'), findsNothing);
      expect(repo.reads, 3);
      expect(calls.where((c) => c.method == 'SystemNavigator.pop').length, 1);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(repo.reads, 4);
      expect(calls.where((c) => c.method == 'SystemNavigator.pop').length, 1);

      // Continuing to browse disarms exit, so Back refreshes the feed again.
      await tester.drag(find.byType(PageView), const Offset(0, -650));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(repo.reads, 5);
      expect(calls.where((c) => c.method == 'SystemNavigator.pop').length, 1);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(repo.reads, 5);
      expect(calls.where((c) => c.method == 'SystemNavigator.pop').length, 2);
    },
  );

  testWidgets('sound starts muted and follows swipes, viewer and comments', (
    tester,
  ) async {
    final video = MemoryVideo();
    tester.view.padding = const FakeViewPadding(top: 60);
    addTearDown(tester.view.resetPadding);
    final repo = MemoryPosts([
      moment('v1', type: 'video'),
      moment('v2', type: 'video'),
    ]);
    addTearDown(repo.commentChanges.close);
    await openFeed(tester, repo, video: video);
    expect(video.volumes[1], 0);
    expect(
      video.calls.indexOf('volume 1 0.0'),
      lessThan(video.calls.indexOf('play 1')),
    );
    await tester.tap(find.byTooltip('Unmute video'));
    await tester.pumpAndSettle();
    expect(video.volumes[1], 1);
    expect(find.byType(PostDetailsScreen), findsNothing);
    await tester.drag(find.byType(PageView), const Offset(0, -650));
    await tester.pumpAndSettle();
    final second = video.created;
    expect(video.volumes[second], 1);
    await tapMedia(tester);
    final detail = video.created;
    expect(video.volumes[detail], 1);
    await tester.tap(find.byTooltip('Mute video'));
    await tester.pumpAndSettle();
    expect(video.volumes[detail], 0);
    expect(video.volumes[second], 0);
    await tester.tap(find.byTooltip('Comments'));
    await tester.pumpAndSettle();
    expect(video.playing[detail], isFalse);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(video.playing[detail], isTrue);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(video.volumes[second], 0);
    expect(video.playing[second], isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pumpAndSettle();
    expect(video.playing, isEmpty);
  });

  testWidgets(
    'blocked comments stay hidden and unsigned viewers cannot submit',
    (tester) async {
      final repo = MemoryPosts([moment('blocked')])
        ..uid = null
        ..blocked = {'blocked'};
      repo.comments.addAll([
        const CommentModel(
          id: 'a',
          authorId: 'blocked',
          text: 'Hidden message',
        ),
        const CommentModel(id: 'b', authorId: 'other', text: 'Visible message'),
      ]);
      addTearDown(repo.commentChanges.close);
      await openFeed(tester, repo);
      await tester.tap(find.byTooltip('Comments'));
      await tester.pumpAndSettle();
      expect(find.text('Hidden message'), findsNothing);
      expect(find.text('Visible message'), findsOneWidget);
      expect(find.text('Sign in to join the conversation.'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    },
  );

  testWidgets('empty mood filter can return to all moments', (tester) async {
    final repo = MemoryPosts([moment('legacy')]);
    await openFeed(tester, repo);
    await tester.tap(find.byTooltip('Filter by mood'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Happy'));
    await tester.pumpAndSettle();
    expect(find.text('No moments in this mood yet'), findsOneWidget);
    await tester.tap(find.text('Show all moods'));
    await tester.pumpAndSettle();
    expect(repo.selectedMood, isNull);
    expect(find.text('A moment worth sharing: legacy'), findsOneWidget);
  });

  testWidgets('feed and comment composer fit narrow phones with large text', (
    tester,
  ) async {
    final repo = MemoryPosts([moment('accessible')])..failSending = true;
    addTearDown(repo.commentChanges.close);
    await openFeed(tester, repo, size: const Size(320, 700), textScale: 2);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Comments'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'A reply');
    await tester.pump();
    await tester.tap(find.byTooltip('Post comment'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Your draft is saved'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

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
    await tester.tap(find.byTooltip('Moment options'));
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
    await tester.tap(find.byTooltip('Moment options'));
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
        expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
        expect(find.byIcon(Icons.play_circle_outline), findsNothing);
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
