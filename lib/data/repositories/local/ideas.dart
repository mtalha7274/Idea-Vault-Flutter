import 'dart:convert';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/helpers.dart';
import '../../../models/idea.dart';
import '../../managers/local/local_storage.dart';

class IdeasRepo {
  const IdeasRepo(this._manager);

  final LocalStorageManager _manager;

  List<Idea> getIdeas() {
    final raw = _manager.getString(key: AppConstants.ideas);
    if (raw == null || raw.isEmpty) {
      return const [];
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List<dynamic>) {
        return const [];
      }

      return decoded
          .whereType<Map<String, dynamic>>()
          .map(Idea.fromJson)
          .toList();
    } catch (error) {
      printLog('Failed to decode saved ideas: $error');
      return const [];
    }
  }

  Future<void> saveIdeas(List<Idea> ideas) async {
    await _manager.setString(
      key: AppConstants.ideas,
      value: jsonEncode(ideas.map((idea) => idea.toJson()).toList()),
    );
  }
}
