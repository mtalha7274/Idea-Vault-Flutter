/// Builds an inserted chunk so it sits on its own line between surrounding text.
String textOnOwnLine(String before, String after, String inserted) {
  final normalized = inserted.trim();
  if (normalized.isEmpty) {
    return '';
  }

  final leadingBreak = before.isNotEmpty && !before.endsWith('\n') ? '\n' : '';
  final trailingBreak = after.isNotEmpty && !after.startsWith('\n') ? '\n' : '';
  return '$leadingBreak$normalized$trailingBreak';
}
