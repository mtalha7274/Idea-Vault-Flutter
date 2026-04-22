import 'package:idea_vault/data/managers/local/local_storage.dart';

class MemoryLocalStorageManager implements LocalStorageManager {
  final Map<String, String> _values = {};

  @override
  Future<void> delete({required String key}) async {
    _values.remove(key);
  }

  @override
  Future<void> deleteAll() async {
    _values.clear();
  }

  @override
  String? getString({required String key}) {
    return _values[key];
  }

  @override
  Future<void> setString({
    required String key,
    required String value,
  }) async {
    _values[key] = value;
  }
}
