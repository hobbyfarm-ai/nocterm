import 'package:meta/meta.dart';

import '../framework/framework.dart';
import '../framework/value_listenable.dart';
import '../rectangle.dart';

/// Where a selection edge ended up relative to a [Selectable] after it
/// handled a [SelectionEdgeUpdateEvent].
///
/// A container delegate uses this to walk its child list toward the edge:
/// [next] means "keep looking after me", [previous] means "keep looking
/// before me", and [end] means "the edge is inside me — stop".
enum SelectionResult {
  /// There is nothing left to select forward in this [Selectable]; the edge
  /// belongs to a later [Selectable] in screen order.
  next,

  /// The edge does not reach this [Selectable]; it belongs to an earlier
  /// [Selectable] in screen order.
  previous,

  /// The selection edge ends inside this [Selectable].
  end,

  /// The result can't be determined this frame (e.g. content is still being
  /// revealed by a scrollable).
  pending,

  /// The event has no positional result ([SelectAllSelectionEvent],
  /// [ClearSelectionEvent]).
  none,
}

/// Whether there is a selection and whether it is collapsed.
enum SelectionStatus {
  /// A non-empty range is selected.
  uncollapsed,

  /// The selection starts and ends at the same location.
  collapsed,

  /// No selection.
  none,
}

/// Events dispatched to [Selectable]s to drive selection.
sealed class SelectionEvent {
  const SelectionEvent();
}

/// Moves one edge of the selection to [globalPosition].
///
/// An active selection has two edges: the start (where the drag began) and
/// the end (where the pointer currently is). [isEnd] selects which edge this
/// event moves.
final class SelectionEdgeUpdateEvent extends SelectionEvent {
  const SelectionEdgeUpdateEvent.forStart({required this.globalPosition})
      : isEnd = false;

  const SelectionEdgeUpdateEvent.forEnd({required this.globalPosition})
      : isEnd = true;

  /// The new edge location in global (terminal root) cell coordinates.
  final Offset globalPosition;

  /// Whether this event moves the end edge rather than the start edge.
  final bool isEnd;
}

/// Selects all content in the receiving [Selectable].
final class SelectAllSelectionEvent extends SelectionEvent {
  const SelectAllSelectionEvent();
}

/// Removes any selection from the receiving [Selectable].
final class ClearSelectionEvent extends SelectionEvent {
  const ClearSelectionEvent();
}

/// Selects the word at [globalPosition] (e.g. from a double-click).
final class SelectWordSelectionEvent extends SelectionEvent {
  const SelectWordSelectionEvent({required this.globalPosition});

  /// The location to select a word at, in global cell coordinates.
  final Offset globalPosition;
}

/// The location of a selection edge within a [Selectable], in the
/// selectable's local cell coordinates.
@immutable
class SelectionPoint {
  const SelectionPoint({required this.localPosition});

  final Offset localPosition;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SelectionPoint && other.localPosition == localPosition;

  @override
  int get hashCode => localPosition.hashCode;

  @override
  String toString() => 'SelectionPoint($localPosition)';
}

/// The current selection state of a [Selectable] or container delegate.
///
/// Positions and rects are in the local coordinates of the reporting object.
@immutable
class SelectionGeometry {
  const SelectionGeometry({
    required this.status,
    required this.hasContent,
    this.startSelectionPoint,
    this.endSelectionPoint,
    this.selectionRects = const [],
  }) : assert(
          (startSelectionPoint == null && endSelectionPoint == null) ||
              status != SelectionStatus.none,
        );

  /// The location of the selection start edge, or null if the start edge
  /// does not fall inside this object.
  final SelectionPoint? startSelectionPoint;

  /// The location of the selection end edge, or null if the end edge does
  /// not fall inside this object.
  final SelectionPoint? endSelectionPoint;

  /// The highlighted cells, as local rects.
  final List<Rect> selectionRects;

  final SelectionStatus status;

  /// Whether this object has any selectable content at all.
  final bool hasContent;

  bool get hasSelection => status != SelectionStatus.none;

  SelectionGeometry copyWith({
    SelectionPoint? startSelectionPoint,
    SelectionPoint? endSelectionPoint,
    List<Rect>? selectionRects,
    SelectionStatus? status,
    bool? hasContent,
  }) {
    return SelectionGeometry(
      startSelectionPoint: startSelectionPoint ?? this.startSelectionPoint,
      endSelectionPoint: endSelectionPoint ?? this.endSelectionPoint,
      selectionRects: selectionRects ?? this.selectionRects,
      status: status ?? this.status,
      hasContent: hasContent ?? this.hasContent,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SelectionGeometry &&
          other.startSelectionPoint == startSelectionPoint &&
          other.endSelectionPoint == endSelectionPoint &&
          _listEquals(other.selectionRects, selectionRects) &&
          other.status == status &&
          other.hasContent == hasContent;

  @override
  int get hashCode => Object.hash(
        startSelectionPoint,
        endSelectionPoint,
        Object.hashAll(selectionRects),
        status,
        hasContent,
      );
}

/// The selected content of a [Selectable] or container delegate.
@immutable
class SelectedContent {
  const SelectedContent({required this.plainText});

  final String plainText;
}

/// Handles [SelectionEvent]s and reports the resulting [SelectionGeometry].
///
/// Implemented by [Selectable] leaves and by container delegates that
/// aggregate multiple selectables while presenting as a single handler to
/// their parent.
abstract class SelectionHandler implements ValueListenable<SelectionGeometry> {
  /// Handles the [event], updating internal selection state and geometry.
  SelectionResult dispatchSelectionEvent(SelectionEvent event);

  /// The currently selected content, or null if nothing is selected.
  SelectedContent? getSelectedContent();

  /// The length of the selectable content in this object.
  int get contentLength;
}

/// Keeps track of the [Selectable]s in a subtree.
///
/// A [Selectable] must register to receive [SelectionEvent]s. Registration
/// follows the render object lifecycle via [SelectionRegistrant].
abstract class SelectionRegistrar {
  void add(Selectable selectable);

  void remove(Selectable selectable);
}

/// An object that can be selected within a [SelectionArea].
///
/// Mixers implement [dispatchSelectionEvent] to update their own selection
/// state, call [updateSelectionGeometry] whenever that state changes, and
/// paint their own highlight. Text render objects mix in `TextSelectable`;
/// container delegates implement this directly to present a whole subtree
/// as a single selectable to their parent.
///
/// The selection is owned here, in the retained layer — a rebuild that
/// replaces the component tree above does not disturb it unless the mixer
/// itself is replaced.
mixin Selectable implements SelectionHandler {
  final List<VoidCallback> _selectionListeners = [];

  @override
  void addListener(VoidCallback listener) => _selectionListeners.add(listener);

  @override
  void removeListener(VoidCallback listener) =>
      _selectionListeners.remove(listener);

  @override
  SelectionGeometry get value => _selectionGeometry;
  SelectionGeometry _selectionGeometry = const SelectionGeometry(
    status: SelectionStatus.none,
    hasContent: false,
  );

  /// Replaces the reported geometry, notifying listeners if it changed.
  @protected
  void updateSelectionGeometry(SelectionGeometry newValue) {
    if (_selectionGeometry == newValue) return;
    _selectionGeometry = newValue;
    for (final listener in List.of(_selectionListeners)) {
      listener();
    }
  }

  /// The origin of this selectable in global (terminal root) cell
  /// coordinates.
  Offset get globalPaintOffset;

  /// This selectable's bounds in global cell coordinates.
  Rect get globalBounds;

  /// Releases resources; unregisters via [SelectionRegistrant] when mixed.
  void dispose();
}

/// The position of [node] in global (terminal root) cell coordinates,
/// accumulated from [BoxParentData] offsets.
Offset globalPaintOffsetOf(RenderObject node) {
  double x = 0;
  double y = 0;
  RenderObject? current = node;
  while (current != null) {
    final parentData = current.parentData;
    if (parentData is BoxParentData) {
      x += parentData.offset.dx;
      y += parentData.offset.dy;
    }
    current = current.parent;
  }
  return Offset(x, y);
}

/// Auto-registers the mixer with a [SelectionRegistrar] while it has content.
///
/// Set [registrar] when the owning component wires up (and to null to tear
/// down). The mixer is only registered while
/// [SelectionGeometry.hasContent] is true, and is unregistered on [dispose].
mixin SelectionRegistrant on Selectable {
  SelectionRegistrar? get registrar => _registrar;
  SelectionRegistrar? _registrar;
  set registrar(SelectionRegistrar? value) {
    if (value == _registrar) return;
    if (value == null) {
      removeListener(_updateRegistration);
    } else if (_registrar == null) {
      addListener(_updateRegistration);
    }
    _unregister();
    _registrar = value;
    _updateRegistration();
  }

  @override
  void dispose() {
    _unregister();
    super.dispose();
  }

  bool _registered = false;

  void _updateRegistration() {
    if (_registrar == null) {
      _registered = false;
      return;
    }
    if (_registered && !value.hasContent) {
      _registrar!.remove(this);
      _registered = false;
    } else if (!_registered && value.hasContent) {
      _registrar!.add(this);
      _registered = true;
    }
  }

  void _unregister() {
    if (_registered) {
      _registrar!.remove(this);
      _registered = false;
    }
  }
}

/// Geometry helpers for handling selection events.
abstract final class SelectionUtils {
  /// Default auto-scroll speed, in rows per second, at the inner row of a hot
  /// band. See [autoScrollVelocity].
  static const double defaultMinPerSecond = 10;

  /// Default auto-scroll speed, in rows per second, at the very edge row. See
  /// [autoScrollVelocity].
  static const double defaultMaxPerSecond = 50;

  /// Default depth, in rows, of the hot band at each edge. See
  /// [autoScrollVelocity].
  static const double defaultHotRows = 5;

  /// Determines a [SelectionResult] from where [point] sits relative to
  /// [targetRect] in screen order.
  ///
  /// Returns [SelectionResult.end] if the point is inside the rect,
  /// [SelectionResult.previous] if it reads before the rect, and
  /// [SelectionResult.next] if it reads after.
  static SelectionResult getResultBasedOnRect(Rect targetRect, Offset point) {
    if (targetRect.contains(point)) {
      return SelectionResult.end;
    }
    if (point.dy < targetRect.top) {
      return SelectionResult.previous;
    }
    if (point.dy >= targetRect.bottom) {
      return SelectionResult.next;
    }
    return point.dx >= targetRect.right
        ? SelectionResult.next
        : SelectionResult.previous;
  }

  /// The auto-scroll velocity, in rows per second, for a selection drag at
  /// [point] relative to [bounds] — 0 in the neutral middle, ramping up inside
  /// a hot band [hotRows] deep at each edge: [minPerSecond] at the band's inner
  /// row, up to [maxPerSecond] at the very edge row.
  ///
  /// The ramp is measured *inside* the viewport, not by how far the pointer is
  /// dragged past the edge: a terminal clamps the pointer to the grid, so a
  /// full-height view has no room past its edge to measure against.
  static double autoScrollVelocity(
    Rect bounds,
    Offset point, {
    required bool vertical,
    double minPerSecond = defaultMinPerSecond,
    double maxPerSecond = defaultMaxPerSecond,
    double hotRows = defaultHotRows,
  }) {
    final (position, start, end) = vertical
        ? (point.dy, bounds.top, bounds.bottom)
        : (point.dx, bounds.left, bounds.right);
    // Cap the band at half the extent so a neutral row survives the middle of
    // a tall view; a view too short for that just activates its edge rows.
    final band = ((end - start - 1) / 2).clamp(0.0, hotRows);
    if (band <= 0) return 0; // a viewport of one row or less has no hot band.
    // Distance from the nearest edge row: 0 at the edge, growing inward.
    final towardStart = position - start <= end - 1 - position;
    final toEdge = towardStart ? position - start : end - 1 - position;
    if (toEdge >= band) return 0;
    final t = ((band - toEdge) / band).clamp(0.0, 1.0);
    final speed = minPerSecond + (maxPerSecond - minPerSecond) * t;
    return towardStart ? -speed : speed;
  }

  /// Moves [point] inside [targetRect] when it falls outside, so a drag past
  /// a selectable's bounds selects to its start or end.
  ///
  /// Points that read before the rect map to its top-left; points that read
  /// after map to its bottom-right.
  static Offset adjustDragOffset(Rect targetRect, Offset point) {
    if (targetRect.contains(point)) {
      return point;
    }
    // Above the element resolves to its very start; below, to its very end.
    if (point.dy < targetRect.top) {
      return Offset(targetRect.left, targetRect.top);
    }
    if (point.dy >= targetRect.bottom) {
      return Offset(targetRect.right, targetRect.bottom - 1);
    }
    // Beside the element but level with one of its rows: clamp to the near
    // horizontal edge while keeping the row.
    return point.dx < targetRect.left
        ? Offset(targetRect.left, point.dy)
        : Offset(targetRect.right, point.dy);
  }
}

/// Turns an auto-scroll velocity (rows/second) into whole rows to move this
/// frame.
class SelectionAutoScroller {
  SelectionAutoScroller({Duration Function()? clock})
      : _clock = clock ?? debugClockOverride ?? _monotonicClock();

  /// Test-only default clock, used when no explicit [clock] is passed. Lets
  /// integration tests drive auto-scroll time deterministically without
  /// threading a clock through every scrollable that builds a scroller.
  @visibleForTesting
  static Duration Function()? debugClockOverride;

  /// A monotonic wall-clock reader; the auto-scroll rate is driven by the real
  /// time between ticks, so a fast pointer firing many ticks can't scroll any
  /// faster than a slow one — each tick only advances by the time it owns.
  final Duration Function() _clock;
  double _remainder = 0;
  Duration? _last;
  int _suppressedSign = 0;

  static Duration Function() _monotonicClock() {
    final stopwatch = Stopwatch()..start();
    return () => stopwatch.elapsed;
  }

  /// Whether auto-scroll is currently allowed to move. See [arm].
  bool get isArmed => _suppressedSign == 0;

  /// Prepares the scroller for a new drag. A nonzero [startVelocity] — the drag
  /// began inside a hot band — suppresses auto-scroll until the pointer leaves
  /// that band.
  void arm(double startVelocity) {
    _suppressedSign = startVelocity.sign.toInt();
    _remainder = 0;
    _last = null;
  }

  /// Whole rows to move given the current [rowsPerSecond], measured against the
  /// real time since the previous tick. A [rowsPerSecond] of 0 (the pointer is
  /// off the edge) resets the clock, so a later return to the edge starts fresh
  /// rather than counting the idle gap as scroll time. Returns 0 while
  /// suppressed (see [arm]).
  int step(double rowsPerSecond) {
    // A neutral tick or a crossing into the opposite band re-arms.
    if (_suppressedSign != 0 && rowsPerSecond.sign.toInt() != _suppressedSign) {
      _suppressedSign = 0;
    }
    if (rowsPerSecond == 0) {
      _remainder = 0;
      _last = null;
      return 0;
    }
    if (_suppressedSign != 0) return 0;
    final now = _clock();
    final elapsed = _last == null ? Duration.zero : now - _last!;
    _last = now;
    _remainder += rowsPerSecond *
        (elapsed.inMicroseconds / Duration.microsecondsPerSecond);
    final whole = _remainder.truncate();
    _remainder -= whole;
    return whole;
  }
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
