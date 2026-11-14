import 'package:idea_vault/data/managers/local/ideas_database.dart';
import 'package:idea_vault/data/repositories/local/ideas.dart';
import 'package:idea_vault/models/idea.dart';

class InMemoryIdeasRepo extends IdeasRepo {
  InMemoryIdeasRepo() : super(IdeasDatabaseManager(databasePath: 'in-memory'));

  List<Idea> _ideas = const [];

  @override
  Future<List<Idea>> getIdeas() async {
    return _ideas.map(_cloneIdea).toList();
  }

  @override
  Future<void> upsertIdea(Idea idea) async {
    final existingIndex =
        _ideas.indexWhere((storedIdea) => storedIdea.id == idea.id);
    if (existingIndex == -1) {
      _ideas = [..._ideas, _cloneIdea(idea)];
      return;
    }

    final nextIdeas = [..._ideas];
    nextIdeas[existingIndex] = _cloneIdea(idea);
    _ideas = nextIdeas;
  }

  @override
  Future<void> deleteIdeas(Iterable<String> ideaIds) async {
    final ids = ideaIds.toSet();
    _ideas =
        _ideas.where((idea) => !ids.contains(idea.id)).map(_cloneIdea).toList();
  }

  @override
  Future<void> updateLastOpenedSectionId({
    required String ideaId,
    required String sectionId,
  }) async {
    _ideas = [
      for (final idea in _ideas)
        if (idea.id == ideaId)
          _cloneIdea(idea.copyWith(lastOpenedSectionId: sectionId))
        else
          _cloneIdea(idea),
    ];
  }

  @override
  Future<void> updateIdeaLockState({
    required String ideaId,
    required bool isLocked,
  }) async {
    _ideas = [
      for (final idea in _ideas)
        if (idea.id == ideaId)
          _cloneIdea(idea.copyWith(isLocked: isLocked))
        else
          _cloneIdea(idea),
    ];
  }

  @override
  Future<void> saveIdeas(List<Idea> ideas) async {
    _ideas = ideas.map(_cloneIdea).toList();
  }

  @override
  Future<void> writeIdeasAtomically(List<Idea> ideas) async {
    for (final idea in ideas) {
      await upsertIdea(idea);
    }
  }

  @override
  Future<bool> hasEncryptedIdeas() async {
    return _ideas.any((idea) => idea.isEncrypted);
  }

  @override
  Future<Set<String>> sectionIdsNotOwnedBy(String ideaId) async {
    return {
      for (final idea in _ideas)
        if (idea.id != ideaId)
          for (final section in idea.sections) section.id,
    };
  }

  int compactCount = 0;

  @override
  Future<void> compact() async {
    compactCount += 1;
  }

  Idea _cloneIdea(Idea idea) {
    return idea.copyWith(
      sections: idea.sections.map((section) => section.copyWith()).toList(),
    );
  }
}
