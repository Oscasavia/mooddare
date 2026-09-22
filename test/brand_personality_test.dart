import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/core/app_theme.dart';
import 'package:mooddare/core/branding/mood_wink.dart';
import 'package:mooddare/core/widgets/mooddare_brand_header.dart';
import 'package:mooddare/core/widgets/mooddare_wordmark.dart';
import 'package:mooddare/core/widgets/app_empty_state.dart';
import 'package:mooddare/features/auth/presentation/screens/auth_form_screen.dart';
import 'package:mooddare/features/main/presentation/screens/main_screen.dart';
import 'entry_polish_test.dart' show EntryAuth, mount;

void main() {
  for (final signup in [false, true]) {
    for (final narrow in [false, true]) {
      testWidgets(
        'branded ${signup ? 'signup' : 'login'} remains usable ${narrow ? 'with keyboard and large text' : 'on an unfolded screen'}',
        (tester) async {
          final semantics = tester.ensureSemantics();
          await mount(
            tester,
            AuthFormScreen(signUp: signup, repository: EntryAuth()),
            scale: narrow ? 2 : 1,
            size: narrow ? const Size(320, 640) : const Size(800, 900),
          );
          final mascot = tester.getRect(find.byType(MoodWink));
          final wordmark = tester.getRect(find.byType(MoodDareWordmark));
          expect(mascot.center.dx, closeTo(wordmark.center.dx, .1));
          expect(wordmark.top, greaterThan(mascot.bottom));
          expect(mascot.width, lessThanOrEqualTo(64));
          expect(find.bySemanticsLabel('MoodDare'), findsOneWidget);
          semantics.dispose();
          final passwordButton = find.widgetWithText(
            FilledButton,
            signup ? 'Create account' : 'Sign in',
          );
          final divider = find.text('or');
          final googleButton = find.byKey(const ValueKey('google_sign_in'));
          expect(divider, findsOneWidget);
          expect(
            tester.getRect(divider).top,
            greaterThan(tester.getRect(passwordButton).bottom),
          );
          expect(
            tester.getRect(divider).bottom,
            lessThan(tester.getRect(googleButton).top),
          );
          final accountLink = find.text(
            signup
                ? 'Already a member? Sign in'
                : 'New here? Create an account',
          );
          expect(
            tester.getRect(accountLink).top,
            greaterThan(tester.getRect(googleButton).bottom),
          );
          final email = find.widgetWithText(TextFormField, 'Email');
          await tester.ensureVisible(email);
          await tester.enterText(email, 'invalid-email');
          if (narrow) {
            tester.view.viewInsets = const FakeViewPadding(bottom: 280);
            addTearDown(tester.view.resetViewInsets);
            await tester.pumpAndSettle();
          }
          final submit = find.widgetWithText(
            FilledButton,
            signup ? 'Create account' : 'Sign in',
          );
          await tester.ensureVisible(submit);
          await tester.pumpAndSettle();
          await tester.tap(submit);
          await tester.pumpAndSettle();
          expect(find.text('Enter a valid email'), findsOneWidget);
          expect(find.text('Enter your password'), findsOneWidget);
          final google = find.byKey(const ValueKey('google_sign_in'));
          await tester.ensureVisible(google);
          await tester.pumpAndSettle();
          expect(google.hitTestable(), findsOneWidget);
          expect(find.byType(MoodDareBrandHeader), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'Discover retains its navigation label and selected branded icon',
    (tester) async {
      await mount(tester, const MainScreen());
      final nav = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(nav.selectedIndex, 1);
      final discover = nav.destinations[1] as NavigationDestination;
      expect(discover.label, 'Discover');
      expect((discover.icon as MoodWink).wink, 0);
      expect((discover.selectedIcon as MoodWink).color, AppTheme.accent);
      expect(find.byIcon(Icons.explore), findsNothing);
      expect(find.text('Discover'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'x_x keeps the silhouette and cuts transparent crossed eyes and a flat mouth',
    () {
      final original = MoodWinkGeometry.path(1);
      final empty = MoodWinkGeometry.path(
        1,
        expression: MoodWinkExpression.error,
      );
      expect(empty.getBounds(), original.getBounds());
      for (final point in [
        const Offset(33, 44),
        const Offset(69, 41),
        const Offset(53, 73),
      ]) {
        expect(empty.contains(point), isFalse);
      }
      expect(empty.contains(const Offset(50, 20)), isTrue);
      expect(
        const MoodWinkPainter(
          wink: 1,
          color: AppTheme.accent,
          expression: MoodWinkExpression.error,
        ).shouldRepaint(const MoodWinkPainter(wink: 1, color: AppTheme.accent)),
        isTrue,
      );
    },
  );

  test('thinking uses distinct brows and eyes within the same silhouette', () {
    final thinking = MoodWinkGeometry.path(
      1,
      expression: MoodWinkExpression.thinking,
    );
    expect(thinking.getBounds(), MoodWinkGeometry.path(1).getBounds());
    for (final feature in [
      const Offset(36, 45),
      const Offset(71, 40),
      const Offset(69, 22),
      const Offset(49, 71),
    ]) {
      expect(thinking.contains(feature), isFalse);
    }
    expect(thinking.contains(const Offset(50, 55)), isTrue);
    expect(thinking.contains(const Offset(23, 44)), isTrue);
    expect(
      const MoodWinkPainter(
        wink: 1,
        color: AppTheme.accent,
        expression: MoodWinkExpression.thinking,
      ).shouldRepaint(
        const MoodWinkPainter(
          wink: 1,
          color: AppTheme.accent,
          expression: MoodWinkExpression.error,
        ),
      ),
      isTrue,
    );
  });

  testWidgets(
    'branded errors keep explanation and retry accessible on a short screen',
    (tester) async {
      var retries = 0;
      await mount(
        tester,
        Scaffold(
          body: AppEmptyState.error(
            title: 'Could not load moments',
            message: 'Check your connection and try again.',
            actionLabel: 'Retry',
            onAction: () => retries++,
          ),
        ),
        size: const Size(320, 300),
        scale: 2,
      );
      expect(
        tester.widget<MoodWink>(find.byType(MoodWink)).expression,
        MoodWinkExpression.error,
      );
      await tester.ensureVisible(find.text('Retry'));
      await tester.tap(find.text('Retry'));
      expect(retries, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
