import 'dart:typed_data';

import 'package:nocterm/src/style.dart';
import 'package:nocterm/src/utils/ansi_color_quantizer.dart';
import 'package:nocterm/src/utils/terminal_color_support.dart';

import 'byte_write_buffer.dart';

/// Writes the ANSI SGR escape sequence(s) representing [style] directly
/// into [buf] as bytes. The output is byte-for-byte equal to
/// `utf8.encode(style.toAnsi())` — see `sgr_encoder_test.dart` — but
/// without the per-call `List<String>` allocation, intermediate `String`
/// materialization, or UTF-8 re-encode that `TextStyle.toAnsi` plus
/// `ByteWriteBuffer.write(String)` would otherwise incur.
///
/// **Invariant — keep in sync with [TextStyle.toAnsi] (style.dart:513)
/// and [Color.toAnsi] (style.dart:153).** Any new style attribute or
/// emission-order change there must also land here, or the bytewise
/// equivalence test will fail.
///
/// Hot path on the diff renderer: called once per cell whose style
/// differs from the previous cell's.
void writeSgrBytesInto(TextStyle style, ByteWriteBuffer buf) {
  // Cache truecolor support outside the per-color branches — the lookup
  // hits a cached bool but reading it once still cheaper than twice.
  final truecolor = supportsTruecolor();

  final fg = style.color;
  if (fg != null) {
    if (fg.isDefault) {
      buf.writeAsciiBytes(_fgDefaultBytes);
    } else if (truecolor) {
      final exact = exactAnsi256Index(fg.red, fg.green, fg.blue);
      if (exact != null) {
        buf
          ..writeAsciiBytes(_fg256Prefix)
          ..writeAsciiInt(exact)
          ..writeAsciiByte(_mByte);
      } else {
        buf
          ..writeAsciiBytes(_fgRgbPrefix)
          ..writeAsciiInt(fg.red)
          ..writeAsciiByte(_semicolonByte)
          ..writeAsciiInt(fg.green)
          ..writeAsciiByte(_semicolonByte)
          ..writeAsciiInt(fg.blue)
          ..writeAsciiByte(_mByte);
      }
    } else {
      buf
        ..writeAsciiBytes(_fg256Prefix)
        ..writeAsciiInt(quantizeRgbToAnsi256(fg.red, fg.green, fg.blue))
        ..writeAsciiByte(_mByte);
    }
  }

  final bg = style.backgroundColor;
  if (bg != null) {
    if (bg.isDefault) {
      buf.writeAsciiBytes(_bgDefaultBytes);
    } else if (truecolor) {
      final exact = exactAnsi256Index(bg.red, bg.green, bg.blue);
      if (exact != null) {
        buf
          ..writeAsciiBytes(_bg256Prefix)
          ..writeAsciiInt(exact)
          ..writeAsciiByte(_mByte);
      } else {
        buf
          ..writeAsciiBytes(_bgRgbPrefix)
          ..writeAsciiInt(bg.red)
          ..writeAsciiByte(_semicolonByte)
          ..writeAsciiInt(bg.green)
          ..writeAsciiByte(_semicolonByte)
          ..writeAsciiInt(bg.blue)
          ..writeAsciiByte(_mByte);
      }
    } else {
      buf
        ..writeAsciiBytes(_bg256Prefix)
        ..writeAsciiInt(quantizeRgbToAnsi256(bg.red, bg.green, bg.blue))
        ..writeAsciiByte(_mByte);
    }
  }

  // Font weight: bold and dim are mutually exclusive in toAnsi (the
  // else-if reflects that — only one is emitted).
  final weight = style.fontWeight;
  if (weight == FontWeight.bold) {
    buf.writeAsciiBytes(_boldBytes);
  } else if (weight == FontWeight.dim) {
    buf.writeAsciiBytes(_dimBytes);
  }

  if (style.fontStyle == FontStyle.italic) {
    buf.writeAsciiBytes(_italicBytes);
  }

  final decoration = style.decoration;
  if (decoration != null) {
    if (decoration.hasUnderline) {
      buf.writeAsciiBytes(_underlineBytes);
    }
    if (decoration.hasLineThrough) {
      buf.writeAsciiBytes(_strikeBytes);
    }
    if (decoration.hasOverline) {
      buf.writeAsciiBytes(_overlineBytes);
    }
  }

  if (style.reverse) {
    buf.writeAsciiBytes(_reverseBytes);
  }
}

// ---------------------------------------------------------------------------
// Precomputed escape-sequence byte constants.
//
// Allocated once at library load and referenced per-cell; per-call cost is
// a single `setRange` memcpy of 4-7 bytes.

const int _semicolonByte = 0x3b; // ;
const int _mByte = 0x6d; // m

final Uint8List _fgRgbPrefix = Uint8List.fromList(
  // \x1b[38;2;
  [0x1b, 0x5b, 0x33, 0x38, 0x3b, 0x32, 0x3b],
);
final Uint8List _bgRgbPrefix = Uint8List.fromList(
  // \x1b[48;2;
  [0x1b, 0x5b, 0x34, 0x38, 0x3b, 0x32, 0x3b],
);
final Uint8List _fg256Prefix = Uint8List.fromList(
  // \x1b[38;5;
  [0x1b, 0x5b, 0x33, 0x38, 0x3b, 0x35, 0x3b],
);
final Uint8List _bg256Prefix = Uint8List.fromList(
  // \x1b[48;5;
  [0x1b, 0x5b, 0x34, 0x38, 0x3b, 0x35, 0x3b],
);
final Uint8List _fgDefaultBytes = Uint8List.fromList(
  // \x1b[39m
  [0x1b, 0x5b, 0x33, 0x39, 0x6d],
);
final Uint8List _bgDefaultBytes = Uint8List.fromList(
  // \x1b[49m
  [0x1b, 0x5b, 0x34, 0x39, 0x6d],
);
final Uint8List _boldBytes = Uint8List.fromList(
  // \x1b[1m
  [0x1b, 0x5b, 0x31, 0x6d],
);
final Uint8List _dimBytes = Uint8List.fromList(
  // \x1b[2m
  [0x1b, 0x5b, 0x32, 0x6d],
);
final Uint8List _italicBytes = Uint8List.fromList(
  // \x1b[3m
  [0x1b, 0x5b, 0x33, 0x6d],
);
final Uint8List _underlineBytes = Uint8List.fromList(
  // \x1b[4m
  [0x1b, 0x5b, 0x34, 0x6d],
);
final Uint8List _strikeBytes = Uint8List.fromList(
  // \x1b[9m
  [0x1b, 0x5b, 0x39, 0x6d],
);
final Uint8List _overlineBytes = Uint8List.fromList(
  // \x1b[53m
  [0x1b, 0x5b, 0x35, 0x33, 0x6d],
);
final Uint8List _reverseBytes = Uint8List.fromList(
  // \x1b[7m
  [0x1b, 0x5b, 0x37, 0x6d],
);
