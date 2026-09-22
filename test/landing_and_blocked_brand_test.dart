import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/core/branding/mood_wink.dart';
import 'package:mooddare/core/widgets/mooddare_wordmark.dart';
import 'package:mooddare/features/auth/presentation/screens/auth_form_screen.dart';
import 'package:mooddare/features/auth/presentation/screens/welcome_screen.dart';
import 'package:mooddare/features/auth/presentation/widgets/welcome_artwork.dart';
import 'package:mooddare/features/profile/presentation/screens/blocked_accounts_screen.dart';
import 'entry_polish_test.dart' show mount, ProfileMemory;
import 'support/moments_fakes.dart';

class BlockedPosts extends MemoryPosts {
  BlockedPosts() : super([]);
  final changes = StreamController<Set<String>>();
  bool failUnblock = false;
  int unblocks = 0;
  @override
  Stream<Set<String>> blockedAuthors() => changes.stream;
  @override
  Future<void> unblockAuthor(String uid) async {
    unblocks++;
    if (failUnblock) throw StateError('offline');
    changes.add({});
  }
}

void main() {
  for (final size in [const Size(320, 640), const Size(840, 900)]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'landing adapts and both account paths work at $size, text $scale',
        (tester) async {
          await mount(tester, const WelcomeScreen(), size: size, scale: scale);
          final art = tester.getRect(find.byType(WelcomeArtwork));
          final title = tester.getRect(
            find.text('A little dare.\nA great story.'),
          );
          final brand = tester.getRect(find.byType(MoodDareWordmark));
          expect(brand.left, closeTo(title.left, .1));
          expect(brand.width, lessThanOrEqualTo(180));
          if (size.width >= 760) {
            expect(art.right, lessThan(title.left));
          } else {
            expect(art.bottom, lessThan(title.top));
          }
          expect(find.byType(MoodWink), findsNWidgets(3));
          expect(find.text('Explore as a guest'), findsNothing);
          for (final signup in [true, false]) {
            final button = find.text(
              signup ? 'Find your next dare' : 'I already have an account',
            );
            await tester.ensureVisible(button);
            await tester.pumpAndSettle();
            await tester.tap(button);
            await tester.pumpAndSettle();
            expect(
              tester.widget<AuthFormScreen>(find.byType(AuthFormScreen)).signUp,
              signup,
            );
            await tester.pageBack();
            await tester.pumpAndSettle();
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'blocked-list expression distinguishes empty, error and real accounts; unblock remains retryable',
    (tester) async {
      final repo = BlockedPosts()..changes.add({});
      addTearDown(repo.changes.close);
      addTearDown(repo.commentChanges.close);
      await mount(
        tester,
        BlockedAccountsScreen(repository: repo, users: ProfileMemory()),
      );
      expect(find.text('No blocked accounts'), findsOneWidget);
      expect(
        tester.widget<MoodWink>(find.byType(MoodWink)).expression,
        MoodWinkExpression.angrySmile,
      );
      repo.changes.addError(StateError('offline'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<MoodWink>(find.byType(MoodWink)).expression,
        MoodWinkExpression.error,
      );
      repo.changes.add({'alice'});
      await tester.pumpAndSettle();
      expect(find.byType(MoodWink), findsNothing);
      expect(find.text('@moodfriend'), findsOneWidget);
      repo.failUnblock = true;
      await tester.tap(find.text('Unblock'));
      await tester.pumpAndSettle();
      expect(find.text('Could not unblock. Please try again.'), findsOneWidget);
      expect(find.text('Unblock'), findsOneWidget);
      repo.failUnblock = false;
      await tester.tap(find.text('Unblock'));
      await tester.pumpAndSettle();
      expect(repo.unblocks, 2);
      expect(find.text('No blocked accounts'), findsOneWidget);
      expect(
        tester.widget<MoodWink>(find.byType(MoodWink)).expression,
        MoodWinkExpression.angrySmile,
      );
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'angry smile changes only the eyes and preserves the familiar silhouette and mouth',
    () {
      final original = MoodWinkGeometry.path(0);
      final angry = MoodWinkGeometry.path(
        1,
        expression: MoodWinkExpression.angrySmile,
      );
      expect(angry.getBounds(), original.getBounds());
      var changed = 0;
      for (var y = 0; y < 100; y++) {
        for (var x = 0; x < 100; x++) {
          final point = Offset(x + .5, y + .5);
          if (original.contains(point) != angry.contains(point)) {
            changed++;
            expect(x, inInclusiveRange(21, 80));
            expect(y, inInclusiveRange(28, 60));
          }
        }
      }
      expect(changed, greaterThan(100));
    },
  );
}
