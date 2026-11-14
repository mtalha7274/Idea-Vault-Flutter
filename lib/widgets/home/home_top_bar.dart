import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/view_constants.dart';
import '../../viewmodels/providers/theme_provider.dart';
import '../../views/ideas/idea_vault_theme.dart';

class HomeTopBar extends StatelessWidget {
  const HomeTopBar({
    super.key,
    required this.onMenuPressed,
    required this.onSearchPressed,
    required this.onSortPressed,
    required this.onNewIdeaPressed,
  });

  static const double height = 56;
  static const double titleSize = 22;

  final VoidCallback onMenuPressed;
  final VoidCallback onSearchPressed;
  final VoidCallback onSortPressed;
  final VoidCallback onNewIdeaPressed;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    final iconBackgroundColor = theme.themeData.brightness == Brightness.light
        ? theme.surfaceHigh
        : theme.surfaceLow;
    final secondaryStyle = IconButton.styleFrom(
      backgroundColor: iconBackgroundColor,
      foregroundColor: theme.primary,
      fixedSize: const Size(40, 40),
      minimumSize: const Size(40, 40),
      padding: EdgeInsets.zero,
      tapTargetSize: MaterialTapTargetSize.padded,
    );

    return SizedBox(
      height: height,
      child: Row(
        children: [
          IconButton(
            key: const Key('ideas-menu-button'),
            onPressed: onMenuPressed,
            tooltip: MaterialLocalizations.of(context).openAppDrawerTooltip,
            style: IconButton.styleFrom(
              foregroundColor: theme.primaryText,
              minimumSize: const Size(48, 48),
            ),
            icon: const Icon(Icons.menu_rounded),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                ViewConstants.homepageTitle.tr(),
                key: const Key('ideas-home-title'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: ideaVaultHeadline(
                  context,
                  size: titleSize,
                  weight: FontWeight.w800,
                  height: 1.1,
                  letterSpacing: -0.4,
                ),
              ),
            ),
          ),
          IconButton(
            key: const Key('ideas-search-button'),
            onPressed: onSearchPressed,
            tooltip: ViewConstants.homepageSearchHint.tr(),
            style: secondaryStyle,
            icon: const Icon(Icons.search_rounded, size: 22),
          ),
          IconButton(
            key: const Key('ideas-sort-button'),
            onPressed: onSortPressed,
            tooltip: ViewConstants.homepageSortSheetTitle.tr(),
            style: secondaryStyle,
            icon: const Icon(Icons.swap_vert_rounded, size: 22),
          ),
          HomeNewIdeaButton(onPressed: onNewIdeaPressed),
        ],
      ),
    );
  }
}

class HomeNewIdeaButton extends StatelessWidget {
  const HomeNewIdeaButton({
    super.key,
    required this.onPressed,
  });

  static const double visibleSize = 40;

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    return IconButton.filled(
      key: const Key('ideas-new-idea-button'),
      onPressed: onPressed,
      tooltip: ViewConstants.homepageFabNewIdea.tr(),
      style: IconButton.styleFrom(
        backgroundColor: theme.primary,
        foregroundColor: theme.onPrimary,
        fixedSize: const Size(visibleSize, visibleSize),
        minimumSize: const Size(visibleSize, visibleSize),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
      icon: const Icon(Icons.add_rounded, size: 24),
    );
  }
}
