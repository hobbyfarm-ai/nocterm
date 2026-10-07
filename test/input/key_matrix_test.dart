import 'dart:convert';
import 'dart:math';

import 'package:nocterm/src/keyboard/input_event.dart';
import 'package:nocterm/src/keyboard/input_parser.dart';
import 'package:nocterm/src/keyboard/keyboard_event.dart';
import 'package:nocterm/src/keyboard/logical_key.dart';
import 'package:test/test.dart';

/// A byte sequence paired with the single key event it must decode to.
class KeyCase {
  const KeyCase(
    this.label,
    this.bytes,
    this.key, {
    this.modifiers = const ModifierKeys(),
    this.character,
  });

  final String label;
  final List<int> bytes;
  final LogicalKey key;
  final ModifierKeys modifiers;
  final String? character;

  KeyCase withMetaPrefix() => KeyCase(
        'ESC $label',
        [0x1b, ...bytes],
        key,
        modifiers: modifiers.copyWith(alt: true),
        character: character,
      );
}

const esc = 0x1b;
const sentinel = 0x7a; // 'z'

List<int> seq(String text) => latin1.encode(text);

/// xterm/kitty encode modifiers as 1 + bitmask.
ModifierKeys modsFor(int value) => ModifierKeys(
      shift: (value - 1) & 1 != 0,
      alt: (value - 1) & 2 != 0,
      ctrl: (value - 1) & 4 != 0,
      meta: (value - 1) & 8 != 0,
    );

const cursorKeys = {
  'A': LogicalKey.arrowUp,
  'B': LogicalKey.arrowDown,
  'C': LogicalKey.arrowRight,
  'D': LogicalKey.arrowLeft,
  'H': LogicalKey.home,
  'F': LogicalKey.end,
};

const tildeKeys = {
  '2': LogicalKey.insert,
  '3': LogicalKey.delete,
  '5': LogicalKey.pageUp,
  '6': LogicalKey.pageDown,
  '15': LogicalKey.f5,
  '17': LogicalKey.f6,
  '18': LogicalKey.f7,
  '19': LogicalKey.f8,
  '20': LogicalKey.f9,
  '21': LogicalKey.f10,
  '23': LogicalKey.f11,
  '24': LogicalKey.f12,
};

const ss3FunctionKeys = {
  'P': LogicalKey.f1,
  'Q': LogicalKey.f2,
  'R': LogicalKey.f3,
  'S': LogicalKey.f4,
};

const modifierValues = [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16];

/// Codepoints the kitty / modifyOtherKeys paths special-case, plus plain ones.
const protocolCodepoints = [97, 65, 32, 13, 9, 27, 127];

KeyCase codepointCase(String label, List<int> bytes, int cp, ModifierKeys m) {
  return switch (cp) {
    13 =>
      KeyCase(label, bytes, LogicalKey.enter, modifiers: m, character: '\n'),
    9 => KeyCase(label, bytes, LogicalKey.tab, modifiers: m, character: '\t'),
    27 => KeyCase(label, bytes, LogicalKey.escape, modifiers: m),
    127 => KeyCase(label, bytes, LogicalKey.backspace, modifiers: m),
    _ => KeyCase(
        label,
        bytes,
        LogicalKey.fromCharacter(String.fromCharCode(cp))!,
        modifiers: m,
        character: String.fromCharCode(cp),
      ),
  };
}

List<KeyCase> buildMatrix() {
  final cases = <KeyCase>[];

  for (final entry in cursorKeys.entries) {
    final f = entry.key;
    final key = entry.value;
    final plainCsi = KeyCase('CSI $f', seq('\x1b[$f'), key);
    final plainSs3 = KeyCase('SS3 $f', seq('\x1bO$f'), key);
    cases.addAll([
      plainCsi,
      plainCsi.withMetaPrefix(),
      plainSs3,
      plainSs3.withMetaPrefix(),
    ]);
    for (final m in modifierValues) {
      final modified = KeyCase('CSI 1;$m $f', seq('\x1b[1;$m$f'), key,
          modifiers: modsFor(m));
      cases.addAll([modified, modified.withMetaPrefix()]);
    }
  }

  for (final entry in tildeKeys.entries) {
    final n = entry.key;
    final key = entry.value;
    final plain = KeyCase('CSI $n~', seq('\x1b[$n~'), key);
    cases.addAll([plain, plain.withMetaPrefix()]);
    for (final m in modifierValues) {
      final modified =
          KeyCase('CSI $n;$m~', seq('\x1b[$n;$m~'), key, modifiers: modsFor(m));
      cases.addAll([modified, modified.withMetaPrefix()]);
    }
  }

  for (final entry in ss3FunctionKeys.entries) {
    final plain =
        KeyCase('SS3 ${entry.key}', seq('\x1bO${entry.key}'), entry.value);
    cases.addAll([plain, plain.withMetaPrefix()]);
  }

  final shiftTab = KeyCase('CSI Z', seq('\x1b[Z'), LogicalKey.tab,
      modifiers: const ModifierKeys(shift: true));
  cases.addAll([shiftTab, shiftTab.withMetaPrefix()]);

  // Alt + every printable ASCII byte, except the CSI and SS3 introducers.
  for (var b = 0x20; b <= 0x7e; b++) {
    if (b == 0x5b || b == 0x4f) continue;
    final ch = String.fromCharCode(b);
    final isUpper = b >= 0x41 && b <= 0x5a;
    cases.add(KeyCase(
      'ESC ${ch == ' ' ? 'SP' : ch}',
      [esc, b],
      LogicalKey.fromCharacter(ch) ?? LogicalKey(b, 'unknown'),
      modifiers: ModifierKeys(alt: true, shift: isUpper),
      character: ch,
    ));
  }
  cases.add(KeyCase('ESC DEL', [esc, 0x7f], LogicalKey.backspace,
      modifiers: const ModifierKeys(alt: true)));

  // Ctrl + letters, minus the bytes that double as Tab/Enter/Backspace.
  for (var b = 0x01; b <= 0x1a; b++) {
    if (b == 0x08 || b == 0x09 || b == 0x0a || b == 0x0d) continue;
    final letter = String.fromCharCode(b + 0x40).toLowerCase();
    cases.add(KeyCase('Ctrl+$letter', [b], LogicalKey.fromCharacter(letter)!,
        modifiers: const ModifierKeys(ctrl: true)));
  }
  cases.addAll([
    const KeyCase('TAB', [0x09], LogicalKey.tab, character: '\t'),
    const KeyCase('CR', [0x0d], LogicalKey.enter, character: '\n'),
    const KeyCase('LF', [0x0a], LogicalKey.enter, character: '\n'),
    const KeyCase('BS', [0x08], LogicalKey.backspace),
    const KeyCase('DEL', [0x7f], LogicalKey.backspace),
    const KeyCase('FS', [0x1c], LogicalKey.backslash,
        modifiers: ModifierKeys(ctrl: true)),
  ]);

  for (final cp in protocolCodepoints) {
    for (final m in [1, ...modifierValues]) {
      cases.add(codepointCase(
          'kitty $cp;$m u', seq('\x1b[$cp;${m}u'), cp, modsFor(m)));
    }
    for (final m in modifierValues) {
      cases.add(codepointCase(
          'MOK 27;$m;$cp~', seq('\x1b[27;$m;$cp~'), cp, modsFor(m)));
    }
  }

  return cases;
}

List<KeyboardEvent> drainKeys(InputParser parser) {
  final out = <KeyboardEvent>[];
  InputEvent? event;
  while ((event = parser.parseNext()) != null) {
    expect(event, isA<KeyboardInputEvent>());
    out.add((event! as KeyboardInputEvent).event);
  }
  return out;
}

void expectMatches(KeyboardEvent event, KeyCase c, String reason) {
  expect(event.logicalKey, equals(c.key), reason: '$reason: key');
  expect(event.modifiers, equals(c.modifiers), reason: '$reason: modifiers');
  expect(event.character, equals(c.character), reason: '$reason: character');
}

void expectSentinel(KeyboardEvent event, String reason) {
  expect(event.logicalKey, equals(LogicalKey.keyZ),
      reason: '$reason: sentinel');
  expect(event.modifiers, equals(const ModifierKeys()),
      reason: '$reason: sentinel modifiers');
  expect(event.character, equals('z'), reason: '$reason: sentinel char');
}

/// Feeds [c] via [feed], then a plain sentinel key, and checks the parser
/// decoded exactly the expected event, the sentinel, and nothing else.
void verifyCase(
    KeyCase c, String strategy, void Function(InputParser, List<int>) feed) {
  final parser = InputParser();
  feed(parser, c.bytes);
  final events = drainKeys(parser);
  expect(events, hasLength(1), reason: '${c.label} [$strategy]: event count');
  expectMatches(events.single, c, '${c.label} [$strategy]');
  expect(parser.hasPendingLoneEscape, isFalse,
      reason: '${c.label} [$strategy]: lone ESC left pending');

  parser.addBytes([sentinel]);
  final after = drainKeys(parser);
  expect(after, hasLength(1), reason: '${c.label} [$strategy]: after count');
  expectSentinel(after.single, '${c.label} [$strategy]');
  expect(parser.parseNext(), isNull);
}

void main() {
  final matrix = buildMatrix();

  group('key matrix (${matrix.length} sequences)', () {
    test('labels are unique', () {
      final labels = matrix.map((c) => c.label).toSet();
      expect(labels, hasLength(matrix.length));
    });

    test('each sequence in one chunk decodes to one sane key', () {
      for (final c in matrix) {
        verifyCase(c, 'chunk', (p, b) => p.addBytes(b));
      }
    });

    test('each sequence byte-by-byte decodes identically', () {
      for (final c in matrix) {
        verifyCase(c, 'bytes', (p, b) {
          for (final byte in b) {
            p.addBytes([byte]);
          }
        });
      }
    });

    test('sequence and sentinel in the same chunk', () {
      for (final c in matrix) {
        final parser = InputParser()..addBytes([...c.bytes, sentinel]);
        final events = drainKeys(parser);
        expect(events, hasLength(2), reason: '${c.label}: count');
        expectMatches(events[0], c, c.label);
        expectSentinel(events[1], c.label);
      }
    });

    test('every sequence back to back, split at random chunk boundaries', () {
      final stream = <int>[];
      for (final c in matrix) {
        stream.addAll(c.bytes);
        stream.add(sentinel);
      }
      final random = Random(0x6b6579);
      for (var round = 0; round < 25; round++) {
        final parser = InputParser();
        var offset = 0;
        while (offset < stream.length) {
          final size = 1 + random.nextInt(7);
          final end = min(offset + size, stream.length);
          parser.addBytes(stream.sublist(offset, end));
          offset = end;
        }
        final events = drainKeys(parser);
        expect(events, hasLength(matrix.length * 2),
            reason: 'round $round: event count');
        for (var i = 0; i < matrix.length; i++) {
          expectMatches(
              events[2 * i], matrix[i], 'round $round ${matrix[i].label}');
          expectSentinel(events[2 * i + 1], 'round $round ${matrix[i].label}');
        }
        expect(parser.hasPendingLoneEscape, isFalse);
      }
    });

    test('a Meta-prefixed sequence that aborts leaves no stale Alt', () {
      for (final c in matrix.where((c) => c.bytes.length > 2)) {
        final truncated = c.bytes.sublist(0, c.bytes.length - 1);
        final parser = InputParser()
          ..addBytes([esc, ...truncated, ...seq('\x1b[A'), sentinel]);
        final events = drainKeys(parser);
        expect(events.last.character, equals('z'), reason: c.label);
        expect(events.last.modifiers, equals(const ModifierKeys()),
            reason: '${c.label}: stale modifiers on sentinel');
        expect(parser.hasPendingLoneEscape, isFalse, reason: c.label);
      }
    });
  });
}
