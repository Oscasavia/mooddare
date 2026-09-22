import 'package:mooddare/features/auth/data/welcome_history.dart';

class MemoryWelcomeHistory implements WelcomeHistory {
  bool seen = false, failRead = false, failReset = false;
  int reads = 0, members = 0, resets = 0;

  @override
  Future<bool> consumeWelcome({bool force = false}) async {
    reads++;
    if (failRead) throw StateError('Storage unavailable');
    final welcome = force || !seen;
    seen = true;
    return welcome;
  }

  @override
  Future<void> rememberMember() async {
    members++;
    seen = true;
  }

  @override
  Future<void> resetAfterDeletion() async {
    resets++;
    if (failReset) throw StateError('Storage unavailable');
    seen = false;
  }
}
