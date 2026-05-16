import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:idea_vault/core/constants/view_constants.dart';
import 'package:idea_vault/core/extensions/int.dart';
import 'package:provider/provider.dart';

import '../config/router/app_router.dart';
import '../data/repositories/local/idea_list_preferences.dart';
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
import '../widgets/idea_vault_pill_text_field.dart';
import '../widgets/random_addition_composer.dart';
import '../widgets/translated_text.dart';
import 'backup_restore_screen.dart';
import 'idea_editor.dart';
import 'ideas/idea_vault_theme.dart';
import 'random_additions_screen.dart';
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
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final Set<String> _selectedIdeaIds = <String>{};
  late final TextEditingController _searchController;
  late final TextEditingController _quickAdditionController;
  late final IdeaListPreferencesRepo _sortPreferencesRepo;

  bool _didHandleResume = false;
  late IdeaSortOption _sortOption;
  late IdeaLayoutOption _layoutOption;

  bool get _isSelectionMode => _selectedIdeaIds.isNotEmpty;
  String get _searchQuery => _searchController.text.trim();

  @override
  void initState() {
    super.initState();
    _sortPreferencesRepo =
        widget.sortPreferencesRepo ?? sl<IdeaListPreferencesRepo>();
    _sortOption = _sortPreferencesRepo.getSortOption();
    _layoutOption = _sortPreferencesRepo.getLayoutOption();
    _searchController = TextEditingController()
      ..addListener(_handleSearchChanged);
    _quickAdditionController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resumeEditorIfNeeded();
      _checkFreshInstallBackup();
    });
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_handleSearchChanged)
      ..dispose();
    _quickAdditionController.dispose();
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
      drawer: _HomeDrawer(hostContext: context),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: Stack(
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
                                  onSortPressed:
                                      _isSelectionMode ? null : _showSortSheet,
                                  layoutOption: _layoutOption,
                                  onLayoutPressed: _isSelectionMode
                                      ? null
                                      : _toggleLayoutOption,
                                ),
                                SizedBox(height: 18.h),
                                Padding(
                                  padding:
                                      EdgeInsets.symmetric(horizontal: 24.w),
                                  child: _SearchField(
                                    controller: _searchController,
                                  ),
                                ),
                                SizedBox(height: 22.h),
                                if (_hasCloudBackupProvider(context))
                                  const BackupRestorePromptBanner(),
                              ],
                            ),
                          ),
                        ),
                      ];
                    },
                    body: Builder(
                      builder: (context) {
                        return CustomScrollView(
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
                                  child: const _EmptyIdeasState(),
                                ),
                              )
                            else if (visibleIdeas.isEmpty)
                              SliverPadding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 24),
                                sliver: SliverFillRemaining(
                                  hasScrollBody: false,
                                  child: Padding(
                                    padding: const EdgeInsets.only(bottom: 180),
                                    child: const _NoSearchResultsState(),
                                  ),
                                ),
                              )
                            else
                              SliverPadding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 0, 16, 200),
                                sliver: SliverToBoxAdapter(
                                  child: _IdeasLayout(
                                    ideas: visibleIdeas,
                                    layoutOption: _layoutOption,
                                    selectedIdeaIds: _selectedIdeaIds,
                                    onTap: _handleIdeaTap,
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
      ),
      floatingActionButton: _isSelectionMode
          ? null
          : Padding(
              padding: const EdgeInsets.only(bottom: 60),
              child: _HomepageFab(
                isExtended: _layoutOption == IdeaLayoutOption.list,
                onPressed: () => AppRouter.push(
                  context,
                  const IdeaEditorScreen(),
                ),
              ),
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
          IgnorePointer(
            child: Container(
              height: 32,
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
          ColoredBox(
            color: theme.background,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                0,
                16,
                MediaQuery.of(context).padding.bottom + 4,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 860),
                child: RandomAdditionComposer(
                  controller: _quickAdditionController,
                  fieldKey: const Key('homepage-random-addition-field'),
                  sendButtonKey: const Key('homepage-random-addition-send'),
                  onSubmit: _submitQuickAddition,
                ),
              ),
            ),
          ),
        ],
      ),
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

    await AppRouter.push(
      context,
      IdeaEditorScreen(ideaId: idea.id),
    );
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

  void _handleIdeaTap(Idea idea) {
    if (_isSelectionMode) {
      _toggleIdeaSelection(idea.id);
      return;
    }

    AppRouter.push(
      context,
      IdeaEditorScreen(ideaId: idea.id),
    );
  }

  Future<void> _submitQuickAddition() async {
    final addition = await context
        .read<RandomAdditionsProvider>()
        .addAddition(_quickAdditionController.text);
    if (addition == null || !mounted) {
      return;
    }

    _quickAdditionController.clear();
    await _openRandomAdditions();
  }

  Future<void> _openRandomAdditions() async {
    await AppRouter.push(
      context,
      const RandomAdditionsScreen(),
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
    await context.read<IdeasProvider>().deleteIdeas(selectedIds);
    if (!mounted) {
      return;
    }

    setState(() {
      _selectedIdeaIds.clear();
    });
  }

  void _handleSearchChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  List<Idea> _visibleIdeas(List<Idea> ideas) {
    final filteredIdeas = ideas
        .where((idea) => _matchesSearch(idea, _searchQuery))
        .toList(growable: false);

    switch (_sortOption) {
      case IdeaSortOption.newestFirst:
        filteredIdeas.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        break;
      case IdeaSortOption.oldestFirst:
        filteredIdeas.sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
        break;
      case IdeaSortOption.mostSections:
        filteredIdeas.sort((a, b) {
          final sectionCountDifference = b.sections.length - a.sections.length;
          if (sectionCountDifference != 0) {
            return sectionCountDifference;
          }
          return b.updatedAt.compareTo(a.updatedAt);
        });
        break;
    }

    return filteredIdeas;
  }

  bool _matchesSearch(Idea idea, String query) {
    if (query.isEmpty) {
      return true;
    }

    final normalizedQuery = query.toLowerCase();
    final titleMatches = idea.title.toLowerCase().contains(normalizedQuery);
    final previewMatches = ideaPreviewText(
      idea,
      fallbackIfEmpty: false,
    ).toLowerCase().contains(normalizedQuery);

    return titleMatches || previewMatches;
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
  });

  final BuildContext hostContext;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    final paywall = _maybePaywallViewModel(context);
    final randomAdditionCount =
        context.watch<RandomAdditionsProvider>().additions.length;
    return Drawer(
      backgroundColor: theme.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (paywall != null && !paywall.isPro)
              ListTile(
                leading: Icon(
                  Icons.workspace_premium_rounded,
                  color: theme.primary,
                ),
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
                if (paywall != null) {
                  final hasAccess = await paywall.ensureAccess(
                    hostContext,
                    PremiumFeature.cloudBackup,
                  );
                  if (!hasAccess || !hostContext.mounted) {
                    return;
                  }
                }
                AppRouter.push(
                  hostContext,
                  const BackupRestoreScreen(),
                );
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

class _Header extends StatelessWidget {
  const _Header({
    required this.ideaCount,
    required this.selectedCount,
    required this.onMenuPressed,
    required this.onDeletePressed,
    required this.onSortPressed,
    required this.layoutOption,
    required this.onLayoutPressed,
  });

  final int ideaCount;
  final int selectedCount;
  final VoidCallback onMenuPressed;
  final VoidCallback? onDeletePressed;
  final VoidCallback? onSortPressed;
  final IdeaLayoutOption layoutOption;
  final VoidCallback? onLayoutPressed;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;

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
                  backgroundColor: theme.surfaceLow,
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
                key: const Key('ideas-layout-toggle'),
                tooltip: layoutOption == IdeaLayoutOption.list
                    ? ViewConstants.homepageSwitchToGridTooltip.tr()
                    : ViewConstants.homepageSwitchToListTooltip.tr(),
                onPressed: onLayoutPressed,
                style: IconButton.styleFrom(
                  backgroundColor: theme.surfaceLow,
                  foregroundColor: theme.primary,
                  padding: const EdgeInsets.all(12),
                ),
                icon: Icon(
                  layoutOption == IdeaLayoutOption.list
                      ? Icons.grid_view_rounded
                      : Icons.view_agenda_rounded,
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                key: const Key('ideas-sort-button'),
                onPressed: onSortPressed,
                style: IconButton.styleFrom(
                  backgroundColor: theme.surfaceLow,
                  foregroundColor: theme.primary,
                  padding: const EdgeInsets.all(12),
                ),
                icon: const Icon(Icons.swap_vert_rounded),
              ),
            ],
            Gap(16.w),
          ],
        ),
      ],
    );
  }
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

enum _IdeaCardLayout {
  list,
  grid,
}

class _IdeasLayout extends StatelessWidget {
  const _IdeasLayout({
    required this.ideas,
    required this.layoutOption,
    required this.selectedIdeaIds,
    required this.onTap,
    required this.onLongPress,
  });

  static const Duration _animationDuration = Duration(milliseconds: 260);

  final List<Idea> ideas;
  final IdeaLayoutOption layoutOption;
  final Set<String> selectedIdeaIds;
  final ValueChanged<Idea> onTap;
  final ValueChanged<Idea> onLongPress;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final metrics = _IdeaLayoutMetrics.calculate(
          maxWidth: constraints.maxWidth,
          itemCount: ideas.length,
          layoutOption: layoutOption,
        );

        return AnimatedSize(
          duration: _animationDuration,
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: SizedBox(
            height: metrics.height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (var index = 0; index < ideas.length; index++)
                  AnimatedPositioned(
                    key: ValueKey('idea-layout-${ideas[index].id}'),
                    duration: _animationDuration,
                    curve: Curves.easeOutCubic,
                    left: metrics.rects[index].left,
                    top: metrics.rects[index].top,
                    width: metrics.rects[index].width,
                    height: metrics.rects[index].height,
                    child: _IdeaCard(
                      idea: ideas[index],
                      layout: metrics.cardLayout,
                      isSelected: selectedIdeaIds.contains(ideas[index].id),
                      onTap: () => onTap(ideas[index]),
                      onLongPress: () => onLongPress(ideas[index]),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _IdeaLayoutMetrics {
  const _IdeaLayoutMetrics({
    required this.height,
    required this.rects,
    required this.cardLayout,
  });

  static const double _listGap = 16;
  static const double _gridGap = 12;
  static const double _listCardHeight = 224;
  static const double _gridCardHeight = 218;
  static const double _minimumTwoColumnWidth = 340;

  final double height;
  final List<Rect> rects;
  final _IdeaCardLayout cardLayout;

  static _IdeaLayoutMetrics calculate({
    required double maxWidth,
    required int itemCount,
    required IdeaLayoutOption layoutOption,
  }) {
    if (itemCount == 0) {
      return const _IdeaLayoutMetrics(
        height: 0,
        rects: [],
        cardLayout: _IdeaCardLayout.list,
      );
    }

    final useGrid = layoutOption == IdeaLayoutOption.grid &&
        maxWidth >= _minimumTwoColumnWidth;
    if (!useGrid) {
      final rects = List<Rect>.generate(itemCount, (index) {
        final top = index * (_listCardHeight + _listGap);
        return Rect.fromLTWH(0, top, maxWidth, _listCardHeight);
      });
      return _IdeaLayoutMetrics(
        height: itemCount * _listCardHeight + (itemCount - 1) * _listGap,
        rects: rects,
        cardLayout: _IdeaCardLayout.list,
      );
    }

    final cardWidth = (maxWidth - _gridGap) / 2;
    final rowCount = (itemCount / 2).ceil();
    final rects = List<Rect>.generate(itemCount, (index) {
      final row = index ~/ 2;
      final column = index % 2;
      return Rect.fromLTWH(
        column * (cardWidth + _gridGap),
        row * (_gridCardHeight + _gridGap),
        cardWidth,
        _gridCardHeight,
      );
    });

    return _IdeaLayoutMetrics(
      height: rowCount * _gridCardHeight + (rowCount - 1) * _gridGap,
      rects: rects,
      cardLayout: _IdeaCardLayout.grid,
    );
  }
}

class _IdeaCard extends StatelessWidget {
  const _IdeaCard({
    required this.idea,
    required this.layout,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
  });

  final Idea idea;
  final _IdeaCardLayout layout;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  bool get _isGrid => layout == _IdeaCardLayout.grid;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    final radius = BorderRadius.circular(_isGrid ? 22 : 28);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('idea-card-${idea.id}'),
        borderRadius: radius,
        onTap: onTap,
        onLongPress: onLongPress,
        child: Ink(
          decoration: BoxDecoration(
            color: isSelected ? theme.accentTint : theme.surface,
            borderRadius: radius,
            border: Border.all(
              color: isSelected
                  ? theme.primary.withValues(alpha: 0.32)
                  : Colors.transparent,
            ),
          ),
          padding: EdgeInsets.all(_isGrid ? 14 : 22),
          child:
              _isGrid ? _buildGridContent(context) : _buildListContent(context),
        ),
      ),
    );
  }

  Widget _buildListContent(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                idea.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: ideaVaultHeadline(
                  context,
                  size: 24,
                  weight: FontWeight.w800,
                  height: 1.15,
                ),
              ),
            ),
            const SizedBox(width: 16),
            _SectionCountPill(idea: idea),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          _ideaPreview(idea),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: ideaVaultBody(
            context,
            size: 15,
            weight: FontWeight.w500,
            color: theme.textMuted,
            height: 1.65,
          ),
        ),
        const Spacer(),
        _UpdatedAtLabel(
          updatedAt: idea.updatedAt,
          iconSize: 18,
          textSize: 13,
        ),
      ],
    );
  }

  Widget _buildGridContent(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          idea.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: ideaVaultHeadline(
            context,
            size: 17,
            weight: FontWeight.w800,
            height: 1.18,
          ),
        ),
        const SizedBox(height: 10),
        _SectionCountPill(
          idea: idea,
          compact: true,
        ),
        const SizedBox(height: 10),
        Expanded(
          child: Text(
            _ideaPreview(idea),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: ideaVaultBody(
              context,
              size: 13,
              weight: FontWeight.w500,
              color: theme.textMuted,
              height: 1.45,
            ),
          ),
        ),
        const SizedBox(height: 10),
        _UpdatedAtLabel(
          updatedAt: idea.updatedAt,
          iconSize: 16,
          textSize: 11,
        ),
      ],
    );
  }

  String _ideaPreview(Idea idea) {
    return ideaPreviewText(idea);
  }
}

class _SectionCountPill extends StatelessWidget {
  const _SectionCountPill({
    required this.idea,
    this.compact = false,
  });

  final Idea idea;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: compact ? 128 : 120),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 12,
          vertical: compact ? 6 : 8,
        ),
        decoration: BoxDecoration(
          color: theme.surfaceLow,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          idea.sections.length == 1
              ? ViewConstants.homepageIdeaCardOneSection.tr()
              : ViewConstants.homepageIdeaCardSectionsMany.tr(
                  namedArgs: {
                    'count': '${idea.sections.length}',
                  },
                ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: ideaVaultLabel(
            context,
            size: compact ? 11 : 12,
            weight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}

class _UpdatedAtLabel extends StatelessWidget {
  const _UpdatedAtLabel({
    required this.updatedAt,
    required this.iconSize,
    required this.textSize,
  });

  final DateTime updatedAt;
  final double iconSize;
  final double textSize;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    return Row(
      children: [
        Icon(
          Icons.schedule_rounded,
          size: iconSize,
          color: theme.textMuted,
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            _formatUpdatedAt(context, updatedAt),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: ideaVaultLabel(
              context,
              size: textSize,
              weight: FontWeight.w600,
              color: theme.textMuted,
            ),
          ),
        ),
      ],
    );
  }

  String _formatUpdatedAt(BuildContext context, DateTime updatedAt) {
    final localizations = MaterialLocalizations.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final updatedDay = DateTime(updatedAt.year, updatedAt.month, updatedAt.day);
    final difference = today.difference(updatedDay).inDays;

    if (difference == 0) {
      return ViewConstants.homepageIdeaCardUpdatedToday.tr(
        namedArgs: {
          'time':
              localizations.formatTimeOfDay(TimeOfDay.fromDateTime(updatedAt)),
        },
      );
    }

    if (difference == 1) {
      return ViewConstants.homepageIdeaCardUpdatedYesterday.tr();
    }

    return ViewConstants.homepageIdeaCardUpdatedOnDate.tr(
      namedArgs: {
        'date': localizations.formatMediumDate(updatedAt),
      },
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
  });

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    return IdeaVaultPillTextField(
      fieldKey: const Key('ideas-search-field'),
      controller: controller,
      hintText: ViewConstants.homepageSearchHint.tr(),
      leading: Icon(
        Icons.search_rounded,
        color: theme.textMuted,
        size: 22,
      ),
      textInputAction: TextInputAction.search,
      useShadow: false,
    );
  }
}

class _NoSearchResultsState extends StatelessWidget {
  const _NoSearchResultsState();

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    return Center(
      child: TranslatedText(
        ViewConstants.homepageNoSearchResults,
        textAlign: TextAlign.center,
        style: ideaVaultBody(
          context,
          size: 16,
          weight: FontWeight.w600,
          color: theme.textMuted,
          height: 1.5,
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

String ideaPreviewText(
  Idea idea, {
  bool fallbackIfEmpty = true,
}) {
  for (final section in idea.sections) {
    final text = plainPreviewText(section.content);
    if (text.isNotEmpty) {
      return text;
    }
  }

  return fallbackIfEmpty
      ? ViewConstants.homepageIdeaCardPreviewPlaceholder.tr()
      : '';
}

String plainPreviewText(String markdown) {
  return markdown
      .replaceAll('```', ' ')
      .replaceAllMapped(
        RegExp(r'\*\*(.*?)\*\*', dotAll: true),
        (match) => match.group(1) ?? '',
      )
      .replaceAllMapped(
        RegExp(r'_(.*?)_', dotAll: true),
        (match) => match.group(1) ?? '',
      )
      .replaceAll(RegExp(r'^#\s*', multiLine: true), '')
      .replaceAll(RegExp(r'^-\s*', multiLine: true), '')
      .replaceAll('\n', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
