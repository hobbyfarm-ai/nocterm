import 'package:characters/characters.dart';
import 'package:termunicode/termunicode.dart' as termunicode;

/// How grapheme clusters are measured.
enum WidthMethod { grapheme, legacy }

/// Utility class for handling Unicode character display width in terminals.
class UnicodeWidth {
  /// Active measurement policy. Detected at startup, before the first
  /// frame.
  static WidthMethod method = WidthMethod.grapheme;

  /// Overrides [method] for tests. Pass null to reset to the default.
  static void setMethodForTesting(WidthMethod? value) {
    method = value ?? WidthMethod.grapheme;
  }

  /// Calculate the display width of a string in terminal columns.
  static int stringWidth(String text) {
    if (text.isEmpty) return 0;

    var totalWidth = 0;
    for (final grapheme in text.characters) {
      totalWidth += graphemeWidth(grapheme);
    }

    return totalWidth;
  }

  /// Calculate the display width of a single grapheme cluster.
  static int graphemeWidth(String grapheme) {
    if (grapheme.isEmpty) return 0;

    // Layout expects a tab to advance the cursor.
    if (grapheme == '\t') return 1;

    if (method == WidthMethod.legacy) {
      var total = 0;
      for (final rune in grapheme.runes) {
        total += termunicode.widthCp(rune);
      }
      return total;
    }

    return termunicode.widthString(grapheme);
  }

  /// Calculate the display width of a single rune/codepoint.
  static int runeWidth(int rune) {
    if (rune == 0x09) return 1;

    return termunicode.widthCp(rune);
  }
}
