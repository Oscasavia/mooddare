import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/core/validation.dart';

void main() {
  test('usernames share one set of validation rules', () {
    for (final value in [
      'ab',
      '',
      'has space',
      'a/b',
      '💜💜💜',
      'a' * 21,
      '___',
      '123',
      '123_456',
      '_alice',
      'alice_',
      'al__ice',
      '@alice',
      'ali.ce',
      'ali-ce',
      'a\u200bb',
      'a\nb',
    ]) {
      expect(validateUsername(value), isNotNull);
    }
    for (final value in [
      'Oscar',
      'mood_123',
      ' abc ',
      '123abc',
      'a_b',
      'a' * 20,
    ]) {
      expect(validateUsername(value), isNull);
    }
  });
}
