import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/core/app_theme.dart';
import 'package:mooddare/features/feed/domain/post_error_message.dart';
import 'package:mooddare/features/feed/data/repositories/post_repository.dart';
import 'package:mooddare/features/feed/presentation/screens/preview_screen.dart';
import 'photo_cropping_test.dart' show fixture, ready;

class DeniedPosts implements PostRepository {
  int attempts = 0;
  bool denied = true;
  final ids = <String?>[];
  @override
  Future<void> createPost({
    required String dareText,
    required File mediaFile,
    required String mediaType,
    String? postId,
    String? moodId,
    String? moodName,
    String? weeklyDareId,
  }) async {
    attempts++;
    ids.add(postId);
    if (denied) {
      throw FirebaseException(
        plugin: 'firebase_storage',
        code: 'unauthorized',
        message: 'private storage path',
      );
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'permission failures do not blame connection or expose server details',
    () {
      for (final code in [
        'unauthorized',
        'storage/unauthorized',
        'permission-denied',
      ]) {
        final text = postErrorMessage(
          FirebaseException(
            plugin: 'firebase_storage',
            code: code,
            message: 'private-path',
          ),
        );
        expect(text, contains('upload was blocked'));
        expect(text, isNot(contains('connection')));
        expect(text, isNot(contains('private-path')));
      }
    },
  );
  test(
    'network, session, quota, cancellation, validation and unknown failures have useful messages',
    () {
      for (final entry in {
        'unavailable': 'connection',
        'retry-limit-exceeded': 'connection',
        'network-request-failed': 'connection',
        'unauthenticated': 'sign in',
        'quota-exceeded': 'temporarily unavailable',
        'canceled': 'cancelled',
        'cancelled': 'cancelled',
        'unknown': 'capture is still here',
      }.entries) {
        expect(
          postErrorMessage(
            FirebaseException(plugin: 'firebase_storage', code: entry.key),
          ),
          contains(entry.value),
        );
      }
      expect(
        postErrorMessage(const SocketException('offline')),
        contains('connection'),
      );
      expect(
        postErrorMessage(
          const FormatException('Choose a capture smaller than 30 MB.'),
        ),
        'Choose a capture smaller than 30 MB.',
      );
      expect(
        postErrorMessage(StateError('private detail')),
        isNot(contains('private detail')),
      );
    },
  );
  testWidgets('denied upload keeps capture and retry uses the same post ID', (
    tester,
  ) async {
    final temp = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('mooddare-post-error-'),
    ))!;
    final original = (await tester.runAsync(
      () => File('${temp.path}/capture.png').writeAsBytes(fixture()),
    ))!;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => temp.path,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('mooddare/beauty'),
      (_) async => null,
    );
    addTearDown(() async {
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        null,
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('mooddare/beauty'),
        null,
      );
      await temp.delete(recursive: true);
    });
    final repo = DeniedPosts();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        home: PreviewScreen(
          mediaFile: original,
          mediaType: 'image',
          dareText: 'Test dare',
          repository: repo,
        ),
      ),
    );
    await ready(
      tester,
      () => find.byKey(const ValueKey('capture_preview')).evaluate().isNotEmpty,
    );
    await tester.tap(find.text('Post dare'));
    await ready(
      tester,
      () => find
          .text(
            'Your upload was blocked. Please try again later or contact support.',
          )
          .evaluate()
          .isNotEmpty,
    );
    expect(find.byKey(const ValueKey('capture_preview')), findsOneWidget);
    expect(await tester.runAsync(original.readAsBytes), fixture());
    repo.denied = false;
    await tester.tap(find.text('Post dare'));
    await ready(tester, () => repo.attempts == 2);
    expect(repo.ids[0], isNotNull);
    expect(repo.ids[1], repo.ids[0]);
    await tester.pumpWidget(const SizedBox());
  });
}
