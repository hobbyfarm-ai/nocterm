import 'dart:math' as math;

import 'package:nocterm/nocterm.dart';
import 'package:test/test.dart';

/// Submits metrics describing a 10-row viewport over [contentRows] of
/// content laid out at [width] columns, returning updateMetrics' verdict.
bool _submit(
  ScrollController controller, {
  required double contentRows,
  required double width,
}) {
  return controller.updateMetrics(
    minScrollExtent: 0,
    maxScrollExtent: math.max(0, contentRows - 10),
    viewportDimension: 10,
    crossAxisExtent: width,
  );
}

void main() {
  group('ScrollController reflow end pin', () {
    test('pins to the end across a reflow when reading the tail', () {
      final controller = ScrollController();
      _submit(controller, contentRows: 50, width: 60);
      controller.jumpTo(40);

      // The pane narrows and the same content re-wraps taller: the tail is
      // still what the reader was reading, so the pass is rejected and the
      // offset corrected to the new end.
      expect(_submit(controller, contentRows: 80, width: 30), isFalse);
      expect(controller.offset, 70);
      expect(_submit(controller, contentRows: 80, width: 30), isTrue);
      controller.dispose();
    });

    test('chases an extent estimate that moves between passes', () {
      // Lazily-measured content revises its total extent as passes build
      // different children; the pin re-applies until offset and end agree.
      final controller = ScrollController();
      _submit(controller, contentRows: 50, width: 60);
      controller.jumpTo(40);

      expect(_submit(controller, contentRows: 80, width: 30), isFalse);
      expect(controller.offset, 70);
      expect(_submit(controller, contentRows: 85, width: 30), isFalse);
      expect(controller.offset, 75);
      expect(_submit(controller, contentRows: 85, width: 30), isTrue);
      expect(controller.offset, 75);
      controller.dispose();
    });

    test('does not stick to the end when content is appended', () {
      // The guard for the whole design: same cross axis means append, and a
      // plain controller at the bottom stays put — following the tail is
      // AutoScrollController's job, opt-in only.
      final controller = ScrollController();
      _submit(controller, contentRows: 50, width: 60);
      controller.jumpTo(40);

      expect(_submit(controller, contentRows: 53, width: 60), isTrue);
      expect(controller.offset, 40);
      controller.dispose();
    });

    test('does not pin a reader in the middle of the content', () {
      final controller = ScrollController();
      _submit(controller, contentRows: 50, width: 60);
      controller.jumpTo(20);

      expect(_submit(controller, contentRows: 80, width: 30), isTrue);
      expect(controller.offset, 20);
      controller.dispose();
    });

    test('never pins an unscrolled view', () {
      // A list that fitted (max 0) and overflows after narrowing must stay
      // at the top: an offset of zero is not "reading the tail".
      final controller = ScrollController();
      _submit(controller, contentRows: 8, width: 60);
      expect(controller.offset, 0);

      expect(_submit(controller, contentRows: 15, width: 30), isTrue);
      expect(controller.offset, 0);
      controller.dispose();
    });

    test('a null cross-axis extent skips detection without forgetting', () {
      final controller = ScrollController();
      _submit(controller, contentRows: 50, width: 60);
      controller.jumpTo(40);

      // A caller that doesn't track a cross axis (an event handler syncing
      // metrics) neither triggers nor clears reflow detection.
      expect(
        controller.updateMetrics(
          minScrollExtent: 0,
          maxScrollExtent: 40,
          viewportDimension: 10,
        ),
        isTrue,
      );
      expect(controller.offset, 40);

      // The stored extent survived: a genuine reflow is still detected.
      expect(_submit(controller, contentRows: 80, width: 30), isFalse);
      expect(controller.offset, 70);
      controller.dispose();
    });

    test('jumpTo cancels a pin in progress', () {
      final controller = ScrollController();
      _submit(controller, contentRows: 50, width: 60);
      controller.jumpTo(40);

      expect(_submit(controller, contentRows: 80, width: 30), isFalse);
      controller.jumpTo(5);

      expect(_submit(controller, contentRows: 80, width: 30), isTrue);
      expect(controller.offset, 5);
      controller.dispose();
    });

    test('stands down when a viewport correction already steered', () {
      // A content anchor only exists when the view was not reading the
      // tail; its corrections land before metrics do, so a received
      // correction means wasNearEnd would be judged against a
      // mid-negotiation offset. The pin must not fight the anchor.
      final controller = ScrollController();
      _submit(controller, contentRows: 50, width: 60);
      controller.jumpTo(39);

      controller.correctBy(-10);
      expect(_submit(controller, contentRows: 80, width: 30), isTrue);
      expect(controller.offset, 29);
      controller.dispose();
    });
  });

  group('AutoScrollController synchronous auto-scroll', () {
    test('corrects to the end in the same layout, no frame late', () {
      final controller = AutoScrollController();
      _submit(controller, contentRows: 50, width: 60);
      controller.jumpTo(40);

      // Content is appended while reading the tail: the pass is rejected
      // with the offset already at the new end — the viewport re-lays-out
      // and the tail is on screen this frame.
      expect(_submit(controller, contentRows: 53, width: 60), isFalse);
      expect(controller.offset, 43);
      expect(_submit(controller, contentRows: 53, width: 60), isTrue);
      controller.dispose();
    });

    test('leaves a reader who scrolled up alone', () {
      final controller = AutoScrollController();
      _submit(controller, contentRows: 50, width: 60);
      controller.jumpTo(40);
      _submit(controller, contentRows: 50, width: 60);
      controller.jumpTo(20);

      expect(_submit(controller, contentRows: 53, width: 60), isTrue);
      expect(controller.offset, 20);
      controller.dispose();
    });
  });
}
