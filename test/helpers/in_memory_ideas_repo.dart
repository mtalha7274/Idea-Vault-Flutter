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
  Future<void> saveIdeas(List<Idea> ideas) async {
    _ideas = ideas.map(_cloneIdea).toList();
  }

  Idea _cloneIdea(Idea idea) {
    return idea.copyWith(
      sections: idea.sections.map((section) => section.copyWith()).toList(),
    );
  }
}
