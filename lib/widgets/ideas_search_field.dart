import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/constants/view_constants.dart';
import '../viewmodels/providers/theme_provider.dart';
import 'idea_vault_pill_text_field.dart';

class IdeasSearchField extends StatelessWidget {
  const IdeasSearchField({
    super.key,
    required this.controller,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final bool autofocus;

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
      autofocus: autofocus,
    );
  }
}
