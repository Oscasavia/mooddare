import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/core/app_theme.dart';
import 'package:mooddare/features/auth/presentation/screens/welcome_screen.dart';
import 'package:mooddare/features/dares/data/repositories/dares_repository.dart';
import 'package:mooddare/features/dares/presentation/screens/dare_generation_screen.dart';
import 'package:mooddare/features/profile/presentation/widgets/stats_and_badges.dart';

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
    await tester.tap(find.text('Try another dare'));
    await tester.pumpAndSettle();
    expect(find.text(before), findsNothing);
    expect(tester.takeException(), isNull);
  });
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
