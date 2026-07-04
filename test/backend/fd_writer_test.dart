@TestOn('mac-os || linux')
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:nocterm/src/backend/fd_writer.dart';
import 'package:test/test.dart';

typedef _NativePipe = Int32 Function(Pointer<Int32>);
typedef _DartPipe = int Function(Pointer<Int32>);
typedef _NativeRead = IntPtr Function(Int32, Pointer<Uint8>, IntPtr);
typedef _DartRead = int Function(int, Pointer<Uint8>, int);
typedef _NativeClose = Int32 Function(Int32);
typedef _DartClose = int Function(int);

final _libc = DynamicLibrary.process();
final _pipe = _libc.lookupFunction<_NativePipe, _DartPipe>('pipe');
final _read = _libc.lookupFunction<_NativeRead, _DartRead>('read');
final _close = _libc.lookupFunction<_NativeClose, _DartClose>('close');

(int, int) _makePipe() {
  final fds = malloc.allocate<Int32>(2 * sizeOf<Int32>());
  try {
    if (_pipe(fds) != 0) throw StateError('pipe() failed');
    return (fds[0], fds[1]);
  } finally {
    malloc.free(fds);
  }
}

Uint8List _readExactly(int fd, int count) {
  final result = Uint8List(count);
  final buf = malloc.allocate<Uint8>(count);
  try {
    var total = 0;
    while (total < count) {
      final n = _read(fd, buf + total, count - total);
      if (n <= 0) throw StateError('read() failed after $total bytes');
      total += n;
    }
    result.setAll(0, buf.asTypedList(count));
    return result;
  } finally {
    malloc.free(buf);
  }
}

void _drainMain(List<int> args) {
  final read =
      DynamicLibrary.process().lookupFunction<_NativeRead, _DartRead>('read');
  final fd = args[0];
  final atLeast = args[1];
  final buf = malloc.allocate<Uint8>(64 * 1024);
  var total = 0;
  while (total < atLeast) {
    final n = read(fd, buf, 64 * 1024);
    if (n <= 0) break;
    total += n;
  }
  malloc.free(buf);
}

void main() {
  group('FdWriter', () {
    test('writes payloads to the fd in submission order', () async {
      final (readFd, writeFd) = _makePipe();
      final writer = FdWriter(fd: writeFd);
      await writer.start();
      expect(writer.isRunning, isTrue);

      final onDrained = writer.drained.first;
      writer.submit(utf8.encode('one '));
      writer.submit(utf8.encode('two '));
      writer.submit(utf8.encode('three'));
      expect(writer.isWriteInFlight, isTrue);
      await onDrained;
      expect(writer.isWriteInFlight, isFalse);

      final written = utf8.decode(_readExactly(readFd, 'one two three'.length));
      expect(written, 'one two three');

      writer.dispose();
      _close(readFd);
      _close(writeFd);
    });

    test('submit returns false before start and after dispose', () async {
      final (readFd, writeFd) = _makePipe();
      final writer = FdWriter(fd: writeFd);
      expect(writer.submit(utf8.encode('early')), isFalse);

      await writer.start();
      expect(writer.submit(utf8.encode('ok')), isTrue);
      await writer.drained.first;

      writer.dispose();
      expect(writer.submit(utf8.encode('late')), isFalse);
      _close(readFd);
      _close(writeFd);
    });

    test('a stalled reader blocks the writer isolate, not the caller',
        () async {
      final (readFd, writeFd) = _makePipe();
      final writer = FdWriter(fd: writeFd);
      await writer.start();

      // Far larger than any kernel pipe buffer: the writer isolate must
      // block on write(2) until the drainer starts consuming.
      const payloadSize = 256 * 1024;
      final payload = Uint8List(payloadSize);
      final onDrained = writer.drained.first;
      writer.submit(payload);

      // The caller's event loop keeps running while the write is stuck —
      // these delays completing at all is the non-blocking guarantee.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(writer.isWriteInFlight, isTrue,
          reason: 'the payload cannot complete until the pipe is drained');

      // waitForDrain is time-boxed against the stall.
      final sw = Stopwatch()..start();
      await writer.waitForDrain(const Duration(milliseconds: 100));
      expect(sw.elapsedMilliseconds, lessThan(2000));
      expect(writer.isWriteInFlight, isTrue);

      await Isolate.spawn(_drainMain, [readFd, payloadSize]);
      await onDrained;
      expect(writer.isWriteInFlight, isFalse);

      writer.dispose();
      _close(readFd);
      _close(writeFd);
    });
  });
}
