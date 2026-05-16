import 'package:equatable/equatable.dart';

import 'idea.dart';

class RandomAddition extends Equatable {
  RandomAddition({
    String? id,
    required this.content,
    DateTime? createdAt,
  })  : id = id ?? generateIdeaVaultId('random-addition'),
        createdAt = createdAt ?? DateTime.now();

  factory RandomAddition.fromJson(Map<String, dynamic> json) {
    return RandomAddition(
      id: json['id'] as String? ?? generateIdeaVaultId('random-addition'),
      content: json['content'] as String? ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  final String id;
  final String content;
  final DateTime createdAt;

  RandomAddition copyWith({
    String? id,
    String? content,
    DateTime? createdAt,
  }) {
    return RandomAddition(
      id: id ?? this.id,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'content': content,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  @override
  List<Object> get props => [id, content, createdAt];
}
