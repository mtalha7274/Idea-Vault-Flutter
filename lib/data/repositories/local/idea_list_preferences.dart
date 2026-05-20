import '../../../core/constants/app_constants.dart';
import '../../managers/local/local_storage.dart';

enum IdeaSortOption {
  newestFirst,
  oldestFirst,
  mostSections,
}

enum IdeaLayoutOption {
  list,
  grid,
}

class IdeaListPreferencesRepo {
  const IdeaListPreferencesRepo(this._manager);

  final LocalStorageManager _manager;

  IdeaSortOption getSortOption() {
    final rawValue = _manager.getString(key: AppConstants.ideaListSort);
    for (final option in IdeaSortOption.values) {
      if (option.name == rawValue) {
        return option;
      }
    }
    return IdeaSortOption.newestFirst;
  }

  Future<void> saveSortOption(IdeaSortOption sortOption) async {
    await _manager.setString(
      key: AppConstants.ideaListSort,
      value: sortOption.name,
    );
  }

  IdeaLayoutOption getLayoutOption() {
    final rawValue = _manager.getString(key: AppConstants.ideaListLayout);
    for (final option in IdeaLayoutOption.values) {
      if (option.name == rawValue) {
        return option;
      }
    }
    return IdeaLayoutOption.list;
  }

  Future<void> saveLayoutOption(IdeaLayoutOption layoutOption) async {
    await _manager.setString(
      key: AppConstants.ideaListLayout,
      value: layoutOption.name,
    );
  }
}
