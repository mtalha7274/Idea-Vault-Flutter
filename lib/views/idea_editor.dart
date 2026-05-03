import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';
import 'package:idea_vault/core/extensions/int.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../config/router/app_router.dart';
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
import '../widgets/popups/delete_ideas_confirmation_dialog.dart';
import '../widgets/sheets/idea_editor_section_sheet.dart';
import '../widgets/sheets/idea_options_sheet.dart';
import '../widgets/sheets/organise_section_sheet.dart';
import '../core/constants/view_constants.dart';
import '../widgets/translated_text.dart';
import 'export_for_ai_screen.dart';
import 'ideas/idea_vault_theme.dart';

/// Aligned with SECTION_CONTENT_MAX_CHARS in Cloud Functions (`organizeSection`).
const int ideaSectionAiSoftCharacterLimit = 2000;

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
    with TickerProviderStateMixin, WidgetsBindingObserver {
  static const _autosaveDelay = Duration(milliseconds: 700);
  static const _untitledIdeaTitle = 'Untitled Idea';

  final SpeechToText _speechToText = SpeechToText();
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;
  late final FocusNode _titleFocusNode;
  late final FocusNode _contentFocusNode;
  late final AnimationController _micScaleController;
  late final AnimationController _micGlowController;
  late final Animation<double> _micScaleAnimation;
  late List<IdeaSection> _sections;
  late Map<String, String> _sectionContentById;
  late String _activeSectionId;
  late String _lastSavedSnapshot;
  late IdeasProvider _ideasProvider;
  late IdeaOrganizationRepository _organizationRepo;

  Timer? _autosaveTimer;
  Future<void>? _saveInFlight;
  String? _savedIdeaId;
  bool _allowPop = false;
  bool _isPreviewMode = false;
  bool _isAutosaving = false;
  bool _hasSaveFailed = false;
  bool _isListening = false;
  bool _isMicPressHeld = false;
  bool _isSpeechInitialized = false;
  bool _didShowPermissionDialog = false;
  bool _isOrganizing = false;
  String _partialSpeechText = '';
  int _lastInsertedSpeechOffset = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    final ideasProvider = context.read<IdeasProvider>();
    _ideasProvider = ideasProvider;
    _organizationRepo = sl<IdeaOrganizationRepository>();
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
    _savedIdeaId = existingIdea?.id;

    _titleController = TextEditingController(text: existingIdea?.title ?? '');
    _contentController = TextEditingController(
      text: _sectionContentById[_activeSectionId] ?? '',
    );
    _titleFocusNode = FocusNode();
    _contentFocusNode = FocusNode();
    _micScaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _micGlowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _micScaleAnimation = Tween<double>(begin: 1, end: 1.65).animate(
      CurvedAnimation(
        parent: _micScaleController,
        curve: Curves.easeOutBack,
      ),
    );
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
    WidgetsBinding.instance.removeObserver(this);
    FocusManager.instance.primaryFocus?.unfocus();
    _speechToText.stop();
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
    _micScaleController.dispose();
    _micGlowController.dispose();
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
    return PopScope<Object?>(
      canPop: _allowPop || !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) {
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
            floatingActionButton: _buildSpeechFab(context),
            body: SafeArea(
              bottom: false,
              child: CustomScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                slivers: [
                  _buildCollapsibleEditorHeader(context),
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
                            _sectionExceedsAiSoftCharacterLimit,
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
          if (_isOrganizing) _buildOrganizingOverlay(context),
        ],
      ),
    );
  }

  Widget _buildCollapsibleEditorHeader(BuildContext context) {
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
          decoration: InputDecoration(
            hintText: 'Enter idea title...',
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

  Widget _buildSpeechFab(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    final primaryColor = theme.primary;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final isKeyboardVisible = keyboardHeight > 0;

    return AnimatedScale(
      scale: isKeyboardVisible ? 0 : 1,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOutCubic,
      child: AnimatedOpacity(
        opacity: isKeyboardVisible ? 0 : 1,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeInOut,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            AnimatedSlide(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              offset: _isListening ? Offset.zero : const Offset(0, 0.3),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 160),
                opacity: _isListening ? 1 : 0,
                child: IgnorePointer(
                  ignoring: !_isListening,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: theme.surface,
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: [
                        BoxShadow(
                          color: primaryColor.withValues(alpha: 0.15),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Text(
                      'Listening...',
                      style: ideaVaultLabel(
                        context,
                        size: 13,
                        weight: FontWeight.w700,
                        color: primaryColor,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            GestureDetector(
              key: const Key('idea-editor-mic-fab'),
              behavior: HitTestBehavior.opaque,
              onLongPress: _handleMicLongPress,
              onLongPressEnd: (_) => _handleMicLongPressEnd(),
              child: ScaleTransition(
                scale: _micScaleAnimation,
                child: AnimatedBuilder(
                  animation: _micGlowController,
                  builder: (context, child) {
                    final glowOpacity =
                        0.16 + (_micGlowController.value * 0.22);
                    final glowRadius = 32.0 + (_micGlowController.value * 12.0);
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      curve: Curves.easeOutCubic,
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: _isListening
                            ? [
                                BoxShadow(
                                  color: primaryColor.withValues(
                                      alpha: glowOpacity),
                                  blurRadius: glowRadius,
                                  spreadRadius: 3,
                                ),
                              ]
                            : const [],
                      ),
                      child: child,
                    );
                  },
                  child: AbsorbPointer(
                    child: FloatingActionButton(
                      heroTag: 'idea-editor-mic-fab',
                      onPressed: () {},
                      elevation: _isListening ? 8 : 6,
                      backgroundColor: primaryColor,
                      foregroundColor: theme.onPrimary,
                      child: Icon(
                        _isListening ? Icons.mic_none : Icons.mic,
                        size: 28,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
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
                      key: Key(
                          'idea-editor-section-tab-${_sections[i].name.toLowerCase()}'),
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

    final nextContent = _sectionContentById[sectionId] ?? '';
    setState(() {
      _activeSectionId = sectionId;
    });
    _replaceEditorContent(nextContent);
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
    _scheduleAutosave();
  }

  void _updateActiveSectionContent(String content) {
    _updateSectionContent(_activeSectionId, content);
  }

  void _handleEditorContentChanged() {
    _updateActiveSectionContent(_contentController.text);
  }

  bool get _sectionExceedsAiSoftCharacterLimit =>
      _contentPlainTextForEditing().length > ideaSectionAiSoftCharacterLimit;

  String _contentPlainTextForEditing() {
    var plain = _contentController.text;
    if (plain.endsWith('\n')) {
      plain = plain.substring(0, plain.length - 1);
    }
    return plain;
  }

  Future<void> _onOrganizeToolbarPressed() async {
    final hasAccess = await _ensurePremiumAccess(PremiumFeature.aiOrganize);
    if (!hasAccess || !mounted) {
      return;
    }

    if (_contentPlainTextForEditing().trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nothing to organize')),
      );
      return;
    }

    final proceed = await showOrganizeSectionSheet(
      context,
      characterLimit: ideaSectionAiSoftCharacterLimit,
      exceedsCharacterLimit: _sectionExceedsAiSoftCharacterLimit,
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

  Future<void> _handleMicLongPress() async {
    if (_isListening) {
      return;
    }

    final hasAccess = await _ensurePremiumAccess(PremiumFeature.speechToText);
    if (!hasAccess || !mounted) {
      return;
    }

    _isMicPressHeld = true;

    HapticFeedback.mediumImpact();
    SystemSound.play(SystemSoundType.click);

    _micScaleController.forward();

    final hasPermission = await _ensureSpeechPermission();
    if (!hasPermission || !_isMicPressHeld || !mounted) {
      await _setListeningState(false);
      return;
    }

    final isAvailable = await _ensureSpeechReady();
    if (!isAvailable || !_isMicPressHeld || !mounted) {
      await _setListeningState(false);
      if (mounted) {
        _showSpeechUnavailableMessage();
      }
      return;
    }

    _partialSpeechText = '';
    _lastInsertedSpeechOffset = _contentController.selection.start;

    await _speechToText.listen(
      onResult: _handleSpeechResult,
      listenOptions: SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
        listenMode: ListenMode.dictation,
      ),
    );

    if (!mounted || !_speechToText.isListening) {
      await _setListeningState(false);
      return;
    }

    await _setListeningState(true);
  }

  Future<void> _handleMicLongPressEnd() async {
    _isMicPressHeld = false;
    if (_isListening) {
      HapticFeedback.lightImpact();
    }
    await _stopListening();
    _partialSpeechText = '';
    _lastInsertedSpeechOffset = 0;
  }

  Future<bool> _ensureSpeechPermission() async {
    final microphoneStatus = await Permission.microphone.request();
    PermissionStatus speechStatus = PermissionStatus.granted;

    if (Platform.isIOS) {
      speechStatus = await Permission.speech.request();
    }

    final hasPermission = microphoneStatus.isGranted && speechStatus.isGranted;
    if (!hasPermission && mounted) {
      await _showMicrophonePermissionDialog();
    }
    return hasPermission;
  }

  Future<bool> _ensureSpeechReady() async {
    if (_isSpeechInitialized) {
      return _speechToText.isAvailable;
    }

    final isAvailable = await _speechToText.initialize(
      onStatus: _handleSpeechStatus,
      onError: _handleSpeechError,
    );
    _isSpeechInitialized = true;
    return isAvailable;
  }

  Future<void> _setListeningState(bool isListening) async {
    if (_isListening == isListening) {
      if (!isListening && _micScaleController.value != 0) {
        await _micScaleController.reverse();
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isListening = isListening;
      });
    } else {
      _isListening = isListening;
    }

    if (isListening) {
      _micGlowController
        ..stop()
        ..reset()
        ..repeat(reverse: true);
      return;
    }

    _micGlowController
      ..stop()
      ..reset();
    _micScaleController.reverse();
  }

  Future<void> _stopListening() async {
    if (_speechToText.isListening) {
      await _speechToText.stop();
    }
    await _setListeningState(false);
  }

  void _handleSpeechStatus(String status) {
    if (!mounted) {
      return;
    }

    if (status == 'done' || status == 'notListening') {
      _stopListening();
    }
  }

  void _handleSpeechError(SpeechRecognitionError error) {
    if (!mounted) {
      return;
    }

    _stopListening();

    final errorMessage = error.errorMsg.toLowerCase();
    final isPermissionIssue =
        errorMessage.contains('permission') || errorMessage.contains('denied');
    if (isPermissionIssue) {
      _showMicrophonePermissionDialog();
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Speech recognition stopped. Please try again.'),
      ),
    );
  }

  void _handleSpeechResult(SpeechRecognitionResult result) {
    final recognizedWords = result.recognizedWords.trim();
    if (recognizedWords.isEmpty) {
      return;
    }

    if (result.finalResult) {
      _insertRecognizedText(recognizedWords, isFinal: true);
      _partialSpeechText = '';
    } else {
      _insertRecognizedText(recognizedWords, isFinal: false);
    }
  }

  void _insertRecognizedText(String dictatedText, {required bool isFinal}) {
    final normalizedText = dictatedText.trim();
    if (normalizedText.isEmpty) {
      return;
    }

    final selection = _contentController.selection;
    final currentText = _contentController.text;
    final canInsertAtCursor = !_isPreviewMode &&
        _contentFocusNode.hasFocus &&
        selection.isValid &&
        selection.start >= 0 &&
        selection.end >= 0;

    if (!canInsertAtCursor) {
      if (isFinal) {
        final middle = _dictatedTextOnOwnLine(currentText, '', normalizedText);
        final updatedText = currentText + middle;
        _contentController.value = TextEditingValue(
          text: updatedText,
          selection: TextSelection.collapsed(offset: updatedText.length),
        );
        _lastInsertedSpeechOffset = updatedText.length;
      }
      return;
    }

    final before = currentText.substring(0, _lastInsertedSpeechOffset);
    final after = currentText.substring(
      _lastInsertedSpeechOffset + _partialSpeechText.length,
    );

    final middle = _dictatedTextOnOwnLine(
      before,
      after,
      normalizedText,
    );

    final updatedText = before + middle + after;
    final nextOffset = before.length + middle.length;

    _contentController.value = TextEditingValue(
      text: updatedText,
      selection: TextSelection.collapsed(offset: nextOffset),
    );

    if (isFinal) {
      _lastInsertedSpeechOffset = nextOffset;
      _partialSpeechText = '';
    } else {
      _partialSpeechText = middle;
    }
  }

  void _showSpeechUnavailableMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Speech recognition is unavailable on this device.'),
      ),
    );
  }

  Future<void> _showMicrophonePermissionDialog() async {
    if (_didShowPermissionDialog || !mounted) {
      return;
    }

    _didShowPermissionDialog = true;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Microphone Access Needed'),
          content: const Text(
            'To use speech to text, please enable microphone access in your device settings.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                await openAppSettings();
              },
              child: const Text('Open Settings'),
            ),
          ],
        );
      },
    );
    _didShowPermissionDialog = false;
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

  Future<void> _showAddSectionSheet() async {
    final result = await showIdeaEditorSectionSheet(
      context,
      sectionCount: _sections.length,
    );
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
    _replaceEditorContent(newSection.content);
    _scheduleAutosave();
    _persistEditorState();
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
    _scheduleAutosave();
    _persistEditorState();
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
        if (await _ensurePremiumAccess(PremiumFeature.exportForAi)) {
          await _openExportScreen(ExportMode.aiExport);
        }
        break;
      case IdeaEditorOptionsSheetAction.exportToPDF:
        if (await _ensurePremiumAccess(PremiumFeature.exportPdf)) {
          await _openExportScreen(ExportMode.pdfExport);
        }
        break;
      case IdeaEditorOptionsSheetAction.deleteIdea:
        await _confirmDeleteIdea();
        break;
    }
  }

  Future<void> _openExportScreen(ExportMode mode) async {
    await _flushAutosave();
    if (!mounted) {
      return;
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
    return title.isEmpty ? _untitledIdeaTitle : title;
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

  Future<void> _handleOrganize() async {
    final currentText = _contentPlainTextForEditing().trim();

    if (currentText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nothing to organize')),
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
          const SnackBar(
              content: Text('Failed to organize. Please try again.')),
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

/// Builds the dictated chunk so it always starts on its own line.
String _dictatedTextOnOwnLine(String before, String after, String dictated) {
  if (before.isEmpty && after.isEmpty) {
    return dictated;
  }
  if (before.isEmpty && after.isNotEmpty) {
    return '$dictated\n';
  }
  if (before.isNotEmpty && !before.endsWith('\n')) {
    return '\n$dictated';
  }
  return dictated;
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
  });

  final VoidCallback onClose;
  final VoidCallback onMenuPressed;
  final bool isAutosaving;
  final bool hasSaveFailed;
  final bool isEditingExisting;

  @override
  Widget build(BuildContext context) {
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
