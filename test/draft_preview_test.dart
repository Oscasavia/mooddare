import 'package:mooddare/models/post_model.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/core/app_theme.dart';
import 'package:mooddare/features/drafts/data/capture_draft.dart';
import 'package:mooddare/features/drafts/data/draft_repository.dart';
import 'package:mooddare/features/drafts/presentation/drafts_screen.dart';
import 'package:mooddare/features/feed/presentation/screens/preview_screen.dart';
import 'package:mooddare/features/profile/presentation/widgets/my_dares_grid.dart';
import 'package:mooddare/features/camera/domain/photo_processing.dart';
import 'package:mooddare/features/camera/presentation/photo_adjustments_panel.dart';
import 'photo_cropping_test.dart' show fixture, ready, preview;
import 'post_error_message_test.dart' show DeniedPosts;
import 'support/moments_fakes.dart' show MemoryPosts;

class DraftPosts extends MemoryPosts {
  DraftPosts() : super([]);
  @override
  Stream<List<PostModel>> getUserPosts(String uid) => Stream.value([]);
}

class FailingDrafts extends DraftRepository {
  bool fail = false;
  FailingDrafts({required super.currentUserId, required super.directory});
  @override
  Future<void> save(CaptureDraft draft) {
    if (fail) {
      return Future.error(const FileSystemException('Storage unavailable'));
    }
    return super.save(draft);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late File capture;
  late FailingDrafts drafts;
  String? uid = 'alice';
  setUp(() async {
    uid = 'alice';
    dir = await Directory.systemTemp.createTemp('draft-preview-');
    capture = await File('${dir.path}/capture.png').writeAsBytes(fixture());
    drafts = FailingDrafts(
      currentUserId: () => uid,
      directory: () async => dir,
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => dir.path,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('mooddare/beauty'),
      (_) async => null,
    );
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });
  Future<void> open(
    WidgetTester tester, {
    CaptureDraft? draft,
    DeniedPosts? posts,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PreviewScreen(
                    mediaFile: draft?.mediaFile ?? capture,
                    mediaType: 'image',
                    dareText: 'Take a deep breath',
                    moodId: 'relaxed',
                    moodName: 'Relaxed',
                    drafts: drafts,
                    draft: draft,
                    repository: posts,
                  ),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pump();
    await ready(
      tester,
      () => find.byKey(const ValueKey('capture_preview')).evaluate().isNotEmpty,
    );
  }

  Future<List<CaptureDraft>> saved(WidgetTester tester) async =>
      (await tester.runAsync(() => drafts.list('alice')))!;
  testWidgets(
    'capture is recoverable; back keeps editing or saves with crop and adjustments intact',
    (tester) async {
      await open(tester);
      expect(await saved(tester), hasLength(1));
      final panel = find.byType(
        PhotoAdjustmentsPanel,
      ); // Controls stay on the existing adjustment wheel.
      await tester.tap(find.byTooltip('Adjust photo'));
      await tester.pumpAndSettle();
      tester
          .widget<PhotoAdjustmentsPanel>(panel)
          .onChanged(const PhotoAdjustments(warmth: .6));
      await tester.pump(const Duration(milliseconds: 500));
      await ready(
        tester,
        () =>
            tester
                .widget<FilledButton>(
                  find
                      .ancestor(
                        of: find.text('Post dare'),
                        matching: find.byWidgetPredicate(
                          (w) => w is FilledButton,
                        ),
                      )
                      .first,
                )
                .onPressed !=
            null,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Crop photo'));
      await ready(
        tester,
        () =>
            find.byKey(const ValueKey('crop_selection')).evaluate().isNotEmpty,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Square'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await ready(
        tester,
        () =>
            find.byKey(const ValueKey('crop_selection')).evaluate().isEmpty &&
            find.byType(LinearProgressIndicator).evaluate().isEmpty,
      );
      await tester.pumpAndSettle();
      final bytes = preview(tester);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Keep this moment?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.byType(PreviewScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save draft'));
      await ready(tester, () => find.byType(PreviewScreen).evaluate().isEmpty);
      final draft = (await saved(tester)).single;
      expect(draft.adjustments.warmth, .6);
      expect(draft.crop.width, lessThan(1));
      await tester.pumpWidget(const SizedBox());
      await open(tester, draft: draft);
      expect(preview(tester), bytes);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await ready(tester, () => find.byType(PreviewScreen).evaluate().isEmpty);
      expect(await saved(tester), isEmpty);
    },
  );
  testWidgets(
    'failed posting preserves draft; restored retry uses the same post ID and clears it after success',
    (tester) async {
      final posts = DeniedPosts();
      await open(tester, posts: posts);
      final id = (await saved(tester)).single.id;
      await tester.tap(find.text('Post dare'));
      await ready(tester, () => posts.attempts == 1);
      await tester.pumpAndSettle();
      expect(await saved(tester), hasLength(1));
      final draft = (await saved(tester)).single;
      await tester.pumpWidget(const SizedBox());
      posts.denied = false;
      await open(tester, draft: draft, posts: posts);
      await tester.tap(find.text('Post dare'));
      await ready(tester, () => find.byType(PreviewScreen).evaluate().isEmpty);
      expect(posts.ids, [id, id]);
      expect(await saved(tester), isEmpty);
    },
  );
  testWidgets('failed draft save keeps the editor open for recovery', (
    tester,
  ) async {
    await open(tester);
    drafts.fail = true;
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save draft'));
    await ready(
      tester,
      () => find
          .text(
            'Could not save this draft. Check device storage and try again.',
          )
          .evaluate()
          .isNotEmpty,
    );
    expect(find.byType(PreviewScreen), findsOneWidget);
    expect(await saved(tester), hasLength(1));
    drafts.fail = false;
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save draft'));
    await ready(tester, () => find.byType(PreviewScreen).evaluate().isEmpty);
    expect(await saved(tester), hasLength(1));
  });
  testWidgets(
    'only own profile with drafts has a tile, and its list can delete with confirmation',
    (tester) async {
      await tester.runAsync(
        () => drafts.save(
          CaptureDraft(
            id: 'draft',
            ownerId: 'alice',
            mediaFile: capture,
            mediaType: 'image',
            dareText: 'Take a deep breath',
            updatedAt: DateTime.now(),
          ),
        ),
      );
      final posts = DraftPosts();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(),
          home: Scaffold(
            body: MyDaresGrid(
              userId: 'alice',
              repository: posts,
              drafts: drafts,
            ),
          ),
        ),
      );
      await ready(tester, () => find.text('Drafts · 1').evaluate().isNotEmpty);
      await tester.tap(find.text('Drafts · 1'));
      await tester.pump();
      await ready(
        tester,
        () => find.text('Take a deep breath').evaluate().isNotEmpty,
      );
      expect(find.byType(DraftsScreen), findsOneWidget);
      await tester.tap(find.byTooltip('Draft options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete draft'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(await saved(tester), hasLength(1));
      await tester.tap(find.byTooltip('Draft options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete draft'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await ready(
        tester,
        () => find.text('Room for your next moment').evaluate().isNotEmpty,
      );
      expect(await saved(tester), isEmpty);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MyDaresGrid(userId: 'other', repository: posts),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Drafts ·'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
