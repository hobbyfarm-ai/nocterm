import 'package:nocterm/nocterm.dart';
import 'package:test/test.dart';

void main() {
  group('TextField paste', () {
    test('inserts pasted text at the cursor', () async {
      await testNocterm('paste inserts', (tester) async {
        final controller = TextEditingController(text: 'ab');
        controller.selection = const TextSelection.collapsed(offset: 1);

        await tester.pumpComponent(
          TextField(controller: controller, focused: true, maxLines: 1),
        );
        await tester.paste('XY');

        expect(controller.text, 'aXYb');
        expect(controller.selection, const TextSelection.collapsed(offset: 3));
      });
    });

    test('flattens line breaks to spaces in a single-line field', () async {
      await testNocterm('paste single-line', (tester) async {
        final controller = TextEditingController();

        await tester.pumpComponent(
          TextField(controller: controller, focused: true, maxLines: 1),
        );
        await tester.paste('Line 1\r\nLine 2\nLine 3');

        expect(controller.text, 'Line 1 Line 2 Line 3');
      });
    });

    test('normalizes line endings in a multi-line field', () async {
      await testNocterm('paste multi-line', (tester) async {
        final controller = TextEditingController();

        await tester.pumpComponent(
          TextField(controller: controller, focused: true, maxLines: 3),
        );
        await tester.paste('a\r\nb\rc');

        expect(controller.text, 'a\nb\nc');
      });
    });

    test('accepts more lines than the viewport shows', () async {
      await testNocterm('paste past the viewport', (tester) async {
        final controller = TextEditingController();
        final lines = List.generate(10, (index) => 'line ${index + 1}');

        await tester.pumpComponent(
          Container(
            width: 20,
            height: 6,
            child:
                TextField(controller: controller, focused: true, maxLines: 6),
          ),
        );
        await tester.paste(lines.join('\n'));

        expect(controller.text.split('\n'), lines);
        expect(tester.terminalState, containsText('line 10'));
        expect(tester.terminalState, isNot(containsText('line 4')));
      });
    });

    test('replaces a selection', () async {
      await testNocterm('paste replaces selection', (tester) async {
        final controller = TextEditingController(text: 'Replace me');

        await tester.pumpComponent(
          TextField(controller: controller, focused: true),
        );
        await tester.sendKeyEvent(KeyboardEvent(
          logicalKey: LogicalKey.keyA,
          modifiers: const ModifierKeys(ctrl: true),
        ));
        await tester.paste('New text');

        expect(controller.text, 'New text');
      });
    });

    test('keeps unicode intact', () async {
      await testNocterm('paste unicode', (tester) async {
        final controller = TextEditingController();
        const text = '你好世界 🎉 Emoji text';

        await tester.pumpComponent(
          TextField(controller: controller, focused: true),
        );
        await tester.paste(text);

        expect(controller.text, text);
      });
    });

    test('onPaste can claim the text', () async {
      await testNocterm('paste claimed', (tester) async {
        final controller = TextEditingController();
        final claimed = <String>[];

        await tester.pumpComponent(
          TextField(
            controller: controller,
            focused: true,
            maxLines: 1,
            onPaste: (text) {
              claimed.add(text);
              return true;
            },
          ),
        );
        await tester.paste('a\nb');

        expect(claimed, ['a b']);
        expect(controller.text, '');
      });
    });

    test('an unfocused field ignores the paste', () async {
      await testNocterm('paste unfocused', (tester) async {
        final controller = TextEditingController();

        await tester.pumpComponent(
          TextField(controller: controller, focused: false),
        );
        await tester.paste('nope');

        expect(controller.text, '');
      });
    });

    test('a read-only field lets the paste bubble', () async {
      await testNocterm('paste read-only', (tester) async {
        final controller = TextEditingController(text: 'fixed');
        final bubbled = <String>[];

        await tester.pumpComponent(
          Focusable(
            focused: true,
            onKeyEvent: (_) => false,
            onPaste: (text) {
              bubbled.add(text);
              return true;
            },
            child: TextField(
              controller: controller,
              focused: true,
              readOnly: true,
            ),
          ),
        );
        await tester.paste('nope');

        expect(controller.text, 'fixed');
        expect(bubbled, ['nope']);
      });
    });
  });

  group('Focusable paste', () {
    test('only a focused Focusable with a handler consumes a paste', () async {
      await testNocterm('focusable paste', (tester) async {
        final outer = <String>[];
        final inner = <String>[];

        await tester.pumpComponent(
          Focusable(
            focused: true,
            onKeyEvent: (_) => false,
            onPaste: (text) {
              outer.add(text);
              return true;
            },
            child: Focusable(
              focused: false,
              onKeyEvent: (_) => false,
              onPaste: (text) {
                inner.add(text);
                return true;
              },
              child: const Text('child'),
            ),
          ),
        );
        await tester.paste('hello');

        expect(inner, hasLength(0));
        expect(outer, ['hello']);
      });
    });

    test('a Focusable without a paste handler lets it bubble', () async {
      await testNocterm('focusable no handler', (tester) async {
        final outer = <String>[];

        await tester.pumpComponent(
          Focusable(
            focused: true,
            onKeyEvent: (_) => false,
            onPaste: (text) {
              outer.add(text);
              return true;
            },
            child: Focusable(
              focused: true,
              onKeyEvent: (_) => false,
              child: const Text('child'),
            ),
          ),
        );
        await tester.paste('hello');

        expect(outer, ['hello']);
      });
    });
  });
}
