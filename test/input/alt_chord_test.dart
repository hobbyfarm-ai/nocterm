import 'dart:convert';

import 'package:nocterm/src/keyboard/input_event.dart';
import 'package:nocterm/src/keyboard/input_parser.dart';
import 'package:nocterm/src/keyboard/keyboard_event.dart';
import 'package:nocterm/src/keyboard/logical_key.dart';
import 'package:test/test.dart';

List<KeyboardEvent> keys(InputParser parser) {
  final out = <KeyboardEvent>[];
  InputEvent? event;
  while ((event = parser.parseNext()) != null) {
    if (event is KeyboardInputEvent) out.add(event.event);
  }
  return out;
}

List<KeyboardEvent> parse(String bytes) =>
    keys(InputParser()..addBytes(latin1.encode(bytes)));

void expectKey(
  KeyboardEvent event,
  LogicalKey key, {
  bool alt = false,
  bool shift = false,
  bool ctrl = false,
  String? character,
}) {
  expect(event.logicalKey, equals(key));
  expect(event.modifiers,
      equals(ModifierKeys(alt: alt, shift: shift, ctrl: ctrl)));
  expect(event.character, equals(character));
}

void main() {
  group('ESC-prefixed Alt chords (macOS Terminal "Option as Meta")', () {
    test('ESC b / ESC f are Alt+B / Alt+F', () {
      final events = parse('\x1bb\x1bf');
      expect(events, hasLength(2));
      expectKey(events[0], LogicalKey.keyB, alt: true, character: 'b');
      expectKey(events[1], LogicalKey.keyF, alt: true, character: 'f');
    });

    test('ESC DEL is Alt+Backspace, not Escape then Backspace', () {
      final events = parse('\x1b\x7f');
      expect(events, hasLength(1));
      expectKey(events[0], LogicalKey.backspace, alt: true);
    });

    test('ESC + uppercase is Alt+Shift+letter', () {
      final events = parse('\x1bB');
      expect(events, hasLength(1));
      expectKey(events[0], LogicalKey.keyB,
          alt: true, shift: true, character: 'B');
    });

    test('ESC + digit or punctuation is an Alt chord', () {
      final events = parse('\x1b1\x1b.');
      expect(events, hasLength(2));
      expect(events[0].character, equals('1'));
      expect(events[0].modifiers.alt, isTrue);
      expect(events[1].character, equals('.'));
      expect(events[1].modifiers.alt, isTrue);
    });
  });

  group('ESC ESC Meta prefix', () {
    test('ESC ESC [ D is Alt+Left, not Escape then Left', () {
      final events = parse('\x1b\x1b[D');
      expect(events, hasLength(1));
      expectKey(events[0], LogicalKey.arrowLeft, alt: true);
    });

    test('ESC ESC O C is Alt+Right in application cursor mode', () {
      final events = parse('\x1b\x1b' 'OC');
      expect(events, hasLength(1));
      expectKey(events[0], LogicalKey.arrowRight, alt: true);
    });

    test('ESC ESC [ 3 ~ is Alt+Delete', () {
      final events = parse('\x1b\x1b[3~');
      expect(events, hasLength(1));
      expectKey(events[0], LogicalKey.delete, alt: true);
    });

    test('Meta prefix combines with xterm modifier params', () {
      final events = parse('\x1b\x1b[1;2D');
      expect(events, hasLength(1));
      expectKey(events[0], LogicalKey.arrowLeft, alt: true, shift: true);
    });

    test('Meta prefix does not leak into the following key', () {
      final events = parse('\x1b\x1b[Da');
      expect(events, hasLength(2));
      expectKey(events[0], LogicalKey.arrowLeft, alt: true);
      expectKey(events[1], LogicalKey.keyA, character: 'a');
    });

    test('Meta prefix is dropped when the sequence aborts', () {
      final events = parse('\x1b\x1b[1;\x1b[A');
      expect(events, hasLength(1));
      expectKey(events[0], LogicalKey.arrowUp);
    });

    test('ESC ESC x is Escape then Alt+X', () {
      final events = parse('\x1b\x1bx');
      expect(events, hasLength(2));
      expectKey(events[0], LogicalKey.escape);
      expectKey(events[1], LogicalKey.keyX, alt: true, character: 'x');
    });

    test('ESC ESC then Enter is two Escapes then Enter', () {
      final events = parse('\x1b\x1b\r');
      expect(events.map((e) => e.logicalKey),
          equals([LogicalKey.escape, LogicalKey.escape, LogicalKey.enter]));
    });

    test('ESC ESC alone is held and flushes as two Escapes', () {
      final parser = InputParser()..addBytes([0x1b, 0x1b]);
      expect(keys(parser), isEmpty);
      expect(parser.hasPendingLoneEscape, isTrue);
      final flushed = parser.flushLoneEscape();
      expect(flushed.map((e) => e.logicalKey),
          equals([LogicalKey.escape, LogicalKey.escape]));
      expect(parser.hasPendingLoneEscape, isFalse);
    });

    test('ESC ESC split across chunks still yields Alt+Left', () {
      final parser = InputParser()
        ..addBytes([0x1b])
        ..addBytes([0x1b])
        ..addBytes(latin1.encode('[D'));
      final events = keys(parser);
      expect(events, hasLength(1));
      expectKey(events[0], LogicalKey.arrowLeft, alt: true);
    });
  });

  group('SS3 cursor keys', () {
    test('ESC O D is Left in application cursor mode', () {
      final events = parse('\x1bOD\x1bOH\x1bOF');
      expect(events.map((e) => e.logicalKey),
          equals([LogicalKey.arrowLeft, LogicalKey.home, LogicalKey.end]));
    });
  });
}
