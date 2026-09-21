import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/main.dart';
import 'package:mooddare/core/widgets/dismiss_keyboard.dart';

void main() {
  testWidgets(
    'startup failure shows retry instead of entering an uninitialized app',
    (tester) async {
      for (final method in ['initializeCore', 'initializeApp']) {
        final channel = BasicMessageChannel<Object?>(
          'dev.flutter.pigeon.firebase_core_platform_interface.FirebaseCoreHostApi.$method',
          const StandardMessageCodec(),
        );
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockDecodedMessageHandler<Object?>(
              channel,
              (_) async => ['offline', 'Initialization unavailable', null],
            );
      }
      await tester.pumpWidget(const MoodDareApp());
      await tester.pumpAndSettle();
      expect(find.byType(DismissKeyboard), findsOneWidget);
      expect(find.text('Let’s try that again'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Let’s try that again'), findsOneWidget);
      expect(find.byType(Scaffold), findsOneWidget);
    },
  );
}
