import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:idea_vault/core/extensions/int.dart';
import 'package:keyboard_actions/keyboard_actions.dart';
import 'package:provider/provider.dart';

import '../config/router/app_router.dart';
import '../core/services/note_lock_auth_service.dart';
import '../core/services/note_lock_biometric_service.dart';
import '../core/utils/helpers.dart';
import '../data/repositories/remote/idea_organization_repository.dart';
import '../injection_container.dart';
import '../models/idea.dart';
import '../models/idea_editor_state.dart';
import '../models/premium/premium_feature.dart';
import '../viewmodels/providers/ideas_provider.dart';
import '../viewmodels/providers/premium/paywall_view_model.dart';
import '../viewmodels/providers/theme_provider.dart';
import '../widgets/ai_loading_overlay.dart';
import '../widgets/idea_markdown_editor.dart';
import '../widgets/note_lock_auth_dialog.dart';
import '../widgets/popups/delete_ideas_confirmation_dialog.dart';
import '../widgets/sheets/idea_editor_section_sheet.dart';
import '../widgets/sheets/idea_options_sheet.dart';
import '../widgets/sheets/organise_section_sheet.dart';
import '../core/constants/view_constants.dart';
import '../widgets/translated_text.dart';
import 'export_for_ai_screen.dart';
import 'ideas/idea_vault_theme.dart';

/// Aligned with SECTION_CONTENT_MAX_CHARS in Cloud Functions (`organizeSection`).
const int ideaSectionAiMaxCharacterLimit = 4200;
const int ideaSectionAiWarningCharacterLimit = 4000;
const String _untitledSectionName = 'Untitled';

class IdeaEditorScreen extends StatefulWidget {
  const IdeaEditorScreen({
    super.key,
    this.ideaId,
  });

  final String? ideaId;

  @override
  State<IdeaEditorScreen> createState() => _IdeaEditorScreenState();
}

class _IdeaEditorScreenState extends State<IdeaEditorScreen>
    with WidgetsBindingObserver {
  static const _autosaveDelay = Duration(milliseconds: 700);
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;
  late final FocusNode _titleFocusNode;
  late final FocusNode _contentFocusNode;
  late List<IdeaSection> _sections;
  late Map<String, String> _sectionContentById;
  late String _activeSectionId;
  late String _lastSavedSnapshot;
  late IdeasProvider _ideasProvider;
  late IdeaOrganizationRepository _organizationRepo;
  late NoteLockAuthService _noteLockAuthService;
  late NoteLockBiometricService _noteLockBiometricService;

  Timer? _autosaveTimer;
  Future<void>? _saveInFlight;
  String? _savedIdeaId;
  bool _allowPop = false;
  bool _isPreviewMode = false;
  bool _isAutosaving = false;
  bool _hasSaveFailed = false;
  bool _isOrganizing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    final ideasProvider = context.read<IdeasProvider>();
    _ideasProvider = ideasProvider;
    _organizationRepo = sl<IdeaOrganizationRepository>();
    _noteLockAuthService = sl.isRegistered<NoteLockAuthService>()
        ? sl<NoteLockAuthService>()
        : NoteLockAuthService();
    _noteLockBiometricService = sl.isRegistered<NoteLockBiometricService>()
        ? sl<NoteLockBiometricService>()
        : NoteLockBiometricService();
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
    _activeSectionId = _resolveInitialSectionId(resumeState, existingIdea);
    _isPreviewMode = resumeState?.isPreviewMode ?? false;
    _savedIdeaId = existingIdea?.id;

    _titleController = TextEditingController(text: existingIdea?.title ?? '');
    _contentController = TextEditingController(
      text: _sectionContentById[_activeSectionId] ?? '',
    );
    _titleFocusNode = FocusNode();
    _contentFocusNode = FocusNode();
    _titleController.addListener(_handleDraftChanged);
    _contentController.addListener(_handleEditorContentChanged);
    _lastSavedSnapshot = _snapshot();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (widget.ideaId == null && _titleController.text.trim().isEmpty) {
        _titleFocusNode.requestFocus();
      }
      if (_savedIdeaId == null) {
        unawaited(_flushAutosave(force: true));
      } else {
        _persistEditorState();
      }
    });
  }

  @override
  void dispose() {
    _clearLockedEditorSessionUnlock();
    WidgetsBinding.instance.removeObserver(this);
    FocusManager.instance.primaryFocus?.unfocus();
    _autosaveTimer?.cancel();
    unawaited(_flushAutosave(updateUi: false));
    _titleController
      ..removeListener(_handleDraftChanged)
      ..dispose();
    _contentController
      ..removeListener(_handleEditorContentChanged)
      ..dispose();
    _titleFocusNode.dispose();
    _contentFocusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      unawaited(_flushAutosave());
    }
  }

  bool get _hasUnsavedChanges => _snapshot() != _lastSavedSnapshot;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    final currentIdea = _currentIdea(context.watch<IdeasProvider>());
    final isEditorLocked = currentIdea != null &&
        currentIdea.isLocked &&
        !_noteLockAuthService.isIdeaUnlocked(currentIdea.id);
    return PopScope<Object?>(
      canPop: _allowPop || !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) {
          _clearLockedEditorSessionUnlock();
          await _ideasProvider.clearEditorState();
          return;
        }

        await _closeEditor();
      },
      child: Stack(
        children: [
          Scaffold(
            backgroundColor: theme.background,
            resizeToAvoidBottomInset: true,
            body: SafeArea(
              bottom: false,
              child: _wrapEditorBodyWithKeyboardActions(
                context,
                CustomScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    _buildCollapsibleEditorHeader(context, currentIdea),
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _PinnedHeaderDelegate(
                        extent: _PinnedHeaderDelegate.sectionTabsExtent,
                        child: _buildPinnedSectionTabsContent(context),
                      ),
                    ),
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _PinnedHeaderDelegate(
                        extent: _PinnedHeaderDelegate.toolbarExtent,
                        child: IdeaEditorToolbarContainer(
                          controller: _contentController,
                          focusNode: _contentFocusNode,
                          isPreviewMode: _isPreviewMode,
                          onPreviewToggle: _togglePreviewMode,
                          onOrganize: () =>
                              unawaited(_onOrganizeToolbarPressed()),
                          organizeEnabled: !_isOrganizing,
                          exceedsAiCharacterLimit:
                              _sectionExceedsAiWarningCharacterLimit,
                        ),
                      ),
                    ),
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: IdeaMarkdownEditor(
                        controller: _contentController,
                        focusNode: _contentFocusNode,
                        placeholder: _sectionPlaceholder(),
                        isPreviewMode: _isPreviewMode,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_isOrganizing) _buildOrganizingOverlay(context),
          if (isEditorLocked) _buildLockedEditorOverlay(context, currentIdea),
        ],
      ),
    );
  }

  Idea? _currentIdea(IdeasProvider ideasProvider) {
    final ideaId = _savedIdeaId ?? widget.ideaId;
    if (ideaId == null) {
      return null;
    }
    return ideasProvider.findById(ideaId);
  }

  Widget _buildLockedEditorOverlay(BuildContext context, Idea idea) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    return Positioned.fill(
      child: Material(
        type: MaterialType.transparency,
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: ColoredBox(
              color: theme.background.withValues(alpha: 0.86),
              child: SafeArea(
                child: Stack(
                  children: [
                    Positioned(
                      top: 8,
                      left: 8,
                      child: IconButton(
                        onPressed: _leaveLockedEditor,
                        icon: Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: theme.primaryText,
                        ),
                      ),
                    ),
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 76,
                              height: 76,
                              decoration: BoxDecoration(
                                color: theme.primary.withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: Icon(
                                Icons.lock_outline_rounded,
                                size: 36,
                                color: theme.primary,
                              ),
                            ),
                            const SizedBox(height: 18),
                            TranslatedText(
                              ViewConstants.noteLockEditorTitle,
                              textAlign: TextAlign.center,
                              style: ideaVaultHeadline(
                                context,
                                size: 24,
                                weight: FontWeight.w800,
                                height: 1.15,
                              ),
                            ),
                            const SizedBox(height: 10),
                            TranslatedText(
                              ViewConstants.noteLockEditorBody,
                              textAlign: TextAlign.center,
                              style: ideaVaultBody(
                                context,
                                size: 15,
                                weight: FontWeight.w500,
                                color: theme.textMuted,
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 22),
                            FilledButton.icon(
                              onPressed: () =>
                                  unawaited(_unlockEditorContent(idea)),
                              icon: const Icon(Icons.lock_open_rounded),
                              label:
                                  Text(ViewConstants.noteLockEditorAction.tr()),
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: _leaveLockedEditor,
                              child: Text(
                                ViewConstants.noteLockEditorBackAction.tr(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _leaveLockedEditor() async {
    await _ideasProvider.clearEditorState();
    if (!mounted) {
      return;
    }
    setState(() {
      _allowPop = true;
    });
    AppRouter.pop(context);
  }

  Future<void> _unlockEditorContent(Idea idea) async {
    final didAuthenticate = await authenticateForNoteLock(
      context,
      _noteLockAuthService,
      _noteLockBiometricService,
      ideaId: idea.id,
    );
    if (!mounted || !didAuthenticate) {
      return;
    }
    setState(() {});
  }

  Widget _wrapEditorBodyWithKeyboardActions(
    BuildContext context,
    Widget child,
  ) {
    if (!Platform.isIOS) {
      return child;
    }
    return KeyboardActions(
      autoScroll: false,
      config: keyboardActionbuildConfig(
        context,
        [_titleFocusNode, _contentFocusNode],
        keyboardActionsPlatform: KeyboardActionsPlatform.IOS,
      ),
      child: child,
    );
  }

  Widget _buildCollapsibleEditorHeader(
    BuildContext context,
    Idea? currentIdea,
  ) {
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(
            onClose: _onClosePressed,
            onMenuPressed: _showMoreOptionsSheet,
            isAutosaving: _isAutosaving,
            hasSaveFailed: _hasSaveFailed,
            isEditingExisting: widget.ideaId != null,
            showLockButton: _savedIdeaId != null,
            isNoteLocked: currentIdea?.isLocked ?? false,
            onLockPressed: () {
              if (currentIdea?.isLocked == true) {
                unawaited(_unlockCurrentIdea());
              } else {
                unawaited(_lockCurrentIdea());
              }
            },
          ),
          Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                child: _buildTitleField(context),
              ),
            ),
          ),
          Gap(12.h)
        ],
      ),
    );
  }

  Widget _buildPinnedSectionTabsContent(
    BuildContext context, {
    Color? background,
  }) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    return SizedBox(
      height: _PinnedHeaderDelegate.sectionTabsExtent,
      child: ColoredBox(
        color: background ?? theme.background,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: _buildSectionTabs(context),
          ),
        ),
      ),
    );
  }

  Widget _buildTitleField(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
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
          scrollPadding: EdgeInsets.only(
            bottom: Platform.isIOS ? 64 : 20,
          ),
          decoration: InputDecoration(
            hintText: ViewConstants.ideaEditorTitleHint.tr(),
            hintStyle: ideaVaultHeadline(
              context,
              size: 38,
              weight: FontWeight.w800,
              color: theme.outline,
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
      ],
    );
  }

  Widget _buildOrganizingOverlay(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: const AiLoadingOverlay(),
    );
  }

  Widget _buildAddSectionTab() {
    return Tooltip(
      message: ViewConstants.ideaEditorAddSectionTooltip.tr(),
      child: _SectionTabButton(
        key: const Key('idea-editor-add-section'),
        icon: Icons.add_rounded,
        isActive: false,
        onTap: _showAddSectionSheet,
      ),
    );
  }

  Widget _buildSectionTabs(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.outlineSoft),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  const SizedBox(width: 24),
                  for (var i = 0; i < _sections.length; i++) ...[
                    if (i > 0) const SizedBox(width: 10),
                    _SectionTabButton(
                      key: Key('idea-editor-section-tab-${_sections[i].id}'),
                      title: _sections[i].name,
                      isActive: _sections[i].id == _activeSectionId,
                      onTap: () => _handleSectionTap(_sections[i]),
                    ),
                  ],
                  const SizedBox(width: 10),
                  _buildAddSectionTab(),
                  const SizedBox(width: 24),
                ],
              ),
            ),
          ),
        ],
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

  String _resolveInitialSectionId(
    IdeaEditorState? resumeState,
    Idea? existingIdea,
  ) {
    final restoredSectionId = resumeState?.activeSectionId;
    if (restoredSectionId != null &&
        _sections.any((section) => section.id == restoredSectionId)) {
      return restoredSectionId;
    }

    final lastOpenedSectionId = existingIdea?.lastOpenedSectionId;
    if (lastOpenedSectionId != null &&
        _sections.any((section) => section.id == lastOpenedSectionId)) {
      return lastOpenedSectionId;
    }

    return _sections.first.id;
  }

  String _sectionPlaceholder() {
    final activeSection = _sections.firstWhere(
      (section) => section.id == _activeSectionId,
    );

    if (activeSection.name == 'Idea') {
      return ViewConstants.ideaEditorPlaceholderDefaultSection.tr();
    }
    return ViewConstants.ideaEditorPlaceholderNamedSection.tr(
      namedArgs: {'section': activeSection.name.toLowerCase()},
    );
  }

  void _switchSection(String sectionId) {
    if (sectionId == _activeSectionId) {
      return;
    }

    final nextContent = _sectionContentById[sectionId] ?? '';
    setState(() {
      _activeSectionId = sectionId;
    });
    _replaceEditorContent(nextContent);
    _persistEditorState();
    unawaited(_persistLastOpenedSectionId());
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
    _scheduleAutosave();
  }

  void _updateActiveSectionContent(String content) {
    _updateSectionContent(_activeSectionId, content);
  }

  void _handleEditorContentChanged() {
    _updateActiveSectionContent(_contentController.text);
  }

  bool get _sectionExceedsAiWarningCharacterLimit =>
      _contentPlainTextForEditing().length > ideaSectionAiWarningCharacterLimit;

  bool get _sectionExceedsAiMaxCharacterLimit =>
      _contentPlainTextForEditing().length > ideaSectionAiMaxCharacterLimit;

  String _contentPlainTextForEditing() {
    var plain = _contentController.text;
    if (plain.endsWith('\n')) {
      plain = plain.substring(0, plain.length - 1);
    }
    return plain;
  }

  Future<void> _onOrganizeToolbarPressed() async {
    if (_contentPlainTextForEditing().trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              TranslatedText(ViewConstants.ideaEditorSnackbarNothingToOrganize),
        ),
      );
      return;
    }

    if (_sectionExceedsAiMaxCharacterLimit) {
      await showOrganizeSectionSheet(
        context,
        warningCharacterLimit: ideaSectionAiWarningCharacterLimit,
        maxCharacterLimit: ideaSectionAiMaxCharacterLimit,
        exceedsWarningLimit: _sectionExceedsAiWarningCharacterLimit,
        exceedsMaxLimit: true,
      );
      return;
    }

    final hasAccess = await _ensurePremiumAccess(PremiumFeature.aiOrganize);
    if (!hasAccess || !mounted) {
      return;
    }

    final proceed = await showOrganizeSectionSheet(
      context,
      warningCharacterLimit: ideaSectionAiWarningCharacterLimit,
      maxCharacterLimit: ideaSectionAiMaxCharacterLimit,
      exceedsWarningLimit: _sectionExceedsAiWarningCharacterLimit,
      exceedsMaxLimit: _sectionExceedsAiMaxCharacterLimit,
    );

    if (proceed && mounted) {
      await _handleOrganize();
    }
  }

  void _replaceEditorContent(String content) {
    final selection = _contentController.selection;
    final cursorOffset = math.min(
      content.length,
      math.max(0, selection.extentOffset),
    );
    _contentController
      ..removeListener(_handleEditorContentChanged)
      ..value = TextEditingValue(
        text: content,
        selection: TextSelection.collapsed(offset: cursorOffset),
      )
      ..addListener(_handleEditorContentChanged);
  }

  void _handlePreviewModeChanged(bool isPreviewMode) {
    if (_isPreviewMode == isPreviewMode) {
      return;
    }

    if (isPreviewMode) {
      _contentFocusNode.unfocus();
    }
    setState(() {
      _isPreviewMode = isPreviewMode;
    });
    _persistEditorState();
  }

  void _togglePreviewMode() {
    final nextMode = !_isPreviewMode;
    _handlePreviewModeChanged(nextMode);

    if (!nextMode) {
      _contentFocusNode.requestFocus();
    }
  }

  Future<void> _persistEditorState() async {
    await _ideasProvider.saveEditorState(
      ideaId: _savedIdeaId,
      activeSectionId: _activeSectionId,
      isPreviewMode: _isPreviewMode,
    );
  }

  Future<void> _persistLastOpenedSectionId() async {
    final ideaId = _savedIdeaId;
    if (ideaId == null) {
      return;
    }

    await _ideasProvider.saveLastOpenedSectionId(
      ideaId: ideaId,
      sectionId: _activeSectionId,
    );
  }

  Future<void> _showAddSectionSheet() async {
    final newSection = IdeaSection.empty(name: _untitledSectionName);
    setState(() {
      _sections = [..._sections, newSection];
      _sectionContentById = {
        ..._sectionContentById,
        newSection.id: newSection.content,
      };
      _activeSectionId = newSection.id;
    });
    _replaceEditorContent(newSection.content);
    _scheduleAutosave();
    _persistEditorState();
    unawaited(_persistLastOpenedSectionId());
  }

  Future<void> _showEditSectionSheet(IdeaSection section) async {
    final result = await showIdeaEditorSectionSheet(
      context,
      section: section,
      sectionCount: _sections.length,
    );
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

    if (nextName == section.name) {
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

    setState(() {
      _sections = [
        for (final candidate in _sections)
          if (candidate.id == section.id)
            candidate.copyWith(name: nextName)
          else
            candidate,
      ];
    });
    _scheduleAutosave();
    _persistEditorState();
    unawaited(_persistLastOpenedSectionId());
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
    final nextContent = _sectionContentById[nextActiveSectionId] ?? '';

    setState(() {
      _sections = remainingSections;
      _sectionContentById = {
        for (final entry in _sectionContentById.entries)
          if (entry.key != sectionId) entry.key: entry.value,
      };
      _activeSectionId = nextActiveSectionId;
    });
    _replaceEditorContent(nextContent);
    _scheduleAutosave();
    _persistEditorState();
    unawaited(_persistLastOpenedSectionId());
  }

  void _showDuplicateSectionMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
            TranslatedText(ViewConstants.ideaEditorSnackbarDuplicateSection),
      ),
    );
  }

  void _handleDraftChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
    _scheduleAutosave();
  }

  Future<void> _onClosePressed() async {
    await _closeEditor();
  }

  Future<void> _showMoreOptionsSheet() async {
    final action = await showIdeaEditorOptionsSheet(context);

    if (!mounted || action == null) {
      return;
    }

    switch (action) {
      case IdeaEditorOptionsSheetAction.exportForAI:
        await _openExportScreen(ExportMode.aiExport);
        break;
      case IdeaEditorOptionsSheetAction.exportToPDF:
        await _openExportScreen(ExportMode.pdfExport);
        break;
      case IdeaEditorOptionsSheetAction.deleteIdea:
        await _confirmDeleteIdea();
        break;
    }
  }

  Future<void> _lockCurrentIdea() async {
    await _flushAutosave();
    if (!mounted) {
      return;
    }

    final ideaId = _savedIdeaId;
    if (ideaId == null) {
      return;
    }

    final isReady = await ensureNoteLockReady(
      context,
      _noteLockAuthService,
      _noteLockBiometricService,
    );
    if (!mounted || !isReady) {
      return;
    }

    await _ideasProvider.setIdeaLocked(ideaId: ideaId, isLocked: true);
    _noteLockAuthService.markIdeaUnlocked(ideaId);
    if (!mounted) {
      return;
    }
    _showNoteLockSnackBar(ViewConstants.noteLockLockedSnackbar);
  }

  Future<void> _unlockCurrentIdea() async {
    await _flushAutosave();
    if (!mounted) {
      return;
    }

    final ideaId = _savedIdeaId;
    if (ideaId == null) {
      return;
    }

    final didAuthenticate = await authenticateForNoteLock(
      context,
      _noteLockAuthService,
      _noteLockBiometricService,
      ideaId: ideaId,
    );
    if (!mounted || !didAuthenticate) {
      return;
    }

    await _ideasProvider.setIdeaLocked(ideaId: ideaId, isLocked: false);
    _noteLockAuthService.markIdeaLocked(ideaId);
    if (!mounted) {
      return;
    }
    _showNoteLockSnackBar(ViewConstants.noteLockUnlockedSnackbar);
  }

  void _showNoteLockSnackBar(String messageKey) {
    final theme = context.read<ThemeProvider>().baseTheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: theme.surface,
        content: Text(
          messageKey.tr(),
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: theme.primaryText,
          ),
        ),
      ),
    );
  }

  Future<void> _openExportScreen(ExportMode mode) async {
    await _flushAutosave();
    if (!mounted) {
      return;
    }

    final currentIdea = _currentIdea(context.read<IdeasProvider>());
    if (currentIdea?.isLocked == true) {
      final didAuthenticate = await authenticateForNoteLock(
        context,
        _noteLockAuthService,
        _noteLockBiometricService,
        ideaId: currentIdea!.id,
      );
      if (!mounted || !didAuthenticate) {
        return;
      }
    }

    await AppRouter.push(
      context,
      ExportForAIScreen(
        ideaTitle: _autosaveTitle,
        sections: _sectionsToSave(),
        mode: mode,
      ),
    );
  }

  Future<bool> _ensurePremiumAccess(PremiumFeature feature) async {
    try {
      return context.read<PaywallViewModel>().ensureAccess(context, feature);
    } on ProviderNotFoundException {
      return true;
    }
  }

  Future<void> _confirmDeleteIdea() async {
    await _flushAutosave();
    if (!mounted) {
      return;
    }

    final ideaId = _savedIdeaId;
    if (ideaId == null) {
      return;
    }

    final currentIdea = _currentIdea(context.read<IdeasProvider>());
    if (currentIdea?.isLocked == true) {
      final didAuthenticate = await authenticateForNoteLock(
        context,
        _noteLockAuthService,
        _noteLockBiometricService,
        ideaId: currentIdea!.id,
      );
      if (!mounted || !didAuthenticate) {
        return;
      }
    }

    final shouldDelete = await showDeleteIdeasConfirmationDialog(
      context,
      selectedCount: 1,
    );
    if (shouldDelete != true || !mounted) {
      return;
    }

    _autosaveTimer?.cancel();
    await _ideasProvider.deleteIdeas([ideaId]);
    if (!mounted) {
      return;
    }

    setState(() {
      _allowPop = true;
    });
    AppRouter.pop(context);
  }

  void _scheduleAutosave() {
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(_autosaveDelay, () {
      unawaited(_flushAutosave());
    });
  }

  Future<void> _flushAutosave({
    bool updateUi = true,
    bool force = false,
  }) {
    _autosaveTimer?.cancel();
    _autosaveTimer = null;

    final inFlightSave = _saveInFlight;
    if (inFlightSave != null) {
      return inFlightSave.then(
        (_) => _flushAutosave(updateUi: updateUi, force: force),
      );
    }

    if (!force && !_hasUnsavedChanges && !_hasSaveFailed) {
      return Future<void>.value();
    }

    final snapshot = _snapshot();
    final saveFuture = _performAutosave(snapshot, updateUi: updateUi);
    _saveInFlight = saveFuture;
    return saveFuture.whenComplete(() {
      if (identical(_saveInFlight, saveFuture)) {
        _saveInFlight = null;
      }
    });
  }

  Future<void> _performAutosave(
    String snapshot, {
    required bool updateUi,
  }) async {
    if (updateUi && mounted) {
      setState(() {
        _isAutosaving = true;
      });
    } else {
      _isAutosaving = true;
    }

    try {
      final savedIdea = await _ideasProvider.saveIdea(
        ideaId: _savedIdeaId,
        title: _autosaveTitle,
        sections: _sectionsToSave(),
        lastOpenedSectionId: _activeSectionId,
      );

      if (savedIdea == null) {
        _setAutosaveFailed(updateUi);
        return;
      }

      _savedIdeaId = savedIdea.id;
      _lastSavedSnapshot = snapshot;
      await _persistEditorState();

      if (updateUi && mounted) {
        setState(() {
          _isAutosaving = false;
          _hasSaveFailed = false;
        });
      } else {
        _isAutosaving = false;
        _hasSaveFailed = false;
      }
    } catch (_) {
      _setAutosaveFailed(updateUi);
    }
  }

  void _setAutosaveFailed(bool updateUi) {
    if (updateUi && mounted) {
      setState(() {
        _isAutosaving = false;
        _hasSaveFailed = true;
      });
      return;
    }

    _isAutosaving = false;
    _hasSaveFailed = true;
  }

  String get _autosaveTitle {
    final title = _titleController.text.trim();
    return title.isEmpty ? ViewConstants.ideaEditorUntitledIdea.tr() : title;
  }

  List<IdeaSection> _sectionsToSave() {
    return _sections
        .map(
          (section) => section.copyWith(
            content: _sectionContentById[section.id] ?? '',
          ),
        )
        .toList();
  }

  Future<void> _closeEditor() async {
    await _flushAutosave();
    if (!mounted) {
      return;
    }
    _clearLockedEditorSessionUnlock();
    await _ideasProvider.clearEditorState();
    if (!mounted) {
      return;
    }
    setState(() {
      _allowPop = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      AppRouter.pop(context, _savedIdeaId);
    });
  }

  void _clearLockedEditorSessionUnlock() {
    final ideaId = _savedIdeaId;
    if (ideaId == null) {
      return;
    }
    final currentIdea = _ideasProvider.findById(ideaId);
    if (currentIdea?.isLocked == true) {
      _noteLockAuthService.markIdeaLocked(ideaId);
    }
  }

  Future<void> _handleOrganize() async {
    final currentText = _contentPlainTextForEditing().trim();

    if (currentText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              TranslatedText(ViewConstants.ideaEditorSnackbarNothingToOrganize),
        ),
      );
      return;
    }

    setState(() {
      _isOrganizing = true;
    });

    try {
      final organizedContent =
          await _organizationRepo.organizeIdea(currentText);
      _replaceEditorContent(organizedContent);
      _updateActiveSectionContent(organizedContent);
      _scheduleAutosave();

      if (mounted) {
        setState(() {
          _isOrganizing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isOrganizing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                TranslatedText(ViewConstants.ideaEditorSnackbarOrganizeFailed),
          ),
        );
      }
    }
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

class _PinnedHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _PinnedHeaderDelegate({
    required this.extent,
    required this.child,
  });

  static const sectionTabsExtent = 46.0;
  static const toolbarExtent = 62.0;

  final double extent;
  final Widget child;

  @override
  double get minExtent => extent;

  @override
  double get maxExtent => extent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return SizedBox.expand(child: child);
  }

  @override
  bool shouldRebuild(covariant _PinnedHeaderDelegate oldDelegate) {
    return extent != oldDelegate.extent || child != oldDelegate.child;
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.onClose,
    required this.onMenuPressed,
    required this.isAutosaving,
    required this.hasSaveFailed,
    required this.isEditingExisting,
    required this.showLockButton,
    required this.isNoteLocked,
    required this.onLockPressed,
  });

  final VoidCallback onClose;
  final VoidCallback onMenuPressed;
  final bool isAutosaving;
  final bool hasSaveFailed;
  final bool isEditingExisting;
  final bool showLockButton;
  final bool isNoteLocked;
  final VoidCallback onLockPressed;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    return Row(
      children: [
        Gap(10.w),
        IconButton(
          key: const Key('idea-editor-close'),
          onPressed: onClose,
          icon: const Icon(Icons.close_rounded),
          padding: EdgeInsets.all(10.d),
        ),
        Gap(10.w),
        Expanded(
          child: TranslatedText(
            isEditingExisting
                ? ViewConstants.ideaEditorTitleEdit
                : ViewConstants.ideaEditorTitleNew,
            style: ideaVaultHeadline(
              context,
              size: 22.f,
              weight: FontWeight.w800,
              height: 1.2,
            ),
          ),
        ),
        if (hasSaveFailed) ...[
          const Icon(
            Icons.cloud_off_rounded,
            key: Key('idea-editor-save-failed'),
            size: 20,
          ),
          Gap(8.w),
        ],
        if (showLockButton) ...[
          Tooltip(
            message: (isNoteLocked
                    ? ViewConstants.ideaEditorOptionsUnlockNote
                    : ViewConstants.ideaEditorOptionsLockNote)
                .tr(),
            child: IconButton(
              key: const Key('idea-editor-lock-toggle'),
              onPressed: onLockPressed,
              style: isNoteLocked
                  ? IconButton.styleFrom(foregroundColor: theme.primary)
                  : null,
              icon: Icon(
                isNoteLocked
                    ? Icons.lock_outline_rounded
                    : Icons.lock_open_rounded,
              ),
              padding: EdgeInsets.all(10.d),
            ),
          ),
        ],
        IconButton(
          key: const Key('idea-editor-menu'),
          onPressed: onMenuPressed,
          icon: const Icon(Icons.more_vert),
          padding: EdgeInsets.all(10.d),
        ),
        Gap(10.w),
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
    final theme = context.watch<ThemeProvider>().baseTheme;
    final color = isActive ? theme.primary : theme.textMuted;

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
              color: isActive ? theme.primary : Colors.transparent,
              width: 2.5,
            ),
          ),
        ),
        child: child,
      ),
    );
  }
}
