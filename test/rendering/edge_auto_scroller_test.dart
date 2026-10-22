import 'package:nocterm/nocterm.dart';
import 'package:test/test.dart';

void main() {
  group('EdgeAutoScroller.velocity', () {
    // Tall/wide enough for a neutral middle: rows 2..13, cols 0..11.
    const rect = Rect.fromLTWH(0, 2, 12, 12);

    // Pin the ramp params so these assertions test the formula, not whatever
    // speed the app currently tunes the defaults to. A band of 4 over rows
    // 2..13 makes rows 2..5 the top band, 10..13 the bottom, 6..9 neutral.
    double v(Rect r, Offset p,
            {Axis axis = Axis.vertical, double maxPerSecond = 20}) =>
        EdgeAutoScroller(
                minPerSecond: 3, maxPerSecond: maxPerSecond, hotRows: 4)
            .velocity(r, p, axis);

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
      expect(v(rect, const Offset(0, 7), axis: Axis.horizontal), -20);
      expect(v(rect, const Offset(11, 7), axis: Axis.horizontal), 20);
      expect(v(rect, const Offset(6, 7), axis: Axis.horizontal), 0);
    });

    test('a two-row viewport is all edge', () {
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

    test('a single-row viewport has no band but scrolls from outside', () {
      const row = Rect.fromLTWH(0, 5, 4, 1);
      expect(v(row, const Offset(1, 5)), 0);
      expect(v(row, const Offset(1, 4)), -20); // reading above it
      expect(v(row, const Offset(1, 6)), 20); // or below
    });

    test('the band is whole rows and leaves the middle neutral', () {
      // rows 0..5 with hotRows 4: (6 - 1) ~/ 2 = 2, so rows 0,1 and 4,5 are
      // the bands and rows 2,3 stay still.
      const short = Rect.fromLTWH(0, 0, 4, 6);
      expect(v(short, const Offset(1, 0)), -20);
      expect(v(short, const Offset(1, 1)), closeTo(-11.5, 1e-9)); // t = 0.5
      expect(v(short, const Offset(1, 2)), 0);
      expect(v(short, const Offset(1, 3)), 0);
      expect(v(short, const Offset(1, 4)), closeTo(11.5, 1e-9));
      expect(v(short, const Offset(1, 5)), 20);
    });

    test('every even height from four up keeps two neutral rows', () {
      for (var rows = 4; rows <= 14; rows += 2) {
        final rect = Rect.fromLTWH(0, 0, 4, rows.toDouble());
        final neutral = [
          for (var y = 0; y < rows; y++)
            if (v(rect, Offset(1, y.toDouble())) == 0) y,
        ];
        expect(neutral, hasLength(greaterThanOrEqualTo(2)), reason: '$rows');
        expect(neutral, contains(rows ~/ 2 - 1), reason: '$rows');
        expect(neutral, contains(rows ~/ 2), reason: '$rows');
      }
    });

    test('the shipped defaults behave sanely on a full-size viewport', () {
      final scroller = EdgeAutoScroller();
      final min = scroller.minPerSecond;
      final max = scroller.maxPerSecond;
      const full = Rect.fromLTWH(0, 0, 80, 30); // rows 0..29
      double d(Offset p) => scroller.velocity(full, p, Axis.vertical);
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

  group('EdgeAutoScroller.step', () {
    // rows 0..11: the edge rows run at exactly the pinned speed.
    const rect = Rect.fromLTWH(0, 0, 4, 12);
    const top = Offset(1, 0);
    const bottom = Offset(1, 11);
    const middle = Offset(1, 5);

    EdgeAutoScroller at(double rowsPerSecond, Duration Function() clock) =>
        EdgeAutoScroller(
          clock: clock,
          minPerSecond: rowsPerSecond,
          maxPerSecond: rowsPerSecond,
        );

    int step(EdgeAutoScroller scroller, Offset point) =>
        scroller.step(rect, point, Axis.vertical);

    test('advances by the real time between ticks', () {
      var now = Duration.zero;
      final scroller = at(10, () => now);
      expect(step(scroller, bottom), 0); // first tick seeds the clock
      now = const Duration(milliseconds: 100);
      expect(step(scroller, bottom), 1); // 10 rows/sec × 0.1s = one row
      expect(scroller.scrolling, isTrue);
    });

    test('the top edge scrolls toward the start', () {
      var now = Duration.zero;
      final scroller = at(10, () => now);
      step(scroller, top);
      now = const Duration(milliseconds: 100);
      expect(step(scroller, top), -1);
    });

    test('carries the sub-row remainder so slow speeds still advance', () {
      var now = Duration.zero;
      final scroller = at(2, () => now);
      var moved = step(scroller, bottom); // seed
      // 2 rows/sec: the whole row lands once 0.5s of real time has elapsed.
      for (var ms = 100; ms <= 500; ms += 100) {
        now = Duration(milliseconds: ms);
        moved += step(scroller, bottom);
      }
      expect(moved, 1);
    });

    test('a fast pointer cannot scroll faster than a slow one', () {
      var slowNow = Duration.zero, fastNow = Duration.zero;
      final slow = at(20, () => slowNow);
      final fast = at(20, () => fastNow);
      // Both cover one real second at 20 rows/sec, every tick under the cap:
      // the slow pointer ticks every 50ms, the fast one every 12.5ms.
      var mSlow = step(slow, bottom);
      for (var us = 50000; us <= 1000000; us += 50000) {
        slowNow = Duration(microseconds: us);
        mSlow += step(slow, bottom);
      }
      var mFast = step(fast, bottom);
      for (var us = 12500; us <= 1000000; us += 12500) {
        fastNow = Duration(microseconds: us);
        mFast += step(fast, bottom);
      }
      expect(mFast, mSlow); // identical distance for identical wall-clock
    });

    test('never moves more than one viewport in a tick', () {
      var now = Duration.zero;
      final scroller = at(50, () => now);
      step(scroller, bottom);
      now = const Duration(seconds: 2); // a stalled frame: 100 rows earned
      expect(step(scroller, bottom), 12);
    });

    test('leaving the edge resets the clock, so an idle gap is not counted',
        () {
      var now = Duration.zero;
      final scroller = at(10, () => now);
      step(scroller, bottom); // seed at the edge
      now = const Duration(milliseconds: 100);
      step(scroller, bottom); // scroll for 0.1s
      // The pointer sits in the neutral middle for five seconds.
      now = const Duration(seconds: 5);
      expect(step(scroller, middle), 0);
      expect(scroller.scrolling, isFalse);
      // Back at the edge: the reset means this tick reseeds — the 5s idle gap
      // produces nothing, rather than a fifty-row lurch.
      now = const Duration(seconds: 5, milliseconds: 100);
      expect(step(scroller, bottom), 0);
      // From here real time counts again as normal.
      now = const Duration(seconds: 5, milliseconds: 200);
      expect(step(scroller, bottom), 1); // 0.1s → one row
    });

    test('a neutral tick clears the remainder and reseeds the clock', () {
      var now = Duration.zero;
      final scroller = at(2, () => now);
      step(scroller, bottom); // seed
      now = const Duration(milliseconds: 300);
      step(scroller, bottom); // remainder 0.6
      expect(step(scroller, middle), 0);
      // Remainder gone and clock reseeded: a fresh short interval yields none.
      now = const Duration(milliseconds: 400);
      expect(step(scroller, bottom), 0);
    });

    test('a drag begun in a band is suppressed while it stays in that band',
        () {
      var now = Duration.zero;
      final scroller = at(10, () => now)
        ..arm(rect, bottom, Axis.vertical); // the drag began inside the band
      expect(scroller.isArmed, isFalse);
      step(scroller, bottom); // seed attempt is ignored while suppressed
      now = const Duration(milliseconds: 100);
      expect(step(scroller, bottom), 0); // same band: no scrolling
      expect(scroller.isArmed, isFalse);
      expect(scroller.scrolling, isFalse);
    });

    test('a neutral tick re-arms a suppressed scroller', () {
      var now = Duration.zero;
      final scroller = at(10, () => now)..arm(rect, bottom, Axis.vertical);
      now = const Duration(milliseconds: 100);
      expect(step(scroller, bottom), 0); // in the band, suppressed
      // Pointer leaves the band, which re-arms.
      now = const Duration(milliseconds: 200);
      expect(step(scroller, middle), 0);
      expect(scroller.isArmed, isTrue);
      // Re-entering the band now scrolls: this tick reseeds the clock...
      now = const Duration(milliseconds: 300);
      expect(step(scroller, bottom), 0);
      // ...and time counts from here.
      now = const Duration(milliseconds: 400);
      expect(step(scroller, bottom), 1); // 0.1s → one row
    });

    test('crossing straight into the opposite band re-arms', () {
      var now = Duration.zero;
      // The drag began in the top band...
      final scroller = at(10, () => now)..arm(rect, top, Axis.vertical);
      expect(scroller.isArmed, isFalse);
      // ...then jumps to the bottom band without a neutral sample. The
      // opposite sign means the drag left its starting band, so it re-arms
      // and this tick reseeds the clock.
      now = const Duration(milliseconds: 100);
      expect(step(scroller, bottom), 0);
      expect(scroller.isArmed, isTrue);
      now = const Duration(milliseconds: 200);
      expect(step(scroller, bottom), 1); // 0.1s → one row
    });

    test('a drag begun in the middle is armed from the start', () {
      final scroller = at(10, () => Duration.zero)
        ..arm(rect, middle, Axis.vertical);
      expect(scroller.isArmed, isTrue);
    });

    test('the default clock is monotonic and the override replaces it', () {
      final real = EdgeAutoScroller();
      expect(real.step(rect, bottom, Axis.vertical), 0);
      var now = Duration.zero;
      EdgeAutoScroller.debugClockOverride = () => now;
      addTearDown(() => EdgeAutoScroller.debugClockOverride = null);
      final faked = EdgeAutoScroller(minPerSecond: 10, maxPerSecond: 10);
      faked.step(rect, bottom, Axis.vertical);
      now = const Duration(milliseconds: 100);
      expect(faked.step(rect, bottom, Axis.vertical), 1);
    });
  });
}
