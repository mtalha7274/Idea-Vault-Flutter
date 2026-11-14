import 'package:flutter/foundation.dart';

class SelectionController extends ChangeNotifier {
  final Set<String> _selectedIds = <String>{};

  Set<String> get selectedIds => Set.unmodifiable(_selectedIds);
  int get count => _selectedIds.length;
  bool get isActive => _selectedIds.isNotEmpty;

  bool isSelected(String id) => _selectedIds.contains(id);

  void select(String id) {
    if (_selectedIds.add(id)) {
      notifyListeners();
    }
  }

  void toggle(String id) {
    if (!_selectedIds.remove(id)) {
      _selectedIds.add(id);
    }
    notifyListeners();
  }

  void selectAll(Iterable<String> ids) {
    final before = _selectedIds.length;
    _selectedIds.addAll(ids);
    if (_selectedIds.length != before) {
      notifyListeners();
    }
  }

  void deselectAll(Iterable<String> ids) {
    final before = _selectedIds.length;
    _selectedIds.removeAll(ids);
    if (_selectedIds.length != before) {
      notifyListeners();
    }
  }

  void clear() {
    if (_selectedIds.isEmpty) {
      return;
    }
    _selectedIds.clear();
    notifyListeners();
  }

  void retainExisting(Iterable<String> existingIds) {
    final existing = existingIds.toSet();
    final before = _selectedIds.length;
    _selectedIds.removeWhere((id) => !existing.contains(id));
    if (_selectedIds.length != before) {
      notifyListeners();
    }
  }

  bool containsAll(Iterable<String> ids) {
    for (final id in ids) {
      if (!_selectedIds.contains(id)) {
        return false;
      }
    }
    return true;
  }
}
