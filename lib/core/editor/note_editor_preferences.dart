import 'dart:convert';
import 'dart:isolate';

import 'package:get_it/get_it.dart';

import '../../data/managers/local/local_storage.dart';
import 'note_markup.dart';

class NoteFormatCheckResult {
  const NoteFormatCheckResult({
    required this.checkedCount,
    required this.failingKeys,
  });

  final int checkedCount;
  final List<String> failingKeys;

  int get failedCount => failingKeys.length;
}

class NoteEditorPreferences {
  const NoteEditorPreferences._();

  static const String forceClassicKey = 'editor_force_classic_v1';
  static const String formatCheckVersionKey = 'editor_format_check_version';
  static const String formatCheckFailuresKey = 'editor_format_check_failures';
  static const String formatCheckVersion = '1';

  static LocalStorageManager? storageOverride;

  static LocalStorageManager? get _storage {
    final override = storageOverride;
    if (override != null) {
      return override;
    }
    final locator = GetIt.instance;
    return locator.isRegistered<LocalStorageManager>()
        ? locator<LocalStorageManager>()
        : null;
  }

  static String sectionKey(String ideaId, String sectionId) =>
      '$ideaId/$sectionId';

  static bool get forceClassicEditor {
    try {
      return _storage?.getString(key: forceClassicKey) == 'true';
    } catch (_) {
      return false;
    }
  }

  static Future<void> setForceClassicEditor(bool value) async {
    await _storage?.setString(key: forceClassicKey, value: '$value');
  }

  static Set<String> get failingSections {
    try {
      final raw = _storage?.getString(key: formatCheckFailuresKey);
      if (raw == null || raw.isEmpty) {
        return const {};
      }
      return (jsonDecode(raw) as List<dynamic>).cast<String>().toSet();
    } catch (_) {
      return const {};
    }
  }

  static bool shouldUseClassicEditor({
    required String? ideaId,
    required String sectionId,
    required String content,
  }) {
    if (forceClassicEditor) {
      return true;
    }
    if (ideaId != null &&
        failingSections.contains(sectionKey(ideaId, sectionId))) {
      return true;
    }
    return !NoteMarkup.isRoundTripSafe(content);
  }

  static bool hasRunFormatCheck({LocalStorageManager? storage}) {
    try {
      return (storage ?? _storage)?.getString(key: formatCheckVersionKey) ==
          formatCheckVersion;
    } catch (_) {
      return false;
    }
  }

  static Future<void> storeFormatCheck(
    NoteFormatCheckResult result, {
    LocalStorageManager? storage,
  }) async {
    final target = storage ?? _storage;
    if (target == null) {
      return;
    }
    await target.setString(
      key: formatCheckFailuresKey,
      value: jsonEncode(result.failingKeys),
    );
    await target.setString(
      key: formatCheckVersionKey,
      value: formatCheckVersion,
    );
  }
}

Future<NoteFormatCheckResult> checkNoteFormats(
  List<(String, String)> sections,
) {
  return Isolate.run(() => checkNoteFormatsSync(sections));
}

NoteFormatCheckResult checkNoteFormatsSync(List<(String, String)> sections) {
  final failing = <String>[];
  for (final (key, content) in sections) {
    if (!NoteMarkup.isRoundTripSafe(content)) {
      failing.add(key);
    }
  }
  return NoteFormatCheckResult(
    checkedCount: sections.length,
    failingKeys: failing,
  );
}
