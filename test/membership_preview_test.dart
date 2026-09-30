import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/core/app_theme.dart';
import 'package:mooddare/features/camera/domain/beauty_lens.dart';
import 'package:mooddare/features/dares/data/repositories/dares_repository.dart';
import 'package:mooddare/features/dares/presentation/widgets/mood_preview.dart';
import 'package:mooddare/features/membership/membership_preview.dart';
import 'package:mooddare/features/profile/presentation/screens/settings_screen.dart';
import 'package:mooddare/models/mood_model.dart';
import 'support/settings_fakes.dart';

Future<void> openPreview(
  WidgetTester tester, {
  double width = 390,
  double scale = 1,
}) async {
  tester.view.physicalSize = Size(width, 850);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.build(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const MembershipPreviewScreen(),
              ),
            ),
            child: const Text('Open preview'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open preview'));
  await tester.pumpAndSettle();
}

Future<void> reveal(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

void main() {
  test('development access needs an explicit opt-in and a debug build', () {
    expect(
      membershipPreviewEnabled,
      kDebugMode && const bool.fromEnvironment('MOODDARE_MEMBERSHIP_PREVIEW'),
    );
  });
  for (final width in [320.0, 390.0, 768.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('comparison and controls fit $width at scale $scale', (
        tester,
      ) async {
        await openPreview(tester, width: width, scale: scale);
        for (final tier in MoodTier.values) {
          final chip = find.byKey(ValueKey('membership_${tier.name}'));
          await reveal(tester, chip);
          await tester.tap(chip);
          await tester.pumpAndSettle();
          expect(
            find.text(MembershipConcept.plans[tier]!.heading),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        }
        for (final label in [
          'At a glance',
          'Current lenses & My look',
          'Epic moods, new AR & profile colors',
          'Back to MoodDare',
        ]) {
          await reveal(tester, find.text(label));
          expect(tester.takeException(), isNull);
        }
        await tester.tap(find.text('Back to MoodDare'));
        await tester.pumpAndSettle();
        expect(find.text('Open preview'), findsOneWidget);
      });
    }
  }
  testWidgets(
    'tier and period changes are temporary and never grant access or change lenses',
    (tester) async {
      final lenses = [for (final lens in BeautyLens.all) lens.settings(1)];
      await openPreview(tester);
      final yearly = find.byKey(const ValueKey('membership_yearly'));
      await reveal(tester, yearly);
      await tester.tap(yearly);
      await tester.pumpAndSettle();
      expect(
        find.text('One payment per year · Pricing to come'),
        findsOneWidget,
      );
      final free = find.byKey(const ValueKey('membership_basic'));
      await reveal(tester, free);
      await tester.tap(free);
      await tester.pumpAndSettle();
      expect(find.text('No subscription needed.'), findsOneWidget);
      expect(yearly, findsNothing);
      final epic = find.byKey(const ValueKey('membership_epic'));
      await reveal(tester, epic);
      await tester.tap(epic);
      await tester.pumpAndSettle();
      expect(
        find.text('One payment per year · Pricing to come'),
        findsOneWidget,
      );
      expect(find.text('Everything in Daring'), findsOneWidget);
      for (final mood in DaresRepository.premiumPreviews) {
        expect(mood.isAvailable, isFalse);
        expect(mood.isLocked, isTrue);
      }
      expect([for (final lens in BeautyLens.all) lens.settings(1)], lenses);
      await reveal(tester, find.text('Back to MoodDare'));
      await tester.tap(find.text('Back to MoodDare'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open preview'));
      await tester.pumpAndSettle();
      expect(
        find.text('One payment per month · Pricing to come'),
        findsOneWidget,
      );
      expect(find.text('A little more adventure.'), findsOneWidget);
    },
  );
  testWidgets(
    'settings entry follows development gate and preserves account actions',
    (tester) async {
      final repo = MemorySettings();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(),
          home: SettingsScreen(repository: repo),
        ),
      );
      await tester.pumpAndSettle();
      final entry = find.text('Membership preview');
      expect(entry, membershipPreviewEnabled ? findsOneWidget : findsNothing);
      if (membershipPreviewEnabled) {
        await reveal(tester, entry);
        await tester.tap(entry);
        await tester.pumpAndSettle();
        expect(find.byType(MembershipPreviewScreen), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
      }
      expect(repo.deletions + repo.signOuts, 0);
    },
  );
  testWidgets(
    'locked mood entry follows gate, opens matching tier and returns to preview',
    (tester) async {
      final mood = DaresRepository.premiumPreviews.firstWhere(
        (m) => m.tier == MoodTier.epic,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(),
          home: Scaffold(
            body: SingleChildScrollView(child: MoodPreviewContent(mood: mood)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final entry = find.text('Preview membership ideas');
      expect(entry, membershipPreviewEnabled ? findsOneWidget : findsNothing);
      if (membershipPreviewEnabled) {
        await tester.tap(entry);
        await tester.pumpAndSettle();
        expect(find.text('Make it unmistakably you.'), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byType(MoodPreviewContent), findsOneWidget);
      }
      expect(mood.isAvailable, isFalse);
    },
  );
}
