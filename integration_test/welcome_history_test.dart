import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mooddare/features/auth/data/welcome_history.dart';

// Run on a test emulator: Flutter's integration runner can uninstall the app.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'native entry preference persists and resets without touching authentication',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('Entry preference check'))),
      );
      final original =
          await WelcomeHistory.channel.invokeMethod<bool>('welcomeSeen') ??
          false;
      try {
        await WelcomeHistory().resetAfterDeletion();
        expect(await WelcomeHistory().consumeWelcome(), isTrue);
        expect(await WelcomeHistory().consumeWelcome(), isFalse);
        await WelcomeHistory().rememberMember();
        expect(await WelcomeHistory().consumeWelcome(), isFalse);
        await WelcomeHistory().resetAfterDeletion();
        expect(await WelcomeHistory().consumeWelcome(), isTrue);
        expect(await WelcomeHistory().consumeWelcome(), isFalse);
        await expectLater(
          WelcomeHistory.channel.invokeMethod<void>(
            'setWelcomeSeen',
            'invalid',
          ),
          throwsA(isA<PlatformException>()),
        );
        expect(await WelcomeHistory().consumeWelcome(), isFalse);
      } finally {
        await WelcomeHistory.channel.invokeMethod<void>(
          'setWelcomeSeen',
          original,
        );
      }
    },
  );
}
