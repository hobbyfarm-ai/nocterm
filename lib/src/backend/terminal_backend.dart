import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:nocterm/src/size.dart';

/// Abstract interface for terminal I/O backends.
///
/// Backends handle platform-specific I/O operations:
/// - StdioBackend: Native terminal via stdin/stdout
/// - SocketBackend: Shell mode via Unix socket
/// - WebBackend: Browser via static bridge for WASM/JS apps
abstract class TerminalBackend {
  /// Write a string directly to the output (immediate, unbuffered).
  void writeRaw(String data);

  /// Write raw UTF-8 bytes directly to the output.
  ///
  /// The default implementation round-trips through `utf8.decode` and
  /// [writeRaw] so existing backends keep working without changes.
  /// Backends that own a byte-oriented sink (e.g., a libc `write(2)`
  /// FFI call against fd 1) SHOULD override this — the renderer
  /// accumulates bytes directly via [ByteWriteBuffer], and skipping
  /// the decode + re-encode round trip is the whole point.
  void writeRawBytes(Uint8List bytes) {
    if (bytes.isEmpty) return;
    writeRaw(utf8.decode(bytes, allowMalformed: true));
  }

  /// True while previously submitted bytes are still draining to the
  /// output. Frame producers should defer rendering until
  /// [writeDrainedStream] emits rather than stacking payloads behind a
  /// stalled reader. Always false for backends that write synchronously.
  bool get isWriteInFlight => false;

  /// Emits each time the backend finishes writing all submitted bytes.
  /// Returns null when writes complete synchronously (nothing to wait for).
  Stream<void>? get writeDrainedStream => null;

  /// Get the current terminal size.
  Size getSize();

  /// Whether this backend supports querying terminal size.
  bool get supportsSize;

  /// Get the input stream for reading terminal input.
  /// Returns null if this backend doesn't provide input.
  Stream<List<int>>? get inputStream;

  /// Stream of terminal resize events.
  /// Returns null if this backend doesn't support resize detection.
  Stream<Size>? get resizeStream;

  /// Stream that emits when the app should shut down gracefully.
  /// (e.g., SIGINT/SIGTERM on native, browser tab close on web)
  /// Returns null if not supported.
  Stream<void>? get shutdownStream;

  /// Enable raw input mode (disable echo, line buffering).
  void enableRawMode();

  /// Disable raw input mode (restore echo, line buffering).
  void disableRawMode();

  /// Whether this backend is currently available/connected.
  bool get isAvailable;

  /// Request process/app exit with the given exit code.
  /// On native: calls dart:io exit()
  /// On web: typically a no-op (can't exit browser tab)
  void requestExit([int exitCode = 0]);

  /// Update the size externally (for backends that receive size via protocol).
  /// Default implementation does nothing.
  void notifySizeChanged(Size newSize) {}

  /// Dispose of any resources held by this backend.
  void dispose();
}
