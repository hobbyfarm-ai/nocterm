import 'package:nocterm/nocterm.dart';
import 'package:test/test.dart';

void main() {
  test('TextField should have default selection color', () async {
    await testNocterm(
      'default selection color',
      (tester) async {
        final controller = TextEditingController(text: 'Test selection colors');

        await tester.pumpComponent(
          Container(
            width: 30,
            height: 3,
            decoration: BoxDecoration(border: BoxBorder.all()),
            child: TextField(
              controller: controller,
              focused: true,
              // No selectionColor or cursorColor specified - using defaults
            ),
          ),
        );

        // Select all text
        await tester.sendKeyEvent(KeyboardEvent(
          logicalKey: LogicalKey.keyA,
          modifiers: ModifierKeys(ctrl: true),
        ));

        // Verify selection is made
        expect(controller.selection.start, 0);
        expect(controller.selection.end, controller.text.length);
        expect(controller.selection.isCollapsed, false);

        final selectedCell = tester.terminalState.buffer.getCell(1, 1);
        expect(selectedCell.char, 'T');
        expect(
          selectedCell.style.backgroundColor,
          TuiThemeData.dark.selection,
        );
        expect(selectedCell.style.color, TuiThemeData.dark.onSelection);
      },
    );
  });
}
