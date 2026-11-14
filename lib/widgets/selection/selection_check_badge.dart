import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../viewmodels/providers/theme_provider.dart';

class SelectionCheckBadge extends StatelessWidget {
  const SelectionCheckBadge({
    super.key,
    required this.isSelected,
    this.size = 24,
  });

  static const Duration _duration = Duration(milliseconds: 180);

  final bool isSelected;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.surface,
                border: Border.all(color: theme.textMuted, width: 2),
              ),
              child: SizedBox.square(dimension: size),
            ),
            AnimatedScale(
              scale: isSelected ? 1 : 0,
              duration: _duration,
              curve: isSelected ? Curves.easeOutBack : Curves.easeIn,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.primary,
                  border: Border.all(color: theme.surface, width: 2),
                ),
                child: SizedBox.square(
                  dimension: size,
                  child: Icon(
                    Icons.check_rounded,
                    size: size * 0.62,
                    color: theme.onPrimary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
