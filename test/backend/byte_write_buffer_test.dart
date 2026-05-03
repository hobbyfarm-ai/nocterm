import 'dart:convert';
import 'dart:typed_data';

import 'package:nocterm/src/backend/byte_write_buffer.dart';
import 'package:test/test.dart';

void main() {
  group('ByteWriteBuffer', () {
    test('starts empty', () {
      final b = ByteWriteBuffer();
      expect(b.isEmpty, isTrue);
      expect(b.length, 0);
      expect(b.takeBytes(), isEmpty);
    });

    test('appends ASCII via fast path', () {
      final b = ByteWriteBuffer()..write('\x1b[38;2;255;100;50m');
      expect(b.length, 18);
      final out = b.takeBytes();
      expect(utf8.decode(out), '\x1b[38;2;255;100;50m');
      expect(b.isEmpty, isTrue, reason: 'takeBytes resets the buffer');
    });

    test('appends non-ASCII via utf8 fallback', () {
      final b = ByteWriteBuffer()..write('█');
      // U+2588 → 3 UTF-8 bytes
      expect(b.length, 3);
      expect(b.takeBytes(), Uint8List.fromList([0xE2, 0x96, 0x88]));
    });

    test('mixed ASCII and non-ASCII across calls', () {
      final b = ByteWriteBuffer()
        ..write('hello ')
        ..write('世界')
        ..write('!');
      expect(utf8.decode(b.takeBytes()), 'hello 世界!');
    });

    test('grows the backing buffer when needed', () {
      final b = ByteWriteBuffer(initialCapacity: 4);
      final long = 'A' * 1000;
      b.write(long);
      expect(b.length, 1000);
      expect(utf8.decode(b.takeBytes()), long);
    });

    test('clear discards without producing output', () {
      final b = ByteWriteBuffer()
        ..write('discard me')
        ..clear();
      expect(b.isEmpty, isTrue);
      expect(b.takeBytes(), isEmpty);
    });

    test('takeBytes returns a freshly-allocated copy', () {
      final b = ByteWriteBuffer()..write('hello');
      final first = b.takeBytes();
      b.write('world');
      final second = b.takeBytes();
      // Mutating one must not affect the other.
      expect(utf8.decode(first), 'hello');
      expect(utf8.decode(second), 'world');
    });

    test('write does nothing for an empty string', () {
      final b = ByteWriteBuffer()..write('');
      expect(b.isEmpty, isTrue);
    });
  });
}
