import 'dart:math' as math;

import 'package:characters/characters.dart';
import 'package:nocterm/nocterm.dart';
import 'package:nocterm/src/framework/terminal_canvas.dart';

/// Utilities for text selection hit testing and painting.
///
/// Computes the character offset for the start of each line in [text].
///
/// The [lines] input should be the layout engine output: line strings with
/// wrapping applied and without embedded `\n` characters. This helper advances
/// past newline characters in [text] so empty lines (consecutive `\n`s) map to
/// distinct offsets.
List<int> lineStartOffsets(String text, List<String> lines) {
  final offsets = <int>[];
  int offset = 0;
  for (int i = 0; i < lines.length; i++) {
    offsets.add(offset);
    offset += lines[i].length;
    if (offset < text.length && text[offset] == '\n') {
      offset++;
    }
  }
  return offsets;
}

/// Maps a local position (x, y) to a character index within [text].
///
/// Pass [lineStarts] (from [lineStartOffsets]) when the caller caches it;
/// omitted, it is computed on the fly.
int getCharacterIndexAtLocalPosition({
  required Offset localPos,
  required String text,
  required List<String> lines,
  List<int>? lineStarts,
}) {
  if (lines.isEmpty) return 0;

  final lineIndex = localPos.dy.toInt().clamp(0, lines.length - 1);
  final lineStartOffset =
      (lineStarts ?? lineStartOffsets(text, lines))[lineIndex];
  final line = lines[lineIndex];
  final targetX = localPos.dx;

  int cumulativeWidth = 0;
  int charIndex = 0;
  for (final grapheme in line.characters) {
    final gw = UnicodeWidth.graphemeWidth(grapheme);
    if (cumulativeWidth.toDouble() + gw / 2.0 > targetX) {
      break;
    }
    cumulativeWidth += gw;
    charIndex += grapheme.length;
  }

  return (lineStartOffset + charIndex).clamp(0, text.length);
}

/// Maps a character [offset] to its local cell position (column, line).
///
/// Pass [lineStarts] (from [lineStartOffsets]) when the caller caches it;
/// omitted, it is computed on the fly.
Offset positionForOffset({
  required int offset,
  required String text,
  required List<String> lines,
  List<int>? lineStarts,
}) {
  if (lines.isEmpty) return Offset.zero;
  final starts = lineStarts ?? lineStartOffsets(text, lines);
  int line = lines.length - 1;
  for (int i = 0; i < lines.length - 1; i++) {
    if (offset < starts[i + 1]) {
      line = i;
      break;
    }
  }
  final local = (offset - starts[line]).clamp(0, lines[line].length);
  final column = UnicodeWidth.stringWidth(lines[line].substring(0, local));
  return Offset(column.toDouble(), line.toDouble());
}

/// Computes one local cell rect per line covered by the character range
/// [start]..[end].
///
/// Pass [lineStarts] (from [lineStartOffsets]) when the caller caches it;
/// omitted, it is computed on the fly.
List<Rect> selectionRectsForRange({
  required String text,
  required List<String> lines,
  required int start,
  required int end,
  List<int>? lineStarts,
}) {
  if (lines.isEmpty || start >= end) return const [];
  final starts = lineStarts ?? lineStartOffsets(text, lines);
  final rects = <Rect>[];
  for (int i = 0; i < lines.length; i++) {
    final lineStart = starts[i];
    final lineEnd = lineStart + lines[i].length;
    final selStart = math.max(start, lineStart);
    final selEnd = math.min(end, lineEnd);
    if (selStart >= selEnd) continue;
    final left =
        UnicodeWidth.stringWidth(lines[i].substring(0, selStart - lineStart));
    final width = UnicodeWidth.stringWidth(
        lines[i].substring(selStart - lineStart, selEnd - lineStart));
    if (width == 0) continue;
    rects
        .add(Rect.fromLTWH(left.toDouble(), i.toDouble(), width.toDouble(), 1));
  }
  return rects;
}

final _wordChar = RegExp(r'[\p{L}\p{N}_]', unicode: true);
final _whitespace = RegExp(r'\s');

/// The character range of the word (or whitespace/symbol run) at [offset].
({int start, int end}) wordRangeAt(
    {required String text, required int offset}) {
  if (text.isEmpty) return (start: 0, end: 0);
  final anchor = offset.clamp(0, text.length - 1);

  bool sameCategory(String a, String b) {
    if (_wordChar.hasMatch(a)) return _wordChar.hasMatch(b);
    if (_whitespace.hasMatch(a)) return _whitespace.hasMatch(b);
    return !_wordChar.hasMatch(b) && !_whitespace.hasMatch(b);
  }

  final anchorChar = text[anchor];
  var start = anchor;
  while (start > 0 && sameCategory(anchorChar, text[start - 1])) {
    start--;
  }
  var end = anchor + 1;
  while (end < text.length && sameCategory(anchorChar, text[end])) {
    end++;
  }
  return (start: start, end: end);
}

/// Paints a single line of text with optional selection highlighting.
///
/// Pass [lineStarts] (from [lineStartOffsets]) when the caller caches it —
/// this runs once per painted line, so recomputing offsets here is
/// quadratic in the line count. Omitted, it is computed on the fly.
void paintTextWithSelection({
  required TerminalCanvas canvas,
  required Offset offset,
  required String line,
  required TextStyle? style,
  required int lineIndex,
  required String text,
  required List<String> lines,
  required int? selectionStart,
  required int? selectionEnd,
  required Color selection,
  required Color onSelection,
  List<int>? lineStarts,
}) {
  if (selectionStart == null ||
      selectionEnd == null ||
      selectionStart == selectionEnd) {
    canvas.drawText(offset, line, style: style);
    return;
  }

  final lineStartOffset =
      (lines.isNotEmpty && lineIndex > 0 && lineIndex < lines.length)
          ? (lineStarts ?? lineStartOffsets(text, lines))[lineIndex]
          : 0;
  final lineEndOffset = lineStartOffset + line.length;

  final selStart = math.min(selectionStart, selectionEnd);
  final selEnd = math.max(selectionStart, selectionEnd);

  if (selEnd > lineStartOffset && selStart < lineEndOffset) {
    final localSelStart = math.max(0, selStart - lineStartOffset);
    final localSelEnd = math.min(line.length, selEnd - lineStartOffset);

    if (localSelStart < localSelEnd) {
      if (localSelStart > 0) {
        final beforeText = line.substring(0, localSelStart);
        canvas.drawText(offset, beforeText, style: style);
      }

      final selectedText = line.substring(localSelStart, localSelEnd);
      final beforeWidth = localSelStart > 0
          ? UnicodeWidth.stringWidth(line.substring(0, localSelStart))
          : 0;
      final selectionStyle = (style ?? const TextStyle())
          .copyWith(backgroundColor: selection, color: onSelection);
      canvas.drawText(
        offset + Offset(beforeWidth.toDouble(), 0),
        selectedText,
        style: selectionStyle,
      );

      if (localSelEnd < line.length) {
        final afterText = line.substring(localSelEnd);
        final beforeSelectedWidth =
            UnicodeWidth.stringWidth(line.substring(0, localSelEnd));
        canvas.drawText(
          offset + Offset(beforeSelectedWidth.toDouble(), 0),
          afterText,
          style: style,
        );
      }
      return;
    }
  }

  canvas.drawText(offset, line, style: style);
}
