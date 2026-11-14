import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/widgets.dart' show StringCharacters, TextRange;

import '../../core/constants/view_constants.dart';
import '../../models/idea.dart';
import 'search_text_normalizer.dart';

enum IdeaSearchMatchTier {
  title,
  sectionName,
  content,
}

class IdeaSearchSnippet {
  const IdeaSearchSnippet({
    required this.text,
    required this.highlights,
  });

  final String text;
  final List<TextRange> highlights;
}

class IdeaSearchResult {
  const IdeaSearchResult({
    required this.idea,
    required this.tier,
    this.sectionId,
    this.sectionName,
    this.snippet,
  });

  final Idea idea;
  final IdeaSearchMatchTier tier;
  final String? sectionId;
  final String? sectionName;
  final IdeaSearchSnippet? snippet;
}

class _IndexedSection {
  _IndexedSection(IdeaSection section)
      : id = section.id,
        name = section.name,
        normalizedName = normalizeSearchQuery(section.name),
        cleanContent = stripFormattingMarkers(section.content) {
    normalizedContent = normalizeForSearch(cleanContent);
  }

  final String id;
  final String name;
  final String normalizedName;
  final String cleanContent;
  late final NormalizedSearchText normalizedContent;
}

class _IndexedIdea {
  _IndexedIdea(this.idea)
      : normalizedTitle = normalizeSearchQuery(idea.title),
        sections = idea.isLocked
            ? const []
            : idea.sections.map(_IndexedSection.new).toList(growable: false);

  final Idea idea;
  final String normalizedTitle;
  final List<_IndexedSection> sections;
}

class IdeaSearchIndex {
  final Map<String, _IndexedIdea> _cache = {};

  int get cachedIdeaCount => _cache.length;

  List<IdeaSearchResult> search(List<Idea> ideas, String query) {
    _prune(ideas);
    final terms = searchQueryTerms(query);
    if (terms.isEmpty) {
      return const [];
    }

    final results = <IdeaSearchResult>[];
    for (final idea in ideas) {
      final result = _match(_indexFor(idea), terms);
      if (result != null) {
        results.add(result);
      }
    }
    results.sort((a, b) {
      final tierOrder = a.tier.index.compareTo(b.tier.index);
      if (tierOrder != 0) {
        return tierOrder;
      }
      return b.idea.updatedAt.compareTo(a.idea.updatedAt);
    });
    return results;
  }

  void clear() => _cache.clear();

  _IndexedIdea _indexFor(Idea idea) {
    final cached = _cache[idea.id];
    if (cached != null &&
        (identical(cached.idea, idea) || cached.idea == idea)) {
      return cached;
    }
    final indexed = _IndexedIdea(idea);
    _cache[idea.id] = indexed;
    return indexed;
  }

  void _prune(List<Idea> ideas) {
    if (_cache.isEmpty) {
      return;
    }
    final liveIds = {for (final idea in ideas) idea.id};
    _cache.removeWhere((id, _) => !liveIds.contains(id));
  }

  IdeaSearchResult? _match(_IndexedIdea indexed, List<String> terms) {
    final idea = indexed.idea;
    if (idea.isLocked) {
      final matchesTitle =
          terms.every((term) => indexed.normalizedTitle.contains(term));
      if (!matchesTitle) {
        return null;
      }
      return IdeaSearchResult(idea: idea, tier: IdeaSearchMatchTier.title);
    }

    final missingFromTitle = terms
        .where((term) => !indexed.normalizedTitle.contains(term))
        .toList(growable: false);
    if (missingFromTitle.isEmpty) {
      return IdeaSearchResult(idea: idea, tier: IdeaSearchMatchTier.title);
    }

    final missingFromNames = missingFromTitle
        .where(
          (term) => !indexed.sections
              .any((section) => section.normalizedName.contains(term)),
        )
        .toList(growable: false);

    final missingEverywhere = missingFromNames
        .where(
          (term) => !indexed.sections.any(
            (section) => section.normalizedContent.text.contains(term),
          ),
        )
        .toList(growable: false);
    if (missingEverywhere.isNotEmpty) {
      return null;
    }

    final contentSection = _bestContentSection(indexed, terms);
    if (missingFromNames.isEmpty) {
      final nameSection = _bestNameSection(indexed, terms);
      final section = contentSection ?? nameSection;
      return IdeaSearchResult(
        idea: idea,
        tier: IdeaSearchMatchTier.sectionName,
        sectionId: section?.id,
        sectionName: section?.name,
        snippet: contentSection == null
            ? null
            : buildSearchSnippet(contentSection.cleanContent,
                contentSection.normalizedContent, terms),
      );
    }

    return IdeaSearchResult(
      idea: idea,
      tier: IdeaSearchMatchTier.content,
      sectionId: contentSection?.id,
      sectionName: contentSection?.name,
      snippet: contentSection == null
          ? null
          : buildSearchSnippet(
              contentSection.cleanContent,
              contentSection.normalizedContent,
              terms,
            ),
    );
  }

  _IndexedSection? _bestContentSection(
    _IndexedIdea indexed,
    List<String> terms,
  ) {
    _IndexedSection? best;
    var bestCount = 0;
    for (final section in indexed.sections) {
      final count = terms
          .where((term) => section.normalizedContent.text.contains(term))
          .length;
      if (count > bestCount) {
        best = section;
        bestCount = count;
      }
    }
    return best;
  }

  _IndexedSection? _bestNameSection(
    _IndexedIdea indexed,
    List<String> terms,
  ) {
    for (final section in indexed.sections) {
      if (terms.any((term) => section.normalizedName.contains(term))) {
        return section;
      }
    }
    return null;
  }
}

const int searchSnippetContextBefore = 36;
const int searchSnippetContextAfter = 110;
const String _ellipsis = '…';

IdeaSearchSnippet? buildSearchSnippet(
  String cleanText,
  NormalizedSearchText normalized,
  List<String> terms,
) {
  final ranges = <(int, int)>[];
  for (final term in terms) {
    var from = 0;
    while (from <= normalized.text.length - term.length) {
      final index = normalized.text.indexOf(term, from);
      if (index == -1) {
        break;
      }
      ranges.add(normalized.sourceRange(index, index + term.length));
      from = index + term.length;
    }
  }
  if (ranges.isEmpty) {
    return null;
  }
  ranges.sort((a, b) => a.$1.compareTo(b.$1));

  final boundaries = _graphemeBoundaries(cleanText);
  final firstStart = _snapDown(boundaries, ranges.first.$1);
  final firstEnd = _snapUp(boundaries, ranges.first.$2);

  var start = _snapDown(
    boundaries,
    (firstStart - searchSnippetContextBefore).clamp(0, cleanText.length),
  );
  if (start > 0) {
    final space = cleanText.indexOf(' ', start);
    if (space != -1 && space < firstStart) {
      start = space + 1;
    }
  }

  var end = _snapUp(
    boundaries,
    (firstEnd + searchSnippetContextAfter).clamp(0, cleanText.length),
  );
  if (end < cleanText.length) {
    final space = cleanText.lastIndexOf(' ', end);
    if (space > firstEnd) {
      end = space;
    }
  }

  final prefix = start > 0 ? _ellipsis : '';
  final suffix = end < cleanText.length ? _ellipsis : '';
  final body = cleanText.substring(start, end);
  final highlights = <TextRange>[];
  var lastEnd = -1;
  for (final (rangeStart, rangeEnd) in ranges) {
    final snappedStart = _snapDown(boundaries, rangeStart);
    final snappedEnd = _snapUp(boundaries, rangeEnd);
    if (snappedEnd <= start || snappedStart >= end) {
      continue;
    }
    final clippedStart =
        (snappedStart < start ? start : snappedStart).clamp(lastEnd, end);
    final clippedEnd = snappedEnd > end ? end : snappedEnd;
    if (clippedEnd <= clippedStart) {
      continue;
    }
    if (highlights.isNotEmpty && clippedStart <= lastEnd) {
      final previous = highlights.removeLast();
      highlights.add(
        TextRange(
          start: previous.start,
          end: clippedEnd - start + prefix.length,
        ),
      );
    } else {
      highlights.add(
        TextRange(
          start: clippedStart - start + prefix.length,
          end: clippedEnd - start + prefix.length,
        ),
      );
    }
    lastEnd = clippedEnd;
  }

  return IdeaSearchSnippet(
    text: '$prefix$body$suffix',
    highlights: highlights,
  );
}

List<int> _graphemeBoundaries(String text) {
  final boundaries = <int>[0];
  var offset = 0;
  for (final cluster in text.characters) {
    offset += cluster.length;
    boundaries.add(offset);
  }
  return boundaries;
}

int _snapDown(List<int> boundaries, int offset) {
  var low = 0;
  var high = boundaries.length - 1;
  var result = 0;
  while (low <= high) {
    final mid = (low + high) >> 1;
    if (boundaries[mid] <= offset) {
      result = boundaries[mid];
      low = mid + 1;
    } else {
      high = mid - 1;
    }
  }
  return result;
}

int _snapUp(List<int> boundaries, int offset) {
  var low = 0;
  var high = boundaries.length - 1;
  var result = boundaries.last;
  while (low <= high) {
    final mid = (low + high) >> 1;
    if (boundaries[mid] >= offset) {
      result = boundaries[mid];
      high = mid - 1;
    } else {
      low = mid + 1;
    }
  }
  return result;
}

bool ideaMatchesSearch(Idea idea, String query) {
  return IdeaSearchIndex().search([idea], query).isNotEmpty;
}

List<Idea> filterIdeasBySearch(List<Idea> ideas, String query) {
  return IdeaSearchIndex()
      .search(ideas, query)
      .map((result) => result.idea)
      .toList(growable: false);
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
  return stripFormattingMarkers(markdown);
}
