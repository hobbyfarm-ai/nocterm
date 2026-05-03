import 'package:nocterm/nocterm.dart';
import 'package:nocterm/src/utils/terminal_color_support.dart';
import 'package:test/test.dart';

void main() {
  group('Color ANSI fallback', () {
    tearDown(() => setSupportsTruecolorForTesting(null));

    test('uses 24-bit ANSI when truecolor is supported', () {
      setSupportsTruecolorForTesting(true);

      // (231, 97, 112) is not on the xterm-256 cube/ramp, so the renderer
      // falls through to the 24-bit truecolor encoding.
      const color = Color.fromRGB(231, 97, 112);
      expect(color.toAnsi(), equals('\x1b[38;2;231;97;112m'));
      expect(
          color.toAnsi(background: true), equals('\x1b[48;2;231;97;112m'));
    });

    test('prefers shorter 256-color SGR for exact palette matches', () {
      setSupportsTruecolorForTesting(true);

      // (255, 0, 0) is xterm-256 cube index 196 — emit the shorter form.
      const color = Color.fromRGB(255, 0, 0);
      expect(color.toAnsi(), equals('\x1b[38;5;196m'));
      expect(color.toAnsi(background: true), equals('\x1b[48;5;196m'));
    });

    test('uses 256-color ANSI when truecolor is not supported', () {
      setSupportsTruecolorForTesting(false);

      const color = Color.fromRGB(255, 0, 0);
      expect(color.toAnsi(), equals('\x1b[38;5;196m'));
      expect(color.toAnsi(background: true), equals('\x1b[48;5;196m'));
    });

    test('grayscale maps to xterm grayscale ramp', () {
      setSupportsTruecolorForTesting(false);

      const gray = Color.fromRGB(128, 128, 128);
      expect(gray.toAnsi(), equals('\x1b[38;5;244m'));
    });
  });
}
