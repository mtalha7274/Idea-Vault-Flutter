import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/view_constants.dart';
import '../../viewmodels/providers/theme_provider.dart';
import '../../views/ideas/idea_vault_theme.dart';

class QuickNoteButton extends StatelessWidget {
  const QuickNoteButton({
    super.key,
    required this.unfiledCount,
    required this.onPressed,
  });

  static const double height = 56;
  static const int maxDisplayedCount = 99;

  final int unfiledCount;
  final VoidCallback onPressed;

  String get _badgeText => unfiledCount > maxDisplayedCount
      ? ViewConstants.homeQuickNoteCountOverflow.tr()
      : '$unfiledCount';

  String? get _countLabel {
    if (unfiledCount <= 0) {
      return null;
    }
    if (unfiledCount == 1) {
      return ViewConstants.randomAdditionsCountOne.tr();
    }
    return ViewConstants.randomAdditionsCountMany.tr(
      namedArgs: {'count': '$unfiledCount'},
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    final label = ViewConstants.randomAdditionsComposerHint.tr();
    final countLabel = _countLabel;
    final shape = StadiumBorder(
      side: BorderSide(color: theme.primary.withValues(alpha: 0.2)),
    );
    return Semantics(
      button: true,
      label: countLabel == null ? label : '$label, $countLabel',
      excludeSemantics: true,
      onTap: onPressed,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(99),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: theme.surface,
          shape: shape,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: const Key('home-quick-note-button'),
            customBorder: shape,
            onTap: onPressed,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: height),
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(18, 8, 9, 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.edit_note_rounded,
                      size: 24,
                      color: theme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ideaVaultBody(
                          context,
                          size: 15,
                          weight: FontWeight.w600,
                          color: theme.textMuted,
                        ),
                      ),
                    ),
                    if (countLabel != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        key: const Key('home-quick-note-count'),
                        constraints: const BoxConstraints(
                          minWidth: 26,
                          maxWidth: 64,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: theme.accentTint,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          _badgeText,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          softWrap: false,
                          style: ideaVaultLabel(
                            context,
                            size: 12,
                            weight: FontWeight.w800,
                            color: theme.primary,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(width: 8),
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: theme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        size: 20,
                        color: theme.onPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
