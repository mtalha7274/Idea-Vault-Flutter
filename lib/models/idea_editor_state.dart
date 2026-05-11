import 'dart:convert';

import 'package:equatable/equatable.dart';

class IdeaEditorState extends Equatable {
  const IdeaEditorState({
    required this.ideaId,
    required this.activeSectionId,
    required this.isPreviewMode,
  });

  factory IdeaEditorState.fromJson(Map<String, dynamic> json) {
    return IdeaEditorState(
      ideaId: json['ideaId'] as String,
      activeSectionId: json['activeSectionId'] as String,
      isPreviewMode: json['isPreviewMode'] as bool? ?? false,
    );
  }

  final String ideaId;
  final String activeSectionId;
  final bool isPreviewMode;

  IdeaEditorState copyWith({
    String? ideaId,
    String? activeSectionId,
    bool? isPreviewMode,
  }) {
    return IdeaEditorState(
      ideaId: ideaId ?? this.ideaId,
      activeSectionId: activeSectionId ?? this.activeSectionId,
      isPreviewMode: isPreviewMode ?? this.isPreviewMode,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ideaId': ideaId,
      'activeSectionId': activeSectionId,
      'isPreviewMode': isPreviewMode,
    };
  }

  String toJsonString() => jsonEncode(toJson());

  @override
  List<Object> get props => [ideaId, activeSectionId, isPreviewMode];
}
