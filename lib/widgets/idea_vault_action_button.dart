import 'package:flutter/material.dart';

import '../views/ideas/idea_vault_theme.dart';
import 'translated_text.dart';

class IdeaVaultActionButton extends StatelessWidget {
  const IdeaVaultActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    required this.backgroundColor,
    required this.foregroundColor,
    this.height = 56,
    this.textSize = 15,
    this.useTranslatedLabel = false,
  });

  final String label;
  final VoidCallback onPressed;
  final Color backgroundColor;
  final Color foregroundColor;
  final double height;
  final double textSize;
  final bool useTranslatedLabel;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(99),
          ),
        ),
        child: useTranslatedLabel
            ? TranslatedText(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ideaVaultLabel(
                  context,
                  size: textSize,
                  weight: FontWeight.w800,
                  color: foregroundColor,
                ),
              )
            : Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ideaVaultLabel(
                  context,
                  size: textSize,
                  weight: FontWeight.w800,
                  color: foregroundColor,
                ),
              ),
      ),
    );
  }
}
