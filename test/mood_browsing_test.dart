import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/core/app_theme.dart';
import 'package:mooddare/models/mood_model.dart';
import 'package:mooddare/features/dares/data/repositories/dares_repository.dart';
import 'package:mooddare/features/dares/presentation/screens/dares_screen.dart';
import 'package:mooddare/features/dares/presentation/screens/dare_generation_screen.dart';
import 'package:mooddare/features/dares/presentation/widgets/mood_preview.dart';
import 'mood_catalog_test.dart' show mood;

Future<void> openCatalog(
  WidgetTester tester, {
  Future<List<MoodModel>> Function()? load,
  Size size = const Size(400, 850),
  double scale = 1,
}) async {
  tester.view.physicalSize = size;
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
      home: DaresScreen(
        repository: DaresRepository(loadMoods: load ?? () async => []),
      ),
    ),
  );
  await tester.pump();
}

Future<void> choose(WidgetTester tester, String collection) async {
  final chip = find.byKey(ValueKey('collection_$collection'));
  await tester.ensureVisible(chip);
  await tester.tap(chip);
  await tester.pumpAndSettle();
  // ensureVisible also scrolls the outer list; return to the search header.
  tester
      .state<ScrollableState>(
        find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      )
      .position
      .jumpTo(0);
  await tester.pumpAndSettle();
}

void main() {
  for (final width in [320.0, 344.0, 390.0]) {
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets(
        'phone width $width keeps two playable columns at text scale $scale',
        (tester) async {
          await openCatalog(tester, size: Size(width, 800), scale: scale);
          final first = find.byKey(const ValueKey('mood_chill'));
          final second = find.byKey(const ValueKey('mood_creative'));
          await tester.scrollUntilVisible(
            first,
            160,
            scrollable: find
                .descendant(
                  of: find.byType(CustomScrollView),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          await tester.pumpAndSettle();
          final left = tester.getRect(first);
          final right = tester.getRect(second);
          expect(left.top, right.top);
          expect(left.right, lessThan(right.left));
          expect(right.right, lessThanOrEqualTo(width));
          expect(left.width, right.width);
          expect(tester.takeException(), isNull);
          await tester.tap(second);
          await tester.pumpAndSettle();
          expect(find.byType(DareDisplayScreen), findsOneWidget);
          expect(find.text('Creative'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'renamed packs use borderless pills and fields retain a visible focus fill',
    (tester) async {
      await openCatalog(tester);
      expect(find.text('Daring'), findsOneWidget);
      expect(find.text('Epic'), findsOneWidget);
      expect(find.text('Gold'), findsNothing);
      expect(find.text('Diamond'), findsNothing);
      final theme = Theme.of(tester.element(find.byType(TextField)));
      final decoration = theme.inputDecorationTheme;
      expect(decoration.enabledBorder!.borderSide, BorderSide.none);
      expect(decoration.focusedBorder!.borderSide, BorderSide.none);
      expect(
        WidgetStateProperty.resolveAs(decoration.fillColor!, {
          WidgetState.focused,
        }),
        isNot(WidgetStateProperty.resolveAs(decoration.fillColor!, {})),
      );
      expect(theme.chipTheme.side, BorderSide.none);
      await choose(tester, 'daring');
      expect(
        tester
            .widget<ChoiceChip>(find.byKey(const ValueKey('collection_daring')))
            .selected,
        isTrue,
      );
      await choose(tester, 'epic');
      expect(
        tester
            .widget<ChoiceChip>(find.byKey(const ValueKey('collection_epic')))
            .selected,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('initial loading resolves to a browsable catalog', (
    tester,
  ) async {
    final pending = Completer<List<MoodModel>>();
    await openCatalog(tester, load: () => pending.future);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.complete([]);
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byKey(const ValueKey('mood_creative')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('free selection opens its dare and back preserves the search', (
    tester,
  ) async {
    await openCatalog(tester);
    await tester.enterText(find.byType(TextField), 'creative');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mood_creative')));
    await tester.pumpAndSettle();
    expect(find.byType(DareDisplayScreen), findsOneWidget);
    expect(find.text('Open camera'), findsOneWidget);
    expect(
      DaresRepository.starterMoods.first.dareList.where(
        (d) => find.text(d).evaluate().isNotEmpty,
      ),
      hasLength(1),
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'creative',
    );
  });

  for (final pack in ['daring', 'epic']) {
    testWidgets('$pack stays preview-only even when legacy isLocked is false', (
      tester,
    ) async {
      final premium = mood(
        'remote-paid',
        name: 'Exclusive',
        pack: pack,
        dares: ['Never display this paid dare.'],
      );
      await openCatalog(tester, load: () async => [premium]);
      await choose(tester, pack == 'daring' ? 'daring' : 'epic');
      await tester.enterText(find.byType(TextField), 'Exclusive');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('mood_remote-paid')));
      await tester.pumpAndSettle();
      expect(find.byType(MoodPreviewContent), findsOneWidget);
      expect(find.text('${premium.tier.label} · Coming soon'), findsOneWidget);
      expect(find.text('Never display this paid dare.'), findsNothing);
      expect(find.text('Open camera'), findsNothing);
      expect(find.byType(DareDisplayScreen), findsNothing);
      await tester.tap(find.text('Back to moods'));
      await tester.pumpAndSettle();
      expect(find.byType(MoodPreviewContent), findsNothing);
    });
  }

  testWidgets('direct premium route also hides paid content and camera', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        home: DareDisplayScreen(
          mood: mood('premium', pack: 'epic', dares: ['Secret dare']),
          isProofRequired: false,
        ),
      ),
    );
    expect(find.byType(MoodPreviewContent), findsOneWidget);
    expect(find.text('Secret dare'), findsNothing);
    expect(find.text('Open camera'), findsNothing);
  });

  testWidgets('seasonal collection opens a themed free dare', (tester) async {
    await openCatalog(tester);
    await choose(tester, 'seasonal');
    expect(find.text('Christmas'), findsOneWidget);
    expect(find.text('New Year'), findsOneWidget);
    expect(find.text('Creative'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('mood_season-christmas')));
    await tester.pumpAndSettle();
    expect(find.text('Open camera'), findsOneWidget);
    expect(
      DaresRepository.seasonalMoods.first.dareList.where(
        (d) => find.text(d).evaluate().isNotEmpty,
      ),
      hasLength(1),
    );
  });

  testWidgets('empty search can reset both query and collection', (
    tester,
  ) async {
    await openCatalog(tester);
    await choose(tester, 'daring');
    await tester.enterText(find.byType(TextField), 'nothing matches');
    await tester.pumpAndSettle();
    expect(find.text('No matching moods'), findsOneWidget);
    await tester.ensureVisible(find.text('Show all moods'));
    await tester.tap(find.text('Show all moods'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const ValueKey('collection_all')))
          .selected,
      isTrue,
    );
    await tester.enterText(find.byType(TextField), 'Happy');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'offline retry preserves filters and replaces fallback with server data',
    (tester) async {
      var calls = 0;
      final retry = Completer<List<MoodModel>>();
      await openCatalog(
        tester,
        load: () {
          if (++calls == 1) return Future.error(StateError('offline'));
          return retry.future;
        },
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Couldn’t refresh. Starter moods are ready.'),
        findsOneWidget,
      );
      await choose(tester, 'daring');
      await tester.enterText(find.byType(TextField), 'brave');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(
        find.byKey(const ValueKey('mood_preview-daring-brave')),
        findsOneWidget,
      );
      retry.complete([mood('server-brave', name: 'Brave', pack: 'gold')]);
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsNothing);
      expect(find.byKey(const ValueKey('mood_server-brave')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('mood_preview-daring-brave')),
        findsNothing,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'brave',
      );
      expect(
        tester
            .widget<ChoiceChip>(find.byKey(const ValueKey('collection_daring')))
            .selected,
        isTrue,
      );
      expect(calls, 2);
    },
  );

  for (final size in [const Size(320, 640), const Size(768, 1024)]) {
    testWidgets('catalog and premium sheets fit $size with large text', (
      tester,
    ) async {
      await openCatalog(tester, size: size, scale: 1.5);
      await choose(tester, 'epic');
      await tester.enterText(find.byType(TextField), 'Main Character');
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      final card = find.byKey(
        const ValueKey('mood_preview-epic-main character'),
      );
      await tester.scrollUntilVisible(
        card,
        180,
        scrollable: find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(card);
      await tester.pumpAndSettle();
      expect(find.text('Epic · Coming soon'), findsOneWidget);
      await tester.ensureVisible(find.text('Back to moods'));
      await tester.tap(find.text('Back to moods'));
      await tester.pumpAndSettle();
      tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byType(CustomScrollView),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('About collections'));
      await tester.pumpAndSettle();
      expect(find.text('More ways to play'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
