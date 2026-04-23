import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/router/app_router.dart';
import '../models/idea.dart';
import '../viewmodels/providers/ideas_provider.dart';
import 'idea_editor.dart';
import 'ideas/idea_vault_theme.dart';

class Homepage extends StatefulWidget {
  const Homepage({super.key});

  @override
  State<Homepage> createState() => _HomepageState();
}

class _HomepageState extends State<Homepage> {
  final Set<String> _selectedIdeaIds = <String>{};
  bool _didHandleResume = false;

  bool get _isSelectionMode => _selectedIdeaIds.isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resumeEditorIfNeeded();
    });
  }

  @override
  Widget build(BuildContext context) {
    final ideasProvider = context.watch<IdeasProvider>();
    final ideas = ideasProvider.ideas;

    return Scaffold(
      backgroundColor: IdeaVaultPalette.background(context),
      body: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Header(
                    ideaCount: ideas.length,
                    selectedCount: _selectedIdeaIds.length,
                    onDeletePressed:
                        _isSelectionMode ? _confirmDeleteSelection : null,
                  ),
                  const SizedBox(height: 28),
                  Expanded(
                    child: ideas.isEmpty
                        ? const _EmptyIdeasState()
                        : ListView.separated(
                            padding: const EdgeInsets.only(bottom: 120),
                            itemCount: ideas.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 16),
                            itemBuilder: (context, index) {
                              final idea = ideas[index];
                              return _IdeaCard(
                                idea: idea,
                                isSelected: _selectedIdeaIds.contains(idea.id),
                                onTap: () => _handleIdeaTap(idea),
                                onLongPress: () => _handleIdeaLongPress(idea),
                              );
                            },
                          ),
                  ),
                ],
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
              backgroundColor: IdeaVaultPalette.primary(context),
              foregroundColor: IdeaVaultPalette.onPrimary(context),
              icon: const Icon(Icons.add_rounded),
              label: Text(
                'New Idea',
                style: ideaVaultLabel(
                  context,
                  size: 14,
                  weight: FontWeight.w700,
                  color: IdeaVaultPalette.onPrimary(context),
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

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final title =
            selectedCount == 1 ? 'Delete selected idea?' : 'Delete ideas?';
        final body = selectedCount == 1
            ? 'This idea will be removed from your vault.'
            : '$selectedCount ideas will be removed from your vault.';

        return AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('ideas-delete-confirm'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
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
}

class _Header extends StatelessWidget {
  const _Header({
    required this.ideaCount,
    required this.selectedCount,
    required this.onDeletePressed,
  });

  final int ideaCount;
  final int selectedCount;
  final VoidCallback? onDeletePressed;

  @override
  Widget build(BuildContext context) {
    final label = ideaCount == 1 ? '1 saved idea' : '$ideaCount saved ideas';
    final selectionLabel =
        selectedCount == 1 ? '1 selected' : '$selectedCount selected';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Idea Vault',
                style: ideaVaultHeadline(
                  context,
                  size: 34,
                  weight: FontWeight.w800,
                  height: 1.06,
                  letterSpacing: -0.9,
                ),
              ),
            ),
            if (selectedCount > 0) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: IdeaVaultPalette.surfaceLow(context),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  selectionLabel,
                  style: ideaVaultLabel(
                    context,
                    size: 12,
                    weight: FontWeight.w700,
                    color: IdeaVaultPalette.textMuted(context),
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                key: const Key('ideas-delete-button'),
                onPressed: onDeletePressed,
                style: IconButton.styleFrom(
                  backgroundColor: IdeaVaultPalette.surfaceLow(context),
                  foregroundColor: IdeaVaultPalette.primary(context),
                  padding: const EdgeInsets.all(12),
                ),
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ] else
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: IdeaVaultPalette.surfaceLow(context),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  label,
                  style: ideaVaultLabel(
                    context,
                    size: 12,
                    weight: FontWeight.w700,
                    color: IdeaVaultPalette.textMuted(context),
                    letterSpacing: 0.2,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Capture rough sparks, refine them into sections, and keep momentum without losing the thread.',
          style: ideaVaultBody(
            context,
            size: 16,
            weight: FontWeight.w500,
            color: IdeaVaultPalette.textMuted(context),
            height: 1.6,
          ),
        ),
      ],
    );
  }
}

class _EmptyIdeasState extends StatelessWidget {
  const _EmptyIdeasState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        key: const Key('ideas-empty-state'),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: IdeaVaultPalette.surface(context),
          borderRadius: BorderRadius.circular(32),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 78,
              width: 78,
              decoration: BoxDecoration(
                color: IdeaVaultPalette.accentTint(context),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.auto_awesome_outlined,
                size: 36,
                color: IdeaVaultPalette.primary(context),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Nothing saved yet',
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
                color: IdeaVaultPalette.textMuted(context),
                height: 1.55,
              ),
            ),
          ],
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('idea-card-${idea.id}'),
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Ink(
          decoration: BoxDecoration(
            color: isSelected
                ? IdeaVaultPalette.accentTint(context)
                : IdeaVaultPalette.surface(context),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: isSelected
                  ? IdeaVaultPalette.primary(context).withValues(alpha: 0.32)
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
                      color: IdeaVaultPalette.surfaceLow(context),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${idea.sections.length} sections',
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
                  color: IdeaVaultPalette.textMuted(context),
                  height: 1.65,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Icon(
                    Icons.schedule_rounded,
                    size: 18,
                    color: IdeaVaultPalette.textMuted(context),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _formatUpdatedAt(context, idea.updatedAt),
                    style: ideaVaultLabel(
                      context,
                      size: 13,
                      weight: FontWeight.w600,
                      color: IdeaVaultPalette.textMuted(context),
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
    for (final section in idea.sections) {
      final text = _plainPreview(section.content);
      if (text.isNotEmpty) {
        return text;
      }
    }

    return 'Tap to keep building this idea.';
  }

  String _plainPreview(String markdown) {
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
