import 'package:equatable/equatable.dart';

const List<String> defaultIdeaSectionNames = [
  'Idea',
];

int _ideaVaultIdCounter = 0;

String generateIdeaVaultId(String prefix) {
  _ideaVaultIdCounter += 1;
  return '$prefix-${DateTime.now().microsecondsSinceEpoch}-$_ideaVaultIdCounter';
}

String createEmptyIdeaContent() => '';

String _legacyContentFromDelta(dynamic rawDelta) {
  if (rawDelta is! List<dynamic>) {
    return '';
  }

  final buffer = StringBuffer();
  for (final operation in rawDelta) {
    if (operation is! Map<String, dynamic>) {
      continue;
    }

    final insert = operation['insert'];
    if (insert is String) {
      buffer.write(insert);
    }
  }

  return buffer.toString();
}

class IdeaSection extends Equatable {
  const IdeaSection({
    required this.id,
    required this.name,
    required this.content,
  });

  factory IdeaSection.empty({
    String? id,
    required String name,
  }) {
    return IdeaSection(
      id: id ?? generateIdeaVaultId('section'),
      name: name,
      content: createEmptyIdeaContent(),
    );
  }

  factory IdeaSection.fromJson(Map<String, dynamic> json) {
    return IdeaSection(
      id: json['id'] as String? ?? generateIdeaVaultId('section'),
      name: json['name'] as String? ?? 'Untitled Section',
      content:
          json['content'] as String? ?? _legacyContentFromDelta(json['delta']),
    );
  }

  final String id;
  final String name;
  final String content;

  IdeaSection copyWith({
    String? id,
    String? name,
    String? content,
  }) {
    return IdeaSection(
      id: id ?? this.id,
      name: name ?? this.name,
      content: content ?? this.content,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'content': content,
    };
  }

  @override
  List<Object> get props => [id, name, content];
}

class Idea extends Equatable {
  Idea({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required List<IdeaSection> sections,
    this.lastOpenedSectionId,
    this.isLocked = false,
    this.encryptedPayload,
    this.titleHidden = false,
  }) : sections = List.unmodifiable(
          sections.map((section) => section.copyWith()).toList(),
        );

  factory Idea.fromJson(Map<String, dynamic> json) {
    final rawSections = json['sections'] as List<dynamic>? ?? const [];
    return Idea(
      id: json['id'] as String? ?? generateIdeaVaultId('idea'),
      title: json['title'] as String? ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
      lastOpenedSectionId: json['lastOpenedSectionId'] as String?,
      isLocked: json['isLocked'] as bool? ?? false,
      encryptedPayload: json['encryptedPayload'] as String?,
      titleHidden: json['titleHidden'] as bool? ?? false,
      sections: rawSections
          .whereType<Map<String, dynamic>>()
          .map(IdeaSection.fromJson)
          .toList(),
    );
  }

  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? lastOpenedSectionId;
  final bool isLocked;
  final String? encryptedPayload;
  final bool titleHidden;
  final List<IdeaSection> sections;

  bool get isEncrypted => encryptedPayload != null;

  Idea copyWith({
    String? id,
    String? title,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? lastOpenedSectionId,
    bool? isLocked,
    List<IdeaSection>? sections,
    String? encryptedPayload,
    bool clearEncryptedPayload = false,
    bool? titleHidden,
  }) {
    return Idea(
      id: id ?? this.id,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastOpenedSectionId: lastOpenedSectionId ?? this.lastOpenedSectionId,
      isLocked: isLocked ?? this.isLocked,
      sections: sections ?? this.sections,
      encryptedPayload: clearEncryptedPayload
          ? null
          : encryptedPayload ?? this.encryptedPayload,
      titleHidden: titleHidden ?? this.titleHidden,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'lastOpenedSectionId': lastOpenedSectionId,
      'isLocked': isLocked,
      if (encryptedPayload != null) 'encryptedPayload': encryptedPayload,
      if (titleHidden) 'titleHidden': true,
      'sections': sections.map((section) => section.toJson()).toList(),
    };
  }

  @override
  List<Object?> get props => [
        id,
        title,
        createdAt,
        updatedAt,
        lastOpenedSectionId,
        isLocked,
        encryptedPayload,
        titleHidden,
        sections,
      ];
}

List<IdeaSection> buildDefaultIdeaSections() {
  return defaultIdeaSectionNames
      .map((name) => IdeaSection.empty(name: name))
      .toList();
}
