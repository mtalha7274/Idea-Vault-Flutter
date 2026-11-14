import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/theme/base.dart';
import '../../core/constants/view_constants.dart';
import '../../viewmodels/providers/theme_provider.dart';
import '../../views/ideas/idea_vault_theme.dart';
import 'note_editing_controller.dart';

enum NoteLinkSheetAction { save, remove }

class NoteLinkSheetResult {
  const NoteLinkSheetResult(this.action, {this.url = '', this.label});

  final NoteLinkSheetAction action;
  final String url;
  final String? label;
}

Future<NoteLinkSheetResult?> showNoteLinkSheet(
  BuildContext context, {
  required String initialUrl,
  required bool askForLabel,
  required bool isExisting,
}) {
  return showModalBottomSheet<NoteLinkSheetResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.32),
    builder: (sheetContext) => _NoteLinkSheet(
      initialUrl: initialUrl,
      askForLabel: askForLabel,
      isExisting: isExisting,
    ),
  );
}

Future<void> editNoteLink(
  BuildContext context,
  NoteEditingController controller,
  FocusNode focusNode, {
  bool refocus = true,
}) async {
  final selectionBefore = controller.selection;
  final existing = controller.linkAtSelection;
  final result = await showNoteLinkSheet(
    context,
    initialUrl: existing?.url ?? '',
    askForLabel: existing == null &&
        (!selectionBefore.isValid || selectionBefore.isCollapsed),
    isExisting: existing != null,
  );
  if (result == null) {
    return;
  }
  if (selectionBefore.isValid) {
    controller.selection = selectionBefore;
  }
  switch (result.action) {
    case NoteLinkSheetAction.save:
      controller.applyLink(result.url, label: result.label);
    case NoteLinkSheetAction.remove:
      controller.removeLink();
  }
  if (refocus) {
    focusNode.requestFocus();
  }
}

Future<bool> openNoteLink(BuildContext context, String url) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  var opened = false;
  try {
    final uri = Uri.tryParse(url);
    if (uri != null) {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  } catch (_) {
    opened = false;
  }
  if (!opened) {
    messenger?.showSnackBar(
      SnackBar(content: Text(ViewConstants.editorLinkOpenFailed.tr())),
    );
  }
  return opened;
}

String noteLinkHost(String url) {
  final uri = Uri.tryParse(url);
  final host = uri?.host ?? '';
  if (host.isEmpty) {
    return '';
  }
  return host.startsWith('www.') ? host.substring(4) : host;
}

class _NoteLinkSheet extends StatefulWidget {
  const _NoteLinkSheet({
    required this.initialUrl,
    required this.askForLabel,
    required this.isExisting,
  });

  final String initialUrl;
  final bool askForLabel;
  final bool isExisting;

  @override
  State<_NoteLinkSheet> createState() => _NoteLinkSheetState();
}

class _NoteLinkSheetState extends State<_NoteLinkSheet> {
  late final TextEditingController _urlController =
      TextEditingController(text: widget.initialUrl);
  late final TextEditingController _labelController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _urlController.addListener(_handleUrlChanged);
  }

  @override
  void dispose() {
    _urlController
      ..removeListener(_handleUrlChanged)
      ..dispose();
    _labelController.dispose();
    super.dispose();
  }

  void _handleUrlChanged() {
    setState(() {});
  }

  bool get _canSave => _urlController.text.trim().isNotEmpty;

  void _save() {
    if (!_canSave) {
      return;
    }
    Navigator.of(context).pop(
      NoteLinkSheetResult(
        NoteLinkSheetAction.save,
        url: _urlController.text.trim(),
        label: _labelController.text,
      ),
    );
  }

  InputDecoration _decoration(
    BuildContext context, {
    required String hintKey,
    required IconData icon,
  }) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    return InputDecoration(
      hintText: hintKey.tr(),
      hintStyle: ideaVaultBody(
        context,
        size: 15,
        weight: FontWeight.w500,
        color: theme.textMuted,
      ),
      prefixIcon: Icon(icon, size: 20, color: theme.textMuted),
      filled: true,
      fillColor: theme.surfaceLow,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    final errorColor = Theme.of(context).colorScheme.error;
    final fieldStyle = ideaVaultBody(
      context,
      size: 15,
      weight: FontWeight.w600,
    );
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.outline.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  (widget.isExisting
                          ? ViewConstants.editorLinkSheetEditTitle
                          : ViewConstants.editorLinkSheetAddTitle)
                      .tr(),
                  style: ideaVaultHeadline(
                    context,
                    size: 20,
                    weight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  key: const Key('note-link-url'),
                  controller: _urlController,
                  autofocus: true,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: widget.askForLabel
                      ? TextInputAction.next
                      : TextInputAction.done,
                  style: fieldStyle,
                  decoration: _decoration(
                    context,
                    hintKey: ViewConstants.editorLinkDialogUrlHint,
                    icon: Icons.link_rounded,
                  ),
                  onSubmitted: widget.askForLabel ? null : (_) => _save(),
                ),
                if (widget.askForLabel) ...[
                  const SizedBox(height: 10),
                  TextField(
                    key: const Key('note-link-label'),
                    controller: _labelController,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.done,
                    style: fieldStyle,
                    decoration: _decoration(
                      context,
                      hintKey: ViewConstants.editorLinkDialogTextHint,
                      icon: Icons.short_text_rounded,
                    ),
                    onSubmitted: (_) => _save(),
                  ),
                ],
                const SizedBox(height: 18),
                Row(
                  children: [
                    if (widget.isExisting) ...[
                      TextButton(
                        key: const Key('note-link-remove'),
                        onPressed: () => Navigator.of(context).pop(
                          const NoteLinkSheetResult(
                            NoteLinkSheetAction.remove,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: errorColor,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 14,
                          ),
                        ),
                        child: Text(
                          ViewConstants.editorLinkDialogRemove.tr(),
                          style: ideaVaultLabel(
                            context,
                            size: 14,
                            weight: FontWeight.w700,
                            color: errorColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: SizedBox(
                        height: 50,
                        child: FilledButton(
                          key: const Key('note-link-save'),
                          onPressed: _canSave ? _save : null,
                          style: FilledButton.styleFrom(
                            backgroundColor: theme.primary,
                            foregroundColor: theme.onPrimary,
                            disabledBackgroundColor: theme.surfaceLow,
                            disabledForegroundColor: theme.textMuted,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                          child: Text(
                            ViewConstants.editorLinkDialogSave.tr(),
                            style: ideaVaultLabel(
                              context,
                              size: 15,
                              weight: FontWeight.w800,
                              color:
                                  _canSave ? theme.onPrimary : theme.textMuted,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class NoteLinkPreviewOverlay extends StatelessWidget {
  const NoteLinkPreviewOverlay({
    super.key,
    required this.anchor,
    required this.url,
    required this.onDismiss,
    required this.onOpen,
    required this.onCopy,
    this.onEdit,
  });

  final Rect anchor;
  final String url;
  final VoidCallback onDismiss;
  final VoidCallback onOpen;
  final VoidCallback onCopy;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final insets = EdgeInsets.only(
      top: media.padding.top,
      bottom: math.max(media.viewInsets.bottom, media.padding.bottom),
    );
    return Stack(
      children: [
        Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => onDismiss(),
          ),
        ),
        Positioned.fill(
          child: CustomSingleChildLayout(
            delegate: _LinkPreviewLayout(anchor: anchor, insets: insets),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: 1),
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                return Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(0, (1 - value) * 6),
                    child: child,
                  ),
                );
              },
              child: _LinkPreviewCard(
                url: url,
                onOpen: onOpen,
                onCopy: onCopy,
                onEdit: onEdit,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LinkPreviewLayout extends SingleChildLayoutDelegate {
  const _LinkPreviewLayout({required this.anchor, required this.insets});

  static const double _margin = 12;
  static const double _gap = 6;
  static const double _maxWidth = 380;

  final Rect anchor;
  final EdgeInsets insets;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints(
      maxWidth: math.max(
        0,
        math.min(_maxWidth, constraints.maxWidth - _margin * 2),
      ),
      maxHeight: constraints.maxHeight,
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final maxLeft = math.max(_margin, size.width - _margin - childSize.width);
    final left = anchor.left.clamp(_margin, maxLeft).toDouble();
    final lowest = size.height - insets.bottom - 8;
    var top = anchor.bottom + _gap;
    if (top + childSize.height > lowest) {
      top = anchor.top - _gap - childSize.height;
    }
    return Offset(left, math.max(top, insets.top + 8));
  }

  @override
  bool shouldRelayout(_LinkPreviewLayout oldDelegate) {
    return oldDelegate.anchor != anchor || oldDelegate.insets != insets;
  }
}

class _LinkPreviewCard extends StatelessWidget {
  const _LinkPreviewCard({
    required this.url,
    required this.onOpen,
    required this.onCopy,
    required this.onEdit,
  });

  final String url;
  final VoidCallback onOpen;
  final VoidCallback onCopy;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    final host = noteLinkHost(url);
    final title = host.isEmpty ? url : host;
    final isDark = theme.themeData.brightness == Brightness.dark;
    return Material(
      key: const Key('note-link-preview'),
      color: noteLinkPreviewColor(theme),
      elevation: isDark ? 12 : 10,
      shadowColor: Colors.black.withValues(alpha: isDark ? 0.6 : 0.22),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: isDark
              ? theme.primaryText.withValues(alpha: 0.16)
              : theme.outline,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 6, 8, 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: InkWell(
                key: const Key('note-link-preview-body'),
                onTap: onOpen,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(6, 6, 8, 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: theme.primary.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.public_rounded,
                          size: 19,
                          color: theme.primary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: ideaVaultBody(
                                context,
                                size: 14,
                                weight: FontWeight.w700,
                                height: 1.25,
                              ),
                            ),
                            if (host.isNotEmpty)
                              Text(
                                url,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: ideaVaultBody(
                                  context,
                                  size: 12,
                                  weight: FontWeight.w500,
                                  color: theme.textMuted,
                                  height: 1.3,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            _LinkPreviewIconButton(
              buttonKey: const Key('note-link-copy'),
              icon: Icons.copy_rounded,
              tooltipKey: ViewConstants.editorLinkPreviewCopy,
              onPressed: onCopy,
            ),
            if (onEdit != null)
              _LinkPreviewIconButton(
                buttonKey: const Key('note-link-edit'),
                icon: Icons.edit_outlined,
                tooltipKey: ViewConstants.editorLinkSheetEditTitle,
                onPressed: onEdit!,
              ),
            const SizedBox(width: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 124),
              child: FilledButton.icon(
                key: const Key('note-link-open'),
                onPressed: onOpen,
                style: FilledButton.styleFrom(
                  backgroundColor: theme.primary,
                  foregroundColor: theme.onPrimary,
                  elevation: 0,
                  minimumSize: const Size(0, 38),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: Text(
                  ViewConstants.editorLinkPreviewOpen.tr(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ideaVaultLabel(
                    context,
                    size: 13,
                    weight: FontWeight.w800,
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

Color noteLinkPreviewColor(BaseTheme theme) {
  return theme.themeData.brightness == Brightness.dark
      ? theme.surfaceHigh
      : theme.surface;
}

class _LinkPreviewIconButton extends StatelessWidget {
  const _LinkPreviewIconButton({
    required this.buttonKey,
    required this.icon,
    required this.tooltipKey,
    required this.onPressed,
  });

  final Key buttonKey;
  final IconData icon;
  final String tooltipKey;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    return IconButton(
      key: buttonKey,
      onPressed: onPressed,
      tooltip: tooltipKey.tr(),
      icon: Icon(icon, size: 19),
      color: theme.textMuted,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(8),
      constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
    );
  }
}

Future<void> copyNoteLink(BuildContext context, String url) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  await Clipboard.setData(ClipboardData(text: url));
  messenger?.showSnackBar(
    SnackBar(content: Text(ViewConstants.editorLinkCopied.tr())),
  );
}
