import '../idea.dart';
import '../random_addition.dart';

class CloudBackupSnapshot {
  const CloudBackupSnapshot({
    required this.version,
    required this.exportedAt,
    required this.ideas,
    required this.randomAdditions,
  });

  static const int currentVersion = 2;

  factory CloudBackupSnapshot.fromJson(Map<String, dynamic> json) {
    final rawIdeas = json['ideas'] as List<dynamic>? ?? const [];
    final rawRandomAdditions =
        json['randomAdditions'] as List<dynamic>? ?? const [];
    return CloudBackupSnapshot(
      version: json['version'] as int? ?? currentVersion,
      exportedAt: DateTime.tryParse(json['exportedAt'] as String? ?? '') ??
          DateTime.now(),
      ideas: rawIdeas
          .whereType<Map<String, dynamic>>()
          .map(Idea.fromJson)
          .toList(growable: false),
      randomAdditions: rawRandomAdditions
          .whereType<Map<String, dynamic>>()
          .map(RandomAddition.fromJson)
          .toList(growable: false),
    );
  }

  factory CloudBackupSnapshot.fromIdeas(List<Idea> ideas) {
    return CloudBackupSnapshot.fromContent(
      ideas: ideas,
      randomAdditions: const [],
    );
  }

  factory CloudBackupSnapshot.fromContent({
    required List<Idea> ideas,
    required List<RandomAddition> randomAdditions,
  }) {
    return CloudBackupSnapshot(
      version: currentVersion,
      exportedAt: DateTime.now().toUtc(),
      ideas: ideas.map((idea) => idea.copyWith()).toList(growable: false),
      randomAdditions: randomAdditions
          .map((addition) => addition.copyWith())
          .toList(growable: false),
    );
  }

  final int version;
  final DateTime exportedAt;
  final List<Idea> ideas;
  final List<RandomAddition> randomAdditions;

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'exportedAt': exportedAt.toIso8601String(),
      'ideas': ideas.map((idea) => idea.toJson()).toList(),
      'randomAdditions':
          randomAdditions.map((addition) => addition.toJson()).toList(),
    };
  }
}
