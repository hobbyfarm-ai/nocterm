import 'package:nocterm/src/framework/framework.dart';
import 'package:nocterm/src/rectangle.dart';
import 'package:nocterm/src/selection/selection.dart';
import 'package:test/test.dart';

class _FakeRegistrar implements SelectionRegistrar {
  final added = <Selectable>[];
  final removed = <Selectable>[];

  @override
  void add(Selectable selectable) => added.add(selectable);

  @override
  void remove(Selectable selectable) => removed.add(selectable);
}

class _TestSelectable extends RenderObject
    with Selectable, SelectionRegistrant {
  @override
  void performLayout() {}

  @override
  Offset get globalPaintOffset => Offset.zero;

  @override
  Rect get globalBounds => const Rect.fromLTWH(0, 0, 0, 0);

  @override
  SelectionResult dispatchSelectionEvent(SelectionEvent event) =>
      SelectionResult.none;

  @override
  SelectedContent? getSelectedContent() => null;

  @override
  int get contentLength => 0;

  void setGeometry(SelectionGeometry geometry) =>
      updateSelectionGeometry(geometry);
}

const _emptyGeometry = SelectionGeometry(
  status: SelectionStatus.none,
  hasContent: false,
);

const _contentGeometry = SelectionGeometry(
  status: SelectionStatus.none,
  hasContent: true,
);

void main() {
  group('SelectionUtils.getResultBasedOnRect', () {
    // Covers rows 1-2, columns 2-6.
    const rect = Rect.fromLTWH(2, 1, 5, 2);

    test('point inside returns end', () {
      expect(SelectionUtils.getResultBasedOnRect(rect, const Offset(3, 1)),
          SelectionResult.end);
      expect(SelectionUtils.getResultBasedOnRect(rect, const Offset(6, 2)),
          SelectionResult.end);
    });

    test('point above returns previous', () {
      expect(SelectionUtils.getResultBasedOnRect(rect, const Offset(3, 0)),
          SelectionResult.previous);
    });

    test('point below returns next', () {
      expect(SelectionUtils.getResultBasedOnRect(rect, const Offset(3, 3)),
          SelectionResult.next);
    });

    test('point right of rect on same rows returns next', () {
      expect(SelectionUtils.getResultBasedOnRect(rect, const Offset(7, 1)),
          SelectionResult.next);
      expect(SelectionUtils.getResultBasedOnRect(rect, const Offset(10, 2)),
          SelectionResult.next);
    });

    test('point left of rect on same rows returns previous', () {
      expect(SelectionUtils.getResultBasedOnRect(rect, const Offset(1, 2)),
          SelectionResult.previous);
      expect(SelectionUtils.getResultBasedOnRect(rect, const Offset(0, 1)),
          SelectionResult.previous);
    });
  });

  group('SelectionUtils.adjustDragOffset', () {
    const rect = Rect.fromLTWH(2, 1, 5, 2);

    test('point inside is unchanged', () {
      expect(SelectionUtils.adjustDragOffset(rect, const Offset(4, 2)),
          const Offset(4, 2));
    });

    test('a point above the element maps to its start', () {
      expect(SelectionUtils.adjustDragOffset(rect, const Offset(4, 0)),
          const Offset(2, 1));
      // Above and to the left is still "before the start".
      expect(SelectionUtils.adjustDragOffset(rect, const Offset(0, 0)),
          const Offset(2, 1));
    });

    test('a point below the element maps to its end', () {
      expect(SelectionUtils.adjustDragOffset(rect, const Offset(4, 5)),
          const Offset(7, 2));
      // Below and to the right is still "past the end".
      expect(SelectionUtils.adjustDragOffset(rect, const Offset(9, 9)),
          const Offset(7, 2));
    });

    test('a point beside the element keeps the row it is level with', () {
      // Left of the element at row 2 → start of row 2, not the top corner.
      expect(SelectionUtils.adjustDragOffset(rect, const Offset(0, 2)),
          const Offset(2, 2));
      // Right of the element at row 1 → end of row 1, not the bottom corner.
      expect(SelectionUtils.adjustDragOffset(rect, const Offset(9, 1)),
          const Offset(7, 1));
    });
  });

  group('SelectionUtils.autoScrollVelocity', () {
    // Tall/wide enough for a neutral middle: rows 2..13, cols 0..11.
    const rect = Rect.fromLTWH(0, 2, 12, 12);

    // Pin the ramp params so these assertions test the formula, not whatever
    // speed the app currently tunes the defaults to. A band of 4 over rows
    // 2..13 makes rows 2..5 the top band, 10..13 the bottom, 6..9 neutral.
    double v(Rect r, Offset p,
            {bool vertical = true, double maxPerSecond = 20}) =>
        SelectionUtils.autoScrollVelocity(r, p,
            vertical: vertical,
            minPerSecond: 3,
            maxPerSecond: maxPerSecond,
            hotRows: 4);

    test('the neutral middle does not scroll', () {
      expect(v(rect, const Offset(5, 6)), 0);
      expect(v(rect, const Offset(5, 7)), 0);
      expect(v(rect, const Offset(5, 8)), 0);
      expect(v(rect, const Offset(5, 9)), 0);
    });

    test('the edge row is the fast zone: it scrolls at the max speed', () {
      expect(v(rect, const Offset(5, 2)), -20); // top edge row
      expect(v(rect, const Offset(5, 13)), 20); // bottom edge row (bottom = 14)
    });

    test('the band ramps from the floor at its inner row to the edge max', () {
      // toEdge 3→2→1: t = 0.25, 0.5, 0.75 over a min=3, max=20 spread.
      expect(v(rect, const Offset(5, 5)), closeTo(-7.25, 1e-9)); // inner row
      expect(v(rect, const Offset(5, 4)), closeTo(-11.5, 1e-9));
      expect(v(rect, const Offset(5, 3)), closeTo(-15.75, 1e-9));
    });

    test('a pointer past the edge stays capped at the max', () {
      expect(v(rect, const Offset(5, -20)), -20);
      expect(v(rect, const Offset(5, 40)), 20);
      expect(v(rect, const Offset(5, 40), maxPerSecond: 50), 50);
    });

    test('horizontal axis measures against left/right edges', () {
      // cols 0..11: left band 0..3, right band 8..11, 4..7 neutral.
      expect(v(rect, const Offset(0, 7), vertical: false), -20); // left edge
      expect(v(rect, const Offset(11, 7), vertical: false), 20); // right edge
      expect(v(rect, const Offset(6, 7), vertical: false), 0); // neutral
    });

    test('a viewport too short for a neutral zone activates its edge rows', () {
      // rows 0..1 — no room for a dead middle, so both edge rows run at max.
      const tiny = Rect.fromLTWH(0, 0, 4, 2);
      expect(v(tiny, const Offset(1, 0)), -20); // top edge row
      expect(v(tiny, const Offset(1, 1)), 20); // bottom edge row
    });

    test('top and bottom bands mirror each other', () {
      // Row k below the top and row k above the bottom scroll at equal speed,
      // opposite sign.
      for (var k = 0; k < 4; k++) {
        final top = v(rect, Offset(5, (2 + k).toDouble()));
        final bottom = v(rect, Offset(5, (13 - k).toDouble()));
        expect(top, -bottom, reason: 'k=$k');
      }
    });

    test('velocity rises monotonically as the pointer nears either edge', () {
      // Walking from the neutral middle out to each edge never slows down.
      double last = 0;
      for (var y = 6; y >= 2; y--) {
        final speed = v(rect, Offset(5, y.toDouble())).abs();
        expect(speed, greaterThanOrEqualTo(last), reason: 'top y=$y');
        last = speed;
      }
      last = 0;
      for (var y = 9; y <= 13; y++) {
        final speed = v(rect, Offset(5, y.toDouble())).abs();
        expect(speed, greaterThanOrEqualTo(last), reason: 'bottom y=$y');
        last = speed;
      }
    });

    test('the neutral/band boundary is exact: last neutral row vs first active',
        () {
      expect(v(rect, const Offset(5, 6)), 0); // last neutral row (toEdge == 4)
      expect(v(rect, const Offset(5, 5)), isNot(0)); // first active (toEdge 3)
      expect(v(rect, const Offset(5, 9)), 0); // last neutral, bottom side
      expect(v(rect, const Offset(5, 10)), isNot(0)); // first active, bottom
    });

    test('an active speed is always above the floor and never past the max',
        () {
      for (var y = 2; y <= 13; y++) {
        final speed = v(rect, Offset(5, y.toDouble())).abs();
        if (speed == 0) continue; // neutral
        expect(speed, greaterThan(3)); // strictly above min
        expect(speed, lessThanOrEqualTo(20)); // never past max
      }
    });

    test('the inner edge of the band approaches the floor speed', () {
      // A fractional position a hair inside the band boundary resolves to just
      // above the minimum — the ramp really does start at the floor.
      expect(v(rect, const Offset(5, 5.999)), closeTo(-3, 0.01));
    });

    test('a single-row viewport has no band and never scrolls', () {
      const row = Rect.fromLTWH(0, 5, 4, 1);
      expect(v(row, const Offset(1, 5)), 0);
      expect(v(row, const Offset(1, 4)), 0); // even reading above it
      expect(v(row, const Offset(1, 6)), 0); // or below
    });

    test('the band is capped at half the extent, not the requested hotRows',
        () {
      // rows 0..5 with hotRows 4: half-extent caps the band at 2.5, so row 2
      // (toEdge 2) sits at t = 0.2, not the 0.5 an uncapped band-of-4 would give.
      const short = Rect.fromLTWH(0, 0, 4, 6);
      expect(v(short, const Offset(1, 0)), -20); // edge still maxes
      expect(v(short, const Offset(1, 2)), closeTo(-6.4, 1e-9)); // t = 0.2
    });

    test('the shipped defaults behave sanely on a full-size viewport', () {
      // No pinned params: exercise the shipped default min/max/hotRows.
      const min = SelectionUtils.defaultMinPerSecond;
      const max = SelectionUtils.defaultMaxPerSecond;
      const full = Rect.fromLTWH(0, 0, 80, 30); // rows 0..29
      double d(Offset p) =>
          SelectionUtils.autoScrollVelocity(full, p, vertical: true);
      expect(d(const Offset(5, 0)), -max); // top edge at max
      expect(d(const Offset(5, 29)), max); // bottom edge at max
      expect(d(const Offset(5, 15)), 0); // deep middle is neutral
      for (var y = 0; y < 30; y++) {
        final speed = d(Offset(5, y.toDouble())).abs();
        expect(speed, lessThanOrEqualTo(max));
        if (speed != 0) expect(speed, greaterThan(min));
      }
    });
  });

  group('SelectionAutoScroller', () {
    test('advances by the real time between ticks', () {
      var now = Duration.zero;
      final scroller = SelectionAutoScroller(clock: () => now);
      expect(scroller.step(10), 0); // first tick seeds the clock
      now = const Duration(milliseconds: 100);
      expect(scroller.step(10), 1); // 10 rows/sec × 0.1s = one row
    });

    test('carries the sub-row remainder so slow speeds still advance', () {
      var now = Duration.zero;
      final scroller = SelectionAutoScroller(clock: () => now);
      var moved = scroller.step(2); // seed
      // 2 rows/sec: the whole row lands once 0.5s of real time has elapsed.
      for (var ms = 100; ms <= 500; ms += 100) {
        now = Duration(milliseconds: ms);
        moved += scroller.step(2);
      }
      expect(moved, 1);
    });

    test('a fast pointer cannot scroll faster than a slow one', () {
      var slowNow = Duration.zero, fastNow = Duration.zero;
      final slow = SelectionAutoScroller(clock: () => slowNow);
      final fast = SelectionAutoScroller(clock: () => fastNow);
      // Both cover one real second at 20 rows/sec, every tick under the cap:
      // the slow pointer ticks every 50ms, the fast one every 12.5ms.
      var mSlow = slow.step(20);
      for (var us = 50000; us <= 1000000; us += 50000) {
        slowNow = Duration(microseconds: us);
        mSlow += slow.step(20);
      }
      var mFast = fast.step(20);
      for (var us = 12500; us <= 1000000; us += 12500) {
        fastNow = Duration(microseconds: us);
        mFast += fast.step(20);
      }
      expect(mFast, mSlow); // identical distance for identical wall-clock
    });

    test('leaving the edge resets the clock, so an idle gap is not counted',
        () {
      var now = Duration.zero;
      final scroller = SelectionAutoScroller(clock: () => now);
      scroller.step(10); // seed at the edge
      now = const Duration(milliseconds: 100);
      scroller.step(10); // scroll for 0.1s
      // The pointer sits in the neutral middle for five seconds (velocity 0).
      now = const Duration(seconds: 5);
      expect(scroller.step(0), 0);
      // Back at the edge: the reset means this tick reseeds — the 5s idle gap
      // produces nothing, rather than a fifty-row lurch.
      now = const Duration(seconds: 5, milliseconds: 100);
      expect(scroller.step(10), 0);
      // From here real time counts again as normal.
      now = const Duration(seconds: 5, milliseconds: 200);
      expect(scroller.step(10), 1); // 0.1s → one row
    });

    test('a zero velocity clears the remainder and reseeds the clock', () {
      var now = Duration.zero;
      final scroller = SelectionAutoScroller(clock: () => now);
      scroller.step(2); // seed
      now = const Duration(milliseconds: 300);
      scroller.step(2); // remainder 0.6
      expect(scroller.step(0), 0);
      // Remainder gone and clock reseeded: a fresh short interval yields none.
      now = const Duration(milliseconds: 400);
      expect(scroller.step(2), 0);
    });

    test('a drag begun in a band is suppressed while it stays in that band',
        () {
      var now = Duration.zero;
      final scroller = SelectionAutoScroller(clock: () => now)
        ..arm(10); // the drag began inside the bottom band
      expect(scroller.isArmed, isFalse);
      scroller.step(10); // seed attempt is ignored while suppressed
      now = const Duration(milliseconds: 100);
      expect(scroller.step(10), 0); // same band: no scrolling
      expect(scroller.isArmed, isFalse);
    });

    test('a neutral tick re-arms a suppressed scroller', () {
      var now = Duration.zero;
      final scroller = SelectionAutoScroller(clock: () => now)..arm(10);
      now = const Duration(milliseconds: 100);
      expect(scroller.step(10), 0); // in the band, suppressed
      // Pointer leaves the band (velocity 0), which re-arms.
      now = const Duration(milliseconds: 200);
      expect(scroller.step(0), 0);
      expect(scroller.isArmed, isTrue);
      // Re-entering the band now scrolls: this tick reseeds the clock...
      now = const Duration(milliseconds: 300);
      expect(scroller.step(10), 0);
      // ...and time counts from here.
      now = const Duration(milliseconds: 400);
      expect(scroller.step(10), 1); // 0.1s → one row
    });

    test('crossing straight into the opposite band re-arms', () {
      var now = Duration.zero;
      // The drag began in the top band (negative velocity)...
      final scroller = SelectionAutoScroller(clock: () => now)..arm(-10);
      expect(scroller.isArmed, isFalse);
      // ...then jumps to the bottom band without a neutral sample. The
      // opposite sign means the drag left its starting band, so it re-arms
      // and this tick reseeds the clock.
      now = const Duration(milliseconds: 100);
      expect(scroller.step(10), 0);
      expect(scroller.isArmed, isTrue);
      now = const Duration(milliseconds: 200);
      expect(scroller.step(10), 1); // 0.1s → one row
    });
  });

  group('SelectionGeometry', () {
    test('equality includes selection rects', () {
      const a = SelectionGeometry(
        status: SelectionStatus.uncollapsed,
        hasContent: true,
        selectionRects: [Rect.fromLTWH(0, 0, 3, 1)],
      );
      const b = SelectionGeometry(
        status: SelectionStatus.uncollapsed,
        hasContent: true,
        selectionRects: [Rect.fromLTWH(0, 0, 3, 1)],
      );
      const c = SelectionGeometry(
        status: SelectionStatus.uncollapsed,
        hasContent: true,
        selectionRects: [Rect.fromLTWH(0, 0, 4, 1)],
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });

    test('copyWith preserves unspecified fields', () {
      const original = SelectionGeometry(
        status: SelectionStatus.collapsed,
        hasContent: true,
        startSelectionPoint: SelectionPoint(localPosition: Offset(1, 0)),
      );
      final copy = original.copyWith(status: SelectionStatus.uncollapsed);
      expect(copy.status, SelectionStatus.uncollapsed);
      expect(copy.hasContent, isTrue);
      expect(copy.startSelectionPoint,
          const SelectionPoint(localPosition: Offset(1, 0)));
    });
  });

  group('Selectable geometry notifications', () {
    test('notifies listeners when geometry changes', () {
      final selectable = _TestSelectable();
      var notifications = 0;
      selectable.addListener(() => notifications++);

      selectable.setGeometry(_contentGeometry);
      expect(notifications, 1);
      expect(selectable.value, _contentGeometry);
    });

    test('does not notify when geometry is unchanged', () {
      final selectable = _TestSelectable();
      var notifications = 0;
      selectable.addListener(() => notifications++);

      selectable.setGeometry(_contentGeometry);
      selectable.setGeometry(_contentGeometry);
      expect(notifications, 1);
    });

    test('removed listeners are not notified', () {
      final selectable = _TestSelectable();
      var notifications = 0;
      void listener() => notifications++;
      selectable.addListener(listener);
      selectable.removeListener(listener);

      selectable.setGeometry(_contentGeometry);
      expect(notifications, 0);
    });
  });

  group('SelectionRegistrant', () {
    test('does not register while there is no content', () {
      final registrar = _FakeRegistrar();
      final selectable = _TestSelectable();

      selectable.registrar = registrar;
      expect(registrar.added, isEmpty);
    });

    test('registers when content appears and unregisters when it goes', () {
      final registrar = _FakeRegistrar();
      final selectable = _TestSelectable();
      selectable.registrar = registrar;

      selectable.setGeometry(_contentGeometry);
      expect(registrar.added, [selectable]);

      selectable.setGeometry(_emptyGeometry);
      expect(registrar.removed, [selectable]);
    });

    test('registers immediately when set while content exists', () {
      final registrar = _FakeRegistrar();
      final selectable = _TestSelectable();
      selectable.setGeometry(_contentGeometry);

      selectable.registrar = registrar;
      expect(registrar.added, [selectable]);
    });

    test('does not register twice for repeated geometry updates', () {
      final registrar = _FakeRegistrar();
      final selectable = _TestSelectable();
      selectable.registrar = registrar;

      selectable.setGeometry(_contentGeometry);
      selectable.setGeometry(_contentGeometry.copyWith(
        status: SelectionStatus.uncollapsed,
        selectionRects: const [Rect.fromLTWH(0, 0, 1, 1)],
      ));
      expect(registrar.added, [selectable]);
    });

    test('unregisters when the registrar is cleared', () {
      final registrar = _FakeRegistrar();
      final selectable = _TestSelectable();
      selectable.registrar = registrar;
      selectable.setGeometry(_contentGeometry);

      selectable.registrar = null;
      expect(registrar.removed, [selectable]);
    });

    test('moves registration when the registrar is replaced', () {
      final first = _FakeRegistrar();
      final second = _FakeRegistrar();
      final selectable = _TestSelectable();
      selectable.registrar = first;
      selectable.setGeometry(_contentGeometry);

      selectable.registrar = second;
      expect(first.removed, [selectable]);
      expect(second.added, [selectable]);
    });

    test('unregisters on dispose', () {
      final registrar = _FakeRegistrar();
      final selectable = _TestSelectable();
      selectable.registrar = registrar;
      selectable.setGeometry(_contentGeometry);

      selectable.dispose();
      expect(registrar.removed, [selectable]);
    });
  });
}
