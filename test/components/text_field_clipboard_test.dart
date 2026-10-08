import 'package:nocterm/nocterm.dart';
import 'package:test/test.dart';

Future<void> _selectAll(NoctermTester tester) => tester.sendKeyEvent(
      KeyboardEvent(
        logicalKey: LogicalKey.keyA,
        modifiers: const ModifierKeys(ctrl: true),
      ),
    );

Future<void> _drag(NoctermTester tester, int fromX, int toX) async {
  await tester.press(fromX, 0);
  await tester.sendMouseEvent(MouseEvent(
    button: MouseButton.left,
    x: toX,
    y: 0,
    pressed: true,
    isMotion: true,
  ));
  await tester.release(toX, 0);
}

void main() {
  group('TextField copy sink', () {
    test('Ctrl+X hands the selection to onCopy and deletes it', () async {
      await testNocterm('cut', (tester) async {
        final controller = TextEditingController(text: 'Cut this text');
        final copied = <String>[];

        await tester.pumpComponent(
          TextField(controller: controller, focused: true, onCopy: copied.add),
        );
        await _selectAll(tester);
        await tester.sendKeyEvent(KeyboardEvent(
          logicalKey: LogicalKey.keyX,
          modifiers: const ModifierKeys(ctrl: true),
        ));

        expect(controller.text, '');
        expect(copied, ['Cut this text']);
      });
    });

    test('Ctrl+X still deletes when onCopy collapses the selection', () async {
      await testNocterm('cut collapsing sink', (tester) async {
        final controller = TextEditingController(text: 'Cut this text');

        await tester.pumpComponent(
          TextField(
            controller: controller,
            focused: true,
            onCopy: (_) => controller.selection =
                TextSelection.collapsed(offset: controller.text.length),
          ),
        );
        await _selectAll(tester);
        await tester.sendKeyEvent(KeyboardEvent(
          logicalKey: LogicalKey.keyX,
          modifiers: const ModifierKeys(ctrl: true),
        ));

        expect(controller.text, '');
      });
    });

    test('Ctrl+X with a collapsed selection does nothing', () async {
      await testNocterm('cut collapsed', (tester) async {
        final controller = TextEditingController(text: 'Keep me');
        final copied = <String>[];

        await tester.pumpComponent(
          TextField(controller: controller, focused: true, onCopy: copied.add),
        );
        await tester.sendKeyEvent(KeyboardEvent(
          logicalKey: LogicalKey.keyX,
          modifiers: const ModifierKeys(ctrl: true),
        ));

        expect(controller.text, 'Keep me');
        expect(copied, hasLength(0));
      });
    });

    test('without onCopy, a cut lands in the in-process clipboard', () async {
      await testNocterm('cut fallback', (tester) async {
        final controller = TextEditingController(text: 'Fallback');

        await tester.pumpComponent(
          TextField(controller: controller, focused: true),
        );
        await _selectAll(tester);
        await tester.sendKeyEvent(KeyboardEvent(
          logicalKey: LogicalKey.keyX,
          modifiers: const ModifierKeys(ctrl: true),
        ));

        expect(controller.text, '');
        expect(ClipboardManager.paste(), 'Fallback');
      });
    });

    test('Ctrl+C bubbles and keeps the selection', () async {
      await testNocterm('ctrl+c bubbles', (tester) async {
        final controller = TextEditingController(text: 'Hello, World!');
        final copied = <String>[];
        final bubbled = <LogicalKey>[];

        await tester.pumpComponent(
          Focusable(
            focused: true,
            onKeyEvent: (event) {
              bubbled.add(event.logicalKey);
              return true;
            },
            child: TextField(
              controller: controller,
              focused: true,
              onCopy: copied.add,
            ),
          ),
        );
        await _selectAll(tester);
        await tester.sendKeyEvent(KeyboardEvent(
          logicalKey: LogicalKey.keyC,
          modifiers: const ModifierKeys(ctrl: true),
        ));

        expect(bubbled, [LogicalKey.keyC]);
        expect(copied, hasLength(0));
        expect(controller.selection.isCollapsed, isFalse);
      });
    });

    test('a mouse drag copies the selection on release', () async {
      await testNocterm('drag copies', (tester) async {
        final controller = TextEditingController(text: 'Hello World');
        final copied = <String>[];

        await tester.pumpComponent(
          Container(
            width: 30,
            height: 1,
            child: TextField(
              controller: controller,
              focused: true,
              maxLines: 1,
              onCopy: copied.add,
            ),
          ),
        );
        await _drag(tester, 1, 4);

        expect(controller.selection.start, 1);
        expect(controller.selection.end, 4);
        expect(copied, ['ell']);
      });
    });

    test('a plain click copies nothing', () async {
      await testNocterm('click copies nothing', (tester) async {
        final controller = TextEditingController(text: 'Hello World');
        final copied = <String>[];

        await tester.pumpComponent(
          Container(
            width: 30,
            height: 1,
            child: TextField(
              controller: controller,
              focused: true,
              maxLines: 1,
              onCopy: copied.add,
            ),
          ),
        );
        await tester.press(3, 0);
        await tester.release(3, 0);

        expect(copied, hasLength(0));
      });
    });

    test('a double-click copies the word', () async {
      await testNocterm('double-click copies', (tester) async {
        final controller = TextEditingController(text: 'Hello World');
        final copied = <String>[];

        await tester.pumpComponent(
          Container(
            width: 30,
            height: 1,
            child: TextField(
              controller: controller,
              focused: true,
              maxLines: 1,
              onCopy: copied.add,
            ),
          ),
        );
        await tester.press(7, 0);
        await tester.release(7, 0);
        await tester.press(7, 0);
        await tester.release(7, 0);

        expect(copied, ['World']);
      });
    });

    test('keyboard selection copies nothing', () async {
      await testNocterm('keyboard selection', (tester) async {
        final controller = TextEditingController(text: 'Hello');
        controller.selection = const TextSelection.collapsed(offset: 0);
        final copied = <String>[];

        await tester.pumpComponent(
          TextField(controller: controller, focused: true, onCopy: copied.add),
        );
        await tester.sendKeyEvent(KeyboardEvent(
          logicalKey: LogicalKey.arrowRight,
          modifiers: const ModifierKeys(shift: true),
        ));

        expect(controller.selection.isCollapsed, isFalse);
        expect(copied, hasLength(0));
      });
    });

    test('an obscured field never copies', () async {
      await testNocterm('obscured', (tester) async {
        final controller = TextEditingController(text: 'hunter2');
        final copied = <String>[];

        await tester.pumpComponent(
          Container(
            width: 30,
            height: 1,
            child: TextField(
              controller: controller,
              focused: true,
              maxLines: 1,
              obscureText: true,
              onCopy: copied.add,
            ),
          ),
        );
        await _drag(tester, 0, 5);

        expect(controller.selection.isCollapsed, isFalse);
        expect(copied, hasLength(0));
      });
    });
  });
}
