import 'dart:async';

import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/theme/base.dart';
import '../core/constants/view_constants.dart';
import '../models/idea.dart';
import '../models/random_addition.dart';
import '../viewmodels/providers/ideas_provider.dart';
import '../viewmodels/providers/random_additions_provider.dart';
import '../viewmodels/providers/theme_provider.dart';
import '../widgets/idea_vault_subpage_app_bar.dart';
import '../widgets/random_addition_composer.dart';
import '../widgets/translated_text.dart';
import 'ideas/idea_vault_theme.dart';

class RandomAdditionsScreen extends StatefulWidget {
  const RandomAdditionsScreen({super.key});

  @override
  State<RandomAdditionsScreen> createState() => _RandomAdditionsScreenState();
}

class _RandomAdditionsScreenState extends State<RandomAdditionsScreen> {
  late final TextEditingController _composerController;

  @override
  void initState() {
    super.initState();
    _composerController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(context.read<RandomAdditionsProvider>().ensureLoaded());
      unawaited(context.read<IdeasProvider>().ensureLoaded());
    });
  }

  @override
  void dispose() {
    _composerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    final additionsProvider = context.watch<RandomAdditionsProvider>();
    final additions = additionsProvider.additions;

    return PopScope(
      onPopInvokedWithResult: (_, __) =>
          FocusManager.instance.primaryFocus?.unfocus(),
      child: Scaffold(
        key: const Key('random-additions-screen'),
        backgroundColor: theme.background,
        appBar: const IdeaVaultSubpageAppBar(
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
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                          itemCount: additions.length,
                          itemBuilder: (context, index) {
                            final addition =
                                additions[additions.length - 1 - index];
                            return _RandomAdditionBubble(
                              addition: addition,
                              onFile: () => _showFilingSheet(addition),
                              isLast: index == 0,
                            );
                          },
                        ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    4,
                    16,
                    MediaQuery.of(context).padding.bottom + 4,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 860),
                    child: RandomAdditionComposer(
                      controller: _composerController,
                      fieldKey: const Key('random-additions-composer'),
                      sendButtonKey: const Key('random-additions-send'),
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

  Future<void> _showFilingSheet(RandomAddition addition) async {
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

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.surface,
      builder: (sectionSheetContext) {
        return _SectionPickerSheet(
          idea: selectedIdea,
          onSectionSelected: (section) async {
            final savedIdea = await ideasProvider.appendContentToSection(
              ideaId: selectedIdea.id,
              sectionId: section.id,
              content: addition.content,
            );
            if (savedIdea == null) {
              return;
            }
            await additionsProvider.deleteAddition(addition.id);
            if (!sectionSheetContext.mounted) {
              return;
            }
            Navigator.of(sectionSheetContext).pop();
            messenger.showSnackBar(
              SnackBar(
                content: Text(
                  ViewConstants.randomAdditionsFiledSnackbar.tr(
                    namedArgs: {
                      'idea': selectedIdea.title,
                      'section': section.name,
                    },
                  ),
                ),
              ),
            );
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

class _RandomAdditionBubble extends StatelessWidget {
  const _RandomAdditionBubble({
    required this.addition,
    required this.onFile,
    this.isLast = false,
  });

  final RandomAddition addition;
  final VoidCallback onFile;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 4),
      child: Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Material(
            color: theme.primary,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(18),
              topRight: Radius.circular(18),
              bottomLeft: Radius.circular(18),
              bottomRight: Radius.circular(6),
            ),
            child: InkWell(
              onTap: onFile,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(18),
                bottomRight: Radius.circular(6),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
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
                          color: theme.onPrimary,
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
                        color: theme.onPrimary.withValues(alpha: 0.16),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.add_rounded,
                        size: 16,
                        color: theme.onPrimary,
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
                  if (ideas.isEmpty) _NoIdeasForFiling(theme: theme),
                ],
              ),
            ),
            if (ideas.isNotEmpty)
              SliverPadding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottomInset),
                sliver: SliverList.separated(
                  itemCount: ideas.length,
                  separatorBuilder: (_, __) => const SizedBox.shrink(),
                  itemBuilder: (context, index) {
                    final idea = ideas[index];
                    return _FilingTile(
                      key: Key('random-addition-idea-${idea.id}'),
                      title: idea.title,
                      subtitle: idea.sections.length == 1
                          ? ViewConstants.homepageIdeaCardOneSection.tr()
                          : ViewConstants.homepageIdeaCardSectionsMany.tr(
                              namedArgs: {
                                'count': '${idea.sections.length}',
                              },
                            ),
                      icon: Icons.lightbulb_outline_rounded,
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
      padding: const EdgeInsets.fromLTRB(4, 24, 4, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
