import 'dart:math' as math;

import 'package:meta/meta.dart';

import '../components/basic.dart' show Axis;
import '../framework/framework.dart' show Offset;
import '../rectangle.dart';

/// Scrolls content under a drag that sits in a hot band at a viewport's
/// edge: still in the middle, [minPerSecond] rows at the band's inner row,
/// [maxPerSecond] at the edge row and anywhere past it.
///
/// The band is measured inside the viewport, since a terminal clamps the
/// pointer to its grid and a full-height view has nothing past its edge.
/// It is [hotRows] deep at most and always leaves the middle rows still
/// from three rows up; a two-row view is all edge.
///
/// Rows are earned by real time between [step]s, so a pointer firing many
/// events scrolls no faster than one firing few.
final class EdgeAutoScroller {
  /// A scroller reading elapsed time from [clock].
  EdgeAutoScroller({
    Duration Function()? clock,
    this.minPerSecond = 10,
    this.maxPerSecond = 50,
    this.hotRows = 5,
  }) : _clock = clock ?? debugClockOverride ?? _monotonicClock();

  /// Test-only default clock, used when no explicit clock is passed.
  @visibleForTesting
  static Duration Function()? debugClockOverride;

  /// Rows per second at the band's inner row.
  final double minPerSecond;

  /// Rows per second at the edge row and past it.
  final double maxPerSecond;

  /// How deep the band is at each edge, at most.
  final double hotRows;

  final Duration Function() _clock;
  double _remainder = 0;
  Duration? _last;
  int _suppressedSign = 0;
  bool _scrolling = false;

  static Duration Function() _monotonicClock() {
    final stopwatch = Stopwatch()..start();
    return () => stopwatch.elapsed;
  }

  /// Whether the scroller may move: a drag that began inside a band is
  /// suppressed until the pointer leaves it.
  bool get isArmed => _suppressedSign == 0;

  /// Whether the last [step] found the pointer in a band, so the caller
  /// should step again next frame.
  bool get scrolling => _scrolling;

  /// Rows per second for a pointer at [point] over [bounds] along [axis]:
  /// 0 in the neutral middle, negative toward the start.
  double velocity(Rect bounds, Offset point, Axis axis) {
    final (position, start, end) = switch (axis) {
      Axis.vertical => (point.dy, bounds.top, bounds.bottom),
      Axis.horizontal => (point.dx, bounds.left, bounds.right),
    };
    final fromStart = position - start;
    final fromEnd = end - 1 - position;
    final towardStart = fromStart <= fromEnd;
    final toEdge = math.min(fromStart, fromEnd);
    final band = _bandOf(end - start);
    final double speed;
    if (toEdge < 0) {
      speed = maxPerSecond;
    } else if (toEdge >= band) {
      return 0;
    } else {
      speed =
          minPerSecond + (maxPerSecond - minPerSecond) * (band - toEdge) / band;
    }
    return towardStart ? -speed : speed;
  }

  /// Readies a drag that began at [point] over [bounds]: one that begins
  /// inside a band stays still until the pointer leaves it.
  void arm(Rect bounds, Offset point, Axis axis) {
    _suppressedSign = velocity(bounds, point, axis).sign.toInt();
    _remainder = 0;
    _last = null;
    _scrolling = false;
  }

  /// Whole rows to scroll now for a pointer at [point] over [bounds], at
  /// most one viewport: 0 while neutral, suppressed, or still accumulating a
  /// row. A neutral tick resets the clock, so a later return to the edge
  /// does not count the idle gap as scroll time.
  int step(Rect bounds, Offset point, Axis axis) {
    final rowsPerSecond = velocity(bounds, point, axis);
    if (_suppressedSign != 0 && rowsPerSecond.sign.toInt() != _suppressedSign) {
      _suppressedSign = 0;
    }
    _scrolling = rowsPerSecond != 0 && isArmed;
    if (rowsPerSecond == 0) {
      _remainder = 0;
      _last = null;
      return 0;
    }
    if (!isArmed) return 0;
    final now = _clock();
    final elapsed = _last == null ? Duration.zero : now - _last!;
    _last = now;
    _remainder += rowsPerSecond *
        (elapsed.inMicroseconds / Duration.microsecondsPerSecond);
    final whole = _remainder.truncate();
    _remainder -= whole;
    final extent = switch (axis) {
      Axis.vertical => bounds.height,
      Axis.horizontal => bounds.width,
    }
        .floor();
    return whole.clamp(-extent, extent);
  }

  double _bandOf(double extent) =>
      extent < 2 ? 0 : ((extent - 1) ~/ 2).clamp(1, hotRows).toDouble();
}
