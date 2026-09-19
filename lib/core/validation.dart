String? validateUsername(String? value) {
  final username = value?.trim() ?? '';
  if (!RegExp(r'^[a-zA-Z0-9_]{3,20}$').hasMatch(username)) {
    return 'Use 3–20 letters, numbers or underscores.';
  }
  return null;
}
