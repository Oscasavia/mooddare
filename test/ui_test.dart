import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/core/app_theme.dart';
import 'package:mooddare/features/auth/presentation/screens/welcome_screen.dart';
import 'package:mooddare/features/dares/data/repositories/dares_repository.dart';
import 'package:mooddare/features/dares/presentation/screens/dare_generation_screen.dart';
import 'package:mooddare/features/profile/presentation/widgets/stats_and_badges.dart';
import 'package:mooddare/models/mood_model.dart';

void main() {
  testWidgets('welcome fits a small screen with enlarged text', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        home: const MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: WelcomeScreen(),
        ),
      ),
    );
    expect(find.text('A little dare.\nA great story.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('shuffle produces a different dare', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        home: DareDisplayScreen(
          mood: DaresRepository.starterMoods.first,
          isProofRequired: false,
        ),
      ),
    );
    final before = DaresRepository.starterMoods.first.dareList.firstWhere(
      (d) => find.text(d).evaluate().isNotEmpty,
    );
    await tester.tap(find.byTooltip('Try another dare'));
    await tester.pumpAndSettle();
    expect(find.text(before), findsNothing);
    expect(tester.takeException(), isNull);
  });
  for (final size in [const Size(320, 640), const Size(768, 1024)]) {
    testWidgets(
      'long selected-mood dares scroll with the camera action fixed at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final longDare = List.filled(
          12,
          'Find a new perspective in an everyday place.',
        ).join(' ');
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.build(),
            home: MediaQuery(
              data: MediaQueryData(
                size: size,
                textScaler: const TextScaler.linear(1.5),
              ),
              child: DareDisplayScreen(
                mood: MoodModel(
                  id: 'test',
                  name: 'A longer mood name',
                  icon: '🌿',
                  pack: 'basic',
                  color: Colors.teal,
                  isLocked: false,
                  dareList: [longDare],
                ),
                isProofRequired: false,
              ),
            ),
          ),
        );
        final button = find.byKey(const ValueKey('mood_open_camera'));
        final before = tester.getRect(button);
        expect(before.bottom, lessThanOrEqualTo(size.height));
        expect(before.left, greaterThanOrEqualTo(0));
        expect(before.right, lessThanOrEqualTo(size.width));
        final textBefore = tester.getRect(find.text(longDare));
        await tester.drag(
          find.byKey(const ValueKey('mood_dare_scroll')),
          const Offset(0, -450),
        );
        await tester.pumpAndSettle();
        expect(
          tester.getRect(find.text(longDare)).top,
          lessThan(textBefore.top),
        );
        expect(tester.getRect(button), before);
        expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('profile progress reflects actual counts', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        home: const Scaffold(
          body: StatsAndBadges(daresCompleted: 2, totalLikes: 5),
        ),
      ),
    );
    expect(find.text('30'), findsOneWidget);
    expect(find.text('Level 1'), findsOneWidget);
    expect(find.text('70 points to your next level'), findsOneWidget);
  });
}
