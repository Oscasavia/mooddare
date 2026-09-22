import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/core/widgets/legal_notice.dart';
import 'package:mooddare/features/auth/presentation/screens/auth_form_screen.dart';
import 'package:mooddare/features/auth/presentation/screens/welcome_screen.dart';
import 'package:mooddare/features/auth/presentation/widgets/welcome_arrow.dart';
import 'package:mooddare/features/settings/presentation/legal_screen.dart';
import 'entry_polish_test.dart' show mount, EntryAuth;
import 'settings_test.dart' show openSettings, tapRow;
import 'support/settings_fakes.dart';

Future<void> tapPolicy(WidgetTester tester, String label) async {
  final notice = find.byType(LegalNotice);
  await tester.ensureVisible(notice);
  await tester.pumpAndSettle();
  final rich = find.descendant(of: notice, matching: find.byType(RichText));
  final paragraph = tester.renderObject<RenderParagraph>(rich);
  final text = paragraph.text.toPlainText();
  expect(
    text,
    'By continuing, you agree to our Terms of Use & Privacy Policy.',
  );
  final start = text.indexOf(label);
  expect(start, greaterThanOrEqualTo(0));
  final box = paragraph
      .getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: start + label.length),
      )
      .first;
  await tester.tapAt(paragraph.localToGlobal(box.toRect().center));
  await tester.pumpAndSettle();
}

void main() {
  for (final size in [const Size(320, 800), const Size(840, 900)]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'welcome centers its call to action and opens both policies at $size / $scale',
        (tester) async {
          await mount(tester, const WelcomeScreen(), size: size, scale: scale);
          final button = find.byKey(const ValueKey('welcome_get_started'));
          await tester.ensureVisible(button);
          await tester.pumpAndSettle();
          final buttonRect = tester.getRect(button);
          final text = find.descendant(
            of: find.text('Get started'),
            matching: find.byType(RichText),
          );
          final paragraph = tester.renderObject<RenderParagraph>(text);
          final boxes = paragraph.getBoxesForSelection(
            const TextSelection(baseOffset: 0, extentOffset: 11),
          );
          final glyphs = boxes
              .map((b) => b.toRect())
              .reduce((a, b) => a.expandToInclude(b));
          expect(
            paragraph.localToGlobal(glyphs.center).dx,
            closeTo(buttonRect.center.dx, 1),
          );
          final arrow = tester.getRect(find.byType(WelcomeArrow));
          expect(arrow.center.dx, greaterThan(buttonRect.center.dx));
          expect(arrow.right, lessThan(buttonRect.right));
          expect(find.byType(FilledButton), findsOneWidget);
          expect(find.byType(OutlinedButton), findsNothing);
          await tester.ensureVisible(find.byType(LegalNotice));
          await tester.pumpAndSettle();
          final notice = tester.getRect(find.byType(LegalNotice));
          expect(notice.bottom, closeTo(size.height - 16, 1));
          for (final privacy in [false, true]) {
            final label = privacy ? 'Privacy Policy' : 'Terms of Use';
            await tapPolicy(tester, label);
            expect(
              tester.widget<LegalScreen>(find.byType(LegalScreen)).document,
              privacy ? LegalDocument.privacy : LegalDocument.terms,
            );
            expect(find.byType(SelectionArea), findsOneWidget);
            await tester.scrollUntilVisible(
              find.text(privacy ? 'Policy updates' : 'Changes and questions'),
              350,
              maxScrolls: 200,
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await tester.pageBack();
            await tester.pumpAndSettle();
            expect(find.byType(WelcomeScreen), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final signup in [false, true]) {
    testWidgets(
      'policies open from ${signup ? 'signup' : 'login'} without submitting or losing the form',
      (tester) async {
        final repo = EntryAuth();
        await mount(tester, AuthFormScreen(signUp: signup, repository: repo));
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Email'),
          'friend@example.com',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Password'),
          'draft-password',
        );
        for (final label in ['Privacy Policy', 'Terms of Use']) {
          await tapPolicy(tester, label);
          expect(find.byType(LegalScreen), findsOneWidget);
          await tester.pageBack();
          await tester.pumpAndSettle();
          expect(find.text('friend@example.com'), findsOneWidget);
          expect(
            tester
                .widget<TextFormField>(
                  find.widgetWithText(TextFormField, 'Password'),
                )
                .controller!
                .text,
            'draft-password',
          );
        }
        expect(repo.googleCalls, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('settings exposes both policies above account actions', (
    tester,
  ) async {
    final repo = MemorySettings();
    await openSettings(tester, repo, scale: 2);
    for (final title in ['Privacy Policy', 'Terms of Use']) {
      await tapRow(tester, title);
      expect(find.byType(LegalScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
    await tester.scrollUntilVisible(find.text('Version 1.0.0 (42)'), 200);
    expect(
      tester.getTopLeft(find.text('Version 1.0.0 (42)')).dy,
      greaterThan(tester.getBottomLeft(find.text('Delete account')).dy),
    );
    expect(repo.signOuts + repo.deletions, 0);
    expect(tester.takeException(), isNull);
  });
}
