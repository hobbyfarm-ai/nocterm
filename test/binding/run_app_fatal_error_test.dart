import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:nocterm/nocterm.dart';
import 'package:test/test.dart' hide isEmpty, isNotEmpty;

class _RecordingBackend implements TerminalBackend {
  final output = StringBuffer();
  bool drainedAfterLastWrite = false;

  @override
  Future<void> drainOutput([
    Duration timeout = const Duration(seconds: 1),
  ]) async {
    drainedAfterLastWrite = true;
  }

  @override
  bool get isWriteInFlight => false;

  @override
  Stream<void>? get writeDrainedStream => null;

  @override
  void writeRaw(String data) {
    output.write(data);
    drainedAfterLastWrite = false;
  }

  @override
  void writeRawBytes(Uint8List bytes) {
    output.write(utf8.decode(bytes, allowMalformed: true));
    drainedAfterLastWrite = false;
  }

  @override
  Size getSize() => const Size(20, 5);

  @override
  bool get supportsSize => true;

  /// Throws when initialization attaches input handling.
  @override
  Stream<List<int>>? get inputStream => throw StateError('boom');

  @override
  Stream<Size>? get resizeStream => null;

  @override
  Stream<void>? get shutdownStream => null;

  @override
  void enableRawMode() {}

  @override
  void disableRawMode() {}

  @override
  bool get isAvailable => true;

  @override
  void notifySizeChanged(Size newSize) {}

  @override
  void requestExit([int exitCode = 0]) {}

  @override
  void dispose() {}
}

void main() {
  test(
    'runApp restores the terminal, reports the error, and rethrows '
    'when startup fails',
    () async {
      final backend = _RecordingBackend();

      await expectLater(
        runApp(
          const Text('unreachable'),
          backend: backend,
          enableHotReload: false,
        ),
        throwsA(
          isA<StateError>().having((e) => e.message, 'message', 'boom'),
        ),
      );

      final written = backend.output.toString();
      // Mouse tracking disabled and main buffer restored, so the terminal is
      // usable again.
      expect(written, contains('\x1B[?1000l'));
      expect(written, contains('\x1B[?1006l'));
      expect(written, contains('\x1b[?1049l'));
      // The failure is reported on the restored screen, after the cleanup
      // sequences.
      expect(
        written.indexOf('Unhandled error: Bad state: boom'),
        greaterThan(written.lastIndexOf('\x1b[?1049l')),
      );
      // Everything was drained to the terminal before rethrowing.
      expect(backend.drainedAfterLastWrite, isTrue);
    },
  );
}
