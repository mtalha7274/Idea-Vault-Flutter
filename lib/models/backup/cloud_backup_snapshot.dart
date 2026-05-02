import '../idea.dart';

class CloudBackupSnapshot {
  const CloudBackupSnapshot({
    required this.version,
    required this.exportedAt,
    required this.ideas,
  });

  static const int currentVersion = 1;

  factory CloudBackupSnapshot.fromJson(Map<String, dynamic> json) {
    final rawIdeas = json['ideas'] as List<dynamic>? ?? const [];
    return CloudBackupSnapshot(
      version: json['version'] as int? ?? currentVersion,
      exportedAt: DateTime.tryParse(json['exportedAt'] as String? ?? '') ??
          DateTime.now(),
      ideas: rawIdeas
          .whereType<Map<String, dynamic>>()
          .map(Idea.fromJson)
          .toList(growable: false),
    );
  }

  factory CloudBackupSnapshot.fromIdeas(List<Idea> ideas) {
    return CloudBackupSnapshot(
      version: currentVersion,
      exportedAt: DateTime.now().toUtc(),
      ideas: ideas.map((idea) => idea.copyWith()).toList(growable: false),
    );
  }

  final int version;
  final DateTime exportedAt;
  final List<Idea> ideas;

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'exportedAt': exportedAt.toIso8601String(),
      'ideas': ideas.map((idea) => idea.toJson()).toList(),
    };
  }
}
