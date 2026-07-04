import '../framework/framework.dart';
import 'selection.dart';

/// Auto-scrolls a selectable's own content while a selection drag sits past
/// its edge.
///
/// [ScrollableSelectionContainerDelegate] serves containers whose children
/// move under a [ScrollController]; this mixin is provided to assist render objects that provide their own content scrolling.
mixin SelfScrollingSelectable on RenderObject, Selectable {
  late final SelectionAutoScroller _autoScroller =
      SelectionAutoScroller(clock: autoScrollClock);

  /// Scrolls this selectable's content by [rows] whole cells — positive
  /// toward the content's end (the drag sits past the bottom edge). Returns
  /// true iff the content actually moved.
  bool scrollSelectionBy(int rows);

  /// Monotonic clock driving the auto-scroll rate. Null uses a real clock;
  /// overridable in tests to advance time deterministically.
  Duration Function()? get autoScrollClock => null;

  @override
  SelectionResult dispatchSelectionEvent(SelectionEvent event) {
    final result = super.dispatchSelectionEvent(event);
    if (event is! SelectionEdgeUpdateEvent) return result;
    if (!event.isEnd) {
      // Suppress auto-scroll for a drag that begins inside the hot band.
      _autoScroller.arm(SelectionUtils.autoScrollVelocity(
          globalBounds, event.globalPosition,
          vertical: true));
      return result;
    }
    final velocity = SelectionUtils.autoScrollVelocity(
      globalBounds,
      event.globalPosition,
      vertical: true,
    );
    // Always step so the neutral zone resets the scroller's clock baseline.
    final rows = _autoScroller.step(velocity);
    if (velocity == 0 || !_autoScroller.isArmed) return result;
    // Never move more than one viewport per tick, so a stalled frame advances
    // at most one screen instead of lurching to the far end.
    final maxRows = globalBounds.height.floor();
    final clamped = rows.clamp(-maxRows, maxRows);
    // clamped == 0 → still accumulating; keep pumping. false → hit the limit.
    if (clamped != 0 && !scrollSelectionBy(clamped)) return result;
    return SelectionResult.pending;
  }
}
