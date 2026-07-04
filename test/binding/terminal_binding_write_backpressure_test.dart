import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:nocterm/nocterm.dart';
import 'package:nocterm/src/backend/terminal.dart' as term;
import 'package:test/test.dart' hide isEmpty, isNotEmpty;

class _FakeBackend implements TerminalBackend {
  bool inFlight = false;
  final drainedController = StreamController<void>.broadcast();
  final writes = <Uint8List>[];

  @override
  bool get isWriteInFlight => inFlight;

  @override
  Stream<void>? get writeDrainedStream => drainedController.stream;

  @override
  void writeRaw(String data) {}

  @override
  void writeRawBytes(Uint8List bytes) {
    writes.add(bytes);
  }

  @override
  Size getSize() => const Size(20, 5);

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
  String text = 'alpha';

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

void main() {
  group('TerminalBinding write backpressure', () {
    // Service extensions register once per isolate, so the binding is
    // shared across the group; the fake backend resets between tests.
    late _FakeBackend backend;

    setUpAll(() {
      NoctermBinding.resetInstance();
      backend = _FakeBackend();
      TerminalBinding(term.Terminal(backend))
        ..enableFrameRateLimiting = false
        ..attachRootComponent(const _Harness());
    });

    setUp(() {
      backend.inFlight = false;
      backend.writes.clear();
    });

    tearDownAll(() async {
      await _settle();
      await backend.drainedController.close();
      NoctermBinding.resetInstance();
    });

    test('frames defer while a write is in flight and coalesce on drain',
        () async {
      _HarnessState.instance!.setText('alpha');
      await _settle();
      expect(backend.writes.length, 1);
      expect(utf8.decode(backend.writes[0]), contains('alpha'));

      backend.inFlight = true;
      _HarnessState.instance!.setText('bravo');
      await _settle();
      _HarnessState.instance!.setText('charlie');
      await _settle();
      expect(backend.writes.length, 1,
          reason: 'frames must not render while the backend is draining');

      backend.inFlight = false;
      backend.drainedController.add(null);
      await _settle();
      expect(backend.writes.length, 2,
          reason: 'one catch-up frame renders the coalesced state');
      expect(utf8.decode(backend.writes[1]), contains('charlie'));
    });

    test('a drain event with no deferred frame schedules nothing', () async {
      _HarnessState.instance!.setText('delta');
      await _settle();
      expect(backend.writes.length, 1);

      backend.drainedController.add(null);
      await _settle();
      expect(backend.writes.length, 1);
    });
  });
}
