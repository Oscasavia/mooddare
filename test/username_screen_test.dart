import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/core/app_theme.dart';
import 'package:mooddare/features/auth/presentation/screens/username_screen.dart';

void main() {
  testWidgets(
    'username setup has no hero @ and rejects invalid handles before saving',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final saved = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(),
          home: UsernameScreen(
            isGuest: false,
            saveUsername: (value) async => saved.add(value),
          ),
        ),
      );
      expect(find.byIcon(Icons.alternate_email), findsNothing);
      for (final value in ['___', '123', '_abc', 'abc_', 'a__b', 'a.b']) {
        await tester.enterText(find.byType(TextFormField), value);
        await tester.tap(find.text('Let’s go'));
        await tester.pumpAndSettle();
        expect(saved, isEmpty);
        expect(tester.takeException(), isNull);
      }
      await tester.enterText(find.byType(TextFormField), 'mood_123');
      await tester.tap(find.text('Let’s go'));
      await tester.pumpAndSettle();
      expect(saved, ['mood_123']);
    },
  );
  testWidgets(
    'taken-name error allows retry and pending save prevents duplicates',
    (tester) async {
      final gate = Completer<void>();
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: UsernameScreen(
            isGuest: false,
            saveUsername: (value) async {
              calls++;
              if (calls == 1) {
                throw const FormatException('That username is already taken.');
              }
              await gate.future;
            },
          ),
        ),
      );
      await tester.enterText(find.byType(TextFormField), 'alice');
      await tester.tap(find.text('Let’s go'));
      await tester.pumpAndSettle();
      expect(find.text('That username is already taken.'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), 'alice_2');
      await tester.tap(find.text('Let’s go'));
      await tester.pump();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      gate.complete();
      await tester.pumpAndSettle();
      expect(calls, 2);
    },
  );
}
