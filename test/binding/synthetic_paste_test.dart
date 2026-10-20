import 'dart:async';

import 'package:nocterm/nocterm.dart';
import 'package:nocterm/src/backend/terminal.dart' as term;
import 'fake_backend.dart';
import 'package:test/test.dart' hide isEmpty, isNotEmpty;

final pastes = <String>[];
final keys = <KeyboardEvent>[];

class _Harness extends StatelessComponent {
  const _Harness();

  @override
  Component build(BuildContext context) => Focusable(
        focused: true,
        onKeyEvent: (event) {
          keys.add(event);
          return true;
        },
        onPaste: (text) {
          pastes.add(text);
          return true;
        },
        child: const Text('ready'),
      );
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  group('synthetic paste from one stdin read', () {
    late FakeBackend backend;

    setUpAll(() {
      NoctermBinding.resetInstance();
      backend = FakeBackend(size: const Size(20, 5));
      TerminalBinding(term.Terminal(backend))
        ..enableFrameRateLimiting = false
        ..initialize()
        ..attachRootComponent(const _Harness());
    });

    setUp(() {
      pastes.clear();
      keys.clear();
    });

    tearDownAll(() async {
      await _settle();
      await backend.close();
      NoctermBinding.resetInstance();
    });

    test('a multi-line chunk arrives as one paste with its newlines', () async {
      backend.input.add('abc\ndef\nghi\n'.codeUnits);
      await _settle();
      expect(pastes, ['abc\ndef\nghi\n']);
      expect(keys, <KeyboardEvent>[]);
    });

    test('a lone line feed is a Ctrl+J key press', () async {
      backend.input.add([0x0A]);
      await _settle();
      expect(pastes, <String>[]);
      expect(keys.map((key) => key.logicalKey), [LogicalKey.keyJ]);
      expect(keys.single.isControlPressed, isTrue);
    });

    test('a single character is a key press, not a paste', () async {
      backend.input.add('x'.codeUnits);
      await _settle();
      expect(pastes, <String>[]);
      expect(keys.single.character, 'x');
    });
  });
}
