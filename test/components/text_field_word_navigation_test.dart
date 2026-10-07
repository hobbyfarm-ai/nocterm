import 'package:nocterm/nocterm.dart';
import 'package:test/test.dart';

void main() {
  const alt = ModifierKeys(alt: true);
  const ctrl = ModifierKeys(ctrl: true);

  Future<TextEditingController> pumpField(
    NoctermTester tester, {
    String text = 'alpha beta gamma',
  }) async {
    final controller = TextEditingController(text: text);
    await tester.pumpComponent(
      SizedBox(
        width: 40,
        height: 1,
        child: TextField(controller: controller, focused: true),
      ),
    );
    return controller;
  }

  Future<void> send(NoctermTester tester, LogicalKey key, ModifierKeys mods) =>
      tester.sendKeyEvent(KeyboardEvent(logicalKey: key, modifiers: mods));

  group('TextField word navigation', () {
    test('Alt+Left/Right jump by word', () async {
      await testNocterm('alt arrows', (tester) async {
        final controller = await pumpField(tester);
        await send(tester, LogicalKey.arrowLeft, alt);
        expect(controller.selection.extentOffset, 11);
        await send(tester, LogicalKey.arrowLeft, alt);
        expect(controller.selection.extentOffset, 6);
        await send(tester, LogicalKey.arrowRight, alt);
        expect(controller.selection.extentOffset, 11);
      });
    });

    test('Alt+B / Alt+F jump by word without inserting text', () async {
      await testNocterm('emacs chords', (tester) async {
        final controller = await pumpField(tester);
        await tester.sendKeyEvent(const KeyboardEvent(
            logicalKey: LogicalKey.keyB, character: 'b', modifiers: alt));
        expect(controller.text, 'alpha beta gamma');
        expect(controller.selection.extentOffset, 11);
        await tester.sendKeyEvent(const KeyboardEvent(
            logicalKey: LogicalKey.keyF, character: 'f', modifiers: alt));
        expect(controller.text, 'alpha beta gamma');
        expect(controller.selection.extentOffset, 16);
      });
    });

    test('Ctrl+Shift+Left and Alt+Shift+Left select by word', () async {
      await testNocterm('word selection', (tester) async {
        final controller = await pumpField(tester);
        await send(tester, LogicalKey.arrowLeft,
            const ModifierKeys(ctrl: true, shift: true));
        expect(controller.selection.baseOffset, 16);
        expect(controller.selection.extentOffset, 11);
        await send(tester, LogicalKey.arrowLeft,
            const ModifierKeys(alt: true, shift: true));
        expect(controller.selection.baseOffset, 16);
        expect(controller.selection.extentOffset, 6);
      });
    });

    test('Alt+Backspace and Ctrl+Backspace delete the previous word', () async {
      await testNocterm('word delete backward', (tester) async {
        final controller = await pumpField(tester);
        await send(tester, LogicalKey.backspace, alt);
        expect(controller.text, 'alpha beta ');
        await send(tester, LogicalKey.backspace, ctrl);
        expect(controller.text, 'alpha ');
      });
    });

    test('Alt+D, Alt+Delete and Ctrl+Delete delete the next word', () async {
      await testNocterm('word delete forward', (tester) async {
        final controller = await pumpField(tester);
        controller.selection = const TextSelection.collapsed(offset: 0);
        await tester.sendKeyEvent(const KeyboardEvent(
            logicalKey: LogicalKey.keyD, character: 'd', modifiers: alt));
        expect(controller.text, 'beta gamma');
        await send(tester, LogicalKey.delete, alt);
        expect(controller.text, 'gamma');
        await send(tester, LogicalKey.delete, ctrl);
        expect(controller.text, '');
      });
    });
  });
}
