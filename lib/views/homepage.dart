import 'dart:async';

import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:idea_vault/core/constants/view_constants.dart';
import 'package:idea_vault/core/extensions/int.dart';
import 'package:provider/provider.dart';

import '../config/config.dart';
import '../config/router/app_router.dart';
import '../core/constants/app_assets.dart';
import '../core/services/note_lock_auth_service.dart';
import '../core/services/note_lock_biometric_service.dart';
import '../data/repositories/local/idea_list_preferences.dart';
import '../data/repositories/local/paid_feature_usage.dart';
import '../injection_container.dart';
import '../models/idea.dart';
import '../models/premium/premium_feature.dart';
import '../viewmodels/providers/backup/cloud_backup_provider.dart';
import '../viewmodels/providers/ideas_provider.dart';
import '../viewmodels/providers/premium/paywall_view_model.dart';
import '../viewmodels/providers/random_additions_provider.dart';
import '../viewmodels/providers/theme_provider.dart';
import '../widgets/popups/delete_ideas_confirmation_dialog.dart';
import '../widgets/backup_restore_prompt_banner.dart';
import '../widgets/free_usage_progress_ring.dart';
import '../widgets/ideas/ideas_layout.dart';
import '../widgets/note_lock_auth_dialog.dart';
import '../widgets/premium_crown_icon.dart';
import '../widgets/random_addition_composer.dart';
import '../widgets/translated_text.dart';
import 'backup_restore_screen.dart';
import 'free_usage_screen.dart';
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
  static const double _dockScrollPaddingBase = 236;
  static const double _dockMultilineExtraPadding = 15 * 1.35;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final Set<String> _selectedIdeaIds = <String>{};
  late final TextEditingController _quickAdditionController;
  late final FocusNode _quickAdditionFocusNode;
  late final IdeaListPreferencesRepo _sortPreferencesRepo;
  late final NoteLockAuthService _noteLockAuthService;
  late final NoteLockBiometricService _noteLockBiometricService;

  bool _didHandleResume = false;
  bool _didCheckFreeUsageIntro = false;
  bool _isQuickAdditionMultiline = false;
  late IdeaSortOption _sortOption;
  late IdeaLayoutOption _layoutOption;

  bool get _isSelectionMode => _selectedIdeaIds.isNotEmpty;

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
    _layoutOption = _sortPreferencesRepo.getLayoutOption();
    _quickAdditionController = TextEditingController();
    _quickAdditionFocusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleInitialHomeEffects();
    });
  }

  @override
  void dispose() {
    _quickAdditionController.dispose();
    _quickAdditionFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    final ideasProvider = context.watch<IdeasProvider>();
    final ideas = ideasProvider.ideas;
    final visibleIdeas = _visibleIdeas(ideas);

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: theme.background,
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
                              Gap(8.h),
                              _Header(
                                ideaCount: ideas.length,
                                selectedCount: _selectedIdeaIds.length,
                                onMenuPressed: () =>
                                    _scaffoldKey.currentState?.openDrawer(),
                                onDeletePressed: _isSelectionMode
                                    ? _confirmDeleteSelection
                                    : null,
                                onSearchPressed:
                                    _isSelectionMode ? null : _openSearchScreen,
                                onSortPressed:
                                    _isSelectionMode ? null : _showSortSheet,
                                layoutOption: _layoutOption,
                                onLayoutPressed: _isSelectionMode
                                    ? null
                                    : _toggleLayoutOption,
                              ),
                              SizedBox(height: 18.h),
                              if (_hasCloudBackupProvider(context)) ...[
                                _BackupOffIndicator(
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
                            handle:
                                NestedScrollView.sliverOverlapAbsorberHandleFor(
                                    context),
                          ),
                          if (ideas.isEmpty)
                            SliverPadding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 24),
                              sliver: SliverFillRemaining(
                                hasScrollBody: false,
                                child: const _EmptyIdeasState(),
                              ),
                            )
                          else
                            SliverPadding(
                              padding: EdgeInsets.fromLTRB(
                                16,
                                0,
                                16,
                                _dockScrollPaddingBase +
                                    (_isQuickAdditionMultiline
                                        ? _dockMultilineExtraPadding
                                        : 0),
                              ),
                              sliver: SliverToBoxAdapter(
                                child: IdeasLayout(
                                  ideas: visibleIdeas,
                                  layoutOption: _layoutOption,
                                  selectedIdeaIds: _selectedIdeaIds,
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
          if (!_isSelectionMode) _buildQuickAdditionDock(context),
        ],
      ),
    );
  }

  Widget _buildQuickAdditionDock(BuildContext context) {
    final theme = context.read<ThemeProvider>().baseTheme;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: Align(
                alignment: Alignment.centerRight,
                child: _HomepageFab(
                  isExtended: _layoutOption == IdeaLayoutOption.list,
                  onPressed: () => AppRouter.push(
                    context,
                    const IdeaEditorScreen(),
                  ),
                ),
              ),
            ),
          ),
          const Gap(24),
          Stack(
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
                    child: RandomAdditionComposer(
                      controller: _quickAdditionController,
                      focusNode: _quickAdditionFocusNode,
                      fieldKey: const Key('homepage-random-addition-field'),
                      sendButtonKey: const Key('homepage-random-addition-send'),
                      onSubmit: _submitQuickAddition,
                      onMultilineChanged: (isMultiline) {
                        if (_isQuickAdditionMultiline == isMultiline) {
                          return;
                        }
                        setState(() {
                          _isQuickAdditionMultiline = isMultiline;
                        });
                      },
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
    if (!mounted) {
      return;
    }
    await _showFreeUsageIntroIfNeeded();
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

    // Don't auto-resume locked notes on cold start — auth on every open is
    // disruptive on Android where the process is frequently killed.
    await ideasProvider.clearEditorState();
  }

  Future<void> _checkFreshInstallBackup() async {
    if (!mounted) {
      return;
    }
    final ideasProvider = context.read<IdeasProvider>();
    await ideasProvider.ensureLoaded();
    if (!mounted) {
      return;
    }
    final backupProvider = _maybeCloudBackupProvider(context);
    if (backupProvider == null) {
      return;
    }
    await backupProvider.checkForFreshInstallBackup(
      hasLocalIdeas: ideasProvider.ideas.isNotEmpty,
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

  PaywallViewModel? _maybePaywallViewModel(BuildContext context) {
    try {
      return context.read<PaywallViewModel>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  Future<void> _showFreeUsageIntroIfNeeded() async {
    if (_didCheckFreeUsageIntro || !mounted) {
      return;
    }
    _didCheckFreeUsageIntro = true;

    final paywall = _maybePaywallViewModel(context);
    final usageRepo = _maybePaidFeatureUsageRepo();
    if (paywall == null ||
        usageRepo == null ||
        usageRepo.usageCount != 0 ||
        usageRepo.hasFreeUsageIntroMetadata) {
      return;
    }

    if (!paywall.isPro && paywall.isLoading) {
      try {
        await paywall.refreshSubscription();
      } catch (_) {}
    }
    if (!mounted || paywall.isPro) {
      return;
    }

    final ideasProvider = context.read<IdeasProvider>();
    final randomAdditionsProvider = context.read<RandomAdditionsProvider>();
    await ideasProvider.ensureLoaded();
    await randomAdditionsProvider.ensureLoaded();
    if (!mounted ||
        ideasProvider.ideas.isNotEmpty ||
        randomAdditionsProvider.additions.isNotEmpty) {
      return;
    }

    await usageRepo.initializeFreeUsageGrantIfNeeded();
    await usageRepo.markFreeUsageIntroSeen();
    await paywall.syncUsageMetadataToCloud();
    if (!mounted) {
      return;
    }

    await AppRouter.push(
      context,
      FreeUsageScreen(
        usageCount: usageRepo.usageCount,
        usageLimit: Config.paidFeatureFreeUsageLimit,
      ),
    );
  }

  Future<void> _handleIdeaTap(Idea idea) async {
    if (_isSelectionMode) {
      _toggleIdeaSelection(idea.id);
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

  Future<void> _submitQuickAddition() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final addition = await context
        .read<RandomAdditionsProvider>()
        .addAddition(_quickAdditionController.text);
    if (addition == null || !mounted) {
      return;
    }

    _quickAdditionController.clear();
    if (_isQuickAdditionMultiline) {
      setState(() {
        _isQuickAdditionMultiline = false;
      });
    }
    await _openRandomAdditions();
  }

  Future<void> _openSearchScreen() async {
    await AppRouter.push(
      context,
      const SearchIdeasScreen(),
    );
  }

  Future<void> _openRandomAdditions() async {
    await AppRouter.push(
      context,
      const RandomAdditionsScreen(),
    );
  }

  Future<void> _openBackupRestore() async {
    if (!mounted) {
      return;
    }

    final paywall = _maybePaywallViewModel(context);
    if (paywall != null) {
      final hasAccess = await paywall.ensureAccess(
        context,
        PremiumFeature.cloudBackup,
      );
      if (!hasAccess || !mounted) {
        return;
      }
    }

    await AppRouter.push(
      context,
      const BackupRestoreScreen(),
    );
  }

  void _handleIdeaLongPress(Idea idea) {
    setState(() {
      _selectedIdeaIds.add(idea.id);
    });
  }

  void _toggleIdeaSelection(String ideaId) {
    setState(() {
      if (_selectedIdeaIds.contains(ideaId)) {
        _selectedIdeaIds.remove(ideaId);
      } else {
        _selectedIdeaIds.add(ideaId);
      }
    });
  }

  Future<void> _confirmDeleteSelection() async {
    final selectedCount = _selectedIdeaIds.length;
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

    final selectedIds = _selectedIdeaIds.toList(growable: false);
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

    setState(() {
      _selectedIdeaIds.clear();
    });
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

  Future<void> _toggleLayoutOption() async {
    final nextLayoutOption = _layoutOption == IdeaLayoutOption.list
        ? IdeaLayoutOption.grid
        : IdeaLayoutOption.list;

    setState(() {
      _layoutOption = nextLayoutOption;
    });
    await _sortPreferencesRepo.saveLayoutOption(nextLayoutOption);
  }
}

class _BackupOffIndicator extends StatelessWidget {
  const _BackupOffIndicator({
    required this.onTap,
  });

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    final backupState = context.watch<CloudBackupProvider>().state;
    if (backupState.enabled) {
      return const SizedBox.shrink();
    }

    final isDarkMode = theme.themeData.brightness == Brightness.dark;
    final indicatorColor = theme.warning.withValues(
      alpha: isDarkMode ? 0.18 : 0.14,
    );
    final borderColor = theme.warning.withValues(
      alpha: isDarkMode ? 0.38 : 0.32,
    );
    final foregroundColor = isDarkMode ? theme.warning : theme.primaryText;

    return Padding(
      padding: EdgeInsets.fromLTRB(24.w, 0, 24.w, 12.h),
      child: Material(
        key: const Key('homepage-backup-off-indicator'),
        color: indicatorColor,
        borderRadius: BorderRadius.circular(99),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(99),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: borderColor),
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(14.w, 10.h, 12.w, 10.h),
              child: Row(
                children: [
                  Icon(
                    Icons.cloud_off_rounded,
                    color: foregroundColor,
                    size: 20.d,
                  ),
                  Gap(10.w),
                  Expanded(
                    child: TranslatedText(
                      ViewConstants.homepageBackupOffIndicator,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ideaVaultBody(
                        context,
                        size: 14,
                        weight: FontWeight.w700,
                        color: theme.primaryText,
                      ),
                    ),
                  ),
                  Gap(10.w),
                  TranslatedText(
                    ViewConstants.homepageBackupOffAction,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ideaVaultLabel(
                      context,
                      size: 13,
                      weight: FontWeight.w800,
                      color: foregroundColor,
                    ),
                  ),
                  Gap(2.w),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: foregroundColor,
                    size: 20.d,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HomepageFab extends StatelessWidget {
  const _HomepageFab({
    required this.isExtended,
    required this.onPressed,
  });

  static const double _height = 56;
  static const double _collapsedWidth = 56;
  static const double _extendedWidth = 144;
  static const BorderRadius _borderRadius = BorderRadius.all(
    Radius.circular(99),
  );
  static const Duration _duration = Duration(milliseconds: 240);

  final bool isExtended;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    final labelStyle = ideaVaultLabel(
      context,
      size: 14,
      weight: FontWeight.w700,
      color: theme.onPrimary,
    );

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(
        end: isExtended ? _extendedWidth : _collapsedWidth,
      ),
      duration: _duration,
      curve: Curves.easeOutCubic,
      builder: (context, width, child) {
        return Semantics(
          button: true,
          label: ViewConstants.homepageFabNewIdea.tr(),
          child: Material(
            key: const Key('ideas-fab'),
            color: theme.primary,
            elevation: 6,
            shadowColor: Colors.black.withValues(alpha: 0.24),
            shape: const RoundedRectangleBorder(
              borderRadius: _borderRadius,
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              customBorder: const RoundedRectangleBorder(
                borderRadius: _borderRadius,
              ),
              onTap: onPressed,
              child: SizedBox(
                width: width,
                height: _height,
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.centerLeft,
                    maxWidth: _extendedWidth,
                    minWidth: _extendedWidth,
                    child: SizedBox(
                      width: _extendedWidth,
                      height: _height,
                      child: Row(
                        children: [
                          const SizedBox(width: 16),
                          Icon(
                            Icons.add_rounded,
                            color: theme.onPrimary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: AnimatedOpacity(
                              opacity: isExtended ? 1 : 0,
                              duration: const Duration(milliseconds: 120),
                              curve: Curves.easeOut,
                              child: Text(
                                ViewConstants.homepageFabNewIdea.tr(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: labelStyle,
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
          ),
        );
      },
    );
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
    final paywall = _maybePaywallViewModel(context);
    final usageRepo = _maybePaidFeatureUsageRepo();
    final showFreeUsageRow = paywall != null &&
        !paywall.isPro &&
        usageRepo != null &&
        !usageRepo.hasReachedFreeLimit;
    final showProRow = paywall != null && !paywall.isPro && !showFreeUsageRow;
    final randomAdditionCount =
        context.watch<RandomAdditionsProvider>().additions.length;
    return Drawer(
      backgroundColor: theme.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showFreeUsageRow)
              _FreeUsageDrawerTile(
                usageRepo: usageRepo,
                hostContext: hostContext,
              )
            else if (showProRow)
              ListTile(
                leading: PremiumCrownIcon(size: 24.d),
                title: TranslatedText(
                  ViewConstants.homepageGetIdeaVaultPro,
                  style: ideaVaultBody(
                    context,
                    size: 16,
                    weight: FontWeight.w700,
                  ),
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  if (!hostContext.mounted) {
                    return;
                  }
                  AppRouter.showPaywall(hostContext);
                },
              ),
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

  PaywallViewModel? _maybePaywallViewModel(BuildContext context) {
    try {
      return context.watch<PaywallViewModel>();
    } on ProviderNotFoundException {
      return null;
    }
  }
}

class _FreeUsageDrawerTile extends StatelessWidget {
  const _FreeUsageDrawerTile({
    required this.usageRepo,
    required this.hostContext,
  });

  final PaidFeatureUsageRepo usageRepo;
  final BuildContext hostContext;

  @override
  Widget build(BuildContext context) {
    final usageLimit = Config.paidFeatureFreeUsageLimit;
    final progress = usageLimit <= 0 ? 1.0 : usageRepo.usageCount / usageLimit;

    return ListTile(
      key: const Key('homepage-free-usage-drawer'),
      leading: Image.asset(
        AppAssets.gift,
        width: 24.d,
        height: 24.d,
      ),
      title: TranslatedText(
        ViewConstants.freeUsageDrawerTitle,
        style: ideaVaultBody(
          context,
          size: 16,
          weight: FontWeight.w700,
        ),
      ),
      trailing: FreeUsageProgressRing(
        progress: progress,
        size: 20.d,
        strokeWidth: 2.4,
        semanticLabel: ViewConstants.freeUsageProgressSemantic.tr(
          namedArgs: {
            'used': usageRepo.usageCount.toString(),
            'limit': usageLimit.toString(),
          },
        ),
      ),
      onTap: () {
        Navigator.of(context).pop();
        if (!hostContext.mounted) {
          return;
        }
        AppRouter.push(
          hostContext,
          FreeUsageScreen(
            usageCount: usageRepo.usageCount,
            usageLimit: usageLimit,
            animationCompleted: true,
          ),
        );
      },
    );
  }
}

PaidFeatureUsageRepo? _maybePaidFeatureUsageRepo() {
  if (!sl.isRegistered<PaidFeatureUsageRepo>()) {
    return null;
  }
  return sl<PaidFeatureUsageRepo>();
}

class _Header extends StatelessWidget {
  const _Header({
    required this.ideaCount,
    required this.selectedCount,
    required this.onMenuPressed,
    required this.onDeletePressed,
    required this.onSearchPressed,
    required this.onSortPressed,
    required this.layoutOption,
    required this.onLayoutPressed,
  });

  final int ideaCount;
  final int selectedCount;
  final VoidCallback onMenuPressed;
  final VoidCallback? onDeletePressed;
  final VoidCallback? onSearchPressed;
  final VoidCallback? onSortPressed;
  final IdeaLayoutOption layoutOption;
  final VoidCallback? onLayoutPressed;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    final iconBackgroundColor = theme.themeData.brightness == Brightness.light
        ? theme.surfaceHigh
        : theme.surfaceLow;
    final menuItemBodyStyle = ideaVaultBody(
      context,
      size: 15,
      weight: FontWeight.w600,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Gap(16.w),
            IconButton(
              key: const Key('ideas-menu-button'),
              onPressed: onMenuPressed,
              icon: const Icon(Icons.menu_rounded),
              padding: EdgeInsets.all(10.d),
            ),
            Gap(10.w),
            Expanded(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: TranslatedText(
                      ViewConstants.homepageTitle,
                      style: ideaVaultHeadline(
                        context,
                        size: 34.f,
                        weight: FontWeight.w800,
                        height: 1.06,
                        letterSpacing: -0.9,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (selectedCount > 0) ...[
              IconButton(
                key: const Key('ideas-delete-button'),
                onPressed: onDeletePressed,
                style: IconButton.styleFrom(
                  backgroundColor: iconBackgroundColor,
                  foregroundColor: theme.primary,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
                icon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$selectedCount',
                      style: ideaVaultLabel(
                        context,
                        size: 14,
                        weight: FontWeight.w800,
                        color: theme.primary,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.delete_outline_rounded, size: 22),
                  ],
                ),
              ),
            ] else ...[
              IconButton(
                key: const Key('ideas-search-button'),
                onPressed: onSearchPressed,
                style: IconButton.styleFrom(
                  backgroundColor: iconBackgroundColor,
                  foregroundColor: theme.primary,
                  padding: const EdgeInsets.all(12),
                ),
                icon: const Icon(Icons.search_rounded),
              ),
              Gap(8.w),
              PopupMenuButton<_HomepageMenuAction>(
                key: const Key('ideas-more-menu'),
                icon: const Icon(Icons.more_vert),
                color: theme.surface,
                padding: EdgeInsets.zero,
                style: IconButton.styleFrom(
                  backgroundColor: iconBackgroundColor,
                  foregroundColor: theme.primary,
                  padding: const EdgeInsets.all(12),
                ),
                onSelected: (action) {
                  switch (action) {
                    case _HomepageMenuAction.layout:
                      onLayoutPressed?.call();
                      break;
                    case _HomepageMenuAction.filter:
                      onSortPressed?.call();
                      break;
                  }
                },
                itemBuilder: (menuContext) {
                  return [
                    PopupMenuItem<_HomepageMenuAction>(
                      key: const Key('ideas-menu-layout'),
                      value: _HomepageMenuAction.layout,
                      child: Row(
                        children: [
                          Icon(
                            layoutOption == IdeaLayoutOption.list
                                ? Icons.grid_view_rounded
                                : Icons.view_agenda_rounded,
                            color: theme.primary,
                            size: 22,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TranslatedText(
                              ViewConstants.homepageMenuChangeLayout,
                              style: menuItemBodyStyle,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuItem<_HomepageMenuAction>(
                      key: const Key('ideas-menu-filter'),
                      value: _HomepageMenuAction.filter,
                      child: Row(
                        children: [
                          Icon(
                            Icons.swap_vert_rounded,
                            color: theme.primary,
                            size: 22,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TranslatedText(
                              ViewConstants.homepageMenuFilter,
                              style: menuItemBodyStyle,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ];
                },
              ),
            ],
            Gap(16.w),
          ],
        ),
      ],
    );
  }
}

enum _HomepageMenuAction {
  layout,
  filter,
}

class _EmptyIdeasState extends StatelessWidget {
  const _EmptyIdeasState();

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 120),
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
