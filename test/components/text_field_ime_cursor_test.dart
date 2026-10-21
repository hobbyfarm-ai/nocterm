import 'package:nocterm/nocterm.dart';
import 'package:test/test.dart';

/// A focused field asks the frame for the terminal cursor at its caret, so
/// an IME composition window anchors there. Rows count real newlines once:
/// the buggy version checked whether the text up to the caret ended with
/// a newline, which never sees the newline at the split, so consecutive
/// empty lines put the cursor a row too low.
void main() {
  group('TextField terminal cursor', () {
    test('tracks the cursor row across consecutive newlines', () async {
      await testNocterm('ime cursor consecutive newlines', (tester) async {
        final controller = TextEditingController(text: 'a\n\nb\nc');
        await tester.pumpComponent(
          TextField(
            controller: controller,
            width: 20,
            maxLines: 6,
            focused: true,
          ),
        );

        controller.selection = const TextSelection.collapsed(offset: 0);
        await tester.pump();
        final atA = tester.cursor;
        expect(atA, isNotNull);

        controller.selection = const TextSelection.collapsed(offset: 3);
        await tester.pump();
        final atB = tester.cursor;
        expect(atB, isNotNull);

        controller.selection = const TextSelection.collapsed(offset: 5);
        await tester.pump();
        final atC = tester.cursor;
        expect(atC, isNotNull);

        expect(atB!.y - atA!.y, 2, reason: "'b' is two rows below 'a'");
        expect(atC!.y - atA.y, 3, reason: "'c' is three rows below 'a'");
        expect(atB.x, atA.x, reason: "'b' starts its line like 'a'");
        expect(atA.shape, CursorShape.block);
      });
    });

    test('an unfocused field asks for no cursor', () async {
      await testNocterm('ime cursor unfocused', (tester) async {
        await tester.pumpComponent(
          TextField(
            controller: TextEditingController(text: 'a'),
            width: 20,
            focused: false,
          ),
        );
        expect(tester.cursor, isNull);
      });
    });

    test('a caret scrolled out of the field asks for no cursor', () async {
      await testNocterm('ime cursor scrolled', (tester) async {
        final controller = TextEditingController(text: 'a\nb\nc\nd\ne');
        await tester.pumpComponent(
          TextField(
            controller: controller,
            width: 20,
            maxLines: 2,
            focused: true,
            cursorStyle: CursorStyle.underline,
          ),
        );
        controller.selection = const TextSelection.collapsed(offset: 8);
        await tester.pump();
        expect(tester.cursor?.shape, CursorShape.underline);
        expect(tester.cursor?.y, 1);
      });
    });
  });
}
