import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:nocterm/nocterm.dart';
import 'package:nocterm/src/backend/terminal.dart' as term;
import 'package:test/test.dart' hide isEmpty, isNotEmpty;

class _FakeBackend implements TerminalBackend {
  final writes = <Uint8List>[];

  @override
  void writeRawBytes(Uint8List bytes) => writes.add(bytes);

  @override
  void writeRaw(String data) {}

  @override
  Future<void> drainOutput(
      [Duration timeout = const Duration(seconds: 1)]) async {}

  @override
  bool get isWriteInFlight => false;

  @override
  Stream<void>? get writeDrainedStream => null;

  @override
  Size getSize() => const Size(20, 3);

  @override
  bool get supportsSize => true;

  @override
  Stream<List<int>>? get inputStream => null;

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

class _Harness extends StatefulComponent {
  const _Harness();

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  static _HarnessState? instance;
  String text = '😀X';

  void setText(String value) => setState(() => text = value);

  @override
  void initState() {
    super.initState();
    instance = this;
  }

  @override
  Component build(BuildContext context) => Text(text);
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 20));

String _decode(List<Uint8List> writes) =>
    writes.map((w) => utf8.decode(w, allowMalformed: true)).join();

void main() {
  group('emoji-safe rendering', () {
    late _FakeBackend backend;

    setUpAll(() {
      NoctermBinding.resetInstance();
      backend = _FakeBackend();
      TerminalBinding(term.Terminal(backend))
        ..enableFrameRateLimiting = false
        ..attachRootComponent(const _Harness());
    });

    setUp(() => backend.writes.clear());

    tearDownAll(() {
      NoctermBinding.resetInstance();
    });

    test('full render positions each row absolutely', () async {
      _HarnessState.instance!.setText('😀X');
      await _settle();
      final out = _decode(backend.writes);
      // Row 1 gets an absolute CUP rather than a bare newline.
      expect(out, contains('\x1b[2;1H'));
    });

    test('full render resyncs the cursor after a multi-codepoint cluster',
        () async {
      _HarnessState.instance!.setText('👍🏽X');
      await _settle();
      final out = _decode(backend.writes);
      expect(out, contains('👍🏽'));
      // After the width-2 cluster at col 0, resync to col 2 (1-based col 3).
      expect(out, contains('\x1b[1;3H'));
    });

    test('diff render repaints the row after an emoji cell changes', () async {
      _HarnessState.instance!.setText('😀X');
      await _settle();
      backend.writes.clear();

      // 😀 (single code point) → 👍🏽 (multi). The trailing X is unchanged
      // but must be repainted, and a CUP must follow the cluster.
      _HarnessState.instance!.setText('👍🏽X');
      await _settle();
      final out = _decode(backend.writes);
      expect(out, contains('👍🏽'));
      expect(out, contains('\x1b[1;3H'));
      expect(out, contains('X'));
    });
  });
}
