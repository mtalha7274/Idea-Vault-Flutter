import 'package:easy_localization/easy_localization.dart';

import '../../core/constants/view_constants.dart';
import '../../models/idea.dart';

bool ideaMatchesSearch(Idea idea, String query) {
  if (query.isEmpty) {
    return false;
  }

  final normalizedQuery = query.toLowerCase();
  final titleMatches = idea.title.toLowerCase().contains(normalizedQuery);
  final previewMatches = ideaPreviewText(
    idea,
    fallbackIfEmpty: false,
  ).toLowerCase().contains(normalizedQuery);

  return titleMatches || previewMatches;
}

List<Idea> filterIdeasBySearch(List<Idea> ideas, String query) {
  final trimmedQuery = query.trim();
  if (trimmedQuery.isEmpty) {
    return const [];
  }

  return ideas
      .where((idea) => ideaMatchesSearch(idea, trimmedQuery))
      .toList(growable: false)
    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
}

String ideaPreviewText(
  Idea idea, {
  bool fallbackIfEmpty = true,
}) {
  for (final section in idea.sections) {
    final text = plainPreviewText(section.content);
    if (text.isNotEmpty) {
      return text;
    }
  }

  return fallbackIfEmpty
      ? ViewConstants.homepageIdeaCardPreviewPlaceholder.tr()
      : '';
}

String plainPreviewText(String markdown) {
  return markdown
      .replaceAll('```', ' ')
      .replaceAllMapped(
        RegExp(r'\*\*(.*?)\*\*', dotAll: true),
        (match) => match.group(1) ?? '',
      )
      .replaceAllMapped(
        RegExp(r'_(.*?)_', dotAll: true),
        (match) => match.group(1) ?? '',
      )
      .replaceAll(RegExp(r'^#\s*', multiLine: true), '')
      .replaceAll(RegExp(r'^-\s*', multiLine: true), '')
      .replaceAll('\n', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
