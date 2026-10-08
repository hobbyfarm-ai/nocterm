import 'package:nocterm/nocterm.dart';
import 'package:test/test.dart';

void main() {
  group('DoubleClickDetector', () {
    late DateTime now;
    late DoubleClickDetector detector;

    setUp(() {
      now = DateTime(2026, 1, 1);
      detector = DoubleClickDetector(now: () => now);
    });

    test('a first press is never a double click', () {
      expect(detector.press(const Offset(3, 2)), isFalse);
    });

    test('a second press within the window on the same cell completes one', () {
      detector.press(const Offset(3, 2));
      now = now.add(const Duration(milliseconds: 100));
      expect(detector.press(const Offset(3, 2)), isTrue);
    });

    test('a second press one column over still counts', () {
      detector.press(const Offset(3, 2));
      expect(detector.press(const Offset(4, 2)), isTrue);
    });

    test('a second press on another row does not count', () {
      detector.press(const Offset(3, 2));
      expect(detector.press(const Offset(3, 3)), isFalse);
    });

    test('a second press beyond the column tolerance does not count', () {
      detector.press(const Offset(3, 2));
      expect(detector.press(const Offset(5, 2)), isFalse);
    });

    test('a second press after the window does not count', () {
      detector.press(const Offset(3, 2));
      now = now.add(const Duration(milliseconds: 400));
      expect(detector.press(const Offset(3, 2)), isFalse);
    });

    test('the press that completes a double click starts nothing', () {
      detector.press(const Offset(3, 2));
      detector.press(const Offset(3, 2));
      expect(detector.press(const Offset(3, 2)), isFalse);
      expect(detector.press(const Offset(3, 2)), isTrue);
    });

    test('a missed press becomes the new first press', () {
      detector.press(const Offset(3, 2));
      detector.press(const Offset(9, 2));
      expect(detector.press(const Offset(9, 2)), isTrue);
    });
  });
}
