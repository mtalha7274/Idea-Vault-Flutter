import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/extensions/int.dart';
import '../viewmodels/providers/theme_provider.dart';
import '../views/ideas/idea_vault_theme.dart';
import 'translated_text.dart';

class IdeaVaultSubpageAppBar extends StatelessWidget implements PreferredSizeWidget {
  const IdeaVaultSubpageAppBar({
    super.key,
    required this.titleKey,
    this.actions,
    this.onPop,
  });

  final String titleKey;
  final List<Widget>? actions;
  final VoidCallback? onPop;

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
      leadingWidth: 52.w,
      leading: IconButton(
        onPressed: onPop ?? () => Navigator.of(context).pop(),
        icon: Icon(
          Icons.arrow_back_ios_new_rounded,
          size: 18.d,
        ),
        padding: EdgeInsets.all(10.d),
        splashRadius: 20.d,
        visualDensity: VisualDensity.compact,
      ),
      title: TranslatedText(
        titleKey,
        style: ideaVaultHeadline(
          context,
          size: 20,
          weight: FontWeight.w800,
        ),
      ),
      actions: actions,
    );
  }
}
