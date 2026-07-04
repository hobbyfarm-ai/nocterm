import 'package:meta/meta.dart';

import '../framework/framework.dart';
import '../framework/terminal_canvas.dart';
import '../rectangle.dart';
import '../style.dart';
import '../text/selection_utils.dart' as selection_utils;
import '../text/text_layout_engine.dart';
import 'selection.dart';

/// Implements the [Selectable] contract for render objects that display
/// line-wrapped text.
///
/// Mixers expose their content via [selectableText] and [selectableLayout],
/// call [didLayoutSelectableText] at the end of `performLayout`, and use
/// [paintTextWithSelection] (or [selectionStart]/[selectionEnd]) to paint
/// the highlight.
mixin TextSelectable on RenderObject, Selectable {
  /// The plain-text content that can be selected.
  String get selectableText;

  /// The cached layout result (line-wrapped text).
  TextLayoutResult? get selectableLayout;

  @override
  Offset get globalPaintOffset => globalPaintOffsetOf(this);

  @override
  Rect get globalBounds {
    final origin = globalPaintOffset;
    return Rect.fromLTWH(
      origin.dx,
      origin.dy,
      hasSize ? size.width : 0,
      hasSize ? size.height : 0,
    );
  }

  Color? _selection;

  /// Background color used to highlight selected text.
  Color? get selection => _selection;
  set selection(Color? value) {
    if (_selection == value) return;
    _selection = value;
    if (hasSelection) markNeedsPaint();
  }

  Color? _onSelection;

  /// Foreground color for text drawn on top of [selection].
  Color? get onSelection => _onSelection;
  set onSelection(Color? value) {
    if (_onSelection == value) return;
    _onSelection = value;
    if (hasSelection) markNeedsPaint();
  }

  int? _selectionStart;
  int? _selectionEnd;

  /// The character offset of the selection start edge, or null if unset.
  ///
  /// May be greater than [selectionEnd] when the selection is reversed.
  int? get selectionStart => _selectionStart;

  /// The character offset of the selection end edge, or null if unset.
  int? get selectionEnd => _selectionEnd;

  /// Whether this render object has a non-collapsed selection.
  bool get hasSelection =>
      _selectionStart != null &&
      _selectionEnd != null &&
      _selectionStart != _selectionEnd;

  @override
  int get contentLength => selectableText.length;

  List<String> get _lines => selectableLayout?.lines ?? const [];

  List<int>? _cachedLineStarts;

  /// Start offset of each layout line within [selectableText], cached per
  /// layout ([didLayoutSelectableText] invalidates it).
  @protected
  List<int> get selectableLineStarts => _cachedLineStarts ??=
      selection_utils.lineStartOffsets(selectableText, _lines);

  @override
  SelectionResult dispatchSelectionEvent(SelectionEvent event) {
    switch (event) {
      case SelectionEdgeUpdateEvent():
        return _handleEdgeUpdate(event);
      case SelectAllSelectionEvent():
        _setSelection(0, contentLength);
        return SelectionResult.none;
      case ClearSelectionEvent():
        _setSelection(null, null);
        return SelectionResult.none;
      case SelectWordSelectionEvent():
        return _handleSelectWord(event);
    }
  }

  SelectionResult _handleEdgeUpdate(SelectionEdgeUpdateEvent event) {
    final bounds = globalBounds;
    final adjusted =
        SelectionUtils.adjustDragOffset(bounds, event.globalPosition);
    final local = adjusted - globalPaintOffset;
    final offset = getCharacterIndexAtLocalPosition(local);
    if (event.isEnd) {
      _setSelection(_selectionStart, offset);
    } else {
      _setSelection(offset, _selectionEnd);
    }
    return SelectionUtils.getResultBasedOnRect(bounds, event.globalPosition);
  }

  SelectionResult _handleSelectWord(SelectWordSelectionEvent event) {
    if (contentLength == 0) return SelectionResult.none;
    final local = event.globalPosition - globalPaintOffset;
    final offset = getCharacterIndexAtLocalPosition(local);
    final range = selection_utils.wordRangeAt(
      text: selectableText,
      offset: offset,
    );
    _setSelection(range.start, range.end);
    return SelectionResult.end;
  }

  @override
  SelectedContent? getSelectedContent() {
    if (!hasSelection) return null;
    final start = _normalizedStart!;
    final end = _normalizedEnd!;
    return SelectedContent(plainText: selectableText.substring(start, end));
  }

  int? get _normalizedStart {
    if (_selectionStart == null || _selectionEnd == null) return null;
    final len = contentLength;
    final a = _selectionStart!.clamp(0, len);
    final b = _selectionEnd!.clamp(0, len);
    return a < b ? a : b;
  }

  int? get _normalizedEnd {
    if (_selectionStart == null || _selectionEnd == null) return null;
    final len = contentLength;
    final a = _selectionStart!.clamp(0, len);
    final b = _selectionEnd!.clamp(0, len);
    return a < b ? b : a;
  }

  void _setSelection(int? start, int? end) {
    if (_selectionStart == start && _selectionEnd == end) return;
    _selectionStart = start;
    _selectionEnd = end;
    _publishGeometry();
    markNeedsPaint();
  }

  /// Notifies this mixin that content or layout changed.
  ///
  /// Call at the end of `performLayout`. Selection edges are clamped to the
  /// new content length and the reported geometry is rebuilt.
  void didLayoutSelectableText() {
    _cachedLineStarts = null;
    final len = contentLength;
    if (_selectionStart != null && _selectionStart! > len) {
      _selectionStart = len;
    }
    if (_selectionEnd != null && _selectionEnd! > len) {
      _selectionEnd = len;
    }
    _publishGeometry();
  }

  void _publishGeometry() {
    updateSelectionGeometry(computeSelectionGeometry());
  }

  /// Computes the current [SelectionGeometry] from the selection edges.
  ///
  /// Override when the mixer's content is not backed by a
  /// [selectableLayout] text layout (or when the default computation is
  /// too expensive for the mixer's content size).
  @protected
  SelectionGeometry computeSelectionGeometry() {
    final hasContent = contentLength > 0;
    final start = _selectionStart;
    final end = _selectionEnd;
    if (start == null || end == null) {
      return SelectionGeometry(
        status: SelectionStatus.none,
        hasContent: hasContent,
      );
    }
    final text = selectableText;
    final lines = _lines;
    final starts = selectableLineStarts;
    return SelectionGeometry(
      status: start == end
          ? SelectionStatus.collapsed
          : SelectionStatus.uncollapsed,
      hasContent: hasContent,
      startSelectionPoint: SelectionPoint(
        localPosition: selection_utils.positionForOffset(
          offset: start,
          text: text,
          lines: lines,
          lineStarts: starts,
        ),
      ),
      endSelectionPoint: SelectionPoint(
        localPosition: selection_utils.positionForOffset(
          offset: end,
          text: text,
          lines: lines,
          lineStarts: starts,
        ),
      ),
      selectionRects: selection_utils.selectionRectsForRange(
        text: text,
        lines: lines,
        start: _normalizedStart!,
        end: _normalizedEnd!,
        lineStarts: starts,
      ),
    );
  }

  /// Paints a single line of text with selection highlighting applied.
  void paintTextWithSelection(
    TerminalCanvas canvas,
    Offset offset,
    String line,
    TextStyle? style,
    int lineIndex,
  ) {
    selection_utils.paintTextWithSelection(
      canvas: canvas,
      offset: offset,
      line: line,
      style: style,
      lineIndex: lineIndex,
      text: selectableText,
      lines: _lines,
      selectionStart: _selectionStart,
      selectionEnd: _selectionEnd,
      selection: selection ?? Colors.blue,
      onSelection: onSelection ?? Colors.white,
      lineStarts: selectableLineStarts,
    );
  }

  /// Maps a local cell position to a character index in [selectableText].
  int getCharacterIndexAtLocalPosition(Offset localPos) {
    return selection_utils.getCharacterIndexAtLocalPosition(
      localPos: localPos,
      text: selectableText,
      lines: _lines,
      lineStarts: selectableLineStarts,
    );
  }
}
