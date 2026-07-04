import 'package:nocterm/nocterm.dart' hide isEmpty;
import 'package:test/test.dart';

import 'test_text_render.dart';

/// A selectable text leaf that records the scroll requests the mixin makes.
class _SelfScrollingRender extends TestTextRender with SelfScrollingSelectable {
  _SelfScrollingRender(super.text);

  final rows = <int>[];
  bool canScroll = true;
  Duration now = Duration.zero;

  @override
  Duration Function()? get autoScrollClock => () => now;

  @override
  bool scrollSelectionBy(int rows) {
    this.rows.add(rows);
    return canScroll;
  }
}

void main() {
  group('SelfScrollingSelectable', () {
    _SelfScrollingRender laidOut() {
      // A 4x7 viewport: rows 0..2 are the top band, 4..6 the bottom, row 3 a
      // neutral middle where a drag selects without auto-scrolling.
      return _SelfScrollingRender('aaaa\nbbbb\ncccc')
        ..layout(BoxConstraints.tight(const Size(4, 7)));
    }

    // Two end-edge ticks a second apart: the first seeds the clock, the second
    // measures one second of elapsed time, so velocity (rows/sec) resolves to
    // whole rows. Returns the second tick's result.
    SelectionResult pump(_SelfScrollingRender render, Offset position) {
      final event = SelectionEdgeUpdateEvent.forEnd(globalPosition: position);
      render.dispatchSelectionEvent(event);
      render.now += const Duration(seconds: 1);
      return render.dispatchSelectionEvent(event);
    }

    test(
        'end edge past the bottom scrolls toward content end and reports '
        'pending', () {
      final render = laidOut();

      final result = pump(render, const Offset(0, 6));

      expect(render.rows.single, greaterThan(0)); // toward content end
      expect(result, SelectionResult.pending);
    });

    test('end edge above the top scrolls toward content start', () {
      final render = laidOut();

      final result = pump(render, const Offset(0, -1));

      expect(render.rows.single, lessThan(0)); // toward content start
      expect(result, SelectionResult.pending);
    });

    test('end edge inside the bounds never scrolls', () {
      final render = laidOut();

      final result = pump(render, const Offset(1, 3));

      expect(render.rows, isEmpty);
      expect(result, isNot(SelectionResult.pending));
    });

    test('exhausted content stops the pump: no movement, no pending', () {
      final render = laidOut()..canScroll = false;

      final result = pump(render, const Offset(0, -1));

      expect(render.rows.single, lessThan(0));
      expect(result, isNot(SelectionResult.pending));
    });

    test(
        'the start edge never auto-scrolls — only the end edge has a '
        'pending re-dispatch pump', () {
      final render = laidOut();

      final result = render.dispatchSelectionEvent(
        const SelectionEdgeUpdateEvent.forStart(globalPosition: Offset(0, -1)),
      );

      expect(render.rows, isEmpty);
      expect(result, isNot(SelectionResult.pending));
    });
  });
}
