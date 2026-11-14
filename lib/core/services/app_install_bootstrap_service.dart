import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';

import '../../data/managers/local/local_storage.dart';
import '../../data/repositories/local/app_install_state.dart';
import '../../data/repositories/local/ideas.dart';
import '../../models/idea.dart';
import '../constants/view_constants.dart';
import '../editor/note_editor_preferences.dart';
import 'note_lock_auth_service.dart';
import 'note_lock_biometric_service.dart';

const String emptyUntitledIdeaEnglishTitle = 'Untitled Idea';
const String emptyUntitledIdeaSectionName = 'Idea';

bool isLeftoverEmptyUntitledIdea(
  Idea idea, {
  Set<String> untitledTitles = const {emptyUntitledIdeaEnglishTitle},
}) {
  if (idea.isLocked) {
    return false;
  }
  if (!untitledTitles.contains(idea.title)) {
    return false;
  }
  if (idea.sections.length != 1) {
    return false;
  }
  final section = idea.sections.single;
  return section.name == emptyUntitledIdeaSectionName &&
      section.content.trim().isEmpty;
}

class AppInstallBootstrapService {
  const AppInstallBootstrapService(
    this._installStateRepo,
    this._noteLockAuthService,
    this._noteLockBiometricService, {
    Future<bool> Function()? hasLocalAppData,
    IdeasRepo? Function()? ideasRepo,
    LocalStorageManager? Function()? localStorage,
    String? Function()? localizedUntitledTitle,
    Future<void> Function()? clearVaultKeyMaterial,
  })  : _hasLocalAppData = hasLocalAppData,
        _clearVaultKeyMaterial = clearVaultKeyMaterial,
        _ideasRepo = ideasRepo,
        _localStorage = localStorage,
        _localizedUntitledTitle = localizedUntitledTitle;

  static const String emptyIdeaCleanupFlagKey =
      'empty_untitled_idea_cleanup_done_v1';

  final AppInstallStateRepo _installStateRepo;
  final NoteLockAuthService _noteLockAuthService;
  final NoteLockBiometricService _noteLockBiometricService;
  final Future<bool> Function()? _hasLocalAppData;
  final IdeasRepo? Function()? _ideasRepo;
  final LocalStorageManager? Function()? _localStorage;
  final String? Function()? _localizedUntitledTitle;
  final Future<void> Function()? _clearVaultKeyMaterial;

  Future<void> runFreshInstallTasks() async {
    await _runInstallMarkerTasks();
    await runEmptyIdeaCleanup();
    unawaited(runNoteFormatCheck());
  }

  Future<NoteFormatCheckResult?> runNoteFormatCheck() async {
    try {
      final storage = _resolveLocalStorage();
      final ideasRepo = _resolveIdeasRepo();
      if (storage == null || ideasRepo == null) {
        return null;
      }
      if (NoteEditorPreferences.hasRunFormatCheck(storage: storage)) {
        return null;
      }
      final ideas = await ideasRepo.getIdeas();
      final sections = [
        for (final idea in ideas)
          for (final section in idea.sections)
            (
              NoteEditorPreferences.sectionKey(idea.id, section.id),
              section.content,
            ),
      ];
      final result = await checkNoteFormats(sections);
      await NoteEditorPreferences.storeFormatCheck(result, storage: storage);
      debugPrint(
        'Note format check: ${result.checkedCount} sections, '
        '${result.failedCount} use the plain editor',
      );
      return result;
    } catch (_) {
      return null;
    }
  }

  Future<void> _runInstallMarkerTasks() async {
    if (_installStateRepo.hasInstallMarker) {
      return;
    }
    if (await (_hasLocalAppData?.call() ?? Future<bool>.value(false))) {
      await _installStateRepo.markInstalled();
      return;
    }
    await _noteLockAuthService.clearPin();
    await _noteLockBiometricService.clearBiometricUnlock();
    await _clearVaultKeyMaterial?.call();
    await _installStateRepo.markInstalled();
  }

  Future<int> runEmptyIdeaCleanup() async {
    try {
      final storage = _resolveLocalStorage();
      final ideasRepo = _resolveIdeasRepo();
      if (storage == null || ideasRepo == null) {
        return 0;
      }
      if (storage.getString(key: emptyIdeaCleanupFlagKey) == 'true') {
        return 0;
      }

      final untitledTitles = {emptyUntitledIdeaEnglishTitle};
      final localizedTitle = _resolveLocalizedUntitledTitle();
      if (localizedTitle != null && localizedTitle.isNotEmpty) {
        untitledTitles.add(localizedTitle);
      }

      final ideas = await ideasRepo.getIdeas();
      final leftoverIds = [
        for (final idea in ideas)
          if (isLeftoverEmptyUntitledIdea(
            idea,
            untitledTitles: untitledTitles,
          ))
            idea.id,
      ];
      if (leftoverIds.isNotEmpty) {
        await ideasRepo.deleteIdeas(leftoverIds);
      }
      await storage.setString(key: emptyIdeaCleanupFlagKey, value: 'true');
      return leftoverIds.length;
    } catch (_) {
      return 0;
    }
  }

  IdeasRepo? _resolveIdeasRepo() {
    final override = _ideasRepo;
    if (override != null) {
      return override();
    }
    final locator = GetIt.instance;
    return locator.isRegistered<IdeasRepo>() ? locator<IdeasRepo>() : null;
  }

  LocalStorageManager? _resolveLocalStorage() {
    final override = _localStorage;
    if (override != null) {
      return override();
    }
    final locator = GetIt.instance;
    return locator.isRegistered<LocalStorageManager>()
        ? locator<LocalStorageManager>()
        : null;
  }

  String? _resolveLocalizedUntitledTitle() {
    final override = _localizedUntitledTitle;
    if (override != null) {
      return override();
    }
    try {
      final translated = ViewConstants.ideaEditorUntitledIdea.tr();
      return translated == ViewConstants.ideaEditorUntitledIdea
          ? null
          : translated;
    } catch (_) {
      return null;
    }
  }
}
