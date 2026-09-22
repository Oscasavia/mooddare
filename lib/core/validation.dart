String? validateUsername(String? value) {
  final username = value?.trim() ?? '';
  if (!RegExp(r'^[a-zA-Z0-9_]{3,20}$').hasMatch(username)) {
    return 'Use 3–20 letters, numbers or underscores.';
  }
  if (!RegExp(r'[a-zA-Z]').hasMatch(username)) {
    return 'Include at least one letter.';
  }
  if (username.startsWith('_') || username.endsWith('_')) {
    return 'Start and end with a letter or number.';
  }
  if (username.contains('__')) {
    return 'Use only one underscore between letters or numbers.';
  }
  return null;
}
