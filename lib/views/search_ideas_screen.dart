import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/router/app_router.dart';
import '../core/constants/view_constants.dart';
import '../core/services/note_lock_auth_service.dart';
import '../core/utils/idea_search.dart';
import '../data/repositories/local/idea_list_preferences.dart';
import '../injection_container.dart';
import '../models/idea.dart';
import '../viewmodels/providers/ideas_provider.dart';
import '../viewmodels/providers/theme_provider.dart';
import '../widgets/idea_vault_subpage_app_bar.dart';
import '../widgets/ideas/ideas_layout.dart';
import '../widgets/ideas_search_field.dart';
import '../widgets/note_lock_auth_dialog.dart';
import '../widgets/translated_text.dart';
import 'idea_editor.dart';
import 'ideas/idea_vault_theme.dart';

class SearchIdeasScreen extends StatefulWidget {
  const SearchIdeasScreen({super.key});

  @override
  State<SearchIdeasScreen> createState() => _SearchIdeasScreenState();
}

class _SearchIdeasScreenState extends State<SearchIdeasScreen> {
  late final TextEditingController _searchController;
  late final NoteLockAuthService _noteLockAuthService;

  String get _searchQuery => _searchController.text.trim();

  @override
  void initState() {
    super.initState();
    _noteLockAuthService = sl.isRegistered<NoteLockAuthService>()
        ? sl<NoteLockAuthService>()
        : NoteLockAuthService();
    _searchController = TextEditingController()
      ..addListener(_handleSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<IdeasProvider>().ensureLoaded();
    });
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_handleSearchChanged)
      ..dispose();
    super.dispose();
  }

  void _handleSearchChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    final ideas = context.watch<IdeasProvider>().ideas;
    final results = filterIdeasBySearch(ideas, _searchQuery);
    final layoutOption = sl<IdeaListPreferencesRepo>().getLayoutOption();

    return PopScope(
      onPopInvokedWithResult: (_, __) =>
          FocusManager.instance.primaryFocus?.unfocus(),
      child: Scaffold(
        key: const Key('search-ideas-screen'),
        backgroundColor: theme.background,
        appBar: IdeaVaultSubpageAppBar(
          titleKey: ViewConstants.searchIdeasScreenTitle,
        ),
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                  child: IdeasSearchField(
                    controller: _searchController,
                    autofocus: true,
                  ),
                ),
                Expanded(
                  child: _searchQuery.isEmpty
                      ? const _SearchEmptyPrompt()
                      : results.isEmpty
                          ? const _NoSearchResultsState()
                          : SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                              child: IdeasLayout(
                                ideas: results,
                                layoutOption: layoutOption,
                                onTap: (idea) => unawaited(_openIdea(idea)),
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

  Future<void> _openIdea(Idea idea) async {
    if (idea.isLocked) {
      final didAuthenticate = await authenticateForNoteLock(
        context,
        _noteLockAuthService,
        ideaId: idea.id,
      );
      if (!mounted || !didAuthenticate) {
        return;
      }
    }

    await AppRouter.push(
      context,
      IdeaEditorScreen(ideaId: idea.id),
    );
    if (idea.isLocked) {
      _noteLockAuthService.markIdeaLocked(idea.id);
    }
  }
}

class _SearchEmptyPrompt extends StatelessWidget {
  const _SearchEmptyPrompt();

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Center(
      child: Padding(
        padding: EdgeInsets.fromLTRB(24, 0, 24, 20 + bottomInset),
        child: Container(
          key: const Key('search-ideas-empty-prompt'),
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
                  Icons.search_rounded,
                  size: 36,
                  color: theme.primary,
                ),
              ),
              const SizedBox(height: 18),
              TranslatedText(
                ViewConstants.searchIdeasEmptyTitle,
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
                ViewConstants.searchIdeasEmptyPrompt,
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

class _NoSearchResultsState extends StatelessWidget {
  const _NoSearchResultsState();

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
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
      ),
    );
  }
}
