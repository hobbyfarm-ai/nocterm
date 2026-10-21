import 'dart:async';
import 'dart:convert';

import 'package:nocterm/nocterm.dart';
import 'package:nocterm/src/backend/terminal.dart' as term;
import 'fake_backend.dart';
import 'package:test/test.dart' hide isEmpty, isNotEmpty;

class _Harness extends StatefulComponent {
  const _Harness();

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  static _HarnessState? instance;
  final controller = TextEditingController(text: 'hi');
  bool focused = true;
  CursorStyle style = CursorStyle.block;

  void set({bool? focused, CursorStyle? style, String? text}) => setState(() {
        this.focused = focused ?? this.focused;
        this.style = style ?? this.style;
        if (text != null) controller.text = text;
        controller.selection =
            TextSelection.collapsed(offset: controller.text.length);
      });

  @override
  void initState() {
    super.initState();
    instance = this;
    controller.selection = const TextSelection.collapsed(offset: 2);
  }

  @override
  Component build(BuildContext context) => TextField(
        controller: controller,
        focused: focused,
        cursorStyle: style,
        width: 20,
      );
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 20));

const _begin = '\x1b[?2026h\x1b[?25l';
const _end = '\x1b[?25h\x1b[?2026l';

void main() {
  group('TerminalBinding frame cursor', () {
    late FakeBackend backend;

    setUpAll(() {
      NoctermBinding.resetInstance();
      backend = FakeBackend(size: const Size(20, 5));
      TerminalBinding(term.Terminal(backend))
        ..enableFrameRateLimiting = false
        ..attachRootComponent(const _Harness());
    });

    setUp(() => backend.writes.clear());

    tearDownAll(() async {
      await _settle();
      await backend.drained.close();
      NoctermBinding.resetInstance();
    });

    String lastFrame() => utf8.decode(backend.writes.last);

    test('a frame hides the cursor for the write and shows it at the caret',
        () async {
      _HarnessState.instance!.set(text: 'hi');
      await _settle();
      expect(backend.writes.length, 1, reason: 'one write per frame');
      final frame = lastFrame();
      expect(frame, startsWith(_begin));
      expect(frame, endsWith('\x1b[1;3H\x1b[1 q$_end'));
      expect('\x1b[?25h'.allMatches(frame).length, 1);
    });

    test('an unchanged shape is not resent', () async {
      _HarnessState.instance!.set(text: 'hey');
      await _settle();
      final frame = lastFrame();
      expect(frame, endsWith('\x1b[1;4H$_end'));
      expect(frame, isNot(contains(' q')));
    });

    test('a new shape is sent once', () async {
      _HarnessState.instance!.set(style: CursorStyle.underline);
      await _settle();
      expect(lastFrame(), endsWith('\x1b[1;4H\x1b[3 q$_end'));
    });

    test('with nothing focused the cursor stays hidden', () async {
      _HarnessState.instance!.set(focused: false);
      await _settle();
      final frame = lastFrame();
      expect(frame, startsWith(_begin));
      expect(frame, endsWith('\x1b[?2026l'));
      expect(frame, isNot(contains('\x1b[?25h')));
    });

    test('focus coming back sends the shape again', () async {
      _HarnessState.instance!.set(focused: true);
      await _settle();
      expect(lastFrame(), endsWith('\x1b[1;4H\x1b[3 q$_end'));
    });
  });
}
