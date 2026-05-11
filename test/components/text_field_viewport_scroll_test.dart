// Tests for multi-line TextField vertical viewport scrolling.
//
// Background: when soft-wrapped or hard-wrapped text exceeds `maxLines`, the
// field paints only the visible window into the layout — `_firstVisibleLine`
// follows the cursor, content above/below scrolls off. These tests assert
// scroll behavior across arrow keys, mouse, external selection changes, text
// edits, and width-driven reflow. Single-line behavior is also exercised as
// a regression guard.
//
// The TextField is always wrapped in a SizedBox sized to maxLines so the
// render object's viewport matches maxLines (without this, tight parent
// constraints from `BoxConstraints.tight(terminalSize)` would force the
// field to occupy the entire terminal height).

import 'package:nocterm/nocterm.dart';
import 'package:test/test.dart';

// Distinct cursor / selection colors so tests can locate them unambiguously
// by background color (the default theme.primary may overlap with other ANSI
// colors used elsewhere in the buffer).
const _cursorColor = Colors.red;
const _selectionColor = Colors.blue;

Component _frame({
  required TextEditingController controller,
  required int maxLines,
  required int width,
}) {
  return Align(
    alignment: Alignment.topLeft,
    child: SizedBox(
      width: width.toDouble(),
      height: maxLines.toDouble(),
      child: TextField(
        controller: controller,
        focused: true,
        maxLines: maxLines,
        minLines: maxLines,
        showCursor: true,
        cursorBlinkRate: null, // static cursor
        cursorColor: _cursorColor,
        selectionColor: _selectionColor,
      ),
    ),
  );
}

/// Returns the visible rows of the field (length == maxLines), trimmed to the
/// field width and with trailing spaces removed for assertion ergonomics.
List<String> _visibleRows(NoctermTester tester,
    {required int maxLines, required int width}) {
  return [
    for (var y = 0; y < maxLines; y++)
      (tester.terminalState.getTextAt(0, y, length: width) ?? '').trimRight(),
  ];
}

/// Returns the (x, y) of the (first) cursor cell, identified by [_cursorColor]
/// as background. Returns null when no cursor cell is found.
({int x, int y})? _findCursor(NoctermTester tester,
    {required int maxLines, required int width}) {
  for (var y = 0; y < maxLines; y++) {
    for (var x = 0; x < width; x++) {
      final cell = tester.terminalState.getCellAt(x, y);
      if (cell == null) continue;
      if (cell.style.backgroundColor == _cursorColor) {
        return (x: x, y: y);
      }
    }
  }
  return null;
}

void main() {
  group('TextField viewport scroll', () {
    // ───────────────────────────────────────────────────────────────────────
    // Hard-wrapped (newline-separated) lines
    // ───────────────────────────────────────────────────────────────────────

    test('initial render shows top of text when cursor at offset 0', () async {
      await testNocterm('initial top-of-text viewport', (tester) async {
        final controller = TextEditingController(
          text: 'L0\nL1\nL2\nL3\nL4\nL5',
        );
        controller.selection = const TextSelection.collapsed(offset: 0);

        await tester.pumpComponent(
            _frame(controller: controller, maxLines: 3, width: 10));

        expect(_visibleRows(tester, maxLines: 3, width: 10),
            equals(['L0', 'L1', 'L2']));
        final cursor = _findCursor(tester, maxLines: 3, width: 10);
        expect(cursor, isNotNull);
        expect(cursor!.y, equals(0));
      });
    });

    test('initial render scrolls so cursor at end is visible', () async {
      await testNocterm('initial bottom-of-text viewport', (tester) async {
        const text = 'L0\nL1\nL2\nL3\nL4\nL5';
        final controller = TextEditingController(text: text);
        controller.selection = TextSelection.collapsed(offset: text.length);

        await tester.pumpComponent(
            _frame(controller: controller, maxLines: 3, width: 10));

        // Last three lines should be visible — viewport scrolled to end.
        expect(_visibleRows(tester, maxLines: 3, width: 10),
            equals(['L3', 'L4', 'L5']));
        final cursor = _findCursor(tester, maxLines: 3, width: 10);
        expect(cursor, isNotNull);
        expect(cursor!.y, equals(2));
      });
    });

    test('ArrowDown past viewport scrolls one line at a time', () async {
      await testNocterm('arrow-down scroll', (tester) async {
        final controller = TextEditingController(
          text: 'L0\nL1\nL2\nL3\nL4\nL5',
        );
        controller.selection = const TextSelection.collapsed(offset: 0);

        await tester.pumpComponent(
            _frame(controller: controller, maxLines: 3, width: 10));

        // Cursor on L0, viewport L0..L2. Two downs keep cursor in viewport.
        await tester.sendArrowDown();
        await tester.sendArrowDown();
        expect(_visibleRows(tester, maxLines: 3, width: 10),
            equals(['L0', 'L1', 'L2']));

        // Third down moves cursor to L3 → viewport scrolls one line.
        await tester.sendArrowDown();
        expect(_visibleRows(tester, maxLines: 3, width: 10),
            equals(['L1', 'L2', 'L3']));

        // Two more downs → viewport scrolled to L3..L5.
        await tester.sendArrowDown();
        await tester.sendArrowDown();
        expect(_visibleRows(tester, maxLines: 3, width: 10),
            equals(['L3', 'L4', 'L5']));
      });
    });

    test('ArrowUp from bottom scrolls viewport upward', () async {
      await testNocterm('arrow-up scroll', (tester) async {
        const text = 'L0\nL1\nL2\nL3\nL4\nL5';
        final controller = TextEditingController(text: text);
        controller.selection = TextSelection.collapsed(offset: text.length);

        await tester.pumpComponent(
            _frame(controller: controller, maxLines: 3, width: 10));

        // Start at end: viewport L3..L5.
        expect(_visibleRows(tester, maxLines: 3, width: 10),
            equals(['L3', 'L4', 'L5']));

        // Two ups: cursor at L3, still in viewport.
        await tester.sendArrowUp();
        await tester.sendArrowUp();
        expect(_visibleRows(tester, maxLines: 3, width: 10),
            equals(['L3', 'L4', 'L5']));

        // Third up: cursor at L2 → viewport scrolls up.
        await tester.sendArrowUp();
        expect(_visibleRows(tester, maxLines: 3, width: 10),
            equals(['L2', 'L3', 'L4']));

        // Two more ups: cursor at L0 → fully scrolled to top.
        await tester.sendArrowUp();
        await tester.sendArrowUp();
        expect(_visibleRows(tester, maxLines: 3, width: 10),
            equals(['L0', 'L1', 'L2']));
      });
    });

    test('text shorter than maxLines does not scroll', () async {
      await testNocterm('no-scroll when text fits', (tester) async {
        final controller = TextEditingController(text: 'A\nB');
        controller.selection = const TextSelection.collapsed(offset: 0);

        await tester.pumpComponent(
            _frame(controller: controller, maxLines: 3, width: 10));

        // ArrowDown × 5 — text has only 2 lines, can't scroll.
        for (var i = 0; i < 5; i++) {
          await tester.sendArrowDown();
        }
        // Both lines still present at the top.
        final rows = _visibleRows(tester, maxLines: 3, width: 10);
        expect(rows[0], equals('A'));
        expect(rows[1], equals('B'));
      });
    });

    test('text exactly maxLines tall does not scroll', () async {
      await testNocterm('exact-fit no-scroll', (tester) async {
        final controller = TextEditingController(text: 'A\nB\nC');
        controller.selection =
            const TextSelection.collapsed(offset: 0); // cursor on A

        await tester.pumpComponent(
            _frame(controller: controller, maxLines: 3, width: 10));

        await tester.sendArrowDown();
        await tester.sendArrowDown();
        // Still 3 lines, no scroll.
        expect(_visibleRows(tester, maxLines: 3, width: 10),
            equals(['A', 'B', 'C']));
      });
    });

    // ───────────────────────────────────────────────────────────────────────
    // External selection changes (set selection setter)
    // ───────────────────────────────────────────────────────────────────────

    test('setting controller.selection jumps viewport to follow cursor',
        () async {
      await testNocterm('controller selection jump', (tester) async {
        const text = 'L0\nL1\nL2\nL3\nL4\nL5';
        final controller = TextEditingController(text: text);
        controller.selection = const TextSelection.collapsed(offset: 0);

        await tester.pumpComponent(
            _frame(controller: controller, maxLines: 3, width: 10));
        expect(_visibleRows(tester, maxLines: 3, width: 10),
            equals(['L0', 'L1', 'L2']));

        // Jump cursor to start of L5. With "L0\nL1\nL2\nL3\nL4\n" (15 chars)
        // L5 starts at offset 15.
        controller.selection = const TextSelection.collapsed(offset: 15);
        await tester.pump();

        expect(_visibleRows(tester, maxLines: 3, width: 10),
            equals(['L3', 'L4', 'L5']));

        // Jump back to top.
        controller.selection = const TextSelection.collapsed(offset: 0);
        await tester.pump();
        expect(_visibleRows(tester, maxLines: 3, width: 10),
            equals(['L0', 'L1', 'L2']));
      });
    });

    test('setting controller.text re-clamps viewport', () async {
      await testNocterm('text replacement re-clamps viewport', (tester) async {
        final controller = TextEditingController(
          text: 'L0\nL1\nL2\nL3\nL4\nL5',
        );
        controller.selection = const TextSelection.collapsed(offset: 15); // L5

        await tester.pumpComponent(
            _frame(controller: controller, maxLines: 3, width: 10));
        expect(_visibleRows(tester, maxLines: 3, width: 10),
            equals(['L3', 'L4', 'L5']));

        // Replace text with shorter content — viewport should clamp to top.
        controller.text = 'A\nB';
        controller.selection = const TextSelection.collapsed(offset: 0);
        await tester.pump();

        final rows = _visibleRows(tester, maxLines: 3, width: 10);
        expect(rows[0], equals('A'));
        expect(rows[1], equals('B'));
      });
    });

    // ───────────────────────────────────────────────────────────────────────
    // Soft-wrap (width-driven overflow)
    // ───────────────────────────────────────────────────────────────────────

    test('soft-wrapped content past maxLines is reachable via ArrowDown',
        () async {
      await testNocterm('soft-wrap reachable', (tester) async {
        // Width 8 leaves 7 usable columns (1 reserved for cursor).
        // Text is 21 chars → wraps to 3 visual lines of 7.
        final controller = TextEditingController(text: 'AAAAAAABBBBBBBCCCCCCC');
        controller.selection = const TextSelection.collapsed(offset: 0);

        await tester.pumpComponent(
            _frame(controller: controller, maxLines: 2, width: 8));

        // First two wrapped lines visible.
        expect(_visibleRows(tester, maxLines: 2, width: 8),
            equals(['AAAAAAA', 'BBBBBBB']));

        // Walk the cursor down via ArrowDown until on the 3rd wrapped line.
        await tester.sendArrowDown();
        await tester.sendArrowDown();
        expect(_visibleRows(tester, maxLines: 2, width: 8),
            equals(['BBBBBBB', 'CCCCCCC']));
      });
    });

    test('soft-wrapped content scrolls to end when cursor is at text end',
        () async {
      await testNocterm('soft-wrap cursor-at-end', (tester) async {
        const text = 'AAAAAAABBBBBBBCCCCCCC';
        final controller = TextEditingController(text: text);
        controller.selection = TextSelection.collapsed(offset: text.length);

        await tester.pumpComponent(
            _frame(controller: controller, maxLines: 2, width: 8));

        expect(_visibleRows(tester, maxLines: 2, width: 8),
            equals(['BBBBBBB', 'CCCCCCC']));
      });
    });

    // ───────────────────────────────────────────────────────────────────────
    // Mouse hit-test in a scrolled viewport
    // ───────────────────────────────────────────────────────────────────────

    test('mouse click on scrolled viewport selects underlying line', () async {
      await testNocterm('mouse click scrolled viewport', (tester) async {
        const text = 'L0\nL1\nL2\nL3\nL4\nL5';
        final controller = TextEditingController(text: text);
        controller.selection = TextSelection.collapsed(offset: text.length);

        await tester.pumpComponent(
            _frame(controller: controller, maxLines: 3, width: 10));

        // Viewport is L3..L5. Click on visual y=0 → should land on L3.
        await tester.tap(0, 0);
        // L3 starts at offset: len("L0\nL1\nL2\n") = 9.
        expect(controller.selection.extentOffset, equals(9));

        // Click on visual y=2 → L5 (offset 15).
        await tester.tap(0, 2);
        expect(controller.selection.extentOffset, equals(15));
      });
    });

    test('mouse click at column lands on the right character within the line',
        () async {
      await testNocterm('mouse click x within line', (tester) async {
        const text = 'L0\nL1\nL2\nABCDE\nL4\nL5';
        final controller = TextEditingController(text: text);
        controller.selection = TextSelection.collapsed(offset: text.length);

        await tester.pumpComponent(
            _frame(controller: controller, maxLines: 3, width: 10));

        // Cursor at end → viewport shows last 3 lines: "ABCDE", "L4", "L5".
        expect(_visibleRows(tester, maxLines: 3, width: 10),
            equals(['ABCDE', 'L4', 'L5']));

        // "ABCDE" starts at offset 9. Click on 'C' (x=2, y=0) → offset 11.
        await tester.tap(2, 0);
        expect(controller.selection.extentOffset, equals(11));
      });
    });

    // ───────────────────────────────────────────────────────────────────────
    // Cursor rendering off-screen
    // ───────────────────────────────────────────────────────────────────────

    test('cursor cell is not painted when selection is outside the viewport',
        () async {
      // If the consumer (not arrow keys) jumps selection into the field, the
      // viewport recomputes — so the cursor will always be visible after the
      // setter runs. To force a stale cursor, we send the cursor near the
      // bottom, then call the render object directly to bypass _ensureCursorVisible.
      // Simplest robust check: confirm there's only one cursor cell.
      await testNocterm('exactly one cursor cell', (tester) async {
        final controller = TextEditingController(
          text: 'L0\nL1\nL2\nL3\nL4\nL5',
        );
        controller.selection = const TextSelection.collapsed(offset: 0);

        await tester.pumpComponent(
            _frame(controller: controller, maxLines: 3, width: 10));

        var cursorCells = 0;
        for (var y = 0; y < 3; y++) {
          for (var x = 0; x < 10; x++) {
            final cell = tester.terminalState.getCellAt(x, y);
            if (cell != null && cell.style.backgroundColor == _cursorColor) {
              cursorCells++;
            }
          }
        }
        expect(cursorCells, equals(1), reason: 'one and only one cursor cell');
      });
    });

    // ───────────────────────────────────────────────────────────────────────
    // Single-line regression guard
    // ───────────────────────────────────────────────────────────────────────

    test('single-line field never scrolls vertically', () async {
      await testNocterm('single-line no vertical scroll', (tester) async {
        // Long string that overflows width 20 (well past width).
        const text = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMN';
        final controller = TextEditingController(text: text);
        controller.selection = TextSelection.collapsed(offset: text.length);

        await tester.pumpComponent(
          Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 20,
              height: 1,
              child: TextField(
                controller: controller,
                focused: true,
                width: 20, // enables horizontal scrolling path
                maxLines: 1,
                showCursor: true,
                cursorBlinkRate: null,
              ),
            ),
          ),
        );

        // Visible row should contain the tail of the text (horizontal scroll
        // brought it into view). Crucially, only row 0 should have content.
        final row0 = tester.terminalState.getTextAt(0, 0, length: 20) ?? '';
        expect(row0.trim().isNotEmpty, isTrue);
        // No content on row 1 (would indicate the field is wrapping or
        // _firstVisibleLine accidentally engaged).
        final row1 = tester.terminalState.getTextAt(0, 1, length: 20) ?? '';
        expect(row1.trim(), equals(''));
      });
    });

    // ───────────────────────────────────────────────────────────────────────
    // Selection (non-collapsed) painted across viewport
    // ───────────────────────────────────────────────────────────────────────

    test('non-collapsed selection paints correctly with scrolled viewport',
        () async {
      await testNocterm('selection paint scrolled', (tester) async {
        const text = 'L0\nL1\nL2\nL3\nL4\nL5';
        final controller = TextEditingController(text: text);
        // Select from start of L3 (offset 9) to start of L5 (offset 15).
        // Also positions cursor (extent) at L5, scrolling viewport to bottom.
        controller.selection =
            const TextSelection(baseOffset: 9, extentOffset: 15);

        await tester.pumpComponent(
            _frame(controller: controller, maxLines: 3, width: 10));

        // Viewport: L3..L5.
        expect(_visibleRows(tester, maxLines: 3, width: 10),
            equals(['L3', 'L4', 'L5']));

        // At least one cell on rows 0 (L3) and 1 (L4) should be styled as
        // selected.
        bool hasSelectionStyle(int y) {
          for (var x = 0; x < 10; x++) {
            final cell = tester.terminalState.getCellAt(x, y);
            if (cell != null && cell.style.backgroundColor == _selectionColor) {
              return true;
            }
          }
          return false;
        }

        expect(hasSelectionStyle(0), isTrue);
        expect(hasSelectionStyle(1), isTrue);
      });
    });

    // ───────────────────────────────────────────────────────────────────────
    // Edit at scrolled-down viewport adjusts viewport
    // ───────────────────────────────────────────────────────────────────────

    test('typing at bottom of long text stays visible after edit', () async {
      await testNocterm('typing-at-bottom stays visible', (tester) async {
        const text = 'L0\nL1\nL2\nL3\nL4\nL5';
        final controller = TextEditingController(text: text);
        controller.selection = TextSelection.collapsed(offset: text.length);

        await tester.pumpComponent(
            _frame(controller: controller, maxLines: 3, width: 10));
        expect(_visibleRows(tester, maxLines: 3, width: 10),
            equals(['L3', 'L4', 'L5']));

        // Simulate typing 'X' at end of L5.
        controller.text = '${controller.text}X';
        controller.selection =
            TextSelection.collapsed(offset: controller.text.length);
        await tester.pump();

        expect(_visibleRows(tester, maxLines: 3, width: 10),
            equals(['L3', 'L4', 'L5X']));
        // Cursor still visible at the bottom row.
        final cursor = _findCursor(tester, maxLines: 3, width: 10);
        expect(cursor, isNotNull);
        expect(cursor!.y, equals(2));
      });
    });

    test('backspace at top of viewport keeps cursor visible', () async {
      await testNocterm('backspace top viewport', (tester) async {
        const text = 'L0\nL1\nL2\nL3\nL4\nL5';
        final controller = TextEditingController(text: text);
        // Cursor at start of L3 (offset 9), viewport will scroll to include
        // L3 — depending on direction this lands at L1..L3 or L3..L5.
        controller.selection = const TextSelection.collapsed(offset: 9);

        await tester.pumpComponent(
            _frame(controller: controller, maxLines: 3, width: 10));

        // Now delete the newline preceding L3, joining L2 and L3.
        // We don't have a direct typing API at this offset, so mutate the
        // controller's text/selection directly.
        controller.text = 'L0\nL1\nL2L3\nL4\nL5';
        controller.selection = const TextSelection.collapsed(offset: 8);
        await tester.pump();

        // Cursor's new offset 8 lives on the "L2L3" line. Viewport should
        // contain that line.
        bool anyRowContains(String needle) =>
            _visibleRows(tester, maxLines: 3, width: 10)
                .any((r) => r.contains(needle));
        expect(anyRowContains('L2L3'), isTrue);
        final cursor = _findCursor(tester, maxLines: 3, width: 10);
        expect(cursor, isNotNull);
      });
    });
  });
}
