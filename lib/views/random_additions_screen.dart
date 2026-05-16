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

    return Scaffold(
      key: const Key('random-additions-screen'),
      backgroundColor: theme.background,
      appBar: const IdeaVaultSubpageAppBar(
        titleKey: ViewConstants.randomAdditionsTitle,
      ),
      body: SafeArea(
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
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
                      itemCount: additions.length,
                      itemBuilder: (context, index) {
                        final addition =
                            additions[additions.length - 1 - index];
                        return _RandomAdditionBubble(
                          addition: addition,
                          onFile: () => _showFilingSheet(addition),
                        );
                      },
                    ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
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
            ),
          ],
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

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.surface,
      builder: (sheetContext) {
        return _RandomAdditionFilingSheet(
          addition: addition,
          ideas: ideasProvider.ideas,
          onSectionSelected: (idea, section) async {
            final sheetNavigator = Navigator.of(sheetContext);
            final savedIdea = await ideasProvider.appendContentToSection(
              ideaId: idea.id,
              sectionId: section.id,
              content: addition.content,
            );
            if (savedIdea == null || !mounted) {
              return;
            }

            await additionsProvider.deleteAddition(addition.id);
            if (!mounted || !sheetContext.mounted) {
              return;
            }

            sheetNavigator.pop();
            messenger.showSnackBar(
              SnackBar(
                content: Text(
                  ViewConstants.randomAdditionsFiledSnackbar.tr(
                    namedArgs: {
                      'idea': idea.title,
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
  });

  final RandomAddition addition;
  final VoidCallback onFile;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: theme.primary,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(18),
                bottomRight: Radius.circular(6),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 6, 6),
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
                  IconButton(
                    key: Key('random-addition-file-${addition.id}'),
                    onPressed: onFile,
                    style: IconButton.styleFrom(
                      backgroundColor: theme.onPrimary.withValues(alpha: 0.16),
                      foregroundColor: theme.onPrimary,
                      fixedSize: const Size(30, 30),
                      padding: EdgeInsets.zero,
                    ),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    tooltip: ViewConstants.randomAdditionsFileTooltip.tr(),
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

class _RandomAdditionFilingSheet extends StatefulWidget {
  const _RandomAdditionFilingSheet({
    required this.addition,
    required this.ideas,
    required this.onSectionSelected,
  });

  final RandomAddition addition;
  final List<Idea> ideas;
  final Future<void> Function(Idea idea, IdeaSection section) onSectionSelected;

  @override
  State<_RandomAdditionFilingSheet> createState() =>
      _RandomAdditionFilingSheetState();
}

class _RandomAdditionFilingSheetState
    extends State<_RandomAdditionFilingSheet> {
  Idea? _selectedIdea;
  bool _isFiling = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    final selectedIdea = _selectedIdea;
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 18, 20, 20 + bottomPadding),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.72,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (selectedIdea != null)
                    IconButton(
                      key: const Key('random-addition-file-back-to-ideas'),
                      onPressed: _isFiling
                          ? null
                          : () => setState(() => _selectedIdea = null),
                      icon: const Icon(Icons.arrow_back_ios_new_rounded),
                    ),
                  Expanded(
                    child: TranslatedText(
                      selectedIdea == null
                          ? ViewConstants.randomAdditionsChooseIdeaTitle
                          : ViewConstants.randomAdditionsChooseSectionTitle,
                      style: ideaVaultHeadline(
                        context,
                        size: 23,
                        weight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (widget.ideas.isEmpty)
                _NoIdeasForFiling(theme: theme)
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: selectedIdea == null
                        ? [
                            for (final idea in widget.ideas)
                              _FilingTile(
                                key: Key('random-addition-idea-${idea.id}'),
                                title: idea.title,
                                subtitle: idea.sections.length == 1
                                    ? ViewConstants.homepageIdeaCardOneSection
                                        .tr()
                                    : ViewConstants.homepageIdeaCardSectionsMany
                                        .tr(
                                        namedArgs: {
                                          'count': '${idea.sections.length}',
                                        },
                                      ),
                                icon: Icons.lightbulb_outline_rounded,
                                onTap: _isFiling
                                    ? null
                                    : () =>
                                        setState(() => _selectedIdea = idea),
                              ),
                          ]
                        : [
                            for (final section in selectedIdea.sections)
                              _FilingTile(
                                key: Key(
                                  'random-addition-section-${section.id}',
                                ),
                                title: section.name,
                                subtitle: ViewConstants
                                    .randomAdditionsAppendToSection
                                    .tr(),
                                icon: Icons.notes_rounded,
                                onTap: _isFiling
                                    ? null
                                    : () => _fileToSection(
                                          selectedIdea,
                                          section,
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

  Future<void> _fileToSection(Idea idea, IdeaSection section) async {
    setState(() => _isFiling = true);
    try {
      await widget.onSectionSelected(idea, section);
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
