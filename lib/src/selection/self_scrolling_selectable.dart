import '../components/basic.dart' show Axis;
import '../framework/framework.dart';
import '../rendering/edge_auto_scroller.dart';
import 'selection.dart';

/// Auto-scrolls a selectable's own content while a selection drag sits past
/// its edge.
///
/// [ScrollableSelectionContainerDelegate] serves containers whose children
/// move under a [ScrollController]; this mixin is provided to assist render objects that provide their own content scrolling.
mixin SelfScrollingSelectable on RenderObject, Selectable {
  late final EdgeAutoScroller _autoScroller =
      EdgeAutoScroller(clock: autoScrollClock);

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
      _autoScroller.arm(globalBounds, event.globalPosition, Axis.vertical);
      return result;
    }
    final rows =
        _autoScroller.step(globalBounds, event.globalPosition, Axis.vertical);
    if (!_autoScroller.scrolling) return result;
    // rows == 0 → still accumulating; keep pumping. false → hit the limit.
    if (rows != 0 && !scrollSelectionBy(rows)) return result;
    return SelectionResult.pending;
  }
}
