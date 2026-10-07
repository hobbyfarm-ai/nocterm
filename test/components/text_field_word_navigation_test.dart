import 'package:nocterm/nocterm.dart';
import 'package:test/test.dart';

void main() {
  const alt = ModifierKeys(alt: true);
  const ctrl = ModifierKeys(ctrl: true);
  const altShift = ModifierKeys(alt: true, shift: true);
  const ctrlShift = ModifierKeys(ctrl: true, shift: true);
  const original = 'alpha beta gamma';

  Future<TextEditingController> pumpField(
    NoctermTester tester,
    WordJumpStyle style,
  ) async {
    final controller = TextEditingController(text: original);
    await tester.pumpComponent(
      SizedBox(
        width: 40,
        height: 1,
        child: TextField(
          controller: controller,
          focused: true,
          wordJumpStyle: style,
        ),
      ),
    );
    return controller;
  }

  Future<void> send(NoctermTester tester, LogicalKey key, ModifierKeys mods) =>
      tester.sendKeyEvent(KeyboardEvent(logicalKey: key, modifiers: mods));

  Future<void> placeCursor(
    NoctermTester tester,
    TextEditingController controller,
    int offset,
  ) async {
    controller.selection = TextSelection.collapsed(offset: offset);
    await tester.pump();
  }

  Future<void> altChord(NoctermTester tester, LogicalKey key, String char) =>
      tester.sendKeyEvent(
          KeyboardEvent(logicalKey: key, character: char, modifiers: alt));

  for (final style in WordJumpStyle.values) {
    group('TextField word navigation ($style)', () {
      test('Alt+Left and Ctrl+Left jump to the previous word start', () async {
        await testNocterm('left', (tester) async {
          final controller = await pumpField(tester, style);
          await send(tester, LogicalKey.arrowLeft, alt);
          expect(controller.selection.extentOffset, 11);
          await send(tester, LogicalKey.arrowLeft, ctrl);
          expect(controller.selection.extentOffset, 6);
        });
      });

      test('Alt+B and Alt+F jump by word without inserting text', () async {
        await testNocterm('emacs chords', (tester) async {
          final controller = await pumpField(tester, style);
          await altChord(tester, LogicalKey.keyB, 'b');
          expect(controller.text, original);
          expect(controller.selection.extentOffset, 11);
          await altChord(tester, LogicalKey.keyF, 'f');
          expect(controller.text, original);
          expect(controller.selection.extentOffset, 16);
        });
      });

      test('Shift with Ctrl or Alt selects by word', () async {
        await testNocterm('word selection', (tester) async {
          final controller = await pumpField(tester, style);
          await send(tester, LogicalKey.arrowLeft, ctrlShift);
          expect(controller.selection.baseOffset, 16);
          expect(controller.selection.extentOffset, 11);
          await send(tester, LogicalKey.arrowLeft, altShift);
          expect(controller.selection.extentOffset, 6);
          await send(tester, LogicalKey.arrowRight, altShift);
          expect(controller.selection.baseOffset, 16);
          expect(controller.selection.extentOffset, greaterThan(6));
        });
      });

      test('Alt+Backspace and Ctrl+Backspace delete the previous word',
          () async {
        await testNocterm('delete backward', (tester) async {
          final controller = await pumpField(tester, style);
          await send(tester, LogicalKey.backspace, alt);
          expect(controller.text, 'alpha beta ');
          await send(tester, LogicalKey.backspace, ctrl);
          expect(controller.text, 'alpha ');
          expect(controller.selection.extentOffset, 6);
        });
      });

      test('word delete removes a selection first', () async {
        await testNocterm('selection delete', (tester) async {
          final controller = await pumpField(tester, style);
          controller.selection =
              const TextSelection(baseOffset: 6, extentOffset: 10);
          await send(tester, LogicalKey.backspace, alt);
          expect(controller.text, 'alpha  gamma');
          expect(controller.selection.extentOffset, 6);
        });
      });

      test('Alt+Right then Alt+Backspace removes exactly the jumped text',
          () async {
        await testNocterm('round trip', (tester) async {
          final controller = await pumpField(tester, style);
          await placeCursor(tester, controller, 0);
          await send(tester, LogicalKey.arrowRight, alt);
          final jumped = controller.selection.extentOffset;
          expect(jumped, greaterThan(0));
          await send(tester, LogicalKey.backspace, alt);
          expect(controller.text, original.substring(jumped));
          expect(controller.selection.extentOffset, 0);
        });
      });
    });
  }

  group('TextField word navigation (end of word)', () {
    const style = WordJumpStyle.endOfWord;

    test('Alt+Right stops at the end of the current word', () async {
      await testNocterm('right', (tester) async {
        final controller = await pumpField(tester, style);
        await placeCursor(tester, controller, 6);
        await send(tester, LogicalKey.arrowRight, alt);
        expect(controller.selection.extentOffset, 10);
        await send(tester, LogicalKey.arrowRight, ctrl);
        expect(controller.selection.extentOffset, 16);
      });
    });

    test('forward word delete keeps the following separator', () async {
      await testNocterm('delete forward', (tester) async {
        final controller = await pumpField(tester, style);
        await placeCursor(tester, controller, 0);
        await altChord(tester, LogicalKey.keyD, 'd');
        expect(controller.text, ' beta gamma');
        await send(tester, LogicalKey.delete, alt);
        expect(controller.text, ' gamma');
        await send(tester, LogicalKey.delete, ctrl);
        expect(controller.text, '');
        expect(controller.selection.extentOffset, 0);
      });
    });
  });

  group('TextField word navigation (start of next word)', () {
    const style = WordJumpStyle.startOfNextWord;

    test('Alt+Right lands on the start of the next word', () async {
      await testNocterm('right', (tester) async {
        final controller = await pumpField(tester, style);
        await placeCursor(tester, controller, 6);
        await send(tester, LogicalKey.arrowRight, alt);
        expect(controller.selection.extentOffset, 11);
        await send(tester, LogicalKey.arrowRight, ctrl);
        expect(controller.selection.extentOffset, 16);
      });
    });

    test('forward word delete takes the following separator too', () async {
      await testNocterm('delete forward', (tester) async {
        final controller = await pumpField(tester, style);
        await placeCursor(tester, controller, 0);
        await altChord(tester, LogicalKey.keyD, 'd');
        expect(controller.text, 'beta gamma');
        await send(tester, LogicalKey.delete, alt);
        expect(controller.text, 'gamma');
        await send(tester, LogicalKey.delete, ctrl);
        expect(controller.text, '');
        expect(controller.selection.extentOffset, 0);
      });
    });
  });
}
