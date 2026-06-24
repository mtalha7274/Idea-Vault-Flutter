import 'dart:ui';

import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/view_constants.dart';
import '../../core/utils/idea_search.dart';
import '../../data/repositories/local/idea_list_preferences.dart';
import '../../models/idea.dart';
import '../../viewmodels/providers/theme_provider.dart';
import '../../views/ideas/idea_vault_theme.dart';

enum IdeaCardLayout {
  list,
  grid,
}

class IdeasLayout extends StatelessWidget {
  const IdeasLayout({
    super.key,
    required this.ideas,
    required this.layoutOption,
    required this.onTap,
    this.selectedIdeaIds = const {},
    this.onLongPress,
  });

  static const Duration _animationDuration = Duration(milliseconds: 260);

  final List<Idea> ideas;
  final IdeaLayoutOption layoutOption;
  final Set<String> selectedIdeaIds;
  final ValueChanged<Idea> onTap;
  final ValueChanged<Idea>? onLongPress;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final metrics = _IdeaLayoutMetrics.calculate(
          maxWidth: constraints.maxWidth,
          itemCount: ideas.length,
          layoutOption: layoutOption,
        );

        return AnimatedSize(
          duration: _animationDuration,
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: SizedBox(
            height: metrics.height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (var index = 0; index < ideas.length; index++)
                  AnimatedPositioned(
                    key: ValueKey('idea-layout-${ideas[index].id}'),
                    duration: _animationDuration,
                    curve: Curves.easeOutCubic,
                    left: metrics.rects[index].left,
                    top: metrics.rects[index].top,
                    width: metrics.rects[index].width,
                    height: metrics.rects[index].height,
                    child: IdeaCard(
                      idea: ideas[index],
                      layout: metrics.cardLayout,
                      isSelected: selectedIdeaIds.contains(ideas[index].id),
                      onTap: () => onTap(ideas[index]),
                      onLongPress: onLongPress == null
                          ? null
                          : () => onLongPress!(ideas[index]),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _IdeaLayoutMetrics {
  const _IdeaLayoutMetrics({
    required this.height,
    required this.rects,
    required this.cardLayout,
  });

  static const double _listGap = 16;
  static const double _gridGap = 12;
  static const double _listCardHeight = 224;
  static const double _gridCardHeight = 218;
  static const double _minimumTwoColumnWidth = 340;

  final double height;
  final List<Rect> rects;
  final IdeaCardLayout cardLayout;

  static _IdeaLayoutMetrics calculate({
    required double maxWidth,
    required int itemCount,
    required IdeaLayoutOption layoutOption,
  }) {
    if (itemCount == 0) {
      return const _IdeaLayoutMetrics(
        height: 0,
        rects: [],
        cardLayout: IdeaCardLayout.list,
      );
    }

    final useGrid = layoutOption == IdeaLayoutOption.grid &&
        maxWidth >= _minimumTwoColumnWidth;
    if (!useGrid) {
      final rects = List<Rect>.generate(itemCount, (index) {
        final top = index * (_listCardHeight + _listGap);
        return Rect.fromLTWH(0, top, maxWidth, _listCardHeight);
      });
      return _IdeaLayoutMetrics(
        height: itemCount * _listCardHeight + (itemCount - 1) * _listGap,
        rects: rects,
        cardLayout: IdeaCardLayout.list,
      );
    }

    final cardWidth = (maxWidth - _gridGap) / 2;
    final rowCount = (itemCount / 2).ceil();
    final rects = List<Rect>.generate(itemCount, (index) {
      final row = index ~/ 2;
      final column = index % 2;
      return Rect.fromLTWH(
        column * (cardWidth + _gridGap),
        row * (_gridCardHeight + _gridGap),
        cardWidth,
        _gridCardHeight,
      );
    });

    return _IdeaLayoutMetrics(
      height: rowCount * _gridCardHeight + (rowCount - 1) * _gridGap,
      rects: rects,
      cardLayout: IdeaCardLayout.grid,
    );
  }
}

class IdeaCard extends StatelessWidget {
  const IdeaCard({
    super.key,
    required this.idea,
    required this.layout,
    required this.isSelected,
    required this.onTap,
    this.onLongPress,
  });

  final Idea idea;
  final IdeaCardLayout layout;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  bool get _isGrid => layout == IdeaCardLayout.grid;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    final radius = BorderRadius.circular(_isGrid ? 22 : 28);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('idea-card-${idea.id}'),
        borderRadius: radius,
        onTap: onTap,
        onLongPress: onLongPress,
        child: Ink(
          decoration: BoxDecoration(
            color: isSelected ? theme.accentTint : theme.surface,
            borderRadius: radius,
            border: Border.all(
              color: isSelected
                  ? theme.primary.withValues(alpha: 0.32)
                  : Colors.transparent,
            ),
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: child,
              ),
              child: idea.isLocked
                  ? _buildLockedCard(context)
                  : Padding(
                      key: ValueKey('unlocked-${idea.id}'),
                      padding: EdgeInsets.all(_isGrid ? 14 : 22),
                      child: _isGrid
                          ? _buildGridContent(context)
                          : _buildListContent(context),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  double get _cardPadding => _isGrid ? 14 : 22;

  Widget _buildLockedCard(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    return Stack(
      key: ValueKey('locked-${idea.id}'),
      fit: StackFit.expand,
      children: [
        Padding(
          padding: EdgeInsets.all(_cardPadding),
          child: _isGrid
              ? _buildGridLockedBlurBase(context)
              : _buildListLockedBlurBase(context),
        ),
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: ColoredBox(
              color: theme.surface.withValues(alpha: 0.78),
            ),
          ),
        ),
        Positioned.fill(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  _cardPadding,
                  _cardPadding,
                  _cardPadding,
                  0,
                ),
                child: _buildLockedTitle(context),
              ),
              Expanded(
                child: Center(
                  child: _buildLockedIcon(context),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildListLockedBlurBase(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLockedBlurBar(context, widthFactor: 1, height: 28),
        SizedBox(height: 6),
        _buildLockedBlurBar(context, widthFactor: 0.55, height: 28),
        SizedBox(height: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildLockedBlurBar(context, widthFactor: 1, height: 12),
                    _buildLockedBlurBar(context, widthFactor: 0.92, height: 12),
                    _buildLockedBlurBar(context, widthFactor: 0.78, height: 12),
                  ],
                ),
              ),
              _buildLockedBlurBar(context, widthFactor: 0.34, height: 12),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGridLockedBlurBase(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLockedBlurBar(context, widthFactor: 1, height: 20),
        SizedBox(height: 6),
        _buildLockedBlurBar(context, widthFactor: 0.72, height: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 10),
              _buildLockedBlurBar(context, widthFactor: 0.42, height: 22),
              const SizedBox(height: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildLockedBlurBar(context, widthFactor: 1, height: 10),
                    _buildLockedBlurBar(context, widthFactor: 0.88, height: 10),
                    _buildLockedBlurBar(context, widthFactor: 0.7, height: 10),
                  ],
                ),
              ),
              _buildLockedBlurBar(context, widthFactor: 0.38, height: 10),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLockedBlurBar(
    BuildContext context, {
    required double widthFactor,
    required double height,
  }) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    return FractionallySizedBox(
      widthFactor: widthFactor,
      alignment: Alignment.centerLeft,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: theme.textMuted.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    );
  }

  Widget _buildLockedTitle(BuildContext context) {
    return Text(
      idea.title,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: ideaVaultHeadline(
        context,
        size: _isGrid ? 17 : 24,
        weight: FontWeight.w800,
        height: _isGrid ? 1.18 : 1.15,
      ),
    );
  }

  Widget _buildLockedIcon(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    return Container(
      width: _isGrid ? 42 : 50,
      height: _isGrid ? 42 : 50,
      decoration: BoxDecoration(
        color: theme.primary.withValues(alpha: 0.14),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.lock_outline_rounded,
        size: _isGrid ? 22 : 26,
        color: theme.primary,
      ),
    );
  }

  Widget _buildListContent(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                idea.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: ideaVaultHeadline(
                  context,
                  size: 24,
                  weight: FontWeight.w800,
                  height: 1.15,
                ),
              ),
            ),
            const SizedBox(width: 16),
            IdeaSectionCountPill(idea: idea),
          ],
        ),
        SizedBox(height: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ideaPreviewText(idea),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: ideaVaultBody(
                  context,
                  size: 15,
                  weight: FontWeight.w500,
                  color: theme.textMuted,
                  height: 1.65,
                ),
              ),
              const Spacer(),
              IdeaUpdatedAtLabel(
                updatedAt: idea.updatedAt,
                iconSize: 18,
                textSize: 13,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGridContent(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          idea.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: ideaVaultHeadline(
            context,
            size: 17,
            weight: FontWeight.w800,
            height: 1.18,
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 10),
              IdeaSectionCountPill(
                idea: idea,
                compact: true,
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Text(
                  ideaPreviewText(idea),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: ideaVaultBody(
                    context,
                    size: 13,
                    weight: FontWeight.w500,
                    color: theme.textMuted,
                    height: 1.45,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              IdeaUpdatedAtLabel(
                updatedAt: idea.updatedAt,
                iconSize: 16,
                textSize: 11,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class IdeaSectionCountPill extends StatelessWidget {
  const IdeaSectionCountPill({
    super.key,
    required this.idea,
    this.compact = false,
  });

  final Idea idea;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: compact ? 128 : 120),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 12,
          vertical: compact ? 6 : 8,
        ),
        decoration: BoxDecoration(
          color: theme.surfaceLow,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          idea.sections.length == 1
              ? ViewConstants.homepageIdeaCardOneSection.tr()
              : ViewConstants.homepageIdeaCardSectionsMany.tr(
                  namedArgs: {
                    'count': '${idea.sections.length}',
                  },
                ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: ideaVaultLabel(
            context,
            size: compact ? 11 : 12,
            weight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}

class IdeaUpdatedAtLabel extends StatelessWidget {
  const IdeaUpdatedAtLabel({
    super.key,
    required this.updatedAt,
    required this.iconSize,
    required this.textSize,
  });

  final DateTime updatedAt;
  final double iconSize;
  final double textSize;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    return Row(
      children: [
        Icon(
          Icons.schedule_rounded,
          size: iconSize,
          color: theme.textMuted,
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            _formatUpdatedAt(context, updatedAt),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: ideaVaultLabel(
              context,
              size: textSize,
              weight: FontWeight.w600,
              color: theme.textMuted,
            ),
          ),
        ),
      ],
    );
  }

  String _formatUpdatedAt(BuildContext context, DateTime updatedAt) {
    final localizations = MaterialLocalizations.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final updatedDay = DateTime(updatedAt.year, updatedAt.month, updatedAt.day);
    final difference = today.difference(updatedDay).inDays;

    if (difference == 0) {
      return ViewConstants.homepageIdeaCardUpdatedToday.tr(
        namedArgs: {
          'time':
              localizations.formatTimeOfDay(TimeOfDay.fromDateTime(updatedAt)),
        },
      );
    }

    if (difference == 1) {
      return ViewConstants.homepageIdeaCardUpdatedYesterday.tr();
    }

    return ViewConstants.homepageIdeaCardUpdatedOnDate.tr(
      namedArgs: {
        'date': localizations.formatMediumDate(updatedAt),
      },
    );
  }
}
