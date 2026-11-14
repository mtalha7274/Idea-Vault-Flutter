import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/view_constants.dart';
import '../../viewmodels/providers/theme_provider.dart';
import '../../views/ideas/idea_vault_theme.dart';

class SelectionCountText extends StatelessWidget {
  const SelectionCountText({
    super.key,
    required this.count,
    this.size = 20,
  });

  final int count;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Text(
        ViewConstants.selectionCount.tr(namedArgs: {'count': '$count'}),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: ideaVaultHeadline(
          context,
          size: size,
          weight: FontWeight.w800,
          height: 1.1,
        ),
      ),
    );
  }
}

class SelectionActionButton extends StatelessWidget {
  const SelectionActionButton({
    super.key,
    required this.icon,
    required this.tooltipKey,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltipKey;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltipKey.tr(),
      style: IconButton.styleFrom(
        foregroundColor: theme.primary,
        disabledForegroundColor: theme.textMuted.withValues(alpha: 0.5),
        minimumSize: const Size(48, 48),
      ),
      icon: Icon(icon, size: 24),
    );
  }
}

class SelectionToolbar extends StatelessWidget {
  const SelectionToolbar({
    super.key,
    required this.count,
    required this.onClose,
    required this.actions,
    this.closeButtonKey,
    this.countKey,
  });

  final int count;
  final VoidCallback onClose;
  final List<Widget> actions;
  final Key? closeButtonKey;
  final Key? countKey;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          IconButton(
            key: closeButtonKey,
            onPressed: onClose,
            tooltip: ViewConstants.selectionClearTooltip.tr(),
            style: IconButton.styleFrom(
              foregroundColor: theme.primaryText,
              minimumSize: const Size(48, 48),
            ),
            icon: const Icon(Icons.close_rounded),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: SelectionCountText(key: countKey, count: count),
          ),
          ...actions,
        ],
      ),
    );
  }
}

class SelectionAppBar extends StatelessWidget implements PreferredSizeWidget {
  const SelectionAppBar({
    super.key,
    required this.count,
    required this.onClose,
    required this.actions,
    this.closeButtonKey,
    this.countKey,
  });

  final int count;
  final VoidCallback onClose;
  final List<Widget> actions;
  final Key? closeButtonKey;
  final Key? countKey;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    return AppBar(
      backgroundColor: theme.background,
      foregroundColor: theme.primaryText,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      automaticallyImplyLeading: false,
      titleSpacing: 0,
      title: Padding(
        padding: const EdgeInsetsDirectional.only(start: 4, end: 4),
        child: SelectionToolbar(
          count: count,
          onClose: onClose,
          actions: actions,
          closeButtonKey: closeButtonKey,
          countKey: countKey,
        ),
      ),
    );
  }
}
