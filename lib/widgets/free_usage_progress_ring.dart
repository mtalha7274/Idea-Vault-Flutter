import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../viewmodels/providers/theme_provider.dart';

class FreeUsageProgressRing extends StatelessWidget {
  const FreeUsageProgressRing({
    super.key,
    required this.progress,
    this.size = 44,
    this.strokeWidth = 5,
    this.semanticLabel,
  });

  final double progress;
  final double size;
  final double strokeWidth;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    final normalizedProgress =
        progress.isFinite ? progress.clamp(0.0, 1.0).toDouble() : 0.0;

    return Semantics(
      label: semanticLabel,
      child: SizedBox.square(
        dimension: size,
        child: CircularProgressIndicator(
          key: const Key('free-usage-progress-ring'),
          value: normalizedProgress,
          strokeWidth: strokeWidth,
          strokeCap: StrokeCap.round,
          backgroundColor: theme.primary.withValues(alpha: 0.16),
          valueColor: AlwaysStoppedAnimation<Color>(theme.primary),
        ),
      ),
    );
  }
}
