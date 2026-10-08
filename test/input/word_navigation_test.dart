import 'package:nocterm/src/text/word_navigation.dart';
import 'package:test/test.dart';

void main() {
  const readline = WordNavigation(WordJumpStyle.endOfWord);
  const windows = WordNavigation(WordJumpStyle.startOfNextWord);
  const text = 'foo_bar, baz.qux  éclair 世界 🎉 end';

  int at(String needle) => text.indexOf(needle);
  int after(String needle) => text.indexOf(needle) + needle.length;

  group('WordNavigation.isWordCharacter', () {
    test('letters, digits, and underscore are word characters', () {
      for (final char in ['a', 'Z', '5', '_', 'é', '世']) {
        expect(WordNavigation.isWordCharacter(char), isTrue, reason: char);
      }
    });

    test('whitespace, punctuation, and symbols separate words', () {
      for (final char in [' ', '\t', '\n', '.', ',', '-', "'", '/', '🎉']) {
        expect(WordNavigation.isWordCharacter(char), isFalse, reason: char);
      }
    });
  });

  group('previousStart (same in every style)', () {
    for (final nav in [readline, windows]) {
      test('${nav.jumpStyle}', () {
        expect(nav.previousStart(text, text.length), at('end'));
        expect(nav.previousStart(text, at('end')), at('世界'));
        expect(nav.previousStart(text, after('baz')), at('baz'));
        expect(nav.previousStart(text, at('baz') + 1), at('baz'));
        expect(nav.previousStart(text, at('baz')), at('foo_bar'));
        expect(nav.previousStart(text, 0), 0);
      });
    }
  });

  group('nextStop', () {
    test('end of word stops after the current or next word', () {
      expect(readline.nextStop(text, 0), after('foo_bar'));
      expect(readline.nextStop(text, after('foo_bar')), after('baz'));
      expect(readline.nextStop(text, after('baz')), after('qux'));
      expect(readline.nextStop(text, after('qux')), after('éclair'));
      expect(readline.nextStop(text, after('世界')), text.length);
      expect(readline.nextStop(text, text.length), text.length);
    });

    test('start of next word skips the separators that follow', () {
      expect(windows.nextStop(text, 0), at('baz'));
      expect(windows.nextStop(text, at('baz')), at('qux'));
      expect(windows.nextStop(text, at('qux')), at('éclair'));
      expect(windows.nextStop(text, at('世界')), at('end'));
      expect(windows.nextStop(text, at('end')), text.length);
      expect(windows.nextStop(text, text.length), text.length);
    });
  });

  group('jump', () {
    test('negative direction is previousStart, positive is nextStop', () {
      expect(readline.jump(text, at('qux'), -1), at('baz'));
      expect(readline.jump(text, at('qux'), 1), after('qux'));
      expect(windows.jump(text, at('qux'), 1), at('éclair'));
    });
  });

  group('rangeAt', () {
    test('bounds the word spanning the offset', () {
      expect(WordNavigation.rangeAt(text, at('qux') + 1),
          WordRange(at('qux'), after('qux')));
    });

    test('a whitespace run is one unit', () {
      final gap = after('qux');
      expect(WordNavigation.rangeAt(text, gap), WordRange(gap, gap + 2));
      expect(WordNavigation.rangeAt(text, gap + 1), WordRange(gap, gap + 2));
    });

    test('a punctuation run is one unit', () {
      expect(WordNavigation.rangeAt('a, ;b', 1), const WordRange(1, 2));
      expect(WordNavigation.rangeAt('a,;.b', 2), const WordRange(1, 4));
    });

    test('the offset just after a word is the separator, not the word', () {
      expect(WordNavigation.rangeAt(text, after('baz')),
          WordRange(after('baz'), at('qux')));
    });

    test('offsets are clamped onto the text', () {
      expect(WordNavigation.rangeAt(text, text.length + 5),
          WordRange(at('end'), text.length));
      expect(WordNavigation.rangeAt(text, -3), WordRange(0, after('foo_bar')));
    });

    test('empty text yields an empty range', () {
      expect(WordNavigation.rangeAt('', 3), const WordRange(0, 0));
      expect(WordNavigation.rangeAt('', 3).isEmpty, isTrue);
    });
  });

  group('offsets are clamped', () {
    test('out-of-range offsets never throw', () {
      expect(readline.previousStart(text, -5), 0);
      expect(readline.nextStop(text, text.length + 5), text.length);
      expect(readline.nextStop('', 0), 0);
    });
  });

  group('invariants over every offset', () {
    for (final nav in [readline, windows]) {
      test('${nav.jumpStyle}: forward always advances, back always retreats',
          () {
        for (var offset = 0; offset <= text.length; offset++) {
          final forward = nav.nextStop(text, offset);
          final back = nav.previousStart(text, offset);
          expect(forward, offset == text.length ? offset : greaterThan(offset),
              reason: 'forward from $offset');
          expect(back, offset == 0 ? 0 : lessThan(offset),
              reason: 'back from $offset');
        }
      });

      test(
          '${nav.jumpStyle}: from inside a word, forward then back never '
          'passes that word\'s start', () {
        for (var offset = 0; offset < text.length; offset++) {
          if (!WordNavigation.isWordCharacter(text[offset])) continue;
          final roundTrip = nav.previousStart(text, nav.nextStop(text, offset));
          expect(roundTrip, lessThanOrEqualTo(offset), reason: 'from $offset');
        }
      });
    }
  });
}
