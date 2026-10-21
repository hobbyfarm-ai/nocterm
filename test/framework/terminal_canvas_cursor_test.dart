import 'package:nocterm/nocterm.dart';
import 'package:test/test.dart';

void main() {
  group('TerminalCanvas.setCursor', () {
    test('lands in the buffer in screen coordinates', () {
      final buffer = Buffer(10, 4);
      TerminalCanvas(buffer, const Rect.fromLTWH(0, 0, 10, 4))
          .clip(const Rect.fromLTWH(2, 1, 5, 2))
          .setCursor(const Offset(1, 1), shape: CursorShape.bar);
      expect(
        buffer.cursor,
        const TerminalCursor(x: 3, y: 2, shape: CursorShape.bar),
      );
    });

    test('drops a cell outside the canvas area', () {
      final buffer = Buffer(10, 4);
      final canvas = TerminalCanvas(buffer, const Rect.fromLTWH(0, 0, 10, 4))
          .clip(const Rect.fromLTWH(2, 1, 5, 2));
      canvas.setCursor(const Offset(0, 2));
      expect(buffer.cursor, isNull);
      canvas.setCursor(const Offset(5, 0));
      expect(buffer.cursor, isNull);
      canvas.setCursor(const Offset(-1, 0));
      expect(buffer.cursor, isNull);
    });

    test('the last request in a frame wins', () {
      final buffer = Buffer(10, 4);
      final canvas = TerminalCanvas(buffer, const Rect.fromLTWH(0, 0, 10, 4));
      canvas.setCursor(const Offset(1, 1));
      canvas.setCursor(const Offset(4, 3), blinking: false);
      expect(buffer.cursor, const TerminalCursor(x: 4, y: 3, blinking: false));
      expect(buffer.cursor.toString(), 'TerminalCursor(4, 3, block)');
    });
  });
}
