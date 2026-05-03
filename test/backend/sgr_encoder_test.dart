import 'dart:convert';
import 'dart:typed_data';

import 'package:nocterm/nocterm.dart';
import 'package:nocterm/src/backend/byte_write_buffer.dart';
import 'package:nocterm/src/backend/sgr_encoder.dart';
import 'package:nocterm/src/utils/terminal_color_support.dart';
import 'package:test/test.dart';

void main() {
  group('writeSgrBytesInto', () {
    tearDown(() => setSupportsTruecolorForTesting(null));

    void expectEquivalent(TextStyle style, {required String label}) {
      final buf = ByteWriteBuffer()..clear();
      writeSgrBytesInto(style, buf);
      final actual = buf.takeBytes();
      final expected = Uint8List.fromList(utf8.encode(style.toAnsi()));
      expect(
        actual,
        equals(expected),
        reason: '$label\n'
            '  expected: ${_describe(expected)}\n'
            '    actual: ${_describe(actual)}',
      );
    }

    group('truecolor branch', () {
      setUp(() => setSupportsTruecolorForTesting(true));

      test('empty style emits no bytes', () {
        expectEquivalent(const TextStyle(), label: 'empty');
      });

      test('truecolor fg only (non-palette RGB)', () {
        expectEquivalent(
          const TextStyle(color: Color.fromRGB(231, 97, 112)),
          label: 'fg=Colors.red',
        );
      });

      test('truecolor bg only', () {
        expectEquivalent(
          const TextStyle(backgroundColor: Color.fromRGB(231, 97, 112)),
          label: 'bg=red',
        );
      });

      test('truecolor fg+bg', () {
        expectEquivalent(
          const TextStyle(
            color: Color.fromRGB(231, 97, 112),
            backgroundColor: Color.fromRGB(40, 50, 60),
          ),
          label: 'fg+bg',
        );
      });

      test('exact palette match (fg)', () {
        // (255, 0, 0) is xterm-256 cube index 196 — should emit 38;5;196.
        expectEquivalent(
          const TextStyle(color: Color.fromRGB(255, 0, 0)),
          label: 'fg=(255,0,0) cube 196',
        );
      });

      test('exact palette match (bg) — grayscale ramp', () {
        // (8, 8, 8) is xterm-256 grayscale index 232.
        expectEquivalent(
          const TextStyle(backgroundColor: Color.fromRGB(8, 8, 8)),
          label: 'bg gray ramp 232',
        );
      });

      test('default fg color', () {
        expectEquivalent(
          const TextStyle(color: Color.defaultColor),
          label: 'fg=default',
        );
      });

      test('default bg color', () {
        expectEquivalent(
          const TextStyle(backgroundColor: Color.defaultColor),
          label: 'bg=default',
        );
      });

      test('bold weight', () {
        expectEquivalent(
          const TextStyle(fontWeight: FontWeight.bold),
          label: 'bold',
        );
      });

      test('dim weight', () {
        expectEquivalent(
          const TextStyle(fontWeight: FontWeight.dim),
          label: 'dim',
        );
      });

      test('italic', () {
        expectEquivalent(
          const TextStyle(fontStyle: FontStyle.italic),
          label: 'italic',
        );
      });

      test('underline only', () {
        expectEquivalent(
          const TextStyle(decoration: TextDecoration.underline),
          label: 'underline',
        );
      });

      test('line-through only', () {
        expectEquivalent(
          const TextStyle(decoration: TextDecoration.lineThrough),
          label: 'line-through',
        );
      });

      test('overline only', () {
        expectEquivalent(
          const TextStyle(decoration: TextDecoration.overline),
          label: 'overline',
        );
      });

      test('underline + line-through (combined decoration)', () {
        expectEquivalent(
          TextStyle(
            decoration: TextDecoration.combine(
              const [TextDecoration.underline, TextDecoration.lineThrough],
            ),
          ),
          label: 'underline+lineThrough',
        );
      });

      test('all three decorations combined', () {
        expectEquivalent(
          TextStyle(
            decoration: TextDecoration.combine(
              const [
                TextDecoration.underline,
                TextDecoration.lineThrough,
                TextDecoration.overline,
              ],
            ),
          ),
          label: 'underline+lineThrough+overline',
        );
      });

      test('reverse', () {
        expectEquivalent(
          const TextStyle(reverse: true),
          label: 'reverse',
        );
      });

      test('kitchen sink — every field set', () {
        expectEquivalent(
          TextStyle(
            color: const Color.fromRGB(231, 97, 112),
            backgroundColor: const Color.fromRGB(255, 0, 0), // exact-256
            fontWeight: FontWeight.bold,
            fontStyle: FontStyle.italic,
            decoration: TextDecoration.combine(
              const [TextDecoration.underline, TextDecoration.overline],
            ),
            reverse: true,
          ),
          label: 'kitchen sink',
        );
      });
    });

    group('256-color fallback (truecolor unsupported)', () {
      setUp(() => setSupportsTruecolorForTesting(false));

      test('arbitrary RGB quantizes to nearest palette index', () {
        expectEquivalent(
          const TextStyle(color: Color.fromRGB(231, 97, 112)),
          label: 'fg quantized',
        );
      });

      test('grayscale color', () {
        expectEquivalent(
          const TextStyle(backgroundColor: Color.fromRGB(128, 128, 128)),
          label: 'bg gray quantized',
        );
      });

      test('default color stays as default-fg/bg', () {
        expectEquivalent(
          const TextStyle(
            color: Color.defaultColor,
            backgroundColor: Color.defaultColor,
          ),
          label: 'both default',
        );
      });
    });
  });
}

String _describe(Uint8List bytes) {
  if (bytes.isEmpty) return '<empty>';
  final buf = StringBuffer();
  for (final b in bytes) {
    if (b == 0x1b) {
      buf.write(r'\x1b');
    } else if (b >= 0x20 && b < 0x7f) {
      buf.writeCharCode(b);
    } else {
      buf.write('\\x${b.toRadixString(16).padLeft(2, '0')}');
    }
  }
  return buf.toString();
}
