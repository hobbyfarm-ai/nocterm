import 'package:nocterm/src/components/text_field/word_navigation.dart';
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

  group('wordStart / wordEnd', () {
    test('bound the word spanning the offset', () {
      expect(readline.wordStart(text, at('qux') + 1), at('qux'));
      expect(readline.wordEnd(text, at('qux') + 1), after('qux'));
    });

    test('collapse to the offset between two separators', () {
      final gap = after('qux') + 1;
      expect(readline.wordStart(text, gap), gap);
      expect(readline.wordEnd(text, gap), gap);
    });

    test('an offset just after a word still selects that word', () {
      expect(readline.wordStart(text, after('baz')), at('baz'));
      expect(readline.wordEnd(text, after('baz')), after('baz'));
    });
  });

  group('offsets are clamped', () {
    test('out-of-range offsets never throw', () {
      expect(readline.previousStart(text, -5), 0);
      expect(readline.nextStop(text, text.length + 5), text.length);
      expect(readline.wordStart('', 3), 0);
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
