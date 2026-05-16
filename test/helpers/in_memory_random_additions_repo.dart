import 'package:idea_vault/data/managers/local/ideas_database.dart';
import 'package:idea_vault/data/repositories/local/random_additions.dart';
import 'package:idea_vault/models/random_addition.dart';

class InMemoryRandomAdditionsRepo extends RandomAdditionsRepo {
  InMemoryRandomAdditionsRepo()
      : super(IdeasDatabaseManager(databasePath: 'in-memory-random'));

  List<RandomAddition> _additions = const [];

  @override
  Future<List<RandomAddition>> getAdditions() async {
    return _additions.map((addition) => addition.copyWith()).toList();
  }

  @override
  Future<void> upsertAddition(RandomAddition addition) async {
    final existingIndex =
        _additions.indexWhere((stored) => stored.id == addition.id);
    if (existingIndex == -1) {
      _additions = [..._additions, addition.copyWith()];
      return;
    }

    final nextAdditions = [..._additions];
    nextAdditions[existingIndex] = addition.copyWith();
    _additions = nextAdditions;
  }

  @override
  Future<void> deleteAddition(String additionId) async {
    _additions = _additions
        .where((addition) => addition.id != additionId)
        .map((addition) => addition.copyWith())
        .toList();
  }

  @override
  Future<void> saveAdditions(List<RandomAddition> additions) async {
    _additions = additions.map((addition) => addition.copyWith()).toList();
  }
}
