import 'package:flutter_test/flutter_test.dart';
import 'package:idea_vault/core/utils/idea_search.dart';
import 'package:idea_vault/core/utils/search_text_normalizer.dart';
import 'package:idea_vault/models/idea.dart';

Idea _idea({
  required String id,
  String title = 'Plain title',
  List<IdeaSection> sections = const [],
  bool isLocked = false,
  DateTime? updatedAt,
}) {
  final time = updatedAt ?? DateTime.utc(2026, 1, 1);
  return Idea(
    id: id,
    title: title,
    createdAt: time,
    updatedAt: time,
    isLocked: isLocked,
    sections: sections,
  );
}

IdeaSection _section(String id, String name, String content) {
  return IdeaSection(id: id, name: name, content: content);
}

String _highlighted(IdeaSearchSnippet snippet) {
  return snippet.highlights
      .map((range) => snippet.text.substring(range.start, range.end))
      .join('|');
}

void main() {
  group('normalizeForSearch', () {
    test('lower-cases, collapses whitespace and folds accents', () {
      expect(
        normalizeForSearch('  Café   CRÈME\n\tBrûlée  ').text,
        'cafe creme brulee',
      );
      expect(normalizeForSearch('Straße Ærø').text, 'strasse aero');
    });

    test('strips Arabic and Urdu vowel marks', () {
      expect(normalizeForSearch('كَتَبَ').text, normalizeForSearch('كتب').text);
      expect(
        normalizeForSearch('مُحَمَّد').text,
        normalizeForSearch('محمد').text,
      );
      expect(normalizeForSearch('أحمد').text, normalizeForSearch('احمد').text);
    });

    test('maps normalized offsets back to the source text', () {
      const source = 'Hi  Café';
      final normalized = normalizeForSearch(source);
      final index = normalized.text.indexOf('cafe');
      final (start, end) = normalized.sourceRange(index, index + 4);
      expect(source.substring(start, end), 'Café');
    });

    test('query of only spaces has no terms', () {
      expect(searchQueryTerms('    '), isEmpty);
      expect(searchQueryTerms(' Solar   ROOF '), ['solar', 'roof']);
    });
  });

  group('stripFormattingMarkers', () {
    test('removes bold, italic, heading and bullet markers', () {
      expect(
        stripFormattingMarkers('# Title\n- **bold** and _soft_ text'),
        'Title bold and soft text',
      );
    });

    test('keeps underscores inside words', () {
      expect(
          stripFormattingMarkers('use snake_case_name'), 'use snake_case_name');
    });
  });

  group('IdeaSearchIndex', () {
    test('finds a match that only exists in a later section', () {
      final idea = _idea(
        id: 'idea-1',
        sections: [
          _section('s1', 'Idea', 'Nothing here'),
          _section('s2', 'Design', 'Also nothing'),
          _section('s3', 'Pricing', 'Charge a monthly subscription fee'),
          _section('s4', 'Notes', 'Unrelated'),
          _section('s5', 'Later', ''),
        ],
      );

      final results = IdeaSearchIndex().search([idea], 'subscription');

      expect(results, hasLength(1));
      expect(results.single.tier, IdeaSearchMatchTier.content);
      expect(results.single.sectionId, 's3');
      expect(results.single.sectionName, 'Pricing');
      expect(results.single.snippet, isNotNull);
      expect(_highlighted(results.single.snippet!), 'subscription');
    });

    test('requires every word but allows any order and any field', () {
      final idea = _idea(
        id: 'idea-1',
        title: 'Garden co-op',
        sections: [
          _section('s1', 'Idea', 'Shared rooftop'),
          _section('s2', 'Budget', 'Solar panels'),
        ],
      );
      final index = IdeaSearchIndex();

      expect(index.search([idea], 'solar garden rooftop'), hasLength(1));
      expect(index.search([idea], 'solar missing'), isEmpty);
    });

    test('matches accented and formatted text', () {
      final idea = _idea(
        id: 'idea-1',
        sections: [
          _section('s1', 'Idea', 'Visit the **Café** near the _plaza_'),
        ],
      );
      final index = IdeaSearchIndex();

      expect(index.search([idea], 'cafe'), hasLength(1));
      expect(index.search([idea], 'CAFÉ plaza'), hasLength(1));
      expect(index.search([idea], 'bold'), isEmpty);
      final snippet = index.search([idea], 'cafe').single.snippet!;
      expect(_highlighted(snippet), 'Café');
      expect(snippet.text, isNot(contains('**')));
    });

    test('matches Urdu text with and without vowel marks', () {
      final idea = _idea(
        id: 'idea-1',
        sections: [_section('s1', 'Idea', 'یہ کِتاب اچھی ہے')],
      );

      expect(IdeaSearchIndex().search([idea], 'کتاب'), hasLength(1));
    });

    test('treats markdown symbols in the query as literal text', () {
      final idea = _idea(
        id: 'idea-1',
        sections: [_section('s1', 'Idea', 'Prefer c# over f*')],
      );
      final index = IdeaSearchIndex();

      expect(index.search([idea], 'c#'), hasLength(1));
      expect(index.search([idea], 'f*'), hasLength(1));
      expect(index.search([idea], '_'), isEmpty);
    });

    test('matches locked ideas by title only and never returns a snippet', () {
      final locked = _idea(
        id: 'locked',
        title: 'Private plans',
        isLocked: true,
        sections: [_section('s1', 'Secret section', 'hidden treasure')],
      );
      final index = IdeaSearchIndex();

      expect(index.search([locked], 'treasure'), isEmpty);
      expect(index.search([locked], 'secret'), isEmpty);
      final results = index.search([locked], 'private');
      expect(results, hasLength(1));
      expect(results.single.snippet, isNull);
      expect(results.single.sectionId, isNull);
      expect(results.single.sectionName, isNull);
    });

    test('ranks title, then section name, then content, ties by updatedAt', () {
      final contentOld = _idea(
        id: 'content-old',
        updatedAt: DateTime.utc(2026, 1, 1),
        sections: [_section('s1', 'Idea', 'about rockets')],
      );
      final contentNew = _idea(
        id: 'content-new',
        updatedAt: DateTime.utc(2026, 3, 1),
        sections: [_section('s1', 'Idea', 'more rockets')],
      );
      final name = _idea(
        id: 'name',
        updatedAt: DateTime.utc(2025, 1, 1),
        sections: [_section('s1', 'Rockets', 'body')],
      );
      final title = _idea(
        id: 'title',
        title: 'Rockets for kids',
        updatedAt: DateTime.utc(2024, 1, 1),
      );

      final results = IdeaSearchIndex()
          .search([contentOld, name, contentNew, title], 'rockets');

      expect(
        results.map((result) => result.idea.id),
        ['title', 'name', 'content-new', 'content-old'],
      );
      expect(results[1].sectionId, 's1');
    });

    test('ideas with no sections match by title only', () {
      final idea = _idea(id: 'idea-1', title: 'Lonely title');
      final index = IdeaSearchIndex();

      expect(index.search([idea], 'lonely'), hasLength(1));
      expect(index.search([idea], 'idea'), isEmpty);
    });

    test('refreshes the cache entry when an idea changes', () {
      final index = IdeaSearchIndex();
      final original = _idea(
        id: 'idea-1',
        sections: [_section('s1', 'Idea', 'first draft')],
      );

      expect(index.search([original], 'second'), isEmpty);
      final edited = original.copyWith(
        sections: [_section('s1', 'Idea', 'second draft')],
      );
      expect(index.search([edited], 'second'), hasLength(1));
      expect(index.search([edited], 'first'), isEmpty);
      expect(index.cachedIdeaCount, 1);

      index.search(const [], 'second');
      expect(index.cachedIdeaCount, 0);
    });

    test('searches a thousand ideas quickly', () {
      final ideas = List<Idea>.generate(
        1000,
        (index) => _idea(
          id: 'idea-$index',
          title: 'Idea number $index',
          sections: [
            for (var section = 0; section < 4; section++)
              _section(
                'idea-$index-section-$section',
                'Section $section',
                List.filled(20, 'lorem ipsum dolor sit amet $index').join(' '),
              ),
          ],
        ),
      );
      final index = IdeaSearchIndex()..search(ideas, 'warm');

      final stopwatch = Stopwatch()..start();
      final results = index.search(ideas, 'dolor 999');
      stopwatch.stop();

      expect(results.map((result) => result.idea.id), contains('idea-999'));
      expect(stopwatch.elapsedMilliseconds, lessThan(250));
    });
  });

  group('buildSearchSnippet', () {
    IdeaSearchSnippet snippetFor(String text, String query) {
      final clean = stripFormattingMarkers(text);
      return buildSearchSnippet(
        clean,
        normalizeForSearch(clean),
        searchQueryTerms(query),
      )!;
    }

    test('match at the start has no leading ellipsis', () {
      final snippet = snippetFor(
        'Rocket ${List.filled(80, 'word').join(' ')}',
        'rocket',
      );

      expect(snippet.text.startsWith('Rocket'), isTrue);
      expect(snippet.text.endsWith('…'), isTrue);
      expect(_highlighted(snippet), 'Rocket');
    });

    test('match at the end has no trailing ellipsis', () {
      final snippet = snippetFor(
        '${List.filled(80, 'word').join(' ')} finale',
        'finale',
      );

      expect(snippet.text.startsWith('…'), isTrue);
      expect(snippet.text.endsWith('finale'), isTrue);
      expect(_highlighted(snippet), 'finale');
    });

    test('short text is returned whole without ellipsis', () {
      final snippet = snippetFor('A tiny note about bees', 'bees');

      expect(snippet.text, 'A tiny note about bees');
    });

    test('never cuts an emoji in half', () {
      final family = '👨‍👩‍👧‍👦';
      final text = '${List.filled(30, family).join()} target '
          '${List.filled(80, '👍🏽').join()}';
      final snippet = snippetFor(text, 'target');

      final body = snippet.text.replaceAll('…', '');
      expect(
        body.replaceAll(family, '').replaceAll('👍🏽', '').trim(),
        'target',
      );
      expect(_highlighted(snippet), 'target');
      expect(snippet.text.startsWith('…'), isTrue);
      expect(snippet.text.endsWith('…'), isTrue);
    });

    test('highlights every term inside the snippet', () {
      final snippet =
          snippetFor('Solar panels on every rooftop', 'rooftop solar');

      expect(_highlighted(snippet), 'Solar|rooftop');
    });
  });
}
