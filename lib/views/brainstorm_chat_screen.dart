import 'package:flutter/material.dart';
import 'package:flutter_ai_toolkit/flutter_ai_toolkit.dart';
import 'package:provider/provider.dart';

import '../core/constants/view_constants.dart';
import '../viewmodels/providers/theme_provider.dart';
import '../widgets/translated_text.dart';
import 'ideas/idea_vault_theme.dart';

class BrainstormChatScreen extends StatefulWidget {
  const BrainstormChatScreen({super.key});

  @override
  State<BrainstormChatScreen> createState() => _BrainstormChatScreenState();
}

class _BrainstormChatScreenState extends State<BrainstormChatScreen> {
  late final EchoProvider _provider;

  @override
  void initState() {
    super.initState();
    _provider = EchoProvider();
  }

  @override
  void dispose() {
    _provider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: theme.background,
        foregroundColor: theme.primaryText,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: TranslatedText(
          ViewConstants.brainstorm,
          style: ideaVaultHeadline(
            context,
            size: 20,
            weight: FontWeight.w800,
            height: 1.2,
            color: theme.primaryText,
          ),
        ),
      ),
      body: LlmChatView(
        provider: _provider,
        enableAttachments: false,
        enableVoiceNotes: false,
        style: LlmChatViewStyle(
          backgroundColor: theme.background,
        ),
      ),
    );
  }
}
