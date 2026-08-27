import 'package:nocterm/nocterm.dart';
import 'package:test/test.dart';

void main() {
  tearDown(() => UnicodeWidth.setMethodForTesting(null));

  group('WidthMethod.legacy', () {
    setUp(() => UnicodeWidth.setMethodForTesting(WidthMethod.legacy));

    test('sums per-codepoint widths of a cluster', () {
      expect(UnicodeWidth.graphemeWidth('👍🏽'), 4); // emoji + skin tone
      expect(UnicodeWidth.graphemeWidth('🇺🇸'), 4); // regional indicator pair
      expect(UnicodeWidth.graphemeWidth('👮‍♂️'), 3); // ZWJ sequence
    });

    test('VS16 narrow base stays width 1', () {
      expect(UnicodeWidth.graphemeWidth('❤️'), 1);
    });

    test('single code points match grapheme mode', () {
      expect(UnicodeWidth.graphemeWidth('中'), 2);
      expect(UnicodeWidth.graphemeWidth('a'), 1);
      expect(UnicodeWidth.graphemeWidth('😀'), 2);
      expect(UnicodeWidth.graphemeWidth('é'), 1); // e + combining acute
      expect(UnicodeWidth.graphemeWidth('\t'), 1);
    });
  });

  group('grapheme mode (default)', () {
    test('clusters are a single width', () {
      expect(UnicodeWidth.graphemeWidth('👍🏽'), 2);
      expect(UnicodeWidth.graphemeWidth('🇺🇸'), 2);
      expect(UnicodeWidth.graphemeWidth('❤️'), 2);
    });
  });

  group('Buffer.setString markers', () {
    test('a legacy width-4 cluster fills three continuation cells', () {
      UnicodeWidth.setMethodForTesting(WidthMethod.legacy);
      final buffer = Buffer(10, 1)..setString(0, 0, '👍🏽');
      expect(buffer.getCell(0, 0).char, '👍🏽');
      expect(buffer.getCell(1, 0).char, '​');
      expect(buffer.getCell(2, 0).char, '​');
      expect(buffer.getCell(3, 0).char, '​');
      expect(buffer.getCell(4, 0).char, ' ');
    });

    test('a grapheme width-2 cluster fills one continuation cell', () {
      final buffer = Buffer(10, 1)..setString(0, 0, '👍🏽');
      expect(buffer.getCell(1, 0).char, '​');
      expect(buffer.getCell(2, 0).char, ' ');
    });

    test('a cluster that would overflow the row is dropped', () {
      UnicodeWidth.setMethodForTesting(WidthMethod.legacy);
      final buffer = Buffer(3, 1)..setString(0, 0, '👍🏽');
      expect(buffer.getCell(0, 0).char, ' ');
    });
  });

  group('Cell.isMultiCodePoint', () {
    test('distinguishes clusters from single code points', () {
      expect(Cell(char: '👍🏽').isMultiCodePoint, isTrue);
      expect(Cell(char: '❤️').isMultiCodePoint, isTrue);
      expect(Cell(char: 'a').isMultiCodePoint, isFalse);
      expect(Cell(char: '中').isMultiCodePoint, isFalse);
      expect(Cell(char: '😀').isMultiCodePoint, isFalse);
    });
  });
}
