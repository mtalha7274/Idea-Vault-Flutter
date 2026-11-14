import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';
import 'package:idea_vault/core/constants/view_constants.dart';
import 'package:idea_vault/core/extensions/int.dart';
import 'package:provider/provider.dart';

import '../config/router/app_router.dart';
import '../core/services/note_lock_auth_service.dart';
import '../core/services/note_lock_biometric_service.dart';
import '../core/utils/selection_controller.dart';
import '../data/repositories/local/idea_list_preferences.dart';
import '../injection_container.dart';
import '../models/backup/cloud_backup_restore.dart';
import '../models/idea.dart';
import '../viewmodels/providers/backup/cloud_backup_provider.dart';
import '../viewmodels/providers/ideas_provider.dart';
import '../viewmodels/providers/random_additions_provider.dart';
import '../viewmodels/providers/theme_provider.dart';
import '../widgets/popups/delete_ideas_confirmation_dialog.dart';
import '../widgets/backup/backup_status_indicator.dart';
import '../widgets/backup_restore_prompt_banner.dart';
import '../widgets/home/home_top_bar.dart';
import '../widgets/home/quick_note_button.dart';
import '../widgets/ideas/ideas_layout.dart';
import '../widgets/note_lock_auth_dialog.dart';
import '../widgets/selection/selection_bar.dart';
import '../widgets/translated_text.dart';
import 'backup_restore_screen.dart';
import 'idea_editor.dart';
import 'ideas/idea_vault_theme.dart';
import 'random_additions_screen.dart';
import 'search_ideas_screen.dart';
import 'settings.dart';

class Homepage extends StatefulWidget {
  const Homepage({
    super.key,
    this.sortPreferencesRepo,
  });

  final IdeaListPreferencesRepo? sortPreferencesRepo;

  @override
  State<Homepage> createState() => _HomepageState();
}

class _HomepageState extends State<Homepage> {
  static const double _quickNoteDockGap = 24;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final SelectionController _selection = SelectionController();
  late final IdeaListPreferencesRepo _sortPreferencesRepo;
  late final NoteLockAuthService _noteLockAuthService;
  late final NoteLockBiometricService _noteLockBiometricService;
  late final IdeasProvider _ideasProvider;

  bool _didHandleResume = false;
  bool _isOpeningEditor = false;
  late IdeaSortOption _sortOption;
  late IdeaLayoutOption _layoutOption;

  bool get _isSelectionMode => _selection.isActive;

  @override
  void initState() {
    super.initState();
    _sortPreferencesRepo =
        widget.sortPreferencesRepo ?? sl<IdeaListPreferencesRepo>();
    _noteLockAuthService = sl.isRegistered<NoteLockAuthService>()
        ? sl<NoteLockAuthService>()
        : NoteLockAuthService();
    _noteLockBiometricService = sl.isRegistered<NoteLockBiometricService>()
        ? sl<NoteLockBiometricService>()
        : NoteLockBiometricService();
    _sortOption = _sortPreferencesRepo.getSortOption();
    _layoutOption = IdeaLayoutOption.grid;
    unawaited(_sortPreferencesRepo.saveLayoutOption(IdeaLayoutOption.grid));
    _selection.addListener(_onSelectionChanged);
    _ideasProvider = context.read<IdeasProvider>();
    _ideasProvider.addListener(_pruneSelection);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleInitialHomeEffects();
    });
  }

  @override
  void dispose() {
    _ideasProvider.removeListener(_pruneSelection);
    _selection.removeListener(_onSelectionChanged);
    _selection.dispose();
    super.dispose();
  }

  void _onSelectionChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _pruneSelection() {
    _selection.retainExisting(_ideasProvider.ideas.map((idea) => idea.id));
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    final ideasProvider = context.watch<IdeasProvider>();
    final ideas = ideasProvider.ideas;
    final visibleIdeas = _visibleIdeas(ideas);
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final listBottomPadding =
        QuickNoteButton.height + _quickNoteDockGap + bottomInset;

    return PopScope(
      canPop: !_isSelectionMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _isSelectionMode) {
          _selection.clear();
        }
      },
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: theme.background,
        drawerEnableOpenDragGesture: !_isSelectionMode,
        drawer: _HomeDrawer(
          hostContext: context,
          onBackupPressed: _openBackupRestore,
        ),
        body: Stack(
          children: [
            SafeArea(
              bottom: false,
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 860),
                  child: NestedScrollView(
                    floatHeaderSlivers: true,
                    headerSliverBuilder: (context, innerBoxIsScrolled) {
                      final handle =
                          NestedScrollView.sliverOverlapAbsorberHandleFor(
                        context,
                      );
                      return [
                        SliverOverlapAbsorber(
                          handle: handle,
                          sliver: SliverToBoxAdapter(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Gap(4.h),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  child: _buildTopBar(visibleIdeas),
                                ),
                                SizedBox(height: 12.h),
                                if (_hasCloudBackupProvider(context)) ...[
                                  BackupStatusIndicator(
                                    onTap: _openBackupRestore,
                                  ),
                                  const BackupRestorePromptBanner(),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ];
                    },
                    body: Builder(
                      builder: (context) {
                        return CustomScrollView(
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          physics: const AlwaysScrollableScrollPhysics(),
                          slivers: [
                            SliverOverlapInjector(
                              handle: NestedScrollView
                                  .sliverOverlapAbsorberHandleFor(context),
                            ),
                            if (ideas.isEmpty)
                              SliverPadding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 24),
                                sliver: SliverFillRemaining(
                                  hasScrollBody: false,
                                  child: _EmptyIdeasState(
                                    bottomPadding: listBottomPadding,
                                    onCreatePressed: _openNewIdea,
                                  ),
                                ),
                              )
                            else
                              SliverPadding(
                                padding: EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  16,
                                  listBottomPadding,
                                ),
                                sliver: SliverToBoxAdapter(
                                  child: IdeasLayout(
                                    ideas: visibleIdeas,
                                    layoutOption: _layoutOption,
                                    selectedIdeaIds: _selection.selectedIds,
                                    isSelectionActive: _isSelectionMode,
                                    onTap: (idea) =>
                                        unawaited(_handleIdeaTap(idea)),
                                    onLongPress: _handleIdeaLongPress,
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
            if (!_isSelectionMode) _buildQuickNoteDock(context),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(List<Idea> visibleIdeas) {
    final Widget bar;
    if (_isSelectionMode) {
      final visibleIds = visibleIdeas.map((idea) => idea.id);
      final allSelected = _selection.containsAll(visibleIds);
      bar = SelectionToolbar(
        key: const ValueKey('ideas-selection-bar'),
        count: _selection.count,
        onClose: _selection.clear,
        closeButtonKey: const Key('ideas-selection-close'),
        countKey: const Key('ideas-selection-count'),
        actions: [
          SelectionActionButton(
            key: const Key('ideas-select-all-button'),
            icon: Icons.select_all_rounded,
            tooltipKey: ViewConstants.selectionSelectAllTooltip,
            onPressed:
                allSelected ? null : () => _selection.selectAll(visibleIds),
          ),
          SelectionActionButton(
            key: const Key('ideas-delete-button'),
            icon: Icons.delete_outline_rounded,
            tooltipKey: ViewConstants.selectionDeleteTooltip,
            onPressed: _confirmDeleteSelection,
          ),
        ],
      );
    } else {
      bar = HomeTopBar(
        key: const ValueKey('ideas-top-bar'),
        onMenuPressed: () => _scaffoldKey.currentState?.openDrawer(),
        onSearchPressed: _openSearchScreen,
        onSortPressed: _showSortSheet,
        onNewIdeaPressed: _openNewIdea,
      );
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: bar,
    );
  }

  Widget _buildQuickNoteDock(BuildContext context) {
    final theme = context.read<ThemeProvider>().baseTheme;
    final unfiledCount =
        context.watch<RandomAdditionsProvider>().additions.length;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ColoredBox(
            color: theme.background,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                0,
                16,
                MediaQuery.of(context).padding.bottom + 8,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 860),
                child: QuickNoteButton(
                  unfiledCount: unfiledCount,
                  onPressed: _openRandomNotesComposer,
                ),
              ),
            ),
          ),
          Positioned(
            top: -32,
            left: 0,
            right: 0,
            height: 32,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      theme.background.withValues(alpha: 0),
                      theme.background,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleInitialHomeEffects() async {
    await _resumeEditorIfNeeded();
    if (!mounted) {
      return;
    }
    await _checkFreshInstallBackup();
    if (!mounted) {
      return;
    }
    await _runAutoBackupCatchUp();
  }

  Future<void> _runAutoBackupCatchUp() async {
    if (!mounted) {
      return;
    }
    final backupProvider = _maybeCloudBackupProvider(context);
    if (backupProvider == null) {
      return;
    }
    final ideasProvider = context.read<IdeasProvider>();
    await ideasProvider.ensureLoaded();
    if (!mounted) {
      return;
    }
    final randomAdditionsProvider = context.read<RandomAdditionsProvider>();
    await randomAdditionsProvider.ensureLoaded();
    if (!mounted) {
      return;
    }
    await backupProvider.initializeAutoBackup();
    if (!mounted) {
      return;
    }
    await backupProvider.runAutoBackupIfDue(
      ideasProvider.ideas,
      randomAdditions: randomAdditionsProvider.additions,
    );
    if (backupProvider.plaintextCleanupPending) {
      await backupProvider.runPlaintextCleanup(
        ideasProvider.ideas,
        randomAdditions: randomAdditionsProvider.additions,
      );
    }
  }

  Future<void> _resumeEditorIfNeeded() async {
    if (_didHandleResume || !mounted) {
      return;
    }
    _didHandleResume = true;

    final ideasProvider = context.read<IdeasProvider>();
    await ideasProvider.ensureLoaded();

    if (!mounted) {
      return;
    }

    final resumeState = ideasProvider.resumeEditorState;
    if (resumeState == null) {
      return;
    }

    final idea = ideasProvider.findById(resumeState.ideaId);
    if (idea == null) {
      await ideasProvider.clearEditorState();
      return;
    }

    if (!mounted) {
      return;
    }

    if (!idea.isLocked) {
      await AppRouter.push(context, IdeaEditorScreen(ideaId: idea.id));
      return;
    }

    await ideasProvider.clearEditorState();
  }

  Future<void> _checkFreshInstallBackup() async {
    if (!mounted) {
      return;
    }
    final ideasProvider = context.read<IdeasProvider>();
    final additionsProvider = context.read<RandomAdditionsProvider>();
    await ideasProvider.ensureLoaded();
    await additionsProvider.ensureLoaded();
    if (!mounted) {
      return;
    }
    final backupProvider = _maybeCloudBackupProvider(context);
    if (backupProvider == null) {
      return;
    }
    await backupProvider.checkForFreshInstallBackup(
      hasLocalContent: ideasProvider.ideas.isNotEmpty ||
          additionsProvider.additions.isNotEmpty,
    );
    await backupProvider.resolvePendingRemoteState(
      local: LocalVaultContent(
        ideas: ideasProvider.ideas,
        randomAdditions: additionsProvider.additions,
      ),
    );
  }

  bool _hasCloudBackupProvider(BuildContext context) {
    return _maybeCloudBackupProvider(context) != null;
  }

  CloudBackupProvider? _maybeCloudBackupProvider(BuildContext context) {
    try {
      return context.read<CloudBackupProvider>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  Future<void> _handleIdeaTap(Idea idea) async {
    if (_isSelectionMode) {
      _selection.toggle(idea.id);
      return;
    }

    if (!idea.isLocked) {
      await AppRouter.push(context, IdeaEditorScreen(ideaId: idea.id));
      return;
    }

    if (!mounted) {
      return;
    }

    await authenticateAndOpenNote(
      context,
      _noteLockAuthService,
      _noteLockBiometricService,
      ideaId: idea.id,
      nextRoute: () => IdeaEditorScreen(ideaId: idea.id),
    );
  }

  Future<void> _openNewIdea() async {
    if (_isOpeningEditor || _isSelectionMode) {
      return;
    }
    _isOpeningEditor = true;
    try {
      await AppRouter.push(context, const IdeaEditorScreen());
    } finally {
      _isOpeningEditor = false;
    }
  }

  Future<void> _openSearchScreen() async {
    await AppRouter.push(
      context,
      const SearchIdeasScreen(),
    );
  }

  Future<void> _openRandomNotesComposer() async {
    await AppRouter.push(
      context,
      const RandomAdditionsScreen(autofocusComposer: true),
    );
  }

  Future<void> _openBackupRestore() async {
    if (!mounted) {
      return;
    }

    await AppRouter.push(
      context,
      const BackupRestoreScreen(),
    );
  }

  void _handleIdeaLongPress(Idea idea) {
    if (_isSelectionMode) {
      _selection.toggle(idea.id);
      return;
    }
    unawaited(HapticFeedback.selectionClick());
    _selection.select(idea.id);
  }

  Future<void> _confirmDeleteSelection() async {
    final selectedCount = _selection.count;
    if (selectedCount == 0) {
      return;
    }

    final shouldDelete = await showDeleteIdeasConfirmationDialog(
      context,
      selectedCount: selectedCount,
    );

    if (shouldDelete != true || !mounted) {
      return;
    }

    final selectedIds = _selection.selectedIds.toList(growable: false);
    final ideasProvider = context.read<IdeasProvider>();
    final selectedIdeas = ideasProvider.ideas
        .where((idea) => selectedIds.contains(idea.id))
        .toList(growable: false);
    final lockedIdeas =
        selectedIdeas.where((idea) => idea.isLocked).toList(growable: false);
    if (lockedIdeas.isNotEmpty) {
      final didAuthenticate = await authenticateForNoteLock(
        context,
        _noteLockAuthService,
        _noteLockBiometricService,
        ideaId: lockedIdeas.first.id,
      );
      if (!didAuthenticate) {
        return;
      }
      if (!mounted) {
        return;
      }
      for (final idea in lockedIdeas) {
        _noteLockAuthService.markIdeaUnlocked(idea.id);
      }
    }
    await ideasProvider.deleteIdeas(selectedIds);
    if (!mounted) {
      return;
    }

    _selection.clear();
  }

  List<Idea> _visibleIdeas(List<Idea> ideas) {
    final sortedIdeas = List<Idea>.from(ideas);

    switch (_sortOption) {
      case IdeaSortOption.newestFirst:
        sortedIdeas.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        break;
      case IdeaSortOption.oldestFirst:
        sortedIdeas.sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
        break;
      case IdeaSortOption.mostSections:
        sortedIdeas.sort((a, b) {
          final sectionCountDifference = b.sections.length - a.sections.length;
          if (sectionCountDifference != 0) {
            return sectionCountDifference;
          }
          return b.updatedAt.compareTo(a.updatedAt);
        });
        break;
    }

    return sortedIdeas;
  }

  Future<void> _showSortSheet() async {
    final sheetSurface = context.read<ThemeProvider>().baseTheme.surface;
    final selectedSortOption = await showModalBottomSheet<IdeaSortOption>(
      context: context,
      backgroundColor: sheetSurface,
      builder: (sheetContext) {
        final sheetTheme = sheetContext.watch<ThemeProvider>().baseTheme;
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TranslatedText(
                ViewConstants.homepageSortSheetTitle,
                style: ideaVaultHeadline(
                  sheetContext,
                  size: 24,
                  weight: FontWeight.w800,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 8),
              TranslatedText(
                ViewConstants.homepageSortSheetSubtitle,
                style: ideaVaultBody(
                  sheetContext,
                  size: 15,
                  weight: FontWeight.w500,
                  color: sheetTheme.textMuted,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 18),
              _SortOptionTile(
                key: const Key('ideas-sort-newest'),
                titleKey: ViewConstants.homepageSortNewestFirst,
                isSelected: _sortOption == IdeaSortOption.newestFirst,
                onTap: () =>
                    Navigator.of(sheetContext).pop(IdeaSortOption.newestFirst),
              ),
              _SortOptionTile(
                key: const Key('ideas-sort-oldest'),
                titleKey: ViewConstants.homepageSortOldestFirst,
                isSelected: _sortOption == IdeaSortOption.oldestFirst,
                onTap: () =>
                    Navigator.of(sheetContext).pop(IdeaSortOption.oldestFirst),
              ),
              _SortOptionTile(
                key: const Key('ideas-sort-most-sections'),
                titleKey: ViewConstants.homepageSortMostSections,
                isSelected: _sortOption == IdeaSortOption.mostSections,
                onTap: () =>
                    Navigator.of(sheetContext).pop(IdeaSortOption.mostSections),
              ),
            ],
          ),
        );
      },
    );

    if (selectedSortOption == null || !mounted) {
      return;
    }

    setState(() {
      _sortOption = selectedSortOption;
    });
    await _sortPreferencesRepo.saveSortOption(selectedSortOption);
  }
}

class _HomeDrawer extends StatelessWidget {
  const _HomeDrawer({
    required this.hostContext,
    required this.onBackupPressed,
  });

  final BuildContext hostContext;
  final Future<void> Function() onBackupPressed;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    final randomAdditionCount =
        context.watch<RandomAdditionsProvider>().additions.length;
    return Drawer(
      backgroundColor: theme.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              leading: Icon(
                Icons.cloud_sync_rounded,
                color: theme.primary,
              ),
              title: TranslatedText(
                ViewConstants.backupRestoreScreenTitle,
                style: ideaVaultBody(
                  context,
                  size: 16,
                  weight: FontWeight.w600,
                ),
              ),
              onTap: () async {
                Navigator.of(context).pop();
                if (!hostContext.mounted) {
                  return;
                }
                await onBackupPressed();
              },
            ),
            ListTile(
              key: const Key('random-additions-drawer'),
              leading: Icon(
                Icons.chat_bubble_outline_rounded,
                color: theme.primary,
              ),
              title: TranslatedText(
                ViewConstants.randomAdditionsTitle,
                style: ideaVaultBody(
                  context,
                  size: 16,
                  weight: FontWeight.w600,
                ),
              ),
              trailing: randomAdditionCount == 0
                  ? null
                  : Container(
                      key: const Key('random-additions-drawer-count'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: theme.primary,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '$randomAdditionCount',
                        style: ideaVaultLabel(
                          context,
                          size: 12,
                          weight: FontWeight.w800,
                          color: theme.onPrimary,
                        ),
                      ),
                    ),
              onTap: () {
                Navigator.of(context).pop();
                if (!hostContext.mounted) {
                  return;
                }
                AppRouter.push(
                  hostContext,
                  const RandomAdditionsScreen(),
                );
              },
            ),
            ListTile(
              leading: Icon(
                Icons.settings_rounded,
                color: theme.primary,
              ),
              title: TranslatedText(
                ViewConstants.settings,
                style: ideaVaultBody(
                  context,
                  size: 16,
                  weight: FontWeight.w600,
                ),
              ),
              onTap: () {
                Navigator.of(context).pop();
                if (!hostContext.mounted) {
                  return;
                }
                AppRouter.push(
                  hostContext,
                  const Settings(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyIdeasState extends StatelessWidget {
  const _EmptyIdeasState({
    required this.bottomPadding,
    required this.onCreatePressed,
  });

  final double bottomPadding;
  final VoidCallback onCreatePressed;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: Center(
        child: Container(
          key: const Key('ideas-empty-state'),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: theme.surface,
            borderRadius: BorderRadius.circular(32),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                height: 78,
                width: 78,
                decoration: BoxDecoration(
                  color: theme.accentTint,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.auto_awesome_outlined,
                  size: 36,
                  color: theme.primary,
                ),
              ),
              const SizedBox(height: 18),
              TranslatedText(
                ViewConstants.homepageEmptyTitle,
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
                ViewConstants.homepageEmptySubtitle,
                textAlign: TextAlign.center,
                style: ideaVaultBody(
                  context,
                  size: 15,
                  weight: FontWeight.w500,
                  color: theme.textMuted,
                  height: 1.55,
                ),
              ),
              const SizedBox(height: 22),
              FilledButton.icon(
                key: const Key('ideas-empty-create-button'),
                onPressed: onCreatePressed,
                style: FilledButton.styleFrom(
                  backgroundColor: theme.primary,
                  foregroundColor: theme.onPrimary,
                  minimumSize: const Size(48, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                ),
                icon: const Icon(Icons.add_rounded),
                label: TranslatedText(
                  ViewConstants.homepageEmptyCreateFirstIdea,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: ideaVaultLabel(
                    context,
                    size: 15,
                    weight: FontWeight.w700,
                    color: theme.onPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SortOptionTile extends StatelessWidget {
  const _SortOptionTile({
    super.key,
    required this.titleKey,
    required this.isSelected,
    required this.onTap,
  });

  final String titleKey;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: TranslatedText(
        titleKey,
        style: ideaVaultBody(
          context,
          size: 16,
          weight: FontWeight.w600,
        ),
      ),
      trailing: isSelected
          ? Icon(
              Icons.check_rounded,
              color: theme.primary,
            )
          : null,
      onTap: onTap,
    );
  }
}
