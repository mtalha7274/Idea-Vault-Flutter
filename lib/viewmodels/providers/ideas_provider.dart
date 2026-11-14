import 'package:flutter/material.dart';

import '../../core/editor/note_markup.dart';
import '../../core/services/vault/note_vault_service.dart';
import '../../data/repositories/local/idea_editor_state.dart';
import '../../data/repositories/local/ideas.dart';
import '../../models/idea.dart';
import '../../models/idea_editor_state.dart';

class IdeasProvider with ChangeNotifier {
  IdeasProvider(
    this._ideasRepo,
    this._ideaEditorStateRepo, {
    NoteVaultService? vault,
  }) : _vault = vault {
    _resumeEditorState = _ideaEditorStateRepo.getState();
    ensureLoaded();
  }

  final IdeasRepo _ideasRepo;
  final IdeaEditorStateRepo _ideaEditorStateRepo;
  final NoteVaultService? _vault;
  List<Idea> _ideas = const [];
  IdeaEditorState? _resumeEditorState;
  Future<void>? _loadFuture;
  bool _isLoading = true;

  List<Idea> get ideas => List.unmodifiable(_ideas);
  IdeaEditorState? get resumeEditorState => _resumeEditorState;
  bool get isLoading => _isLoading;
  NoteVaultService? get vault => _vault;

  Future<bool> encryptsLockedIdeas() async {
    final vault = _vault;
    return vault != null && await vault.isSetUp();
  }

  Future<void> ensureLoaded() {
    return _loadFuture ??= _loadIdeas();
  }

  Future<void> reloadFromStorage() {
    final future = _loadIdeas();
    _loadFuture = future;
    return future;
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
    String? lastOpenedSectionId,
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
    var savedIdea = Idea(
      id: existingIdea?.id ?? generateIdeaVaultId('idea'),
      title: normalizedTitle,
      createdAt: existingIdea?.createdAt ?? now,
      updatedAt: now,
      lastOpenedSectionId:
          lastOpenedSectionId ?? existingIdea?.lastOpenedSectionId,
      isLocked: existingIdea?.isLocked ?? false,
      sections: normalizedSections,
    );

    final vault = _vault;
    if (savedIdea.isLocked && await encryptsLockedIdeas()) {
      try {
        savedIdea = await vault!.encryptIdea(savedIdea);
      } finally {
        vault!.releaseIfIdle();
      }
    } else if (existingIdea?.isEncrypted ?? false) {
      return null;
    }

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

  Future<void> saveLastOpenedSectionId({
    required String ideaId,
    required String sectionId,
  }) async {
    await ensureLoaded();

    final existingIndex = _ideas.indexWhere((idea) => idea.id == ideaId);
    if (existingIndex == -1) {
      return;
    }

    final idea = _ideas[existingIndex];
    if ((!idea.isEncrypted &&
            !idea.sections.any((section) => section.id == sectionId)) ||
        idea.lastOpenedSectionId == sectionId) {
      return;
    }

    await _ideasRepo.updateLastOpenedSectionId(
      ideaId: ideaId,
      sectionId: sectionId,
    );

    final nextIdeas = [..._ideas];
    nextIdeas[existingIndex] = idea.copyWith(lastOpenedSectionId: sectionId);
    _ideas = nextIdeas;
    notifyListeners();
  }

  Future<void> setIdeaLocked({
    required String ideaId,
    required bool isLocked,
  }) async {
    await ensureLoaded();

    final existingIndex = _ideas.indexWhere((idea) => idea.id == ideaId);
    if (existingIndex == -1) {
      return;
    }

    final idea = _ideas[existingIndex];
    if (idea.isLocked == isLocked && !(isLocked && _needsEncryption(idea))) {
      return;
    }

    final vault = _vault;
    if (vault != null && (idea.isEncrypted || await vault.isSetUp())) {
      final Idea stored;
      try {
        if (isLocked) {
          stored = await vault.encryptIdea(idea.copyWith(isLocked: true));
        } else {
          final plain = await vault.decryptIdea(idea);
          stored = await _withFreeSectionIds(
            plain.copyWith(isLocked: false, titleHidden: false),
          );
        }
      } finally {
        vault.releaseIfIdle();
      }
      await _ideasRepo.upsertIdea(stored);
      if (isLocked) {
        await _ideasRepo.compact();
      }
      _replaceInMemory(stored);
      return;
    }

    await _ideasRepo.updateIdeaLockState(
      ideaId: ideaId,
      isLocked: isLocked,
    );

    final nextIdeas = [..._ideas];
    nextIdeas[existingIndex] = idea.copyWith(isLocked: isLocked);
    _ideas = nextIdeas;
    notifyListeners();
  }

  bool _needsEncryption(Idea idea) =>
      idea.isLocked && !idea.isEncrypted && _vault != null;

  void _replaceInMemory(Idea stored) {
    final index = _ideas.indexWhere((idea) => idea.id == stored.id);
    final nextIdeas = [..._ideas];
    if (index == -1) {
      nextIdeas.add(stored);
    } else {
      nextIdeas[index] = stored;
    }
    _ideas = _sortIdeas(nextIdeas);
    notifyListeners();
  }

  Future<Idea> _withFreeSectionIds(Idea idea) async {
    final taken = await _ideasRepo.sectionIdsNotOwnedBy(idea.id);
    if (!idea.sections.any((section) => taken.contains(section.id))) {
      return idea;
    }
    final remapped = <String, String>{};
    final sections = [
      for (final section in idea.sections)
        if (taken.contains(section.id))
          section.copyWith(
            id: remapped[section.id] = generateIdeaVaultId('section'),
          )
        else
          section,
    ];
    final lastOpened = idea.lastOpenedSectionId;
    return idea.copyWith(
      sections: sections,
      lastOpenedSectionId:
          lastOpened == null ? null : remapped[lastOpened] ?? lastOpened,
    );
  }

  Future<Idea?> openLockedIdea(String ideaId) async {
    await ensureLoaded();
    final idea = findById(ideaId);
    if (idea == null || !idea.isEncrypted) {
      return idea;
    }
    final vault = _vault;
    if (vault == null) {
      return null;
    }
    try {
      return await vault.decryptIdea(idea);
    } finally {
      vault.releaseIfIdle();
    }
  }

  Future<int> encryptPendingLockedIdeas() async {
    final vault = _vault;
    if (vault == null || !await vault.isSetUp()) {
      return 0;
    }
    final count = await vault.encryptPlaintextLockedIdeas();
    if (count > 0) {
      await reloadFromStorage();
    }
    return count;
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

    final idea = await openLockedIdea(ideaId);
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
              NoteMarkup.escapeLiteral(trimmedContent),
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
