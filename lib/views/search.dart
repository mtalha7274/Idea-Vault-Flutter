import 'package:flutter/material.dart';
import 'package:idea_vault/core/constants/view_constants.dart';
import 'package:provider/provider.dart';

import '../viewmodels/providers/theme_provider.dart';
import '../widgets/translated_text.dart';

class Search extends StatefulWidget {
  const Search({super.key});

  @override
  State<Search> createState() => _SearchState();
}

class _SearchState extends State<Search> {
  @override
  Widget build(BuildContext context) {
    final ThemeProvider themeProvider = context.watch<ThemeProvider>();
    return Scaffold(
      body: Center(
        child: TranslatedText(
          ViewConstants.search,
          style: TextStyle(color: themeProvider.baseTheme.primaryText),
        ),
      ),
    );
  }
}
