import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:idea_vault/core/extensions/int.dart';
import 'package:keyboard_actions/keyboard_actions.dart';
import 'package:provider/provider.dart';

import '../config/router/app_router.dart';
import '../core/editor/note_editor_preferences.dart';
import '../core/services/note_lock_auth_service.dart';
import '../core/services/note_lock_biometric_service.dart';
import '../core/services/note_lock_session_guard.dart';
import '../core/services/vault/vault_crypto.dart';
import '../core/utils/helpers.dart';
import '../injection_container.dart';
import '../models/idea.dart';
import '../models/idea_editor_state.dart';
import '../viewmodels/providers/ideas_provider.dart';
import '../viewmodels/providers/theme_provider.dart';
import '../widgets/editor/note_editing_controller.dart';
import '../widgets/idea_markdown_editor.dart';
import '../widgets/note_lock_auth_dialog.dart';
import '../widgets/popups/delete_ideas_confirmation_dialog.dart';
import '../widgets/sheets/idea_editor_section_sheet.dart';
import '../widgets/sheets/idea_options_sheet.dart';
import '../core/constants/view_constants.dart';
import '../widgets/translated_text.dart';
import 'export_for_ai_screen.dart';
import 'ideas/idea_vault_theme.dart';

const String _untitledSectionName = 'Untitled';
const String _lockedPlaceholderSectionId = 'locked-placeholder-section';

class IdeaEditorScreen extends StatefulWidget {
  const IdeaEditorScreen({
    super.key,
    this.ideaId,
    this.initialSectionId,
  });

  final String? ideaId;
  final String? initialSectionId;

  @override
  State<IdeaEditorScreen> createState() => _IdeaEditorScreenState();
}

class _IdeaEditorScreenState extends State<IdeaEditorScreen>
    with WidgetsBindingObserver {
  static const _autosaveDelay = Duration(milliseconds: 700);
  late final TextEditingController _titleController;
  final Map<String, TextEditingController> _sectionControllers = {};
  final Set<String> _dirtySectionIds = {};
  late final FocusNode _titleFocusNode;
  late final FocusNode _contentFocusNode;
  late List<IdeaSection> _sections;
  late Map<String, String> _sectionContentById;
  late String _activeSectionId;
  late String _lastSavedSnapshot;
  late IdeasProvider _ideasProvider;
  late NoteLockAuthService _noteLockAuthService;
  late NoteLockBiometricService _noteLockBiometricService;

  Timer? _autosaveTimer;
  Future<void>? _saveInFlight;
  String? _savedIdeaId;
  bool _allowPop = false;
  bool _isAutosaving = false;
  bool _hasSaveFailed = false;
  late final bool _createdInSession;
  late final String _initialStructureSignature;
  bool _isDiscarding = false;
  bool _showPrivacyCover = false;
  bool _holdsSecureWindow = false;
  bool _didApplyInitialSection = false;
  bool _lockedContentReady = true;
  bool _lockedContentFailed = false;
  bool _isLoadingLockedContent = false;
  bool _holdsVaultSession = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    final ideasProvider = context.read<IdeasProvider>();
    _ideasProvider = ideasProvider;
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

    _lockedContentReady = !(existingIdea?.isEncrypted ?? false);
    _sections = !_lockedContentReady
        ? [_lockedPlaceholderSection()]
        : existingIdea?.sections
                .map((section) => section.copyWith())
                .toList() ??
            ideasProvider.createDefaultSections();
    _sectionContentById = {
      for (final section in _sections) section.id: section.content,
    };
    _activeSectionId = _resolveInitialSectionId(resumeState, existingIdea);
    _savedIdeaId = existingIdea?.id;
    _createdInSession = existingIdea == null;
    _initialStructureSignature = _structureSignature();

    _titleController = TextEditingController(text: existingIdea?.title ?? '');
    _titleFocusNode = FocusNode();
    _contentFocusNode = FocusNode();
    _titleController.addListener(_handleDraftChanged);
    _controllerFor(_activeSectionId);
    _lastSavedSnapshot = _snapshot();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (widget.ideaId == null && _titleController.text.trim().isEmpty) {
        _titleFocusNode.requestFocus();
      }
      if (!_lockedContentReady) {
        final ideaId = _savedIdeaId;
        if (ideaId != null && _noteLockAuthService.isIdeaUnlocked(ideaId)) {
          unawaited(_loadLockedContent());
        }
        return;
      }
      if (_savedIdeaId != null) {
        _persistEditorState();
        if (_didApplyInitialSection) {
          unawaited(_persistLastOpenedSectionId());
        }
      }
    });
  }

  @override
  void dispose() {
    _clearLockedEditorSessionUnlock();
    WidgetsBinding.instance.removeObserver(this);
    FocusManager.instance.primaryFocus?.unfocus();
    _autosaveTimer?.cancel();
    if (_holdsSecureWindow) {
      _holdsSecureWindow = false;
      NoteLockSecureWindow.release();
    }
    if (!_isDiscarding) {
      _materializeDirtySections();
      final emptySessionIdeaId = _emptySessionIdeaId;
      if (emptySessionIdeaId != null) {
        _savedIdeaId = null;
        unawaited(_ideasProvider.deleteIdeas([emptySessionIdeaId]));
        _releaseVaultSession();
      } else {
        unawaited(
          _flushAutosave(updateUi: false).whenComplete(_releaseVaultSession),
        );
      }
    } else {
      _releaseVaultSession();
    }
    _titleController
      ..removeListener(_handleDraftChanged)
      ..dispose();
    for (final controller in _sectionControllers.values) {
      controller.dispose();
    }
    _sectionControllers.clear();
    _titleFocusNode.dispose();
    _contentFocusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
        unawaited(_flushAutosave());
        _relockOnBackground();
        _setPrivacyCover(true);
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        _setPrivacyCover(true);
      case AppLifecycleState.resumed:
        _setPrivacyCover(false);
      case AppLifecycleState.detached:
        break;
    }
  }

  bool get _hasUnsavedChanges =>
      _dirtySectionIds.isNotEmpty || _snapshot() != _lastSavedSnapshot;

  bool get _isDraftMeaningful {
    if (_titleController.text.trim().isNotEmpty) {
      return true;
    }
    for (final section in _sections) {
      final controller = _sectionControllers[section.id];
      final content = controller?.text ??
          _sectionContentById[section.id] ??
          section.content;
      if (content.trim().isNotEmpty) {
        return true;
      }
    }
    return _structureSignature() != _initialStructureSignature;
  }

  bool get _hasNothingToSave => _createdInSession && !_isDraftMeaningful;

  String? get _emptySessionIdeaId {
    final ideaId = _savedIdeaId;
    if (ideaId == null || !_hasNothingToSave) {
      return null;
    }
    return ideaId;
  }

  String _structureSignature() {
    return jsonEncode([for (final section in _sections) section.name]);
  }

  bool get _isCurrentIdeaLocked =>
      _currentIdea(_ideasProvider)?.isLocked ?? false;

  IdeaSection _lockedPlaceholderSection() {
    return const IdeaSection(
      id: _lockedPlaceholderSectionId,
      name: '',
      content: '',
    );
  }

  void _acquireVaultSession() {
    final vault = _ideasProvider.vault;
    if (_holdsVaultSession || vault == null) {
      return;
    }
    _holdsVaultSession = true;
    vault.openSession();
  }

  void _releaseVaultSession() {
    if (!_holdsVaultSession) {
      return;
    }
    _holdsVaultSession = false;
    _ideasProvider.vault?.closeSession();
  }

  Future<void> _loadLockedContent() async {
    final ideaId = _savedIdeaId;
    if (ideaId == null || _isLoadingLockedContent) {
      return;
    }
    _isLoadingLockedContent = true;
    if (mounted) {
      setState(() {
        _lockedContentFailed = false;
      });
    }
    Idea? plain;
    try {
      _acquireVaultSession();
      plain = await _ideasProvider.openLockedIdea(ideaId);
    } on VaultCryptoException {
      plain = null;
    } catch (_) {
      plain = null;
    } finally {
      _isLoadingLockedContent = false;
    }
    if (!mounted) {
      return;
    }
    if (plain == null || plain.isEncrypted) {
      _releaseVaultSession();
      setState(() {
        _lockedContentFailed = true;
      });
      return;
    }
    final loaded = plain;
    for (final controller in _sectionControllers.values) {
      WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    }
    _sectionControllers.clear();
    _dirtySectionIds.clear();
    final sections = loaded.sections.isEmpty
        ? _ideasProvider.createDefaultSections()
        : loaded.sections.map((section) => section.copyWith()).toList();
    setState(() {
      _sections = sections;
      _sectionContentById = {
        for (final section in sections) section.id: section.content,
      };
      _activeSectionId = _resolveInitialSectionId(
        _matchingResumeState(_ideasProvider),
        loaded,
      );
      _lockedContentReady = true;
      _lockedContentFailed = false;
    });
    _titleController.removeListener(_handleDraftChanged);
    _titleController.text = loaded.title;
    _titleController.addListener(_handleDraftChanged);
    _controllerFor(_activeSectionId);
    _lastSavedSnapshot = _snapshot();
    _persistEditorState();
    if (_didApplyInitialSection) {
      unawaited(_persistLastOpenedSectionId());
    }
  }

  void _dropLockedContent() {
    final currentIdea = _currentIdea(_ideasProvider);
    if (!mounted ||
        currentIdea == null ||
        !currentIdea.isEncrypted ||
        _noteLockAuthService.isIdeaUnlocked(currentIdea.id)) {
      return;
    }
    for (final controller in _sectionControllers.values) {
      WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    }
    _sectionControllers.clear();
    _dirtySectionIds.clear();
    final placeholder = _lockedPlaceholderSection();
    setState(() {
      _sections = [placeholder];
      _sectionContentById = {placeholder.id: ''};
      _activeSectionId = placeholder.id;
      _lockedContentReady = false;
    });
    _titleController.removeListener(_handleDraftChanged);
    _titleController.text = currentIdea.title;
    _titleController.addListener(_handleDraftChanged);
    _controllerFor(placeholder.id);
    _lastSavedSnapshot = _snapshot();
    _releaseVaultSession();
  }

  void _relockOnBackground() {
    if (NoteLockSessionGuard.isRelockSuppressed) {
      return;
    }
    final currentIdea = _currentIdea(_ideasProvider);
    final wasUnlocked = currentIdea != null &&
        currentIdea.isLocked &&
        _noteLockAuthService.isIdeaUnlocked(currentIdea.id);
    _noteLockAuthService.clearSessionUnlocks();
    if (!wasUnlocked || !mounted) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {});
    if (currentIdea.isEncrypted || _ideasProvider.vault != null) {
      unawaited(_flushAutosave().whenComplete(_dropLockedContent));
    }
  }

  void _setPrivacyCover(bool visible) {
    final shouldShow = visible &&
        defaultTargetPlatform == TargetPlatform.iOS &&
        !NoteLockSessionGuard.isRelockSuppressed &&
        _isCurrentIdeaLocked;
    if (!mounted || shouldShow == _showPrivacyCover) {
      return;
    }
    setState(() {
      _showPrivacyCover = shouldShow;
    });
  }

  void _syncSecureWindow(bool wantsSecure) {
    if (wantsSecure == _holdsSecureWindow) {
      return;
    }
    _holdsSecureWindow = wantsSecure;
    if (wantsSecure) {
      NoteLockSecureWindow.acquire();
    } else {
      NoteLockSecureWindow.release();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    final currentIdea = _currentIdea(context.watch<IdeasProvider>());
    final isEditorLocked = currentIdea != null &&
        currentIdea.isLocked &&
        (!_noteLockAuthService.isIdeaUnlocked(currentIdea.id) ||
            !_lockedContentReady);
    final isIdeaLocked = currentIdea?.isLocked ?? false;
    _syncSecureWindow(isIdeaLocked);
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
                          controller: _activeController,
                          focusNode: _contentFocusNode,
                          enabled: !isEditorLocked,
                        ),
                      ),
                    ),
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: IdeaMarkdownEditor(
                        controller: _activeController,
                        focusNode: _contentFocusNode,
                        placeholder: _sectionPlaceholder(),
                        enablePersonalizedLearning: !isIdeaLocked,
                        readOnly: isEditorLocked,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (isEditorLocked) _buildLockedEditorOverlay(context, currentIdea),
          if (_showPrivacyCover) _buildPrivacyCover(context),
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
    final isOpening = _noteLockAuthService.isIdeaUnlocked(idea.id) &&
        !_lockedContentReady &&
        !_lockedContentFailed;
    final bodyKey = _lockedContentFailed
        ? ViewConstants.vaultOpenFailed
        : isOpening
            ? ViewConstants.vaultLoadingNote
            : ViewConstants.noteLockEditorBody;
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
                              bodyKey,
                              key: const Key('idea-editor-locked-body'),
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
                            if (isOpening)
                              const CircularProgressIndicator()
                            else
                              FilledButton.icon(
                                onPressed: () =>
                                    unawaited(_unlockEditorContent(idea)),
                                icon: const Icon(Icons.lock_open_rounded),
                                label: Text(
                                  ViewConstants.noteLockEditorAction.tr(),
                                ),
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

  Widget _buildPrivacyCover(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    return Positioned.fill(
      key: const Key('idea-editor-privacy-cover'),
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: ColoredBox(
            color: theme.background.withValues(alpha: 0.96),
            child: Center(
              child: Icon(
                Icons.lock_outline_rounded,
                size: 44,
                color: theme.primary,
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
    final alreadyUnlocked = _noteLockAuthService.isIdeaUnlocked(idea.id);
    final didAuthenticate = alreadyUnlocked ||
        await authenticateForNoteLock(
          context,
          _noteLockAuthService,
          _noteLockBiometricService,
          ideaId: idea.id,
        );
    if (!mounted || !didAuthenticate) {
      return;
    }
    setState(() {});
    final current = _currentIdea(_ideasProvider);
    if (!_lockedContentReady && (current?.isEncrypted ?? false)) {
      await _loadLockedContent();
    }
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
            hasSaveFailed: _hasSaveFailed,
            isEditingExisting: widget.ideaId != null,
            controller: _activeController,
            historyEnabled: _lockedContentReady &&
                !(currentIdea != null &&
                    currentIdea.isLocked &&
                    !_noteLockAuthService.isIdeaUnlocked(currentIdea.id)),
            onHistoryAction: _runHistoryAction,
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
          enableIMEPersonalizedLearning: !_isCurrentIdeaLocked,
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
    final requestedSectionId = widget.initialSectionId;
    if (requestedSectionId != null &&
        _sections.any((section) => section.id == requestedSectionId)) {
      _didApplyInitialSection = true;
      return requestedSectionId;
    }

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

    _controllerFor(sectionId);
    setState(() {
      _activeSectionId = sectionId;
    });
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

  TextEditingController get _activeController =>
      _controllerFor(_activeSectionId);

  TextEditingController _controllerFor(String sectionId) {
    final existing = _sectionControllers[sectionId];
    if (existing != null) {
      return existing;
    }
    final content = _sectionContentById[sectionId] ?? '';
    final useClassic = NoteEditorPreferences.shouldUseClassicEditor(
      ideaId: _savedIdeaId,
      sectionId: sectionId,
      content: content,
    );
    final TextEditingController controller;
    if (useClassic) {
      final classic = TextEditingController(text: content);
      var lastText = content;
      classic.addListener(() {
        if (classic.text != lastText) {
          lastText = classic.text;
          _markSectionDirty(sectionId);
        }
      });
      controller = classic;
    } else {
      final rich = NoteEditingController(markup: content);
      rich.contentRevision.addListener(() => _markSectionDirty(sectionId));
      controller = rich;
    }
    _sectionControllers[sectionId] = controller;
    return controller;
  }

  void _markSectionDirty(String sectionId) {
    if (!_sectionControllers.containsKey(sectionId)) {
      return;
    }
    final wasClean = _dirtySectionIds.isEmpty;
    _dirtySectionIds.add(sectionId);
    if (wasClean && mounted) {
      setState(() {});
    }
    _scheduleAutosave();
  }

  void _materializeDirtySections() {
    if (_dirtySectionIds.isEmpty) {
      return;
    }
    final next = {..._sectionContentById};
    for (final sectionId in _dirtySectionIds) {
      final controller = _sectionControllers[sectionId];
      if (controller == null) {
        continue;
      }
      next[sectionId] = controller is NoteEditingController
          ? controller.markup
          : controller.text;
    }
    _dirtySectionIds.clear();
    _sectionContentById = next;
  }

  void _disposeSectionController(String sectionId) {
    final controller = _sectionControllers.remove(sectionId);
    _dirtySectionIds.remove(sectionId);
    if (controller == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
  }

  Future<void> _persistEditorState() async {
    if (!_lockedContentReady) {
      return;
    }
    await _ideasProvider.saveEditorState(
      ideaId: _savedIdeaId,
      activeSectionId: _activeSectionId,
      isPreviewMode: false,
    );
  }

  Future<void> _persistLastOpenedSectionId() async {
    final ideaId = _savedIdeaId;
    if (ideaId == null || !_lockedContentReady) {
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
    _controllerFor(newSection.id);
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
    _controllerFor(nextActiveSectionId);
    _disposeSectionController(sectionId);

    setState(() {
      _sections = remainingSections;
      _sectionContentById = {
        for (final entry in _sectionContentById.entries)
          if (entry.key != sectionId) entry.key: entry.value,
      };
      _activeSectionId = nextActiveSectionId;
    });
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
    await _flushAutosave();
    if (!mounted) {
      return;
    }
    final currentIdea = _currentIdea(context.read<IdeasProvider>());
    final action = await showIdeaEditorOptionsSheet(
      context,
      isUnsavedDraft: _savedIdeaId == null,
      isNoteLocked:
          _savedIdeaId == null ? null : currentIdea?.isLocked ?? false,
    );

    if (!mounted || action == null) {
      return;
    }

    switch (action) {
      case IdeaEditorOptionsSheetAction.lockNote:
        await _lockCurrentIdea();
        break;
      case IdeaEditorOptionsSheetAction.unlockNote:
        await _unlockCurrentIdea();
        break;
      case IdeaEditorOptionsSheetAction.exportForAI:
        await _openExportScreen(ExportMode.aiExport);
        break;
      case IdeaEditorOptionsSheetAction.exportToPDF:
        await _openExportScreen(ExportMode.pdfExport);
        break;
      case IdeaEditorOptionsSheetAction.deleteIdea:
        await _confirmDeleteIdea();
        break;
      case IdeaEditorOptionsSheetAction.discardDraft:
        await _discardDraft();
        break;
    }
  }

  // Undo/redo only change the text; they must not open the keyboard.
  void _runHistoryAction(VoidCallback action) => action();

  Future<void> _discardDraft() async {
    _isDiscarding = true;
    _autosaveTimer?.cancel();
    _autosaveTimer = null;
    final inFlightSave = _saveInFlight;
    if (inFlightSave != null) {
      await inFlightSave;
    }
    final ideaId = _savedIdeaId;
    _savedIdeaId = null;
    if (ideaId != null && _createdInSession) {
      await _ideasProvider.deleteIdeas([ideaId]);
    }
    await _ideasProvider.clearEditorState();
    if (!mounted) {
      return;
    }
    setState(() {
      _allowPop = true;
      _hasSaveFailed = false;
    });
    AppRouter.pop(context);
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

    FocusManager.instance.primaryFocus?.unfocus();
    try {
      await _ideasProvider.setIdeaLocked(ideaId: ideaId, isLocked: true);
    } catch (_) {
      if (mounted) {
        _showNoteLockSnackBar(ViewConstants.vaultNeedsUnlockFirst);
      }
      return;
    }
    _noteLockAuthService.markIdeaUnlocked(ideaId);
    if (_currentIdea(_ideasProvider)?.isEncrypted ?? false) {
      _acquireVaultSession();
    }
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

    try {
      await _ideasProvider.setIdeaLocked(ideaId: ideaId, isLocked: false);
    } catch (_) {
      if (mounted) {
        _showNoteLockSnackBar(ViewConstants.vaultOpenFailed);
      }
      return;
    }
    _noteLockAuthService.markIdeaLocked(ideaId);
    _releaseVaultSession();
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

    final exportScreen = ExportForAIScreen(
      ideaTitle: _autosaveTitle,
      sections: _sectionsToSave(),
      mode: mode,
      isLocked: currentIdea?.isLocked == true,
    );
    await AppRouter.push(context, exportScreen);
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
  }) {
    _autosaveTimer?.cancel();
    _autosaveTimer = null;
    _materializeDirtySections();

    if (_isDiscarding || !_lockedContentReady) {
      return Future<void>.value();
    }

    final inFlightSave = _saveInFlight;
    if (inFlightSave != null) {
      return inFlightSave.then(
        (_) => _flushAutosave(updateUi: updateUi),
      );
    }

    if (_hasNothingToSave) {
      if (_hasSaveFailed || _isAutosaving) {
        if (updateUi && mounted) {
          setState(() {
            _hasSaveFailed = false;
            _isAutosaving = false;
          });
        } else {
          _hasSaveFailed = false;
          _isAutosaving = false;
        }
      }
      return Future<void>.value();
    }

    if (!_hasUnsavedChanges && !_hasSaveFailed) {
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
    final emptySessionIdeaId = _emptySessionIdeaId;
    if (emptySessionIdeaId != null) {
      _savedIdeaId = null;
      _lastSavedSnapshot = _snapshot();
      await _ideasProvider.deleteIdeas([emptySessionIdeaId]);
      if (!mounted) {
        return;
      }
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
    required this.hasSaveFailed,
    required this.isEditingExisting,
    required this.controller,
    required this.historyEnabled,
    required this.onHistoryAction,
  });

  static const double _iconSize = 20;

  final VoidCallback onClose;
  final VoidCallback onMenuPressed;
  final bool hasSaveFailed;
  final bool isEditingExisting;
  final TextEditingController controller;
  final bool historyEnabled;
  final ValueChanged<VoidCallback> onHistoryAction;

  @override
  Widget build(BuildContext context) {
    final rich = controller;
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          Gap(8.w),
          _HeaderIconButton(
            buttonKey: const Key('idea-editor-close'),
            icon: Icons.close_rounded,
            onPressed: onClose,
          ),
          Gap(6.w),
          Expanded(
            child: TranslatedText(
              isEditingExisting
                  ? ViewConstants.ideaEditorTitleEdit
                  : ViewConstants.ideaEditorTitleNew,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ideaVaultHeadline(
                context,
                size: 17.f,
                weight: FontWeight.w800,
                height: 1.2,
              ),
            ),
          ),
          if (hasSaveFailed) ...[
            const Icon(
              Icons.cloud_off_rounded,
              key: Key('idea-editor-save-failed'),
              size: 18,
            ),
            Gap(6.w),
          ],
          if (rich is NoteEditingController)
            ListenableBuilder(
              listenable: rich,
              builder: (context, _) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _HeaderIconButton(
                      buttonKey: const Key('idea-editor-toolbar-undo'),
                      icon: Icons.undo_rounded,
                      tooltip: ViewConstants.editorToolbarUndo,
                      onPressed: historyEnabled && rich.canUndo
                          ? () => onHistoryAction(rich.undo)
                          : null,
                    ),
                    _HeaderIconButton(
                      buttonKey: const Key('idea-editor-toolbar-redo'),
                      icon: Icons.redo_rounded,
                      tooltip: ViewConstants.editorToolbarRedo,
                      onPressed: historyEnabled && rich.canRedo
                          ? () => onHistoryAction(rich.redo)
                          : null,
                    ),
                  ],
                );
              },
            ),
          _HeaderIconButton(
            buttonKey: const Key('idea-editor-menu'),
            icon: Icons.more_vert,
            onPressed: onMenuPressed,
          ),
          Gap(8.w),
        ],
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.buttonKey,
    required this.icon,
    required this.onPressed,
    this.tooltip,
  });

  final Key buttonKey;
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    return IconButton(
      key: buttonKey,
      onPressed: onPressed,
      tooltip: tooltip?.tr(),
      icon: Icon(icon, size: _Header._iconSize),
      color: theme.primaryText,
      disabledColor: theme.textMuted.withValues(alpha: 0.4),
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(6),
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      style: IconButton.styleFrom(
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
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
