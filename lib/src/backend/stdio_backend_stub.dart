// Stub file for web platforms.
// The actual implementation is in stdio_backend.dart (IO only).

import 'dart:async';

import 'package:nocterm/src/size.dart';

import 'terminal_backend.dart';
import 'dart:convert';
import 'dart:typed_data';

/// Stub StdioBackend for web platforms.
/// This class exists so that code can reference StdioBackend without
/// conditional imports, but it will throw if actually used on web.
class StdioBackend implements TerminalBackend {
  StdioBackend() {
    throw UnsupportedError(
        'StdioBackend is only available on native platforms');
  }

  @override
  bool get isWriteInFlight => false;

  @override
  Stream<void>? get writeDrainedStream => null;

  @override
  void writeRaw(String data) {
    throw UnsupportedError(
        'StdioBackend is only available on native platforms');
  }

  @override
  void writeRawBytes(Uint8List bytes) {
    if (bytes.isEmpty) return;
    writeRaw(utf8.decode(bytes, allowMalformed: true));
  }

  @override
  Size getSize() {
    throw UnsupportedError(
        'StdioBackend is only available on native platforms');
  }

  @override
  bool get supportsSize => throw UnsupportedError(
      'StdioBackend is only available on native platforms');

  @override
  Stream<List<int>>? get inputStream => throw UnsupportedError(
      'StdioBackend is only available on native platforms');

  @override
  Stream<Size>? get resizeStream => throw UnsupportedError(
      'StdioBackend is only available on native platforms');

  @override
  Stream<void>? get shutdownStream => throw UnsupportedError(
      'StdioBackend is only available on native platforms');

  @override
  void enableRawMode() {
    throw UnsupportedError(
        'StdioBackend is only available on native platforms');
  }

  @override
  void disableRawMode() {
    throw UnsupportedError(
        'StdioBackend is only available on native platforms');
  }

  @override
  bool get isAvailable => throw UnsupportedError(
      'StdioBackend is only available on native platforms');

  @override
  void notifySizeChanged(Size newSize) {
    throw UnsupportedError(
        'StdioBackend is only available on native platforms');
  }

  @override
  void requestExit([int exitCode = 0]) {
    throw UnsupportedError(
        'StdioBackend is only available on native platforms');
  }

  @override
  void dispose() {
    throw UnsupportedError(
        'StdioBackend is only available on native platforms');
  }
}
