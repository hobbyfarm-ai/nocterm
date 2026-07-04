import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:nocterm/nocterm.dart';
import 'package:nocterm/src/backend/terminal.dart' as term;
import 'package:test/test.dart' hide isEmpty, isNotEmpty;

class _FakeBackend implements TerminalBackend {
  final inputController = StreamController<List<int>>();

  @override
  bool get isWriteInFlight => false;

  @override
  Stream<void>? get writeDrainedStream => null;

  @override
  void writeRaw(String data) {}

  @override
  void writeRawBytes(Uint8List bytes) {}

  @override
  Size getSize() => const Size(80, 24);

  @override
  bool get supportsSize => true;

  @override
  Stream<List<int>>? get inputStream => inputController.stream;

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
  group('TerminalBinding mouse motion coalescing', () {
    late _FakeBackend backend;
    late TerminalBinding binding;

    setUpAll(() {
      NoctermBinding.resetInstance();
      backend = _FakeBackend();
      binding = TerminalBinding(term.Terminal(backend))..initialize();
    });

    tearDownAll(() async {
      await backend.inputController.close();
      NoctermBinding.resetInstance();
    });

    /// Feeds [sequences] to the binding as a single stdin chunk and returns
    /// the mouse events it routes.
    Future<List<MouseEvent>> feed(String sequences) async {
      final events = <MouseEvent>[];
      final subscription = binding.mouseEvents.listen(events.add);
      backend.inputController.add(utf8.encode(sequences));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await subscription.cancel();
      return events;
    }

    test('a run of drag motion reports collapses to its last event', () async {
      final events = await feed(
        '\x1b[<0;3;2M' // press left at (2,1)
        '\x1b[<32;4;2M\x1b[<32;5;2M\x1b[<32;6;2M' // drag motion run
        '\x1b[<0;7;2m', // release at (6,1)
      );

      expect(events.length, 3);
      expect(events[0].pressed, isTrue);
      expect(events[0].isMotion, isFalse);
      expect((events[0].x, events[0].y), (2, 1));
      expect(events[1].isMotion, isTrue);
      expect((events[1].x, events[1].y), (5, 1),
          reason: 'only the last motion report of the run survives');
      expect(events[2].pressed, isFalse);
      expect((events[2].x, events[2].y), (6, 1));
    });

    test('a wheel tick bounds motion runs and is never coalesced', () async {
      final events = await feed(
        '\x1b[<32;2;2M\x1b[<32;3;2M' // drag motion run
        '\x1b[<64;3;2M' // wheel up
        '\x1b[<32;4;2M\x1b[<32;5;2M', // second drag motion run
      );

      expect(events.length, 3);
      expect(events[0].isMotion, isTrue);
      expect((events[0].x, events[0].y), (2, 1));
      expect(events[1].button, MouseButton.wheelUp);
      expect(events[2].isMotion, isTrue);
      expect((events[2].x, events[2].y), (4, 1));
    });

    test('hover and drag motion runs stay separate', () async {
      final events = await feed(
        '\x1b[<35;2;2M\x1b[<35;3;2M' // hover motion run (no button down)
        '\x1b[<32;4;2M\x1b[<32;5;2M', // drag motion run
      );

      expect(events.length, 2);
      expect(events[0].pressed, isFalse);
      expect((events[0].x, events[0].y), (2, 1));
      expect(events[1].pressed, isTrue);
      expect((events[1].x, events[1].y), (4, 1));
    });
  });
}
