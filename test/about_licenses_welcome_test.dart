import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/core/app_theme.dart';
import 'package:mooddare/features/auth/presentation/widgets/welcome_arrow.dart';
import 'package:mooddare/features/settings/presentation/about_screen.dart';
import 'package:mooddare/features/settings/presentation/licenses_screen.dart';
import 'entry_polish_test.dart' show mount;
import 'settings_test.dart' show openSettings;
import 'support/settings_fakes.dart';

class UnavailableVersion extends MemorySettings {
  @override
  Future<String> version() async => throw StateError('not available');
}

class Notice extends LicenseEntry {
  @override
  Iterable<String> get packages => ['Alpha', 'shared'];
  @override
  Iterable<LicenseParagraph> get paragraphs => const [
    LicenseParagraph(
      'Copyright notice retained',
      LicenseParagraph.centeredIndent,
    ),
    LicenseParagraph('Permission and attribution retained.', 1),
    LicenseParagraph('FULL DISCLAIMER RETAINED.', 0),
  ];
}

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets('About fits a narrow phone with text scale $scale', (
      tester,
    ) async {
      await mount(
        tester,
        const AboutScreen(),
        size: const Size(320, 640),
        scale: scale,
      );
      await tester.scrollUntilVisible(
        find.text('Stay curious. Be kind. Dare a little.'),
        200,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(AboutDialog), findsNothing);
    });

    testWidgets(
      'licenses search, shared notices, details and back retain data at scale $scale',
      (tester) async {
        var loads = 0;
        await mount(
          tester,
          LicensesScreen(
            loadLicenses: () {
              loads++;
              return Stream.fromIterable([
                LicenseEntryWithLineBreaks(['Zebra'], 'Zebra notice'),
                Notice(),
                LicenseEntryWithLineBreaks(['Alpha'], 'Second complete notice'),
              ]);
            },
          ),
          size: const Size(320, 700),
          scale: scale,
        );
        await tester.ensureVisible(find.byType(TextField));
        await tester.enterText(find.byType(TextField), ' ALPHA ');
        await tester.pumpAndSettle();
        expect(find.text('Zebra'), findsNothing);
        expect(find.text('2 notices'), findsOneWidget);
        await tester.ensureVisible(find.text('Alpha'));
        await tester.tap(find.text('Alpha'));
        await tester.pumpAndSettle();
        expect(find.byType(SelectionArea), findsOneWidget);
        expect(find.text('Copyright notice retained'), findsOneWidget);
        expect(
          tester.widget<Text>(find.text('Copyright notice retained')).textAlign,
          TextAlign.center,
        );
        await tester.scrollUntilVisible(
          find.text('Second complete notice'),
          160,
        );
        expect(find.text('FULL DISCLAIMER RETAINED.'), findsOneWidget);
        expect(find.text('Second complete notice'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<EditableText>(find.byType(EditableText))
              .controller
              .text,
          ' ALPHA ',
        );
        expect(find.text('Zebra'), findsNothing);
        await tester.ensureVisible(find.byType(TextField));
        await tester.enterText(find.byType(TextField), 'shared');
        await tester.pumpAndSettle();
        expect(find.text('1 notice'), findsOneWidget);
        await tester.enterText(find.byType(TextField), 'absent');
        await tester.pumpAndSettle();
        expect(find.text('No matching licenses'), findsOneWidget);
        await tester.enterText(find.byType(TextField), '');
        await tester.pumpAndSettle();
        expect(find.text('Alpha'), findsOneWidget);
        expect(loads, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('license load failure retries through loading and empty states', (
    tester,
  ) async {
    var calls = 0;
    final gate = Completer<void>();
    Stream<LicenseEntry> load() async* {
      calls++;
      if (calls == 1) throw StateError('failed');
      await gate.future;
    }

    await mount(tester, LicensesScreen(loadLicenses: load));
    expect(find.text('Could not load licenses'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Could not load licenses'), findsNothing);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('No matching licenses'), findsOneWidget);
    expect(calls, 2);
  });

  testWidgets('unavailable version stays safely below account actions', (
    tester,
  ) async {
    await openSettings(tester, UnavailableVersion());
    await tester.scrollUntilVisible(find.text('Version unavailable'), 240);
    expect(find.text('Version unavailable'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'arrow nudges right, returns to rest and respects reduced motion changes',
    (tester) async {
      Future<void> render({bool reduced = false, bool accessible = false}) =>
          tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.build(),
              home: MediaQuery(
                data: MediaQueryData(
                  disableAnimations: reduced,
                  accessibleNavigation: accessible,
                ),
                child: const Scaffold(body: WelcomeArrow()),
              ),
            ),
          );
      double x() => tester
          .widget<Transform>(
            find.descendant(
              of: find.byType(WelcomeArrow),
              matching: find.byType(Transform),
            ),
          )
          .transform
          .storage[12];
      await render();
      expect(x(), 0);
      await tester.pump(const Duration(milliseconds: 225));
      expect(x(), greaterThan(0));
      await tester.pumpAndSettle();
      expect(x(), closeTo(0, .001));
      await tester.pumpWidget(const SizedBox());
      await render(reduced: true);
      await tester.pump(const Duration(milliseconds: 225));
      expect(x(), closeTo(0, .001));
      expect(tester.binding.hasScheduledFrame, isFalse);
      await tester.pumpWidget(const SizedBox());
      await render();
      await tester.pump(const Duration(milliseconds: 225));
      await render(accessible: true);
      expect(x(), closeTo(0, .001));
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
}
