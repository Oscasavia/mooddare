import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/core/validation.dart';

void main() {
  test('usernames share one set of validation rules', () {
    for (final value in ['ab', '', 'has space', 'a/b', '💜💜💜', 'a' * 21]) {
      expect(validateUsername(value), isNotNull);
    }
    for (final value in ['Oscar', 'mood_123', ' abc ']) {
      expect(validateUsername(value), isNull);
    }
  });
}
