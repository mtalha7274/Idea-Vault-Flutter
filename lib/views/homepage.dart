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
import '../viewmodels/providers/ideas_provider.dart';
import '../viewmodels/providers/theme_provider.dart';
import '../widgets/popups/delete_ideas_confirmation_dialog.dart';
import '../widgets/translated_text.dart';
import 'backup_restore_screen.dart';
import 'idea_editor.dart';
import 'ideas/idea_vault_theme.dart';
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
  late final IdeaListPreferencesRepo _sortPreferencesRepo;

  bool _didHandleResume = false;
  late IdeaSortOption _sortOption;

  bool get _isSelectionMode => _selectedIdeaIds.isNotEmpty;
  String get _searchQuery => _searchController.text.trim();

  @override
  void initState() {
    super.initState();
    _sortPreferencesRepo =
        widget.sortPreferencesRepo ?? sl<IdeaListPreferencesRepo>();
    _sortOption = _sortPreferencesRepo.getSortOption();
    _searchController = TextEditingController()
      ..addListener(_handleSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resumeEditorIfNeeded();
    });
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_handleSearchChanged)
      ..dispose();
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
      drawer: const _HomeDrawer(),
      body: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: NestedScrollView(
              floatHeaderSlivers: true,
              headerSliverBuilder: (context, innerBoxIsScrolled) {
                final handle =
                    NestedScrollView.sliverOverlapAbsorberHandleFor(context);
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
                          ),
                          SizedBox(height: 18.h),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 24.w),
                            child: _SearchField(
                              controller: _searchController,
                            ),
                          ),
                          SizedBox(height: 22.h),
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
                        handle: NestedScrollView.sliverOverlapAbsorberHandleFor(
                            context),
                      ),
                      if (ideas.isEmpty)
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          sliver: SliverFillRemaining(
                            hasScrollBody: false,
                            child: const _EmptyIdeasState(),
                          ),
                        )
                      else if (visibleIdeas.isEmpty)
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          sliver: SliverFillRemaining(
                            hasScrollBody: false,
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 120),
                              child: const _NoSearchResultsState(),
                            ),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(24, 0, 24, 120),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                if (index.isOdd) {
                                  return const SizedBox(height: 16);
                                }
                                final ideaIndex = index ~/ 2;
                                final idea = visibleIdeas[ideaIndex];
                                return _IdeaCard(
                                  idea: idea,
                                  isSelected:
                                      _selectedIdeaIds.contains(idea.id),
                                  onTap: () => _handleIdeaTap(idea),
                                  onLongPress: () => _handleIdeaLongPress(idea),
                                );
                              },
                              childCount: visibleIdeas.length * 2 - 1,
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
      floatingActionButton: _isSelectionMode
          ? null
          : FloatingActionButton.extended(
              key: const Key('ideas-fab'),
              onPressed: () => AppRouter.push(
                context,
                const IdeaEditorScreen(),
              ),
              backgroundColor: theme.primary,
              foregroundColor: theme.onPrimary,
              icon: const Icon(Icons.add_rounded),
              label: Text(
                'New Idea',
                style: ideaVaultLabel(
                  context,
                  size: 14,
                  weight: FontWeight.w700,
                  color: theme.onPrimary,
                ),
              ),
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
              Text(
                'Sort ideas',
                style: ideaVaultHeadline(
                  sheetContext,
                  size: 24,
                  weight: FontWeight.w800,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Choose how your vault is arranged.',
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
                title: 'Newest First',
                isSelected: _sortOption == IdeaSortOption.newestFirst,
                onTap: () =>
                    Navigator.of(sheetContext).pop(IdeaSortOption.newestFirst),
              ),
              _SortOptionTile(
                key: const Key('ideas-sort-oldest'),
                title: 'Oldest First',
                isSelected: _sortOption == IdeaSortOption.oldestFirst,
                onTap: () =>
                    Navigator.of(sheetContext).pop(IdeaSortOption.oldestFirst),
              ),
              _SortOptionTile(
                key: const Key('ideas-sort-most-sections'),
                title: 'Most Sections',
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
  const _HomeDrawer();

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
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
              onTap: () {
                Navigator.of(context).pop();
                AppRouter.push(
                  context,
                  const BackupRestoreScreen(),
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
                AppRouter.push(
                  context,
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

class _Header extends StatelessWidget {
  const _Header({
    required this.ideaCount,
    required this.selectedCount,
    required this.onMenuPressed,
    required this.onDeletePressed,
    required this.onSortPressed,
  });

  final int ideaCount;
  final int selectedCount;
  final VoidCallback onMenuPressed;
  final VoidCallback? onDeletePressed;
  final VoidCallback? onSortPressed;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;

    final menuStyle = IconButton.styleFrom(
      backgroundColor: theme.surfaceLow,
      foregroundColor: theme.primary,
      padding: const EdgeInsets.all(12),
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
              _SavedIdeasCountTipButton(
                ideaCount: ideaCount,
                menuStyle: menuStyle,
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

class _SavedIdeasCountTipButton extends StatefulWidget {
  const _SavedIdeasCountTipButton({
    required this.ideaCount,
    required this.menuStyle,
  });

  final int ideaCount;
  final ButtonStyle menuStyle;

  @override
  State<_SavedIdeasCountTipButton> createState() =>
      _SavedIdeasCountTipButtonState();
}

class _SavedIdeasCountTipButtonState extends State<_SavedIdeasCountTipButton> {
  final GlobalKey<TooltipState> _tooltipKey = GlobalKey<TooltipState>();

  String _tooltipMessage() {
    final n = widget.ideaCount;
    if (n == 1) {
      return ViewConstants.homepageSavedIdeasTooltipOne.tr();
    }
    return ViewConstants.homepageSavedIdeasTooltipMany
        .tr(namedArgs: {'count': '$n'});
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    return Tooltip(
      key: _tooltipKey,
      message: _tooltipMessage(),
      triggerMode: TooltipTriggerMode.manual,
      showDuration: const Duration(seconds: 2),
      child: IconButton(
        key: const Key('ideas-count-button'),
        onPressed: () => _tooltipKey.currentState?.ensureTooltipVisible(),
        style: widget.menuStyle,
        icon: Badge(
          backgroundColor: theme.primary,
          padding: EdgeInsets.symmetric(
            horizontal: widget.ideaCount > 9 ? 5 : 6,
            vertical: 2,
          ),
          label: Text(
            '${widget.ideaCount}',
            style: ideaVaultLabel(
              context,
              size: 10,
              weight: FontWeight.w800,
              color: theme.onPrimary,
            ),
          ),
          child: Icon(
            Icons.inventory_2_outlined,
            size: 22,
            color: theme.primary,
          ),
        ),
      ),
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
              Text(
                'Nothing saved yet',
                textAlign: TextAlign.center,
                style: ideaVaultHeadline(
                  context,
                  size: 24,
                  weight: FontWeight.w800,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Start with one fast idea, then break it into requirements, design notes, or any custom section you need.',
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

class _IdeaCard extends StatelessWidget {
  const _IdeaCard({
    required this.idea,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
  });

  final Idea idea;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('idea-card-${idea.id}'),
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Ink(
          decoration: BoxDecoration(
            color: isSelected ? theme.accentTint : theme.surface,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: isSelected
                  ? theme.primary.withValues(alpha: 0.32)
                  : Colors.transparent,
            ),
          ),
          padding: const EdgeInsets.all(22),
          child: Column(
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
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: theme.surfaceLow,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      idea.sections.length == 1
                          ? '1 section'
                          : '${idea.sections.length} sections',
                      style: ideaVaultLabel(
                        context,
                        size: 12,
                        weight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
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
              const SizedBox(height: 18),
              Row(
                children: [
                  Icon(
                    Icons.schedule_rounded,
                    size: 18,
                    color: theme.textMuted,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _formatUpdatedAt(context, idea.updatedAt),
                    style: ideaVaultLabel(
                      context,
                      size: 13,
                      weight: FontWeight.w600,
                      color: theme.textMuted,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _ideaPreview(Idea idea) {
    return ideaPreviewText(idea);
  }

  String _formatUpdatedAt(BuildContext context, DateTime updatedAt) {
    final localizations = MaterialLocalizations.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final updatedDay = DateTime(updatedAt.year, updatedAt.month, updatedAt.day);
    final difference = today.difference(updatedDay).inDays;

    if (difference == 0) {
      return 'Updated today • ${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(updatedAt))}';
    }

    if (difference == 1) {
      return 'Updated yesterday';
    }

    return 'Updated ${localizations.formatMediumDate(updatedAt)}';
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
    return TextField(
      key: const Key('ideas-search-field'),
      controller: controller,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        hintText: 'Search ideas',
        prefixIcon: Icon(
          Icons.search_rounded,
          color: theme.textMuted,
        ),
        filled: true,
        fillColor: theme.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
        hintStyle: ideaVaultBody(
          context,
          size: 15,
          weight: FontWeight.w500,
          color: theme.outline,
        ),
      ),
      style: ideaVaultBody(
        context,
        size: 15,
        weight: FontWeight.w600,
      ),
    );
  }
}

class _NoSearchResultsState extends StatelessWidget {
  const _NoSearchResultsState();

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    return Center(
      child: Text(
        'No ideas match your search',
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
    required this.title,
    required this.isSelected,
    required this.onTap,
  });

  final String title;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        title,
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

  return fallbackIfEmpty ? 'Tap to keep building this idea.' : '';
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
