import 'dart:convert';

import 'package:nocterm/src/keyboard/input_event.dart';
import 'package:nocterm/src/keyboard/input_parser.dart';
import 'package:nocterm/src/keyboard/logical_key.dart';
import 'package:test/test.dart';

/// Drains all events, describing each compactly for equality checks.
List<String> drain(InputParser parser) {
  final out = <String>[];
  InputEvent? event;
  while ((event = parser.parseNext()) != null) {
    out.add(switch (event!) {
      KeyboardInputEvent(:final event) =>
        'key:${event.logicalKey.debugName}:${event.character}'
            ':${event.modifiers.shift}${event.modifiers.alt}'
            '${event.modifiers.ctrl}',
      MouseInputEvent(:final event) => 'mouse:${event.button}:${event.x},'
          '${event.y}:${event.pressed}:${event.isMotion}',
      PasteInputEvent(:final text) => 'paste:$text',
      _ => 'other',
    });
  }
  return out;
}

void main() {
  group('InputParser state machine', () {
    // A stream mixing everything: SGR mouse, arrows (plain + modified),
    // kitty, tilde keys, alt-chord, UTF-8 (2-4 byte), paste, plain text.
    final canonical = <int>[
      ...utf8.encode('\x1b[<35;10;5M'), // hover motion
      ...utf8.encode('\x1b[<0;3;4M'), // left press
      ...utf8.encode('\x1b[<32;4;4M'), // drag
      ...utf8.encode('\x1b[<0;4;4m'), // release
      ...utf8.encode('\x1b[A'), // arrow up
      ...utf8.encode('\x1b[1;5C'), // ctrl+right
      ...utf8.encode('\x1b[13;2u'), // kitty shift+enter
      ...utf8.encode('\x1b[3~'), // delete
      ...utf8.encode('\x1bx'), // alt+x
      ...utf8.encode('hé€🎉'), // 1,2,3,4-byte UTF-8
      ...utf8.encode('\x1b[200~pasted!\x1b[201~'), // bracketed paste
      ...utf8.encode('\x1b[M'), 32 + 0, 32 + 5, 32 + 7, // X10 left press
      ...utf8.encode('q'),
    ];

    test('canonical stream parses to the expected events', () {
      final parser = InputParser()..addBytes(canonical);
      final events = drain(parser);
      expect(events, hasLength(16));
      expect(events[0], startsWith('mouse:MouseButton.left:9,4:false:true'));
      expect(events[1], startsWith('mouse:MouseButton.left:2,3:true:false'));
      expect(events[4], contains('arrowUp'));
      expect(events[5], contains('arrowRight'));
      expect(events[5], endsWith('falsefalsetrue')); // ctrl
      expect(events[6], contains('enter'));
      expect(events[7], contains('delete'));
      expect(events[8], contains('keyX'));
      expect(events[9], startsWith('key:') /* h */);
      expect(events[10], contains('é'));
      expect(events[11], contains('€'));
      expect(events[12], contains('🎉'));
      expect(events[13], equals('paste:pasted!'));
      expect(events[14], startsWith('mouse:MouseButton.left:4,6:true'));
      expect(events[15], contains('keyQ'));
    });

    test('splitting the stream at every byte boundary yields identical events',
        () {
      final whole = InputParser()..addBytes(canonical);
      final expected = drain(whole);

      for (var split = 1; split < canonical.length; split++) {
        final parser = InputParser()
          ..addBytes(canonical.sublist(0, split))
          ..addBytes(canonical.sublist(split));
        expect(drain(parser), equals(expected),
            reason: 'split at byte $split changed the parse');
      }
    });

    test('ESC ] garbage cannot wedge the parser', () {
      // Simulates a leaked partial OSC: the parser must consume it and keep
      // parsing subsequent mouse events (regression: this used to stall
      // parseNext forever).
      final parser = InputParser()
        ..addBytes(utf8.encode('\x1b]11;rgb'))
        ..addBytes(utf8.encode('\x1b[<0;3;4M'));
      final events = drain(parser);
      expect(events.last, startsWith('mouse:MouseButton.left:2,3:true'));
    });

    test('ESC + uppercase with trailing bytes cannot wedge the parser', () {
      // Regression: ESC A with more bytes queued used to return null forever.
      final parser = InputParser()
        ..addBytes([0x1b, 0x41, ...utf8.encode('\x1b[<0;3;4M')]);
      final events = drain(parser);
      expect(events[0], contains('escape'));
      expect(events[1], contains('keyA'));
      expect(events.last, startsWith('mouse:MouseButton.left:2,3:true'));
    });

    test('ESC aborts a partial CSI and recovers', () {
      final parser = InputParser()
        ..addBytes(utf8.encode('\x1b[<35;10')) // truncated mouse sequence
        ..addBytes(utf8.encode('\x1b[B')); // fresh arrow-down
      final events = drain(parser);
      expect(events, hasLength(1));
      expect(events[0], contains('arrowDown'));
    });

    test('lone ESC defers and flushes on timeout', () {
      final parser = InputParser()..addBytes([0x1b]);
      expect(parser.parseNext(), isNull);
      expect(parser.hasPendingLoneEscape, isTrue);
      final escape = parser.flushLoneEscape();
      expect(escape?.logicalKey, equals(LogicalKey.escape));
      expect(parser.hasPendingLoneEscape, isFalse);
    });

    test('paste content split across many chunks', () {
      final bytes = utf8.encode('\x1b[200~line one\nline two\x1b[201~');
      for (var split = 1; split < bytes.length; split++) {
        final parser = InputParser()
          ..addBytes(bytes.sublist(0, split))
          ..addBytes(bytes.sublist(split));
        expect(drain(parser), equals(['paste:line one\nline two']),
            reason: 'split at byte $split broke paste');
      }
    });
  });
}
