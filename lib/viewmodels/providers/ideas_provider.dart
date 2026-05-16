import 'package:flutter/material.dart';

import '../../data/repositories/local/idea_editor_state.dart';
import '../../data/repositories/local/ideas.dart';
import '../../models/idea.dart';
import '../../models/idea_editor_state.dart';

class IdeasProvider with ChangeNotifier {
  IdeasProvider(
    this._ideasRepo,
    this._ideaEditorStateRepo,
  ) {
    _resumeEditorState = _ideaEditorStateRepo.getState();
    ensureLoaded();
  }

  final IdeasRepo _ideasRepo;
  final IdeaEditorStateRepo _ideaEditorStateRepo;
  List<Idea> _ideas = const [];
  IdeaEditorState? _resumeEditorState;
  Future<void>? _loadFuture;
  bool _isLoading = true;

  List<Idea> get ideas => List.unmodifiable(_ideas);
  IdeaEditorState? get resumeEditorState => _resumeEditorState;
  bool get isLoading => _isLoading;

  Future<void> ensureLoaded() {
    return _loadFuture ??= _loadIdeas();
  }

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

  Future<void> saveEditorState({
    required String? ideaId,
    required String activeSectionId,
    required bool isPreviewMode,
  }) async {
    if (ideaId == null) {
      await clearEditorState();
      return;
    }

    final nextState = IdeaEditorState(
      ideaId: ideaId,
      activeSectionId: activeSectionId,
      isPreviewMode: isPreviewMode,
    );
    _resumeEditorState = nextState;
    await _ideaEditorStateRepo.saveState(nextState);
  }

  Future<void> clearEditorState() async {
    _resumeEditorState = null;
    await _ideaEditorStateRepo.clearState();
  }

  Future<Idea?> saveIdea({
    String? ideaId,
    required String title,
    required List<IdeaSection> sections,
  }) async {
    await ensureLoaded();

    final normalizedTitle = title.trim();
    final normalizedSections =
        sections.map((section) => section.copyWith()).toList();
    final existingIdea = ideaId == null ? null : findById(ideaId);

    if (normalizedTitle.isEmpty) {
      return null;
    }

    final now = DateTime.now();
    final savedIdea = Idea(
      id: existingIdea?.id ?? generateIdeaVaultId('idea'),
      title: normalizedTitle,
      createdAt: existingIdea?.createdAt ?? now,
      updatedAt: now,
      sections: normalizedSections,
    );

    await _ideasRepo.upsertIdea(savedIdea);

    final existingIndex =
        _ideas.indexWhere((storedIdea) => storedIdea.id == savedIdea.id);
    if (existingIndex == -1) {
      _ideas = _sortIdeas([..._ideas, savedIdea]);
    } else {
      final nextIdeas = [..._ideas];
      nextIdeas[existingIndex] = savedIdea;
      _ideas = _sortIdeas(nextIdeas);
    }

    notifyListeners();
    return savedIdea;
  }

  Future<void> deleteIdeas(Iterable<String> ideaIds) async {
    await ensureLoaded();
    final ids = ideaIds.toSet();
    if (ids.isEmpty) {
      return;
    }

    await _ideasRepo.deleteIdeas(ids);
    _ideas = _ideas.where((idea) => !ids.contains(idea.id)).toList();

    final activeIdeaId = _resumeEditorState?.ideaId;
    if (activeIdeaId != null && ids.contains(activeIdeaId)) {
      await clearEditorState();
    }

    notifyListeners();
  }

  Future<void> replaceIdeas(List<Idea> ideas) async {
    await ensureLoaded();
    await _ideasRepo.saveIdeas(ideas);
    _ideas = _sortIdeas(ideas);
    await clearEditorState();
    notifyListeners();
  }

  Future<Idea?> appendContentToSection({
    required String ideaId,
    required String sectionId,
    required String content,
  }) async {
    await ensureLoaded();

    final trimmedContent = content.trim();
    if (trimmedContent.isEmpty) {
      return null;
    }

    final idea = findById(ideaId);
    if (idea == null) {
      return null;
    }

    var didFindSection = false;
    final nextSections = [
      for (final section in idea.sections)
        if (section.id == sectionId)
          section.copyWith(
            content: _appendSectionContent(
              section.content,
              trimmedContent,
            ),
          )
        else
          section,
    ];

    for (final section in idea.sections) {
      if (section.id == sectionId) {
        didFindSection = true;
        break;
      }
    }

    if (!didFindSection) {
      return null;
    }

    return saveIdea(
      ideaId: idea.id,
      title: idea.title,
      sections: nextSections,
    );
  }

  Future<void> _loadIdeas() async {
    _isLoading = true;
    final loadedIdeas = await _ideasRepo.getIdeas();
    _ideas = _sortIdeas(loadedIdeas);
    _isLoading = false;
    notifyListeners();
  }

  List<Idea> _sortIdeas(List<Idea> ideas) {
    final sortedIdeas = [...ideas];
    sortedIdeas.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return sortedIdeas;
  }

  String _appendSectionContent(String existingContent, String addition) {
    final trimmedExistingContent = existingContent.trimRight();
    if (trimmedExistingContent.isEmpty) {
      return addition;
    }

    return '$trimmedExistingContent\n\n$addition';
  }
}
