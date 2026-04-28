import 'dart:convert';

import '../../../core/constants/app_constants.dart';
import '../../../models/idea_editor_state.dart';
import '../../managers/local/local_storage.dart';

class IdeaEditorStateRepo {
  const IdeaEditorStateRepo(this._manager);

  final LocalStorageManager _manager;

  IdeaEditorState? getState() {
    final rawValue = _manager.getString(key: AppConstants.ideaEditorState);
    if (rawValue == null || rawValue.isEmpty) {
      return null;
    }

    try {
      final json = jsonDecode(rawValue);
      if (json is! Map<String, dynamic>) {
        return null;
      }

      return IdeaEditorState.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveState(IdeaEditorState state) async {
    await _manager.setString(
      key: AppConstants.ideaEditorState,
      value: state.toJsonString(),
    );
  }

  Future<void> clearState() async {
    await _manager.delete(key: AppConstants.ideaEditorState);
  }
}
