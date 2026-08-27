import 'dart:convert';

import 'package:nocterm/src/keyboard/input_event.dart';
import 'package:nocterm/src/keyboard/input_parser.dart';
import 'package:test/test.dart';

List<InputEvent> drainEvents(InputParser parser) {
  final out = <InputEvent>[];
  InputEvent? event;
  while ((event = parser.parseNext()) != null) {
    out.add(event!);
  }
  return out;
}

void main() {
  group('cursor position report', () {
    test('parses CSI row;col R into a CursorPositionReport', () {
      final parser = InputParser()..addBytes(utf8.encode('\x1b[12;34R'));
      final events = drainEvents(parser);
      expect(events, hasLength(1));
      final report = events.single as CursorPositionReport;
      expect(report.row, 12);
      expect(report.col, 34);
    });

    test('emits no keyboard event', () {
      final parser = InputParser()..addBytes(utf8.encode('\x1b[1;5R'));
      final events = drainEvents(parser);
      expect(events.whereType<KeyboardInputEvent>(), isEmpty);
    });

    test('tolerates the DECXCPR ? prefix', () {
      final parser = InputParser()..addBytes(utf8.encode('\x1b[?9;80R'));
      final report = parser.parseNext() as CursorPositionReport;
      expect(report.row, 9);
      expect(report.col, 80);
    });

    test('ignores a malformed report', () {
      final parser = InputParser()..addBytes(utf8.encode('\x1b[R'));
      expect(parser.parseNext(), isNull);
    });

    test('survives chunk boundaries mid-sequence', () {
      final parser = InputParser()
        ..addBytes(utf8.encode('\x1b[12'))
        ..addBytes(utf8.encode(';34R'));
      final report = parser.parseNext() as CursorPositionReport;
      expect(report.row, 12);
      expect(report.col, 34);
    });
  });
}
