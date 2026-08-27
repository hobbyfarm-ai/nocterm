import 'package:nocterm/nocterm.dart';
import 'package:nocterm/src/binding/width_probe.dart';
import 'package:test/test.dart';

void main() {
  group('classifyWidthMethod', () {
    // Probe order: 👍🏽, ❤️, 🇺🇸, 中.
    const graphemeAdvances = [2, 2, 2, 2];
    const legacyAdvances = [4, 1, 4, 2];

    test('all-clustered advances → grapheme', () {
      expect(classifyWidthMethod(graphemeAdvances, {}), WidthMethod.grapheme);
    });

    test('per-codepoint advances → legacy', () {
      expect(classifyWidthMethod(legacyAdvances, {}), WidthMethod.legacy);
    });

    test('null (no reply) falls back to env hint', () {
      expect(classifyWidthMethod(null, {}), WidthMethod.grapheme);
      expect(
        classifyWidthMethod(null, {'TERM_PROGRAM': 'Apple_Terminal'}),
        WidthMethod.legacy,
      );
    });

    test('incoherent anchor (CJK != 2) falls back to env hint', () {
      expect(classifyWidthMethod([2, 2, 2, 1], {}), WidthMethod.grapheme);
      expect(
        classifyWidthMethod(
          [2, 2, 2, 1],
          {'TERM_PROGRAM': 'Apple_Terminal'},
        ),
        WidthMethod.legacy,
      );
    });

    test('mixed clustering resolves by majority', () {
      // 3 grapheme-shaped, anchor ok: leans grapheme.
      expect(classifyWidthMethod([2, 2, 4, 2], {}), WidthMethod.grapheme);
      // 3 legacy-shaped, anchor ok: leans legacy.
      expect(classifyWidthMethod([4, 1, 2, 2], {}), WidthMethod.legacy);
    });

    test('wrong-length advances fall back', () {
      expect(classifyWidthMethod([2, 2], {}), WidthMethod.grapheme);
    });
  });
}
