import 'dart:io';
import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/constants/view_constants.dart';
import '../core/editor/note_document.dart';
import '../viewmodels/providers/theme_provider.dart';
import '../views/ideas/idea_vault_theme.dart';
import 'editor/note_editing_controller.dart';
import 'editor/note_editor_theme.dart';
import 'editor/note_link_dialog.dart';

const double _editorBodyTextSize = 17;

const double _toolbarEdgePadding = 18;

const double _toolbarArrowWidth = 76;

class IdeaMarkdownEditor extends StatefulWidget {
  const IdeaMarkdownEditor({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.placeholder,
    this.enablePersonalizedLearning = true,
    this.readOnly = false,
    this.onOpenLink,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String placeholder;
  final bool enablePersonalizedLearning;
  final bool readOnly;
  final ValueChanged<String>? onOpenLink;

  @override
  State<IdeaMarkdownEditor> createState() => _IdeaMarkdownEditorState();
}

class _IdeaMarkdownEditorState extends State<IdeaMarkdownEditor>
    with WidgetsBindingObserver {
  final GlobalKey _fieldHostKey = GlobalKey();
  final ScrollController _fieldScrollController = ScrollController();
  Offset? _lastPointerDown;
  OverlayEntry? _linkEntry;
  String? _linkPreviewText;
  ScrollPosition? _linkScrollPosition;

  NoteEditingController? get _rich {
    final controller = widget.controller;
    return controller is NoteEditingController ? controller : null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.focusNode.addListener(_handleFocusChanged);
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void didUpdateWidget(covariant IdeaMarkdownEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_handleFocusChanged);
      widget.focusNode.addListener(_handleFocusChanged);
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      widget.controller.addListener(_handleControllerChanged);
      _hideLinkPreview();
    }
    if (widget.readOnly && !oldWidget.readOnly) {
      _hideLinkPreview();
    }
  }

  @override
  void dispose() {
    _hideLinkPreview();
    _fieldScrollController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    widget.focusNode.removeListener(_handleFocusChanged);
    widget.controller.removeListener(_handleControllerChanged);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    _hideLinkPreview();
  }

  void _handleFocusChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _handleControllerChanged() {
    if (_linkEntry != null && widget.controller.text != _linkPreviewText) {
      _hideLinkPreview();
    }
  }

  RenderEditable? _findRenderEditable() {
    RenderEditable? result;
    void visit(Element element) {
      if (result != null) {
        return;
      }
      if (element is StatefulElement && element.state is EditableTextState) {
        result = (element.state as EditableTextState).renderEditable;
        return;
      }
      element.visitChildren(visit);
    }

    _fieldHostKey.currentContext?.visitChildElements(visit);
    final editable = result;
    if (editable == null || !editable.attached || !editable.hasSize) {
      return null;
    }
    return editable;
  }

  List<Rect> _rangeRects(RenderEditable editable, int start, int end) {
    return [
      for (final box in editable.getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: end),
      ))
        box.toRect(),
    ];
  }

  int? _checkboxLineAt(
    NoteEditingController rich,
    RenderEditable editable,
    Offset globalPosition,
  ) {
    final position = editable.getPositionForPoint(globalPosition);
    final (lineIndex, _) = rich.locate(position.offset);
    if (rich.lineAt(lineIndex).type != NoteBlockType.checklist) {
      return null;
    }
    final start = rich.lineStartOffset(lineIndex);
    final rects = _rangeRects(editable, start, start + 1);
    if (rects.isEmpty) {
      return null;
    }
    final box = rects.first;
    final zone = Rect.fromLTRB(
      box.left - 20,
      box.top - 2,
      box.right + 12,
      box.bottom + 2,
    );
    return zone.contains(editable.globalToLocal(globalPosition))
        ? lineIndex
        : null;
  }

  NoteLinkSpan? _linkAt(
    NoteEditingController rich,
    RenderEditable editable,
    Offset globalPosition,
  ) {
    final position = editable.getPositionForPoint(globalPosition);
    final span = rich.linkSpanAt(position.offset);
    if (span == null) {
      return null;
    }
    final local = editable.globalToLocal(globalPosition);
    final isOnLink = _rangeRects(editable, span.start, span.end)
        .any((rect) => rect.inflate(4).contains(local));
    return isOnLink ? span : null;
  }

  bool _shouldInterceptTap(Offset globalPosition) {
    final rich = _rich;
    final editable = _findRenderEditable();
    if (rich == null || editable == null || widget.readOnly) {
      return false;
    }
    if (_checkboxLineAt(rich, editable, globalPosition) != null) {
      return true;
    }
    return !widget.focusNode.hasFocus &&
        _linkAt(rich, editable, globalPosition) != null;
  }

  void _handleInterceptedTap(Offset globalPosition) {
    final rich = _rich;
    final editable = _findRenderEditable();
    if (rich == null || editable == null || widget.readOnly) {
      return;
    }
    final lineIndex = _checkboxLineAt(rich, editable, globalPosition);
    if (lineIndex != null) {
      if (rich.toggleChecklistAt(lineIndex)) {
        HapticFeedback.selectionClick();
      }
      return;
    }
    final span = _linkAt(rich, editable, globalPosition);
    if (span != null) {
      _showLinkPreview(rich, editable, span);
    }
  }

  void _handleFieldTap() {
    final rich = _rich;
    final editable = _findRenderEditable();
    final pointer = _lastPointerDown;
    if (rich == null || editable == null || pointer == null) {
      return;
    }
    final span = _linkAt(rich, editable, pointer);
    if (span != null) {
      _showLinkPreview(rich, editable, span);
    }
  }

  void _showLinkPreview(
    NoteEditingController rich,
    RenderEditable editable,
    NoteLinkSpan span,
  ) {
    _hideLinkPreview();
    final rects = _rangeRects(editable, span.start, span.end);
    final overlay = Overlay.maybeOf(context);
    if (rects.isEmpty || overlay == null) {
      return;
    }
    final first = rects.first;
    final anchor = Rect.fromPoints(
      editable.localToGlobal(first.topLeft),
      editable.localToGlobal(first.bottomRight),
    );
    final canEdit = !span.isAuto && !widget.readOnly;
    final entry = OverlayEntry(
      builder: (overlayContext) => NoteLinkPreviewOverlay(
        anchor: anchor,
        url: span.url,
        onDismiss: _hideLinkPreview,
        onOpen: () => _openLink(span.url),
        onCopy: () => _copyLink(span.url),
        onEdit: canEdit ? () => _editLink(rich, span) : null,
      ),
    );
    _linkEntry = entry;
    _linkPreviewText = rich.text;
    _linkScrollPosition = Scrollable.maybeOf(context)?.position
      ?..addListener(_hideLinkPreview);
    overlay.insert(entry);
  }

  void _hideLinkPreview() {
    _linkScrollPosition?.removeListener(_hideLinkPreview);
    _linkScrollPosition = null;
    _linkPreviewText = null;
    final entry = _linkEntry;
    _linkEntry = null;
    if (entry != null) {
      entry
        ..remove()
        ..dispose();
    }
  }

  void _openLink(String url) {
    _hideLinkPreview();
    final open = widget.onOpenLink;
    if (open != null) {
      open(url);
    } else {
      openNoteLink(context, url);
    }
  }

  void _copyLink(String url) {
    _hideLinkPreview();
    copyNoteLink(context, url);
  }

  void _editLink(NoteEditingController rich, NoteLinkSpan span) {
    _hideLinkPreview();
    final hadFocus = widget.focusNode.hasFocus;
    rich.selection = TextSelection.collapsed(offset: span.start);
    editNoteLink(context, rich, widget.focusNode, refocus: hadFocus);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    final controller = widget.controller;
    final richController = _rich;
    final isDark = theme.themeData.brightness == Brightness.dark;
    final bodyStyle = ideaVaultBody(
      context,
      size: _editorBodyTextSize,
      weight: FontWeight.w500,
      color: theme.primaryText,
      height: 1.72,
    );
    final field = TextField(
      key: const Key('idea-markdown-text-field'),
      controller: controller,
      focusNode: widget.focusNode,
      scrollController: _fieldScrollController,
      readOnly: widget.readOnly,
      expands: true,
      minLines: null,
      maxLines: null,
      textAlignVertical: TextAlignVertical.top,
      keyboardType: TextInputType.multiline,
      textCapitalization: TextCapitalization.sentences,
      enableIMEPersonalizedLearning: widget.enablePersonalizedLearning,
      scrollPadding: EdgeInsets.only(
        bottom: Platform.isIOS ? 52 : 12,
      ),
      inputFormatters: [
        if (richController != null)
          NoteInputFormatter(richController)
        else
          ClassicBulletListFormatter(),
      ],
      onTap: richController == null ? null : _handleFieldTap,
      style: bodyStyle,
      decoration: InputDecoration(
        hintText: widget.placeholder,
        hintStyle: bodyStyle.copyWith(color: theme.outline),
        border: InputBorder.none,
        isCollapsed: true,
      ),
    );
    return SizedBox.expand(
      child: DecoratedBox(
        decoration: BoxDecoration(color: theme.surface),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
              child: NoteEditorTheme(
                data: NoteEditorThemeData(
                  textColor: theme.primaryText,
                  mutedColor: theme.textMuted,
                  accentColor: theme.primary,
                  codeBackground: isDark
                      ? NoteEditorThemeData.darkCodeBackground
                      : NoteEditorThemeData.lightCodeBackground,
                  inlineCodeColor: isDark
                      ? NoteEditorThemeData.darkInlineCodeColor
                      : NoteEditorThemeData.lightInlineCodeColor,
                ),
                child: Listener(
                  onPointerDown: (event) {
                    _lastPointerDown = event.position;
                  },
                  child: KeyedSubtree(
                    key: _fieldHostKey,
                    child: richController == null
                        ? field
                        : _CodeBackdrop(
                            controller: richController,
                            scrollController: _fieldScrollController,
                            checkedColor: theme.primary,
                            checkMarkColor: theme.onPrimary,
                            uncheckedColor: theme.textMuted,
                            color: isDark
                                ? NoteEditorThemeData.darkCodeBackground
                                : NoteEditorThemeData.lightCodeBackground,
                            chipHalfHeight: _editorBodyTextSize * 0.9 * 0.6 +
                                NoteEditorThemeData.inlineCodePadding,
                            child: field,
                          ),
                  ),
                ),
              ),
            ),
            if (richController != null && !widget.readOnly)
              _EditorTapLayer(
                shouldIntercept: _shouldInterceptTap,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  excludeFromSemantics: true,
                  onTapUp: (details) =>
                      _handleInterceptedTap(details.globalPosition),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CodeBackdrop extends SingleChildRenderObjectWidget {
  const _CodeBackdrop({
    required this.controller,
    required this.scrollController,
    required this.color,
    required this.chipHalfHeight,
    required this.checkedColor,
    required this.checkMarkColor,
    required this.uncheckedColor,
    required super.child,
  });

  final NoteEditingController controller;
  final ScrollController scrollController;
  final Color color;
  final double chipHalfHeight;
  final Color checkedColor;
  final Color checkMarkColor;
  final Color uncheckedColor;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderCodeBackdrop(
      controller: controller,
      scrollController: scrollController,
      color: color,
      chipHalfHeight: chipHalfHeight,
      checkedColor: checkedColor,
      checkMarkColor: checkMarkColor,
      uncheckedColor: uncheckedColor,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderCodeBackdrop renderObject,
  ) {
    renderObject
      ..controller = controller
      ..scrollController = scrollController
      ..color = color
      ..chipHalfHeight = chipHalfHeight
      ..checkColors = (checkedColor, checkMarkColor, uncheckedColor);
  }
}

class _RenderCodeBackdrop extends RenderProxyBox {
  _RenderCodeBackdrop({
    required NoteEditingController controller,
    required ScrollController scrollController,
    required Color color,
    required double chipHalfHeight,
    required Color checkedColor,
    required Color checkMarkColor,
    required Color uncheckedColor,
  })  : _controller = controller,
        _scrollController = scrollController,
        _color = color,
        _chipHalfHeight = chipHalfHeight,
        _checkColors = (checkedColor, checkMarkColor, uncheckedColor);

  (Color, Color, Color) _checkColors;

  set checkColors((Color, Color, Color) value) {
    if (value == _checkColors) {
      return;
    }
    _checkColors = value;
    markNeedsPaint();
  }

  static const double _blockPadding = 10;
  static const Radius _chipRadius = Radius.circular(6);
  static const Radius _blockRadius = Radius.circular(10);

  NoteEditingController _controller;
  ScrollController _scrollController;
  Color _color;
  double _chipHalfHeight;

  set controller(NoteEditingController value) {
    if (identical(value, _controller)) {
      return;
    }
    if (attached) {
      _controller.removeListener(markNeedsPaint);
      value.addListener(markNeedsPaint);
    }
    _controller = value;
    markNeedsPaint();
  }

  set scrollController(ScrollController value) {
    if (identical(value, _scrollController)) {
      return;
    }
    if (attached) {
      _scrollController.removeListener(markNeedsPaint);
      value.addListener(markNeedsPaint);
    }
    _scrollController = value;
    markNeedsPaint();
  }

  set color(Color value) {
    if (value == _color) {
      return;
    }
    _color = value;
    markNeedsPaint();
  }

  set chipHalfHeight(double value) {
    if (value == _chipHalfHeight) {
      return;
    }
    _chipHalfHeight = value;
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _controller.addListener(markNeedsPaint);
    _scrollController.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _controller.removeListener(markNeedsPaint);
    _scrollController.removeListener(markNeedsPaint);
    super.detach();
  }

  RenderEditable? _findEditable() {
    RenderEditable? found;
    void visit(RenderObject node) {
      if (found != null) {
        return;
      }
      if (node is RenderEditable) {
        found = node;
        return;
      }
      node.visitChildren(visit);
    }

    visitChildren(visit);
    return found;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final editable = _findEditable();
    if (editable != null &&
        editable.attached &&
        editable.hasSize &&
        _controller.text.isNotEmpty) {
      final canvas = context.canvas;
      canvas
        ..save()
        ..clipRect(
          Rect.fromLTRB(
            offset.dx - _blockPadding - 2,
            offset.dy,
            offset.dx + size.width + _blockPadding + 2,
            offset.dy + size.height,
          ),
        );
      final transform = editable.getTransformTo(this);
      final paint = Paint()..color = _color;
      Rect toLocal(Rect rect) =>
          MatrixUtils.transformRect(transform, rect).shift(offset);
      for (final range in _controller.codeBlockRanges) {
        final rect = _blockRect(editable, range);
        if (rect != null) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(toLocal(rect), _blockRadius),
            paint,
          );
        }
      }
      for (final range in _controller.inlineCodeRanges) {
        for (final rect in _chipRects(editable, range)) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(toLocal(rect), _chipRadius),
            paint,
          );
        }
      }
      for (final mark in _controller.checklistMarks) {
        final rect = _checkboxRect(editable, mark.offset);
        if (rect != null) {
          _paintCheckbox(canvas, toLocal(rect), checked: mark.checked);
        }
      }
      canvas.restore();
    }
    super.paint(context, offset);
  }

  Rect? _blockRect(RenderEditable editable, TextRange range) {
    final length = _controller.text.length;
    final start = range.start.clamp(0, length);
    final end = range.end.clamp(0, length);
    double? top;
    double? bottom;
    if (end > start) {
      for (final box in editable.getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: end),
      )) {
        top = top == null ? box.top : math.min(top, box.top);
        bottom = bottom == null ? box.bottom : math.max(bottom, box.bottom);
      }
    }
    final first = editable.getLocalRectForCaret(TextPosition(offset: start));
    final last = editable.getLocalRectForCaret(TextPosition(offset: end));
    top = math.min(top ?? first.top, first.center.dy);
    bottom = math.max(bottom ?? last.bottom, last.center.dy);
    if (bottom <= top) {
      return null;
    }
    return Rect.fromLTRB(
      -_blockPadding,
      top + 1,
      editable.size.width + _blockPadding,
      bottom - 1,
    );
  }

  Rect? _checkboxRect(RenderEditable editable, int offset) {
    if (offset + 1 > _controller.text.length) {
      return null;
    }
    final boxes = editable.getBoxesForSelection(
      TextSelection(baseOffset: offset, extentOffset: offset + 1),
    );
    if (boxes.isEmpty) {
      return null;
    }
    final box = boxes.first.toRect();
    final side = (box.width - 1).clamp(14.0, 18.0);
    return Rect.fromCenter(center: box.center, width: side, height: side);
  }

  void _paintCheckbox(Canvas canvas, Rect rect, {required bool checked}) {
    final (checkedColor, checkMarkColor, uncheckedColor) = _checkColors;
    final radius = Radius.circular(rect.width * 0.28);
    if (!checked) {
      final stroke = rect.width * 0.11;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.deflate(stroke / 2), radius),
        Paint()
          ..color = uncheckedColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke,
      );
      return;
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, radius),
      Paint()..color = checkedColor,
    );
    final w = rect.width;
    final path = Path()
      ..moveTo(rect.left + w * 0.26, rect.top + w * 0.52)
      ..lineTo(rect.left + w * 0.43, rect.top + w * 0.69)
      ..lineTo(rect.left + w * 0.75, rect.top + w * 0.34);
    canvas.drawPath(
      path,
      Paint()
        ..color = checkMarkColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.13
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  List<Rect> _chipRects(RenderEditable editable, TextRange range) {
    final boxes = editable
        .getBoxesForSelection(
          TextSelection(baseOffset: range.start, extentOffset: range.end),
        )
        .map((box) => box.toRect())
        .where((rect) => rect.width > 0)
        .toList();
    if (boxes.isEmpty) {
      return const [];
    }
    final rows = <List<Rect>>[];
    for (final rect in boxes) {
      final row = rows.where(
        (candidate) => (candidate.first.center.dy - rect.center.dy).abs() < 2,
      );
      if (row.isEmpty) {
        rows.add([rect]);
      } else {
        row.first.add(rect);
      }
    }
    rows.sort((a, b) => a.first.top.compareTo(b.first.top));
    const pad = NoteEditorThemeData.inlineCodePadding;
    final result = <Rect>[];
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      var left = row.first.left;
      var right = row.first.right;
      var centerY = 0.0;
      for (final rect in row) {
        if (rect.left < left) {
          left = rect.left;
        }
        if (rect.right > right) {
          right = rect.right;
        }
        centerY += rect.center.dy;
      }
      centerY /= row.length;
      if (i == rows.length - 1) {
        final endCaret = editable.getLocalRectForCaret(
          TextPosition(offset: range.end, affinity: TextAffinity.upstream),
        );
        right = endCaret.left - NoteEditorThemeData.inlineCodeGap;
      }
      result.add(Rect.fromLTRB(
        left - pad,
        centerY - _chipHalfHeight,
        math.max(left, right) + pad,
        centerY + _chipHalfHeight,
      ));
    }
    return result;
  }
}

class _EditorTapLayer extends SingleChildRenderObjectWidget {
  const _EditorTapLayer({
    required this.shouldIntercept,
    required super.child,
  });

  final bool Function(Offset globalPosition) shouldIntercept;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderEditorTapLayer(shouldIntercept);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderEditorTapLayer renderObject,
  ) {
    renderObject.shouldIntercept = shouldIntercept;
  }
}

class _RenderEditorTapLayer extends RenderProxyBox {
  _RenderEditorTapLayer(this.shouldIntercept);

  bool Function(Offset globalPosition) shouldIntercept;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!size.contains(position) || !shouldIntercept(localToGlobal(position))) {
      return false;
    }
    return super.hitTest(result, position: position);
  }
}

class IdeaEditorToolbarContainer extends StatelessWidget {
  const IdeaEditorToolbarContainer({
    super.key,
    required this.controller,
    required this.focusNode,
    this.enabled = true,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    return DecoratedBox(
      decoration: BoxDecoration(color: theme.surface),
      child: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: IdeaEditorToolbar(
          controller: controller,
          focusNode: focusNode,
          enabled: enabled,
        ),
      ),
    );
  }
}

class IdeaEditorToolbar extends StatefulWidget {
  const IdeaEditorToolbar({
    super.key,
    required this.controller,
    required this.focusNode,
    this.enabled = true,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;

  @override
  State<IdeaEditorToolbar> createState() => _IdeaEditorToolbarState();
}

class _IdeaEditorToolbarState extends State<IdeaEditorToolbar> {
  static const double _arrowClearance = 60;
  static const Duration _scrollDuration = Duration(milliseconds: 240);

  final ScrollController _scrollController = ScrollController();
  final GlobalKey _rowKey = GlobalKey();
  bool _canScroll = false;
  bool _atEnd = false;
  int _toolCount = 0;

  TextEditingController get controller => widget.controller;
  FocusNode get focusNode => widget.focusNode;
  bool get enabled => widget.enabled;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_syncArrow);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_syncArrow)
      ..dispose();
    super.dispose();
  }

  void _syncArrow() {
    if (!mounted || !_scrollController.hasClients) {
      return;
    }
    final position = _scrollController.position;
    if (!position.hasContentDimensions) {
      return;
    }
    final canScroll = position.maxScrollExtent > position.minScrollExtent;
    final atEnd = canScroll && position.pixels >= position.maxScrollExtent - 1;
    if (canScroll != _canScroll || atEnd != _atEnd) {
      setState(() {
        _canScroll = canScroll;
        _atEnd = atEnd;
      });
    }
  }

  double _toolExtent() {
    final row = _rowKey.currentContext?.findRenderObject();
    if (row is RenderBox && row.hasSize && _toolCount > 0) {
      return row.size.width / _toolCount;
    }
    return 56;
  }

  void _handleArrow() {
    if (!_scrollController.hasClients) {
      return;
    }
    final position = _scrollController.position;
    if (_atEnd) {
      _scrollController.animateTo(
        position.minScrollExtent,
        duration: _scrollDuration * 2,
        curve: Curves.easeOutCubic,
      );
      return;
    }
    final step = _toolExtent();
    var target = (position.pixels / step).floorToDouble() * step + step;
    if (target - position.pixels < step * 0.4) {
      target += step;
    }
    _scrollController.animateTo(
      target.clamp(position.minScrollExtent, position.maxScrollExtent),
      duration: _scrollDuration,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final rich = controller;
        final buttons = rich is NoteEditingController
            ? _richButtons(context, rich)
            : _classicButtons(context);
        _toolCount = buttons.length;
        return Stack(
          alignment: AlignmentDirectional.centerStart,
          children: [
            NotificationListener<ScrollMetricsNotification>(
              onNotification: (_) {
                _syncArrow();
                return false;
              },
              child: SingleChildScrollView(
                key: const Key('idea-editor-toolbar-scroll'),
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                padding: EdgeInsetsDirectional.only(
                  start: _toolbarEdgePadding,
                  end: _canScroll ? _arrowClearance : _toolbarEdgePadding - 8,
                ),
                child: Row(key: _rowKey, children: buttons),
              ),
            ),
            if (_canScroll)
              PositionedDirectional(
                end: 0,
                top: 0,
                bottom: 0,
                width: _toolbarArrowWidth,
                child: _ToolbarScrollArrow(
                  buttonKey: const Key('idea-editor-toolbar-more'),
                  isFlipped: _atEnd,
                  tooltipKey: _atEnd
                      ? ViewConstants.editorToolbarBack
                      : ViewConstants.editorToolbarMore,
                  onPressed: _handleArrow,
                ),
              ),
          ],
        );
      },
    );
  }

  void _run(VoidCallback action) {
    action();
    if (!focusNode.hasFocus) {
      focusNode.requestFocus();
    }
  }

  List<Widget> _richButtons(
    BuildContext context,
    NoteEditingController rich,
  ) {
    final state = rich.toolbarState;
    final inCode = state.blockType == NoteBlockType.code;
    return [
      _ToolbarIconButton(
        key: const Key('idea-editor-toolbar-link'),
        icon: Icons.link_rounded,
        tooltip: ViewConstants.editorToolbarLink,
        enabled: enabled && !inCode,
        isActive: state.link,
        onPressed: () => editNoteLink(context, rich, focusNode),
      ),
      _ToolbarIconButton(
        key: const Key('idea-editor-toolbar-heading'),
        icon: Icons.title,
        tooltip: ViewConstants.editorToolbarHeading,
        iconSize: 26,
        enabled: enabled,
        isActive: state.blockType?.isHeading ?? false,
        onPressed: () => _run(rich.cycleHeading),
      ),
      _ToolbarIconButton(
        key: const Key('idea-editor-toolbar-bold'),
        icon: Icons.format_bold,
        tooltip: ViewConstants.editorToolbarBold,
        enabled: enabled && !inCode,
        isActive: state.bold,
        onPressed: () =>
            _run(() => rich.toggleInline(NoteInlineAttribute.bold)),
      ),
      _ToolbarIconButton(
        key: const Key('idea-editor-toolbar-italic'),
        icon: Icons.format_italic,
        tooltip: ViewConstants.editorToolbarItalic,
        enabled: enabled && !inCode,
        isActive: state.italic,
        onPressed: () =>
            _run(() => rich.toggleInline(NoteInlineAttribute.italic)),
      ),
      _ToolbarIconButton(
        key: const Key('idea-editor-toolbar-bullet'),
        icon: Icons.format_list_bulleted,
        tooltip: ViewConstants.editorToolbarBulletList,
        enabled: enabled,
        isActive: state.blockType == NoteBlockType.bullet,
        onPressed: () => _run(() => rich.toggleBlock(NoteBlockType.bullet)),
      ),
      _ToolbarIconButton(
        key: const Key('idea-editor-toolbar-numbered'),
        icon: Icons.format_list_numbered,
        tooltip: ViewConstants.editorToolbarNumberedList,
        enabled: enabled,
        isActive: state.blockType == NoteBlockType.numbered,
        onPressed: () => _run(() => rich.toggleBlock(NoteBlockType.numbered)),
      ),
      _ToolbarIconButton(
        key: const Key('idea-editor-toolbar-checklist'),
        icon: Icons.checklist_rounded,
        tooltip: ViewConstants.editorToolbarChecklist,
        enabled: enabled,
        isActive: state.blockType == NoteBlockType.checklist,
        onPressed: () => _run(() => rich.toggleBlock(NoteBlockType.checklist)),
      ),
      _ToolbarIconButton(
        key: const Key('idea-editor-toolbar-code-block'),
        icon: Icons.code,
        tooltip: ViewConstants.editorToolbarCodeBlock,
        enabled: enabled,
        isActive: inCode,
        onPressed: () => _run(() => rich.toggleBlock(NoteBlockType.code)),
      ),
      _ToolbarIconButton(
        key: const Key('idea-editor-toolbar-inline-code'),
        icon: Icons.data_object_rounded,
        tooltip: ViewConstants.editorToolbarInlineCode,
        enabled: enabled && !inCode,
        isActive: state.inlineCode,
        onPressed: () =>
            _run(() => rich.toggleInline(NoteInlineAttribute.code)),
      ),
    ];
  }

  List<Widget> _classicButtons(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    return [
      Container(
        key: const Key('idea-editor-plain-text-marker'),
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: theme.surfaceLow,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          ViewConstants.editorPlainTextMarker.tr(),
          style: ideaVaultLabel(
            context,
            size: 12,
            weight: FontWeight.w700,
            color: theme.textMuted,
          ),
        ),
      ),
      _ToolbarIconButton(
        icon: Icons.title,
        tooltip: ViewConstants.editorToolbarHeading,
        iconSize: 26,
        enabled: enabled,
        onPressed: () => _wrapSelection('## ', '', true),
      ),
      _ToolbarIconButton(
        icon: Icons.format_bold,
        tooltip: ViewConstants.editorToolbarBold,
        enabled: enabled,
        onPressed: () => _wrapSelection('**', '**', false),
      ),
      _ToolbarIconButton(
        icon: Icons.format_italic,
        tooltip: ViewConstants.editorToolbarItalic,
        enabled: enabled,
        onPressed: () => _wrapSelection('_', '_', false),
      ),
      _ToolbarIconButton(
        icon: Icons.format_list_bulleted,
        tooltip: ViewConstants.editorToolbarBulletList,
        enabled: enabled,
        onPressed: () => _wrapSelection('- ', '', true),
      ),
      _ToolbarIconButton(
        icon: Icons.code,
        tooltip: ViewConstants.editorToolbarCodeBlock,
        enabled: enabled,
        onPressed: () => _wrapSelection('```\n', '\n```', false),
      ),
    ];
  }

  void _wrapSelection(String prefix, String suffix, bool linePrefix) {
    final value = controller.value;
    final text = value.text;
    final selection = value.selection;
    final start = selection.start < 0 ? text.length : selection.start;
    final end = selection.end < 0 ? text.length : selection.end;

    if (linePrefix) {
      final lineStartIndex = text.lastIndexOf('\n', start == 0 ? 0 : start - 1);
      final lineStart = lineStartIndex == -1 ? 0 : lineStartIndex + 1;
      final lineEndIndex = end < text.length ? text.indexOf('\n', end) : -1;
      final lineEnd = lineEndIndex == -1 ? text.length : lineEndIndex;
      final lines = text.substring(lineStart, lineEnd).split('\n');
      final allHavePrefix = lines.every((line) => line.startsWith(prefix));
      final transformed = lines.map((line) {
        if (allHavePrefix) {
          return line.substring(prefix.length);
        }
        return line.startsWith(prefix) ? line : '$prefix$line';
      }).join('\n');
      final updatedText = text.replaceRange(lineStart, lineEnd, transformed);
      final offsetDelta = allHavePrefix ? -prefix.length : prefix.length;
      final newStart = start + (start >= lineStart ? offsetDelta : 0);
      final newEnd = end + (lines.length * offsetDelta);
      controller.value = TextEditingValue(
        text: updatedText,
        selection: TextSelection(
          baseOffset: math.max(0, math.min(updatedText.length, newStart)),
          extentOffset: math.max(0, math.min(updatedText.length, newEnd)),
        ),
      );
      focusNode.requestFocus();
      return;
    }

    final selectedText = text.substring(start, end);
    final replacement = '$prefix$selectedText$suffix';
    final updatedText = text.replaceRange(start, end, replacement);
    final nextOffset = selectedText.isEmpty
        ? start + prefix.length
        : start + replacement.length;
    controller.value = TextEditingValue(
      text: updatedText,
      selection: TextSelection.collapsed(offset: nextOffset),
    );
    focusNode.requestFocus();
  }
}

class _ToolbarScrollArrow extends StatelessWidget {
  const _ToolbarScrollArrow({
    required this.buttonKey,
    required this.isFlipped,
    required this.tooltipKey,
    required this.onPressed,
  });

  final Key buttonKey;
  final bool isFlipped;
  final String tooltipKey;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final solid = theme.surface;
    final clear = solid.withValues(alpha: 0);
    final isDark = theme.themeData.brightness == Brightness.dark;
    final fill = Color.alphaBlend(
      theme.textMuted.withValues(alpha: isDark ? 0.28 : 0.18),
      theme.surface,
    );
    final turns = (isFlipped ? 0.5 : 0.0) + (isRtl ? 0.5 : 0.0);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.centerStart,
          end: AlignmentDirectional.centerEnd,
          colors: [clear, solid, solid],
          stops: const [0, 0.3, 1],
        ),
      ),
      child: Align(
        alignment: AlignmentDirectional.centerEnd,
        child: Padding(
          padding: const EdgeInsetsDirectional.only(start: 4, end: 8),
          child: IconButton(
            key: buttonKey,
            onPressed: onPressed,
            tooltip: tooltipKey.tr(),
            isSelected: isFlipped,
            style: IconButton.styleFrom(
              backgroundColor: fill,
              foregroundColor: theme.primaryText.withValues(alpha: 0.72),
            ),
            icon: AnimatedRotation(
              turns: turns,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: const Icon(Icons.chevron_right_rounded),
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolbarIconButton extends StatelessWidget {
  const _ToolbarIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.iconSize,
    this.enabled = true,
    this.isActive = false,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;
  final double? iconSize;
  final bool enabled;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    final foregroundColor = !enabled
        ? theme.textMuted.withValues(alpha: 0.55)
        : isActive
            ? theme.onPrimary
            : theme.primary;
    final backgroundColor =
        isActive && enabled ? theme.primary : theme.surfaceLow;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Tooltip(
        message: tooltip.tr(),
        child: IgnorePointer(
          ignoring: !enabled,
          child: IconButton(
            onPressed: enabled ? onPressed : () {},
            isSelected: isActive,
            style: IconButton.styleFrom(
              backgroundColor: backgroundColor,
              foregroundColor: foregroundColor,
            ),
            icon: Icon(icon, size: iconSize, color: foregroundColor),
          ),
        ),
      ),
    );
  }
}
