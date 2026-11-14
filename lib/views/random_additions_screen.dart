import 'dart:async';

import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/utils/idea_display.dart';
import '../config/theme/base.dart';
import '../core/constants/view_constants.dart';
import '../core/services/note_lock_auth_service.dart';
import '../core/services/note_lock_biometric_service.dart';
import '../core/utils/selection_controller.dart';
import '../injection_container.dart';
import '../models/idea.dart';
import '../models/random_addition.dart';
import '../viewmodels/providers/ideas_provider.dart';
import '../viewmodels/providers/random_additions_provider.dart';
import '../viewmodels/providers/theme_provider.dart';
import '../widgets/idea_vault_subpage_app_bar.dart';
import '../widgets/note_lock_auth_dialog.dart';
import '../widgets/popups/delete_ideas_confirmation_dialog.dart';
import '../widgets/random_addition_composer.dart';
import '../widgets/selection/selection_bar.dart';
import '../widgets/selection/selection_check_badge.dart';
import '../widgets/selection/selection_style.dart';
import '../widgets/translated_text.dart';
import 'ideas/idea_vault_theme.dart';

class RandomAdditionsScreen extends StatefulWidget {
  const RandomAdditionsScreen({
    super.key,
    this.autofocusComposer = false,
  });

  final bool autofocusComposer;

  @override
  State<RandomAdditionsScreen> createState() => _RandomAdditionsScreenState();
}

class _RandomAdditionsScreenState extends State<RandomAdditionsScreen> {
  final SelectionController _selection = SelectionController();
  late final TextEditingController _composerController;
  late final RandomAdditionsProvider _additionsProvider;

  bool get _isSelectionMode => _selection.isActive;

  @override
  void initState() {
    super.initState();
    _composerController = TextEditingController();
    _selection.addListener(_onSelectionChanged);
    _additionsProvider = context.read<RandomAdditionsProvider>();
    _additionsProvider.addListener(_pruneSelection);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(context.read<RandomAdditionsProvider>().ensureLoaded());
      unawaited(context.read<IdeasProvider>().ensureLoaded());
    });
  }

  @override
  void dispose() {
    _additionsProvider.removeListener(_pruneSelection);
    _selection.removeListener(_onSelectionChanged);
    _selection.dispose();
    _composerController.dispose();
    super.dispose();
  }

  void _onSelectionChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _pruneSelection() {
    _selection.retainExisting(
      _additionsProvider.additions.map((addition) => addition.id),
    );
  }

  List<RandomAddition> _selectedAdditionsInTimeOrder() {
    final selected = _additionsProvider.additions
        .where((addition) => _selection.isSelected(addition.id))
        .toList();
    selected.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return selected;
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    final additionsProvider = context.watch<RandomAdditionsProvider>();
    final additions = additionsProvider.additions;

    return PopScope(
      canPop: !_isSelectionMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _selection.clear();
          return;
        }
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Scaffold(
        key: const Key('random-additions-screen'),
        backgroundColor: theme.background,
        appBar: _isSelectionMode
            ? SelectionAppBar(
                count: _selection.count,
                onClose: _selection.clear,
                closeButtonKey: const Key('random-additions-selection-close'),
                countKey: const Key('random-additions-selection-count'),
                actions: [
                  SelectionActionButton(
                    key: const Key('random-additions-copy-button'),
                    icon: Icons.copy_rounded,
                    tooltipKey: ViewConstants.selectionCopyTooltip,
                    onPressed: () => unawaited(_copySelection()),
                  ),
                  SelectionActionButton(
                    key: const Key('random-additions-file-button'),
                    icon: Icons.playlist_add_rounded,
                    tooltipKey: ViewConstants.randomAdditionsFileTooltip,
                    onPressed: () => unawaited(_fileSelection()),
                  ),
                  SelectionActionButton(
                    key: const Key('random-additions-delete-button'),
                    icon: Icons.delete_outline_rounded,
                    tooltipKey: ViewConstants.selectionDeleteTooltip,
                    onPressed: () => unawaited(_confirmDeleteSelection()),
                  ),
                ],
              )
            : const IdeaVaultSubpageAppBar(
                titleKey: ViewConstants.randomAdditionsTitle,
              ),
        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: SafeArea(
            top: false,
            bottom: false,
            child: Column(
              children: [
                Expanded(
                  child: additions.isEmpty
                      ? const _RandomAdditionsEmptyState()
                      : ListView.builder(
                          key: const Key('random-additions-list'),
                          reverse: true,
                          padding: const EdgeInsets.fromLTRB(0, 8, 0, 2),
                          itemCount: additions.length,
                          itemBuilder: (context, index) {
                            final addition =
                                additions[additions.length - 1 - index];
                            return _RandomAdditionRow(
                              key: ValueKey('random-addition-${addition.id}'),
                              addition: addition,
                              isSelected: _selection.isSelected(addition.id),
                              isSelectionActive: _isSelectionMode,
                              onTap: () => _handleAdditionTap(addition),
                              onLongPress: () =>
                                  _handleAdditionLongPress(addition),
                            );
                          },
                        ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    4,
                    16,
                    MediaQuery.of(context).padding.bottom + 8,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 860),
                    child: RandomAdditionComposer(
                      controller: _composerController,
                      fieldKey: const Key('random-additions-composer'),
                      sendButtonKey: const Key('random-additions-send'),
                      autofocus: widget.autofocusComposer,
                      onSubmit: _submitAddition,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submitAddition() async {
    final provider = context.read<RandomAdditionsProvider>();
    final addition = await provider.addAddition(_composerController.text);
    if (addition == null || !mounted) {
      return;
    }
    _composerController.clear();
  }

  void _handleAdditionTap(RandomAddition addition) {
    if (_isSelectionMode) {
      _selection.toggle(addition.id);
      return;
    }

    unawaited(_fileAdditions([addition]));
  }

  void _handleAdditionLongPress(RandomAddition addition) {
    if (_isSelectionMode) {
      _selection.toggle(addition.id);
      return;
    }
    unawaited(HapticFeedback.selectionClick());
    _selection.select(addition.id);
  }

  Future<void> _copySelection() async {
    final selected = _selectedAdditionsInTimeOrder();
    if (selected.isEmpty) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(
      ClipboardData(
        text: selected.map((addition) => addition.content).join('\n\n'),
      ),
    );
    if (!mounted) {
      return;
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          selected.length == 1
              ? ViewConstants.selectionCopiedOne.tr()
              : ViewConstants.selectionCopiedMany.tr(
                  namedArgs: {'count': '${selected.length}'},
                ),
        ),
      ),
    );
    _selection.clear();
  }

  Future<void> _fileSelection() async {
    final selected = _selectedAdditionsInTimeOrder();
    if (selected.isEmpty) {
      return;
    }
    await _fileAdditions(selected);
  }

  Future<void> _confirmDeleteSelection() async {
    final selectedCount = _selection.count;
    if (selectedCount == 0) {
      return;
    }

    final shouldDelete = await showSelectionDeleteConfirmationDialog(
      context,
      title: selectedCount == 1
          ? ViewConstants.selectionDeleteNoteTitleOne.tr()
          : ViewConstants.selectionDeleteNotesTitleMany.tr(
              namedArgs: {'count': '$selectedCount'},
            ),
      body: selectedCount == 1
          ? ViewConstants.selectionDeleteNoteBodyOne.tr()
          : ViewConstants.selectionDeleteNotesBodyMany.tr(
              namedArgs: {'count': '$selectedCount'},
            ),
      confirmKey: const Key('random-additions-delete-confirm'),
    );

    if (shouldDelete != true || !mounted) {
      return;
    }

    final selectedIds = _selection.selectedIds.toList(growable: false);
    await context.read<RandomAdditionsProvider>().deleteAdditions(selectedIds);
    if (!mounted) {
      return;
    }

    _selection.clear();
  }

  Future<void> _fileAdditions(List<RandomAddition> additions) async {
    if (additions.isEmpty) {
      return;
    }
    final ideasProvider = context.read<IdeasProvider>();
    final additionsProvider = context.read<RandomAdditionsProvider>();
    final theme = context.read<ThemeProvider>().baseTheme;
    final messenger = ScaffoldMessenger.of(context);
    await ideasProvider.ensureLoaded();
    if (!mounted) {
      return;
    }

    final selectedIdea = await showModalBottomSheet<Idea>(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.surface,
      builder: (ideaSheetContext) {
        return _IdeaPickerSheet(
          ideas: ideasProvider.ideas,
          onIdeaSelected: (idea) => Navigator.of(ideaSheetContext).pop(idea),
        );
      },
    );

    if (selectedIdea == null || !mounted) {
      return;
    }

    final noteLockAuthService = sl.isRegistered<NoteLockAuthService>()
        ? sl<NoteLockAuthService>()
        : NoteLockAuthService();
    if (selectedIdea.isLocked) {
      final noteLockBiometricService =
          sl.isRegistered<NoteLockBiometricService>()
              ? sl<NoteLockBiometricService>()
              : NoteLockBiometricService();
      final didAuthenticate = await authenticateForNoteLock(
        context,
        noteLockAuthService,
        noteLockBiometricService,
        ideaId: selectedIdea.id,
      );
      if (!didAuthenticate || !mounted) {
        return;
      }
    }

    var pickerIdea = selectedIdea;
    final vault = ideasProvider.vault;
    if (selectedIdea.isEncrypted) {
      vault?.openSession();
      Idea? opened;
      try {
        opened = await ideasProvider.openLockedIdea(selectedIdea.id);
      } catch (_) {
        opened = null;
      }
      if (opened == null || opened.isEncrypted || !mounted) {
        vault?.closeSession();
        noteLockAuthService.markIdeaLocked(selectedIdea.id);
        if (mounted) {
          messenger.showSnackBar(
            SnackBar(content: Text(ViewConstants.vaultOpenFailed.tr())),
          );
        }
        return;
      }
      pickerIdea = opened;
    }

    try {
      await _showSectionPicker(
        additions: additions,
        selectedIdea: pickerIdea,
        ideasProvider: ideasProvider,
        additionsProvider: additionsProvider,
        theme: theme,
        messenger: messenger,
      );
    } finally {
      if (selectedIdea.isEncrypted) {
        vault?.closeSession();
      }
      if (selectedIdea.isLocked) {
        noteLockAuthService.markIdeaLocked(selectedIdea.id);
      }
    }
  }

  Future<int> _appendInTimeOrder({
    required List<RandomAddition> additions,
    required Idea idea,
    required IdeaSection section,
    required IdeasProvider ideasProvider,
    required RandomAdditionsProvider additionsProvider,
  }) async {
    var filedCount = 0;
    for (final addition in additions) {
      try {
        final savedIdea = await ideasProvider.appendContentToSection(
          ideaId: idea.id,
          sectionId: section.id,
          content: addition.content,
        );
        if (savedIdea == null) {
          break;
        }
        await additionsProvider.deleteAddition(addition.id);
      } on Object {
        break;
      }
      filedCount += 1;
    }
    return filedCount;
  }

  Future<void> _showSectionPicker({
    required List<RandomAddition> additions,
    required Idea selectedIdea,
    required IdeasProvider ideasProvider,
    required RandomAdditionsProvider additionsProvider,
    required BaseTheme theme,
    required ScaffoldMessengerState messenger,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.surface,
      builder: (sectionSheetContext) {
        return _SectionPickerSheet(
          idea: selectedIdea,
          onSectionSelected: (section) async {
            final filedCount = await _appendInTimeOrder(
              additions: additions,
              idea: selectedIdea,
              section: section,
              ideasProvider: ideasProvider,
              additionsProvider: additionsProvider,
            );
            if (filedCount == 0 && additions.length == 1) {
              return;
            }
            if (!sectionSheetContext.mounted) {
              return;
            }
            Navigator.of(sectionSheetContext).pop();
            final String message;
            if (filedCount < additions.length) {
              message = ViewConstants.selectionFilePartialFailure.tr();
            } else if (filedCount == 1) {
              message = ViewConstants.randomAdditionsFiledSnackbar.tr(
                namedArgs: {
                  'idea': selectedIdea.title,
                  'section': section.name,
                },
              );
            } else {
              message = ViewConstants.selectionFiledManySnackbar.tr(
                namedArgs: {
                  'count': '$filedCount',
                  'idea': selectedIdea.title,
                  'section': section.name,
                },
              );
            }
            messenger.showSnackBar(SnackBar(content: Text(message)));
          },
        );
      },
    );
  }
}

class _RandomAdditionsEmptyState extends StatelessWidget {
  const _RandomAdditionsEmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 0, 28, 72),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              key: const Key('random-additions-empty'),
              height: 72,
              width: 72,
              decoration: BoxDecoration(
                color: theme.accentTint,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.chat_bubble_outline_rounded,
                color: theme.primary,
                size: 32,
              ),
            ),
            const SizedBox(height: 18),
            TranslatedText(
              ViewConstants.randomAdditionsEmptyTitle,
              textAlign: TextAlign.center,
              style: ideaVaultHeadline(
                context,
                size: 23,
                weight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            TranslatedText(
              ViewConstants.randomAdditionsEmptySubtitle,
              textAlign: TextAlign.center,
              style: ideaVaultBody(
                context,
                size: 15,
                weight: FontWeight.w500,
                color: theme.textMuted,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RandomAdditionRow extends StatelessWidget {
  const _RandomAdditionRow({
    super.key,
    required this.addition,
    required this.isSelected,
    required this.isSelectionActive,
    required this.onTap,
    required this.onLongPress,
  });

  final RandomAddition addition;
  final bool isSelected;
  final bool isSelectionActive;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    return Semantics(
      selected: isSelectionActive ? isSelected : null,
      child: GestureDetector(
        key: Key('random-addition-row-${addition.id}'),
        behavior: HitTestBehavior.opaque,
        onTap: isSelectionActive ? onTap : null,
        onLongPress: onLongPress,
        child: AnimatedContainer(
          key: Key('random-addition-band-${addition.id}'),
          duration: const Duration(milliseconds: 150),
          color: isSelected ? selectionBandColor(theme) : Colors.transparent,
          padding: const EdgeInsetsDirectional.fromSTEB(16, 2, 16, 2),
          child: Row(
            children: [
              if (isSelectionActive) ...[
                SelectionCheckBadge(
                  key: Key('random-addition-check-${addition.id}'),
                  isSelected: isSelected,
                  size: 22,
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: _RandomAdditionBubble(
                    addition: addition,
                    onTap: onTap,
                    onLongPress: onLongPress,
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

class _RandomAdditionBubble extends StatelessWidget {
  const _RandomAdditionBubble({
    required this.addition,
    required this.onTap,
    required this.onLongPress,
  });

  final RandomAddition addition;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    const radius = BorderRadiusDirectional.only(
      topStart: Radius.circular(18),
      topEnd: Radius.circular(18),
      bottomStart: Radius.circular(18),
      bottomEnd: Radius.circular(6),
    );
    final foregroundColor = theme.onPrimary;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Material(
        color: theme.primary,
        shape: const RoundedRectangleBorder(borderRadius: radius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: Key('random-addition-bubble-${addition.id}'),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 8, 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Flexible(
                  child: Text(
                    addition.content,
                    style: ideaVaultBody(
                      context,
                      size: 15,
                      weight: FontWeight.w600,
                      color: foregroundColor,
                      height: 1.38,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  key: Key('random-addition-file-${addition.id}'),
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: foregroundColor.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.add_rounded,
                    size: 16,
                    color: foregroundColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _IdeaPickerSheet extends StatelessWidget {
  const _IdeaPickerSheet({
    required this.ideas,
    required this.onIdeaSelected,
  });

  final List<Idea> ideas;
  final ValueChanged<Idea> onIdeaSelected;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.5,
      minChildSize: 0.25,
      maxChildSize: 0.9,
      snap: true,
      snapSizes: const [0.5, 0.9],
      builder: (context, scrollController) {
        return CustomScrollView(
          controller: scrollController,
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: theme.outline.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                    child: TranslatedText(
                      ViewConstants.randomAdditionsChooseIdeaTitle,
                      style: ideaVaultHeadline(
                        context,
                        size: 23,
                        weight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (ideas.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: EdgeInsets.only(bottom: 20 + bottomInset),
                  child: Center(
                    child: _NoIdeasForFiling(theme: theme),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottomInset),
                sliver: SliverList.separated(
                  itemCount: ideas.length,
                  separatorBuilder: (_, __) => const SizedBox.shrink(),
                  itemBuilder: (context, index) {
                    final idea = ideas[index];
                    return _FilingTile(
                      key: Key('random-addition-idea-${idea.id}'),
                      title: ideaDisplayTitle(idea),
                      subtitle: idea.isLocked
                          ? ViewConstants.noteLockPickerLockedSubtitle.tr()
                          : idea.sections.length == 1
                              ? ViewConstants.homepageIdeaCardOneSection.tr()
                              : ViewConstants.homepageIdeaCardSectionsMany.tr(
                                  namedArgs: {
                                    'count': '${idea.sections.length}',
                                  },
                                ),
                      icon: idea.isLocked
                          ? Icons.lock_outline_rounded
                          : Icons.lightbulb_outline_rounded,
                      onTap: () => onIdeaSelected(idea),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SectionPickerSheet extends StatefulWidget {
  const _SectionPickerSheet({
    required this.idea,
    required this.onSectionSelected,
  });

  final Idea idea;
  final Future<void> Function(IdeaSection section) onSectionSelected;

  @override
  State<_SectionPickerSheet> createState() => _SectionPickerSheetState();
}

class _SectionPickerSheetState extends State<_SectionPickerSheet> {
  bool _isFiling = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.5,
      minChildSize: 0.25,
      maxChildSize: 0.9,
      snap: true,
      snapSizes: const [0.5, 0.9],
      builder: (context, scrollController) {
        return CustomScrollView(
          controller: scrollController,
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: theme.outline.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                    child: TranslatedText(
                      ViewConstants.randomAdditionsChooseSectionTitle,
                      style: ideaVaultHeadline(
                        context,
                        size: 23,
                        weight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottomInset),
              sliver: SliverList.separated(
                itemCount: widget.idea.sections.length,
                separatorBuilder: (_, __) => const SizedBox.shrink(),
                itemBuilder: (context, index) {
                  final section = widget.idea.sections[index];
                  return _FilingTile(
                    key: Key('random-addition-section-${section.id}'),
                    title: section.name,
                    subtitle: ViewConstants.randomAdditionsAppendToSection.tr(),
                    icon: Icons.notes_rounded,
                    onTap: _isFiling ? null : () => _file(section),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _file(IdeaSection section) async {
    setState(() => _isFiling = true);
    try {
      await widget.onSectionSelected(section);
    } finally {
      if (mounted) {
        setState(() => _isFiling = false);
      }
    }
  }
}

class _NoIdeasForFiling extends StatelessWidget {
  const _NoIdeasForFiling({
    required this.theme,
  });

  final BaseTheme theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const Key('random-additions-no-ideas'),
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            Icons.lightbulb_outline_rounded,
            size: 38,
            color: theme.primary,
          ),
          const SizedBox(height: 12),
          TranslatedText(
            ViewConstants.randomAdditionsNoIdeasTitle,
            textAlign: TextAlign.center,
            style:
                ideaVaultHeadline(context, size: 21, weight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          TranslatedText(
            ViewConstants.randomAdditionsNoIdeasSubtitle,
            textAlign: TextAlign.center,
            style: ideaVaultBody(
              context,
              size: 15,
              color: theme.textMuted,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilingTile extends StatelessWidget {
  const _FilingTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: CircleAvatar(
        backgroundColor: theme.accentTint,
        foregroundColor: theme.primary,
        child: Icon(icon),
      ),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: ideaVaultBody(
          context,
          size: 16,
          weight: FontWeight.w700,
        ),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: ideaVaultLabel(context, size: 13, weight: FontWeight.w600),
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}
