import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

typedef _NativeWrite = IntPtr Function(Int32 fd, Pointer<Uint8> buf, IntPtr n);
typedef _DartWrite = int Function(int fd, Pointer<Uint8> buf, int n);

/// Writes payloads to a POSIX file descriptor from a dedicated isolate.
///
/// A terminal that stops draining its pty leaves the kernel's output buffer
/// full, and the next blocking `write(2)` freezes whichever isolate issued
/// it — timers, stdin, and isolate messages all stall until the terminal
/// catches up. Routing writes through this writer parks the stall in the
/// writer isolate instead, so the main event loop keeps running.
///
/// Payloads are written in submission order. [isWriteInFlight] is true while
/// submitted payloads are still being written; [drained] emits each time the
/// queue empties. Frame producers should defer rendering while a write is in
/// flight rather than stacking payloads behind a stalled reader.
class FdWriter {
  FdWriter({this.fd = 1});

  /// Target file descriptor. Defaults to stdout.
  final int fd;

  SendPort? _commands;
  ReceivePort? _replies;
  ReceivePort? _errors;
  int _outstanding = 0;
  bool _disposed = false;
  final _drainedController = StreamController<void>.broadcast();

  /// True while previously submitted payloads are still being written.
  bool get isWriteInFlight => _outstanding > 0;

  /// Emits each time all submitted payloads have finished writing.
  Stream<void> get drained => _drainedController.stream;

  /// Whether the writer isolate is running and accepting payloads.
  bool get isRunning => _commands != null && !_disposed;

  /// Spawns the writer isolate. Until this completes, [submit] returns
  /// false and callers should write synchronously themselves.
  Future<void> start() async {
    if (_disposed || _replies != null) return;
    final replies = ReceivePort();
    final errors = ReceivePort();
    _replies = replies;
    _errors = errors;
    final ready = Completer<SendPort?>();
    replies.listen((message) {
      if (message is SendPort) {
        ready.complete(message);
        return;
      }
      if (_outstanding > 0) {
        _outstanding--;
        if (_outstanding == 0 && !_disposed) {
          _drainedController.add(null);
        }
      }
    });
    errors.listen((_) {
      if (!ready.isCompleted) ready.complete(null);
      _handleWriterFailure();
    });
    try {
      await Isolate.spawn(
        _writerMain,
        _WriterArgs(fd, replies.sendPort),
        onError: errors.sendPort,
        debugName: 'nocterm-fd-writer',
      );
    } on Object {
      if (!ready.isCompleted) ready.complete(null);
      _handleWriterFailure();
      return;
    }
    final commands = await ready.future;
    if (commands == null) return;
    if (_disposed) {
      commands.send(null);
      return;
    }
    _commands = commands;
  }

  /// Queues [bytes] for writing. Returns false when the writer isn't
  /// accepting payloads (not started yet, failed, or disposed) — the
  /// caller should write synchronously instead.
  bool submit(Uint8List bytes) {
    final commands = _commands;
    if (commands == null || _disposed) return false;
    _outstanding++;
    commands.send(TransferableTypedData.fromList([bytes]));
    return true;
  }

  /// Completes when all submitted payloads have been written, or when
  /// [timeout] elapses — whichever comes first. Never throws.
  Future<void> waitForDrain(Duration timeout) async {
    if (_outstanding == 0) return;
    try {
      await drained.first.timeout(timeout);
    } on Object {
      // Timed out against a stalled reader, or the writer was disposed
      // mid-wait. Either way the caller just wanted a bounded wait.
    }
  }

  /// Stops accepting payloads and lets the isolate exit once its queue is
  /// written. [drained] emits nothing after this.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _commands?.send(null);
    _commands = null;
    _replies?.close();
    _errors?.close();
    _drainedController.close();
  }

  /// The isolate died (spawn failure or uncaught error). Settle the
  /// outstanding count so producers waiting on [drained] aren't wedged,
  /// and route future submissions back to the synchronous path.
  void _handleWriterFailure() {
    _commands = null;
    if (_outstanding > 0) {
      _outstanding = 0;
      if (!_disposed) _drainedController.add(null);
    }
  }
}

class _WriterArgs {
  const _WriterArgs(this.fd, this.replies);

  final int fd;
  final SendPort replies;
}

/// Upper bound on consecutive failed `write(2)` calls (1ms apart) before a
/// payload is abandoned, so a dead fd can't wedge the isolate forever.
const _maxConsecutiveWriteFailures = 1000;

void _writerMain(_WriterArgs args) {
  final write = DynamicLibrary.process()
      .lookupFunction<_NativeWrite, _DartWrite>('write');
  final commands = ReceivePort();
  args.replies.send(commands.sendPort);
  commands.listen((message) {
    if (message == null) {
      commands.close();
      return;
    }
    final bytes =
        (message as TransferableTypedData).materialize().asUint8List();
    _writeAll(write, args.fd, bytes);
    args.replies.send(bytes.length);
  });
}

/// Blocking write loop. Blocking is the point: a stalled reader parks this
/// isolate only. Transient failures (EINTR) retry after a short sleep.
void _writeAll(_DartWrite write, int fd, Uint8List bytes) {
  if (bytes.isEmpty) return;
  final buf = malloc.allocate<Uint8>(bytes.length);
  try {
    buf.asTypedList(bytes.length).setAll(0, bytes);
    var written = 0;
    var failures = 0;
    while (written < bytes.length) {
      final n = write(fd, buf + written, bytes.length - written);
      if (n > 0) {
        written += n;
        failures = 0;
        continue;
      }
      failures++;
      if (failures >= _maxConsecutiveWriteFailures) return;
      sleep(const Duration(milliseconds: 1));
    }
  } finally {
    malloc.free(buf);
  }
}
