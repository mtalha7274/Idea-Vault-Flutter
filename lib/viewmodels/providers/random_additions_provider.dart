import 'package:flutter/material.dart';

import '../../data/repositories/local/random_additions.dart';
import '../../models/random_addition.dart';

class RandomAdditionsProvider with ChangeNotifier {
  RandomAdditionsProvider(this._repo) {
    ensureLoaded();
  }

  final RandomAdditionsRepo _repo;
  List<RandomAddition> _additions = const [];
  Future<void>? _loadFuture;
  bool _isLoading = true;

  List<RandomAddition> get additions => List.unmodifiable(_additions);
  bool get isLoading => _isLoading;

  Future<void> ensureLoaded() {
    return _loadFuture ??= _loadAdditions();
  }

  Future<RandomAddition?> addAddition(String content) async {
    await ensureLoaded();

    final normalizedContent = content.trim();
    if (normalizedContent.isEmpty) {
      return null;
    }

    final addition = RandomAddition(content: normalizedContent);
    await _repo.upsertAddition(addition);
    _additions = _sortAdditions([..._additions, addition]);
    notifyListeners();
    return addition;
  }

  Future<void> deleteAddition(String additionId) async {
    await ensureLoaded();
    await _repo.deleteAddition(additionId);
    _additions = _additions
        .where((addition) => addition.id != additionId)
        .toList(growable: false);
    notifyListeners();
  }

  Future<void> deleteAdditions(Iterable<String> additionIds) async {
    await ensureLoaded();
    final ids = additionIds.toSet();
    if (ids.isEmpty) {
      return;
    }

    for (final id in ids) {
      await _repo.deleteAddition(id);
    }
    _additions = _additions
        .where((addition) => !ids.contains(addition.id))
        .toList(growable: false);
    notifyListeners();
  }

  Future<void> replaceAdditions(List<RandomAddition> additions) async {
    await ensureLoaded();
    final nextAdditions =
        additions.map((addition) => addition.copyWith()).toList();
    await _repo.saveAdditions(nextAdditions);
    _additions = _sortAdditions(nextAdditions);
    notifyListeners();
  }

  Future<void> _loadAdditions() async {
    _isLoading = true;
    final loadedAdditions = await _repo.getAdditions();
    _additions = _sortAdditions(loadedAdditions);
    _isLoading = false;
    notifyListeners();
  }

  List<RandomAddition> _sortAdditions(List<RandomAddition> additions) {
    final sortedAdditions = [...additions];
    sortedAdditions.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return sortedAdditions;
  }
}
