import 'package:flutter/material.dart';

import '../../data/repositories/local/ideas.dart';
import '../../models/idea.dart';

class IdeasProvider with ChangeNotifier {
  IdeasProvider(this._ideasRepo) {
    _ideas = _sortIdeas(_ideasRepo.getIdeas());
  }

  final IdeasRepo _ideasRepo;
  late List<Idea> _ideas;

  List<Idea> get ideas => List.unmodifiable(_ideas);

  Idea? findById(String id) {
    for (final idea in _ideas) {
      if (idea.id == id) {
        return idea;
      }
    }
    return null;
  }

  List<IdeaSection> createDefaultSections() {
    return buildDefaultIdeaSections();
  }

  Future<Idea?> saveIdea({
    String? ideaId,
    required String title,
    required List<IdeaSection> sections,
  }) async {
    final normalizedTitle = title.trim();
    final normalizedSections =
        sections.map((section) => section.copyWith()).toList();
    final existingIdea = ideaId == null ? null : findById(ideaId);

    if (existingIdea == null &&
        normalizedTitle.isEmpty &&
        _allSectionsEmpty(normalizedSections)) {
      return null;
    }

    final now = DateTime.now();
    final savedIdea = Idea(
      id: existingIdea?.id ?? generateIdeaVaultId('idea'),
      title: normalizedTitle.isEmpty ? 'Untitled idea' : normalizedTitle,
      createdAt: existingIdea?.createdAt ?? now,
      updatedAt: now,
      sections: normalizedSections,
    );

    final existingIndex =
        _ideas.indexWhere((storedIdea) => storedIdea.id == savedIdea.id);

    if (existingIndex == -1) {
      _ideas = _sortIdeas([..._ideas, savedIdea]);
    } else {
      final nextIdeas = [..._ideas];
      nextIdeas[existingIndex] = savedIdea;
      _ideas = _sortIdeas(nextIdeas);
    }

    await _ideasRepo.saveIdeas(_ideas);
    notifyListeners();
    return savedIdea;
  }

  List<Idea> _sortIdeas(List<Idea> ideas) {
    final sortedIdeas = [...ideas];
    sortedIdeas.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return sortedIdeas;
  }

  bool _allSectionsEmpty(List<IdeaSection> sections) {
    for (final section in sections) {
      final text = section.content.trim();
      if (text.isNotEmpty) {
        return false;
      }
    }
    return true;
  }
}
