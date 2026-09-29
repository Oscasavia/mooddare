import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/core/app_theme.dart';
import 'package:mooddare/features/dares/data/weekly_dare_preferences.dart';
import 'package:mooddare/features/dares/data/repositories/weekly_dare_repository.dart';
import 'package:mooddare/features/dares/presentation/widgets/weekly_dare_card.dart';
import 'weekly_dare_test.dart' show TestWeekly, schedule, MemoryPreference;

void main() {
  test(
    'choice survives a new store; rapid writes stay ordered and corrupt files default expanded',
    () async {
      final temp = await Directory.systemTemp.createTemp('weekly-preference-');
      final store = WeeklyDarePreferences(directory: () async => temp);
      try {
        expect(await store.load(), isNull);
        final writes = [
          store.save('2026-09-21'),
          store.save(null),
          store.save('2026-09-28'),
        ];
        expect(await store.load(), '2026-09-28');
        await Future.wait(writes);
        final reopened = WeeklyDarePreferences(directory: () async => temp);
        expect(await reopened.load(), '2026-09-28');
        await reopened.save(null);
        expect(await store.load(), isNull);
        await File(
          '${temp.path}/weekly-dare-collapsed.txt',
        ).writeAsString('invalid');
        expect(await reopened.load(), isNull);
      } finally {
        await temp.delete(recursive: true);
      }
    },
  );
  test('a failed write does not poison subsequent writes', () async {
    final temp = await Directory.systemTemp.createTemp('weekly-preference-');
    var fail = true;
    final store = WeeklyDarePreferences(
      directory: () async {
        if (fail) throw FileSystemException('Unavailable');
        return temp;
      },
    );
    try {
      await expectLater(
        store.save('2026-09-21'),
        throwsA(isA<FileSystemException>()),
      );
      fail = false;
      await store.save('2026-09-21');
      expect(await store.load(), '2026-09-21');
    } finally {
      await temp.delete(recursive: true);
    }
  });

  for (final width in [320.0, 390.0]) {
    testWidgets(
      'collapse header works at $width with large text, restores after reopening and resets for next week',
      (tester) async {
        tester.view.physicalSize = Size(width, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var now = DateTime.utc(2026, 9, 23);
        final prefs = MemoryPreference(), repo = TestWeekly();
        addTearDown(repo.close);
        Future<void> mount() async {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.build(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
              home: Scaffold(
                body: SingleChildScrollView(
                  child: WeeklyDareCard(
                    repository: repo,
                    preferences: prefs,
                    now: () => now,
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          repo.changes.add(
            WeeklyDare.parse(WeeklyDare.weekId(now), schedule(now)),
          );
          await tester.pumpAndSettle();
        }

        await mount();
        final card = find.byKey(const ValueKey('weekly_dare_card'));
        final expandedHeight = tester.getSize(card).height;
        expect(find.byIcon(Icons.keyboard_arrow_up_rounded), findsOneWidget);
        // The title itself toggles the card, not just the chevron.
        await tester.tap(find.text('A little joy'));
        await tester.pumpAndSettle();
        expect(find.text('This week’s dare'), findsOneWidget);
        expect(find.text('A little joy'), findsOneWidget);
        expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);
        expect(find.text('Join this week'), findsNothing);
        expect(tester.getSize(card).height, lessThan(expandedHeight / 2));
        expect(prefs.value, '2026-09-21');
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await mount();
        expect(find.text('Join this week'), findsNothing);
        await tester.tap(find.byTooltip('Expand weekly dare'));
        await tester.pumpAndSettle();
        expect(find.text('Join this week'), findsOneWidget);
        expect(prefs.value, isNull);
        await tester.tap(find.byTooltip('Collapse weekly dare'));
        await tester.pumpAndSettle();
        now = DateTime.utc(2026, 9, 28);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        repo.changes.add(
          WeeklyDare.parse(WeeklyDare.weekId(now), schedule(now)),
        );
        await tester.pumpAndSettle();
        expect(find.text('Join this week'), findsOneWidget);
        expect(find.byIcon(Icons.keyboard_arrow_up_rounded), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'unavailable local storage does not block collapse or participation',
    (tester) async {
      final repo = TestWeekly(), prefs = MemoryPreference()..fail = true;
      addTearDown(repo.close);
      final now = DateTime.utc(2026, 9, 23);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: WeeklyDareCard(
                repository: repo,
                preferences: prefs,
                now: () => now,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      repo.changes.add(WeeklyDare.parse(WeeklyDare.weekId(now), schedule(now)));
      await tester.pumpAndSettle();
      expect(find.text('Join this week'), findsOneWidget);
      await tester.tap(find.text('A little joy'));
      await tester.pumpAndSettle();
      expect(find.text('Join this week'), findsNothing);
      await tester.tap(find.text('A little joy'));
      await tester.pumpAndSettle();
      expect(find.text('Join this week'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
