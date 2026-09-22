import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/features/auth/data/welcome_history.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  bool seen = false;
  bool fail = false;
  final writes = <bool>[];
  Completer<void>? writeGate;
  setUp(() {
    seen = false;
    fail = false;
    writeGate = null;
    writes.clear();
    messenger.setMockMethodCallHandler(WelcomeHistory.channel, (call) async {
      if (fail) throw PlatformException(code: 'preference-write');
      if (call.method == 'welcomeSeen') return seen;
      if (call.method == 'setWelcomeSeen') {
        await writeGate?.future;
        seen = call.arguments as bool;
        writes.add(seen);
        return null;
      }
      throw MissingPluginException();
    });
  });
  tearDown(
    () => messenger.setMockMethodCallHandler(WelcomeHistory.channel, null),
  );

  test(
    'first launch is consumed, new instances restore it, deletion resets it',
    () async {
      expect(await WelcomeHistory().consumeWelcome(), isTrue);
      expect(await WelcomeHistory().consumeWelcome(), isFalse);
      await WelcomeHistory().resetAfterDeletion();
      expect(await WelcomeHistory().consumeWelcome(), isTrue);
      expect(await WelcomeHistory().consumeWelcome(), isFalse);
      expect(writes, [true, false, true]);
    },
  );

  test(
    'existing member skips welcome and forced welcome is consumed only once',
    () async {
      final history = WelcomeHistory();
      await history.rememberMember();
      expect(await history.consumeWelcome(), isFalse);
      expect(await history.consumeWelcome(force: true), isTrue);
      expect(await WelcomeHistory().consumeWelcome(), isFalse);
    },
  );

  test(
    'queued membership write cannot overwrite a newer deletion reset',
    () async {
      final history = WelcomeHistory();
      writeGate = Completer<void>();
      final member = history.rememberMember();
      final reset = history.resetAfterDeletion();
      writeGate!.complete();
      await Future.wait([member, reset]);
      expect(writes, [true, false]);
      expect(await history.consumeWelcome(), isTrue);
    },
  );

  test('storage errors propagate but do not poison later operations', () async {
    final history = WelcomeHistory();
    fail = true;
    await expectLater(
      history.consumeWelcome(),
      throwsA(isA<PlatformException>()),
    );
    await expectLater(
      history.rememberMember(),
      throwsA(isA<PlatformException>()),
    );
    fail = false;
    expect(await history.consumeWelcome(), isTrue);
  });
}
