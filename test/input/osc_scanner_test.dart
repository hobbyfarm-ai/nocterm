import 'dart:convert';

import 'package:nocterm/src/keyboard/osc_scanner.dart';
import 'package:test/test.dart';

void main() {
  group('OscScanner', () {
    (OscScanner, List<String>) makeScanner() {
      final oscs = <String>[];
      final scanner = OscScanner(onOsc: (c) => oscs.add(utf8.decode(c)));
      return (scanner, oscs);
    }

    test('extracts a complete BEL-terminated OSC and passes other bytes on',
        () {
      final (scanner, oscs) = makeScanner();
      final bytes = [
        ...utf8.encode('ab'),
        ...utf8.encode('\x1b]11;rgb:1a/2b/3c\x07'),
        ...utf8.encode('cd'),
      ];
      final out = scanner.filter(bytes);
      expect(utf8.decode(out), equals('abcd'));
      expect(oscs, equals(['11;rgb:1a/2b/3c']));
    });

    test('extracts an ST-terminated OSC', () {
      final (scanner, oscs) = makeScanner();
      final out = scanner.filter(utf8.encode('\x1b]2;title\x1b\\x'));
      expect(utf8.decode(out), equals('x'));
      expect(oscs, equals(['2;title']));
    });

    test('holds a split OSC across chunks at every boundary', () {
      final stream = [
        ...utf8.encode('\x1b[<35;10;5M'),
        ...utf8.encode('\x1b]11;rgb:aa/bb/cc\x07'),
        ...utf8.encode('\x1b[<0;3;4M'),
      ];
      for (var split = 1; split < stream.length; split++) {
        final (scanner, oscs) = makeScanner();
        final out = <int>[
          ...scanner.filter(stream.sublist(0, split)),
          ...scanner.filter(stream.sublist(split)),
        ];
        expect(utf8.decode(out), equals('\x1b[<35;10;5M\x1b[<0;3;4M'),
            reason: 'split at $split leaked or ate bytes');
        expect(oscs, equals(['11;rgb:aa/bb/cc']),
            reason: 'split at $split broke OSC extraction');
      }
    });

    test('split ST terminator (ESC in one chunk, backslash in the next)', () {
      final (scanner, oscs) = makeScanner();
      final out = <int>[
        ...scanner.filter(utf8.encode('\x1b]0;t\x1b')),
        ...scanner.filter(utf8.encode('\\z')),
      ];
      expect(utf8.decode(out), equals('z'));
      expect(oscs, equals(['0;t']));
    });

    test('chunk-final ESC is held and resolved by the next chunk', () {
      // Next chunk starts a non-OSC sequence: ESC is released ahead of it.
      final (scanner, _) = makeScanner();
      expect(scanner.filter([0x1b]), equals(<int>[]));
      expect(scanner.hasPendingEsc, isTrue);
      expect(utf8.decode(scanner.filter(utf8.encode('[A'))), equals('\x1b[A'));
      expect(scanner.hasPendingEsc, isFalse);
    });

    test('chunk-final ESC followed by ] becomes an OSC', () {
      final (scanner, oscs) = makeScanner();
      expect(scanner.filter([0x1b]), equals(<int>[]));
      final out = scanner.filter(utf8.encode(']11;rgb:01/02/03\x07x'));
      expect(utf8.decode(out), equals('x'));
      expect(oscs, equals(['11;rgb:01/02/03']));
    });

    test('takePendingEsc releases a held ESC for Escape commit', () {
      final (scanner, _) = makeScanner();
      scanner.filter([0x1b]);
      expect(scanner.takePendingEsc(), equals([0x1b]));
      expect(scanner.hasPendingEsc, isFalse);
      expect(scanner.takePendingEsc(), equals(<int>[]));
    });

    test('ESC aborting an OSC hands the new sequence to the parser', () {
      final (scanner, oscs) = makeScanner();
      final out = scanner.filter(utf8.encode('\x1b]0;t\x1b[A'));
      expect(utf8.decode(out), equals('\x1b[A'));
      expect(oscs, equals(['0;t']));
    });
  });
}
