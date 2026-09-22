import 'package:flutter/services.dart';

/// Installation-local entry preference; it never stores credentials or user IDs.
/// Serialize reads and writes so a deletion reset cannot race an earlier write.
class WelcomeHistory {
  static final instance = WelcomeHistory();
  static const channel = MethodChannel('mooddare/settings');
  Future<void> _pending = Future.value();

  Future<T> _ordered<T>(Future<T> Function() action) {
    final operation = _pending.then((_) => action());
    _pending = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }

  Future<bool> consumeWelcome({bool force = false}) => _ordered(() async {
    final seen = await channel.invokeMethod<bool>('welcomeSeen') ?? false;
    if (!seen || force) {
      await channel.invokeMethod<void>('setWelcomeSeen', true);
    }
    return force || !seen;
  });

  Future<void> rememberMember() =>
      _ordered(() => channel.invokeMethod<void>('setWelcomeSeen', true));

  Future<void> resetAfterDeletion() =>
      _ordered(() => channel.invokeMethod<void>('setWelcomeSeen', false));
}
