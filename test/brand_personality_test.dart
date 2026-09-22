import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/core/app_theme.dart';
import 'package:mooddare/core/branding/mood_wink.dart';
import 'package:mooddare/core/widgets/mooddare_brand_header.dart';
import 'package:mooddare/core/widgets/mooddare_wordmark.dart';
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
        expression: MoodWinkExpression.noResults,
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
          expression: MoodWinkExpression.noResults,
        ).shouldRepaint(const MoodWinkPainter(wink: 1, color: AppTheme.accent)),
        isTrue,
      );
    },
  );
}
