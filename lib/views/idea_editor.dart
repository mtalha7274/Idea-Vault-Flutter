import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/router/app_router.dart';
import '../models/idea.dart';
import '../models/idea_editor_state.dart';
import '../viewmodels/providers/ideas_provider.dart';
import '../widgets/idea_markdown_editor.dart';
import 'ideas/idea_vault_theme.dart';

class IdeaEditorScreen extends StatefulWidget {
  const IdeaEditorScreen({
    super.key,
    this.ideaId,
  });

  final String? ideaId;

  @override
  State<IdeaEditorScreen> createState() => _IdeaEditorScreenState();
}

class _IdeaEditorScreenState extends State<IdeaEditorScreen> {
  late final TextEditingController _titleController;
  late final FocusNode _titleFocusNode;
  late List<IdeaSection> _sections;
  late Map<String, String> _sectionContentById;
  late String _activeSectionId;
  late String _initialSnapshot;

  bool _allowPop = false;
  bool _isPreviewMode = false;
  bool _isSaving = false;
  bool _showTitleError = false;

  @override
  void initState() {
    super.initState();

    final ideasProvider = context.read<IdeasProvider>();
    final existingIdea =
        widget.ideaId == null ? null : ideasProvider.findById(widget.ideaId!);
    final resumeState =
        existingIdea == null ? null : _matchingResumeState(ideasProvider);

    _sections =
        existingIdea?.sections.map((section) => section.copyWith()).toList() ??
            ideasProvider.createDefaultSections();
    _sectionContentById = {
      for (final section in _sections) section.id: section.content,
    };
    _activeSectionId = _resolveInitialSectionId(resumeState);
    _isPreviewMode = resumeState?.isPreviewMode ?? false;

    _titleController = TextEditingController(text: existingIdea?.title ?? '');
    _titleFocusNode = FocusNode();
    _titleController.addListener(_handleDraftChanged);
    _initialSnapshot = _snapshot();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (widget.ideaId == null && _titleController.text.trim().isEmpty) {
        _titleFocusNode.requestFocus();
      }
      _persistEditorState();
    });
  }

  @override
  void dispose() {
    FocusManager.instance.primaryFocus?.unfocus();
    _titleController
      ..removeListener(_handleDraftChanged)
      ..dispose();
    _titleFocusNode.dispose();
    super.dispose();
  }

  bool get _hasUnsavedChanges => _snapshot() != _initialSnapshot;

  @override
  Widget build(BuildContext context) {
    final navigator = Navigator.of(context);
    return PopScope<Object?>(
      canPop: _allowPop || !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) {
          await context.read<IdeasProvider>().clearEditorState();
          return;
        }

        final shouldClose = await _handleCloseRequest();
        if (shouldClose && mounted) {
          await _prepareForExit();
          if (mounted) {
            navigator.pop();
          }
        }
      },
      child: Scaffold(
        backgroundColor: IdeaVaultPalette.background(context),
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 10),
                child: _Header(
                  onClose: _onClosePressed,
                  onSave: _isSaving ? null : _onSavePressed,
                  isSaving: _isSaving,
                  isEditingExisting: widget.ideaId != null,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 860),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildTitleField(context),
                              const SizedBox(height: 20),
                              _buildSectionTabs(context),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: IdeaMarkdownEditor(
                        key: ValueKey(_activeSectionId),
                        initialValue:
                            _sectionContentById[_activeSectionId] ?? '',
                        placeholder: _sectionPlaceholder(),
                        initialPreviewMode: _isPreviewMode,
                        onPreviewModeChanged: _handlePreviewModeChanged,
                        onChanged: _updateActiveSectionContent,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTitleField(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const Key('idea-editor-title'),
          controller: _titleController,
          focusNode: _titleFocusNode,
          autofocus: widget.ideaId == null,
          textCapitalization: TextCapitalization.sentences,
          minLines: 1,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: 'Enter idea title...',
            hintStyle: ideaVaultHeadline(
              context,
              size: 38,
              weight: FontWeight.w800,
              color: IdeaVaultPalette.outline(context),
              height: 1.08,
              letterSpacing: -1.2,
            ),
            border: InputBorder.none,
            isCollapsed: true,
          ),
          style: ideaVaultHeadline(
            context,
            size: 38,
            weight: FontWeight.w800,
            height: 1.08,
            letterSpacing: -1.2,
          ),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: _titleErrorText == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    _titleErrorText!,
                    key: const Key('idea-editor-title-error'),
                    style: ideaVaultLabel(
                      context,
                      size: 13,
                      weight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  String? get _titleErrorText {
    if (!_showTitleError || _titleController.text.trim().isNotEmpty) {
      return null;
    }
    return 'Please add a title before saving';
  }

  Widget _buildAddSectionTab() {
    return Tooltip(
      message: 'Add section',
      child: _SectionTabButton(
        key: const Key('idea-editor-add-section'),
        icon: Icons.add_rounded,
        isActive: false,
        onTap: _showAddSectionSheet,
      ),
    );
  }

  Widget _buildSectionTabs(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: IdeaVaultPalette.outlineSoft(context)),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < _sections.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              _SectionTabButton(
                key: Key(
                    'idea-editor-section-tab-${_sections[i].name.toLowerCase()}'),
                title: _sections[i].name,
                isActive: _sections[i].id == _activeSectionId,
                onTap: () => _handleSectionTap(_sections[i]),
              ),
            ],
            const SizedBox(width: 10),
            _buildAddSectionTab(),
          ],
        ),
      ),
    );
  }

  IdeaEditorState? _matchingResumeState(IdeasProvider ideasProvider) {
    final state = ideasProvider.resumeEditorState;
    if (state == null || state.ideaId != widget.ideaId) {
      return null;
    }
    return state;
  }

  String _resolveInitialSectionId(IdeaEditorState? resumeState) {
    final restoredSectionId = resumeState?.activeSectionId;
    if (restoredSectionId != null &&
        _sections.any((section) => section.id == restoredSectionId)) {
      return restoredSectionId;
    }

    return _sections.first.id;
  }

  String _sectionPlaceholder() {
    final activeSection = _sections.firstWhere(
      (section) => section.id == _activeSectionId,
    );

    if (activeSection.name == 'Idea') {
      return 'Start articulating your vision here.';
    }
    return 'Capture ${activeSection.name.toLowerCase()} here.';
  }

  void _switchSection(String sectionId) {
    if (sectionId == _activeSectionId) {
      return;
    }

    setState(() {
      _activeSectionId = sectionId;
    });
    _persistEditorState();
  }

  Future<void> _handleSectionTap(IdeaSection section) async {
    if (section.id != _activeSectionId) {
      _switchSection(section.id);
      return;
    }

    await _showEditSectionSheet(section);
  }

  void _updateSectionContent(String sectionId, String content) {
    if (_sectionContentById[sectionId] == content) {
      return;
    }

    setState(() {
      _sectionContentById = {
        ..._sectionContentById,
        sectionId: content,
      };
    });
  }

  void _updateActiveSectionContent(String content) {
    _updateSectionContent(_activeSectionId, content);
  }

  void _handlePreviewModeChanged(bool isPreviewMode) {
    if (_isPreviewMode == isPreviewMode) {
      return;
    }

    setState(() {
      _isPreviewMode = isPreviewMode;
    });
    _persistEditorState();
  }

  Future<void> _persistEditorState() async {
    await context.read<IdeasProvider>().saveEditorState(
          ideaId: widget.ideaId,
          activeSectionId: _activeSectionId,
          isPreviewMode: _isPreviewMode,
        );
  }

  Future<void> _showAddSectionSheet() async {
    final result = await _showSectionSheet();
    if (!mounted || result == null || result.name == null) {
      return;
    }

    final normalizedName = result.name!.trim();
    if (normalizedName.isEmpty) {
      return;
    }

    final hasDuplicate = _sections.any(
      (section) => section.name.toLowerCase() == normalizedName.toLowerCase(),
    );
    if (hasDuplicate) {
      _showDuplicateSectionMessage();
      return;
    }

    final newSection = IdeaSection.empty(name: normalizedName);
    setState(() {
      _sections = [..._sections, newSection];
      _sectionContentById = {
        ..._sectionContentById,
        newSection.id: newSection.content,
      };
      _activeSectionId = newSection.id;
    });
    _persistEditorState();
  }

  Future<void> _showEditSectionSheet(IdeaSection section) async {
    final result = await _showSectionSheet(section: section);
    if (!mounted || result == null) {
      return;
    }

    if (result.shouldDelete) {
      _deleteSection(section.id);
      return;
    }

    final nextName = result.name?.trim() ?? '';
    if (nextName.isEmpty) {
      return;
    }

    final hasDuplicate = _sections.any(
      (candidate) =>
          candidate.id != section.id &&
          candidate.name.toLowerCase() == nextName.toLowerCase(),
    );
    if (hasDuplicate) {
      _showDuplicateSectionMessage();
      return;
    }

    if (nextName == section.name) {
      return;
    }

    setState(() {
      _sections = [
        for (final candidate in _sections)
          if (candidate.id == section.id)
            candidate.copyWith(name: nextName)
          else
            candidate,
      ];
    });
    _persistEditorState();
  }

  Future<_SectionSheetResult?> _showSectionSheet({
    IdeaSection? section,
  }) async {
    final nameController = TextEditingController();
    nameController.text = section?.name ?? '';
    nameController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: nameController.text.length,
    );

    final result = await showModalBottomSheet<_SectionSheetResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: IdeaVaultPalette.surface(context),
      builder: (sheetContext) {
        final bottomInset = MediaQuery.viewInsetsOf(sheetContext).bottom;
        final isEditing = section != null;
        final canDelete = isEditing && _sections.length > 1;
        return Padding(
          padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + bottomInset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isEditing ? 'Edit section' : 'Add section',
                style: ideaVaultHeadline(
                  sheetContext,
                  size: 24,
                  weight: FontWeight.w800,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                isEditing
                    ? 'Rename this section or remove it from this idea.'
                    : 'Create another space for this idea.',
                style: ideaVaultBody(
                  sheetContext,
                  size: 15,
                  weight: FontWeight.w500,
                  color: IdeaVaultPalette.textMuted(sheetContext),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 18),
              TextField(
                key: const Key('idea-editor-section-name'),
                controller: nameController,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  hintText: 'Section name',
                  filled: true,
                  fillColor: IdeaVaultPalette.surfaceLow(sheetContext),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    child: Text(
                      'Cancel',
                      style: ideaVaultLabel(
                        sheetContext,
                        size: 14,
                        weight: FontWeight.w700,
                        color: IdeaVaultPalette.textMuted(sheetContext),
                      ),
                    ),
                  ),
                  if (canDelete) ...[
                    TextButton(
                      key: const Key('idea-editor-delete-section'),
                      onPressed: () => Navigator.of(sheetContext).pop(
                        const _SectionSheetResult.delete(),
                      ),
                      child: Text(
                        'Delete',
                        style: ideaVaultLabel(
                          sheetContext,
                          size: 14,
                          weight: FontWeight.w700,
                          color: Theme.of(sheetContext).colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  FilledButton(
                    key: const Key('idea-editor-create-section'),
                    style: FilledButton.styleFrom(
                      backgroundColor: IdeaVaultPalette.primary(sheetContext),
                      foregroundColor: IdeaVaultPalette.onPrimary(sheetContext),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                    ),
                    onPressed: () {
                      final nextName = nameController.text.trim();
                      if (nextName.isEmpty) {
                        return;
                      }
                      Navigator.of(sheetContext).pop(
                        _SectionSheetResult.rename(nextName),
                      );
                    },
                    child: Text(
                      isEditing ? 'Save' : 'Add',
                      style: ideaVaultLabel(
                        sheetContext,
                        size: 14,
                        weight: FontWeight.w700,
                        color: IdeaVaultPalette.onPrimary(sheetContext),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      nameController.dispose();
    });
    return result;
  }

  void _deleteSection(String sectionId) {
    if (_sections.length <= 1) {
      return;
    }

    final currentIndex =
        _sections.indexWhere((section) => section.id == sectionId);
    if (currentIndex == -1) {
      return;
    }

    final remainingSections = [..._sections]..removeAt(currentIndex);
    final nextActiveSectionId = sectionId == _activeSectionId
        ? remainingSections[
                (currentIndex - 1).clamp(0, remainingSections.length - 1)]
            .id
        : _activeSectionId;

    setState(() {
      _sections = remainingSections;
      _sectionContentById = {
        for (final entry in _sectionContentById.entries)
          if (entry.key != sectionId) entry.key: entry.value,
      };
      _activeSectionId = nextActiveSectionId;
    });
    _persistEditorState();
  }

  void _showDuplicateSectionMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('That section already exists.')),
    );
  }

  void _handleDraftChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Future<void> _onSavePressed() async {
    if (_titleController.text.trim().isEmpty) {
      setState(() {
        _showTitleError = true;
      });
      _titleFocusNode.requestFocus();
      return;
    }

    setState(() {
      _showTitleError = false;
      _isSaving = true;
    });

    final ideasProvider = context.read<IdeasProvider>();
    final sectionsToSave = _sections
        .map(
          (section) => section.copyWith(
            content: _sectionContentById[section.id] ?? '',
          ),
        )
        .toList();

    final savedIdea = await ideasProvider.saveIdea(
      ideaId: widget.ideaId,
      title: _titleController.text,
      sections: sectionsToSave,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _isSaving = false;
    });

    if (savedIdea == null) {
      if (_titleController.text.trim().isEmpty) {
        setState(() {
          _showTitleError = true;
        });
        _titleFocusNode.requestFocus();
      }
      return;
    }

    _initialSnapshot = _snapshot();
    await _prepareForExit();
    if (mounted) {
      AppRouter.pop(context, savedIdea.id);
    }
  }

  Future<void> _onClosePressed() async {
    final shouldClose = await _handleCloseRequest();
    if (shouldClose && mounted) {
      await _prepareForExit();
      if (mounted) {
        AppRouter.pop(context);
      }
    }
  }

  Future<bool> _handleCloseRequest() async {
    if (!_hasUnsavedChanges) {
      return true;
    }

    final discardChanges = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Discard changes?'),
          content: const Text(
            'You have unsaved edits in this idea. Leaving now will lose them.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Keep editing'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Discard'),
            ),
          ],
        );
      },
    );

    return discardChanges ?? false;
  }

  Future<void> _prepareForExit() async {
    if (mounted && !_allowPop) {
      setState(() {
        _allowPop = true;
      });
    }
    await context.read<IdeasProvider>().clearEditorState();
  }

  String _snapshot() {
    final sectionsSnapshot = _sections
        .map(
          (section) => {
            'id': section.id,
            'name': section.name,
            'content': _sectionContentById[section.id] ?? section.content,
          },
        )
        .toList();

    return jsonEncode({
      'title': _titleController.text,
      'sections': sectionsSnapshot,
    });
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.onClose,
    required this.onSave,
    required this.isSaving,
    required this.isEditingExisting,
  });

  final VoidCallback onClose;
  final VoidCallback? onSave;
  final bool isSaving;
  final bool isEditingExisting;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          key: const Key('idea-editor-close'),
          onPressed: onClose,
          style: IconButton.styleFrom(
            backgroundColor: IdeaVaultPalette.surfaceLow(context),
            foregroundColor: IdeaVaultPalette.primary(context),
            padding: const EdgeInsets.all(14),
          ),
          icon: const Icon(Icons.close_rounded),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            isEditingExisting ? 'Edit Idea' : 'New Idea',
            style: ideaVaultHeadline(
              context,
              size: 22,
              weight: FontWeight.w800,
              height: 1.2,
            ),
          ),
        ),
        FilledButton(
          key: const Key('idea-editor-save'),
          onPressed: onSave,
          style: FilledButton.styleFrom(
            backgroundColor: IdeaVaultPalette.primary(context),
            foregroundColor: IdeaVaultPalette.onPrimary(context),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          ),
          child: Text(
            isSaving ? 'Saving...' : 'Save',
            style: ideaVaultLabel(
              context,
              size: 14,
              weight: FontWeight.w700,
              color: IdeaVaultPalette.onPrimary(context),
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionTabButton extends StatelessWidget {
  const _SectionTabButton({
    super.key,
    this.title,
    this.icon,
    required this.isActive,
    required this.onTap,
  }) : assert(
          (title != null && icon == null) || (title == null && icon != null),
          'Exactly one of title or icon must be set',
        );

  final String? title;
  final IconData? icon;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = isActive
        ? IdeaVaultPalette.primary(context)
        : IdeaVaultPalette.textMuted(context);

    final child = icon != null
        ? Icon(
            icon,
            size: 22,
            color: color,
          )
        : Text(
            title!,
            style: ideaVaultBody(
              context,
              size: 18,
              weight: isActive ? FontWeight.w700 : FontWeight.w600,
              color: color,
            ),
          );

    return InkWell(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        constraints: const BoxConstraints(minWidth: 0),
        alignment: Alignment.center,
        padding: EdgeInsets.symmetric(
          horizontal: icon != null ? 10 : 11,
          vertical: 10,
        ),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isActive
                  ? IdeaVaultPalette.primary(context)
                  : Colors.transparent,
              width: 2.5,
            ),
          ),
        ),
        child: child,
      ),
    );
  }
}

class _SectionSheetResult {
  const _SectionSheetResult.rename(this.name) : shouldDelete = false;

  const _SectionSheetResult.delete()
      : name = null,
        shouldDelete = true;

  final String? name;
  final bool shouldDelete;
}
