import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:nocterm/nocterm.dart';

/// A backend whose terminal is the test: bytes pushed into [input] are
/// stdin, byte writes land in [writes], every write is appended to
/// [output], and the test reports a finished write through [drained].
class FakeBackend implements TerminalBackend {
  FakeBackend({this.size = const Size(80, 24), this.inputFailure});

  /// The terminal size reported to the binding.
  final Size size;

  /// Thrown from [inputStream] when set, as a backend without stdin would.
  final Object? inputFailure;

  /// What the binding reads as stdin.
  final input = StreamController<List<int>>();

  /// Fires when the test says an in-flight write has finished.
  final drained = StreamController<void>.broadcast();

  /// Every byte write, in order.
  final writes = <Uint8List>[];

  final _output = StringBuffer();

  /// Whether the binding should wait before writing another frame.
  bool inFlight = false;

  /// Whether the binding drained output after its last write.
  bool drainedAfterLastWrite = false;

  /// Everything written, raw strings and bytes alike, as text.
  String get output => _output.toString();

  @override
  Future<void> drainOutput([
    Duration timeout = const Duration(seconds: 1),
  ]) async {
    drainedAfterLastWrite = true;
  }

  @override
  bool get isWriteInFlight => inFlight;

  @override
  Stream<void>? get writeDrainedStream => drained.stream;

  @override
  void writeRaw(String data) {
    _output.write(data);
    drainedAfterLastWrite = false;
  }

  @override
  void writeRawBytes(Uint8List bytes) {
    writes.add(bytes);
    _output.write(utf8.decode(bytes, allowMalformed: true));
    drainedAfterLastWrite = false;
  }

  @override
  Size getSize() => size;

  @override
  bool get supportsSize => true;

  @override
  Stream<List<int>>? get inputStream {
    if (inputFailure case final failure?) throw failure;
    return input.stream;
  }

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

  /// Closes the streams so a test isolate can exit.
  Future<void> close() async {
    await input.close();
    await drained.close();
  }
}
