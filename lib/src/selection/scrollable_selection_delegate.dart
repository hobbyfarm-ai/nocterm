import '../components/scroll_controller.dart';
import '../framework/axis.dart';
import '../framework/framework.dart';
import 'selection.dart';
import 'selection_container_delegate.dart';

/// A selection delegate for content that scrolls under an active selection.
///
/// Selection edges arrive in screen coordinates, but scrolled content moves
/// under the screen. This delegate stores both drag edges relative to the
/// scroll origin — pinned to the content — and translates them back through
/// the current scroll offset whenever an edge event is dispatched, so a
/// selection anchor keeps pointing at the same text no matter how far the
/// content has scrolled since the drag began.
///
/// Each child records the scroll offset it last received an edge event at.
/// Before any new event reaches a child with a stale record (including
/// children that mount mid-drag when a lazy viewport reveals them), the
/// missing edges are synthesized from the origin-relative positions, keeping
/// every child consistent with the selection regardless of when it joined.
///
/// Dragging past the viewport while a selection is in progress auto-scrolls
/// toward the pointer and reports [SelectionResult.pending], which asks the
/// selection root to re-dispatch the edge each frame until the pointer
/// returns inside the viewport or the scrollable runs out of extent.
class ScrollableSelectionContainerDelegate
    extends MultiSelectableSelectionContainerDelegate {
  ScrollableSelectionContainerDelegate({
    required ScrollController controller,
    super.schedulePostFrame,
    Duration Function()? clock,
  })  : _controller = controller,
        _autoScroller = SelectionAutoScroller(clock: clock) {
    _controller.addListener(_scheduleLayoutChange);
  }

  static const Offset _afterContent =
      Offset(double.maxFinite, double.maxFinite);

  ScrollController _controller;
  ScrollController get controller => _controller;
  set controller(ScrollController value) {
    if (identical(_controller, value)) return;
    _controller.removeListener(_scheduleLayoutChange);
    _controller = value;
    _controller.addListener(_scheduleLayoutChange);
  }

  final Map<Selectable, double> _selectableStartEdgeUpdateRecords =
      <Selectable, double>{};
  final Map<Selectable, double> _selectableEndEdgeUpdateRecords =
      <Selectable, double>{};

  Offset? _currentDragStartRelatedToOrigin;
  Offset? _currentDragEndRelatedToOrigin;
  bool _selectionStartsInScrollable = false;
  bool _scheduledLayoutChange = false;

  final SelectionAutoScroller _autoScroller;

  bool get _isVertical =>
      _controller.axisDirection == AxisDirection.down ||
      _controller.axisDirection == AxisDirection.up;

  /// The offset from the content origin to the top-left of the viewport.
  Offset get deltaToOrigin {
    return switch (_controller.axisDirection) {
      AxisDirection.down => Offset(0, _controller.offset),
      AxisDirection.up => Offset(0, -_controller.offset),
      AxisDirection.right => Offset(_controller.offset, 0),
      AxisDirection.left => Offset(-_controller.offset, 0),
    };
  }

  void _scheduleLayoutChange() {
    if (_scheduledLayoutChange) return;
    _scheduledLayoutChange = true;
    postFrameScheduler(() {
      if (!_scheduledLayoutChange) return;
      _scheduledLayoutChange = false;
      layoutDidChange();
    });
  }

  @override
  SelectionResult handleSelectionEdgeUpdate(SelectionEdgeUpdateEvent event) {
    if (_currentDragEndRelatedToOrigin == null &&
        _currentDragStartRelatedToOrigin == null) {
      _selectionStartsInScrollable =
          globalBounds.contains(event.globalPosition);
      // Suppress auto-scroll for a drag that begins inside the hot band.
      _autoScroller.arm(SelectionUtils.autoScrollVelocity(
          globalBounds, event.globalPosition,
          vertical: _isVertical));
    }
    final delta = deltaToOrigin;
    final SelectionEdgeUpdateEvent translated;
    if (event.isEnd) {
      _currentDragEndRelatedToOrigin =
          _inferPositionRelatedToOrigin(event.globalPosition);
      translated = SelectionEdgeUpdateEvent.forEnd(
          globalPosition: _currentDragEndRelatedToOrigin! - delta);
    } else {
      _currentDragStartRelatedToOrigin =
          _inferPositionRelatedToOrigin(event.globalPosition);
      translated = SelectionEdgeUpdateEvent.forStart(
          globalPosition: _currentDragStartRelatedToOrigin! - delta);
    }
    final result = super.handleSelectionEdgeUpdate(translated);
    if (result == SelectionResult.pending) return result;
    if (_selectionStartsInScrollable) {
      return _autoScrollIfNecessary(event.globalPosition, result);
    }
    return result;
  }

  Offset _inferPositionRelatedToOrigin(Offset globalPosition) {
    final bounds = globalBounds;
    final local = globalPosition - Offset(bounds.left, bounds.top);
    if (!_selectionStartsInScrollable) {
      // A selection that started outside this scrollable treats a crossing
      // of its boundary as selecting all of its content: positions that
      // read before the viewport pin to the content origin, positions that
      // read after pin past the content's end.
      if (local.dy < 0 || local.dx < 0) {
        return Offset(bounds.left, bounds.top);
      }
      if (local.dy >= bounds.height || local.dx >= bounds.width) {
        return _afterContent;
      }
    }
    return globalPosition + deltaToOrigin;
  }

  SelectionResult _autoScrollIfNecessary(
    Offset globalPosition,
    SelectionResult result,
  ) {
    final velocity = SelectionUtils.autoScrollVelocity(
      globalBounds,
      globalPosition,
      vertical: _isVertical,
    );
    // Always step so the neutral zone resets the scroller's clock baseline.
    final rows = _autoScroller.step(velocity);
    if (velocity == 0 || !_autoScroller.isArmed) return result;
    if (rows == 0) return SelectionResult.pending; // accumulating

    // Never move more than one viewport per tick, so a stalled frame advances
    // at most one screen instead of lurching to the far end.
    final maxRows = _controller.viewportDimension.floor();
    final scroll = rows.clamp(-maxRows, maxRows);
    final towardContentEnd = _controller.axisDirection == AxisDirection.down ||
        _controller.axisDirection == AxisDirection.right;
    final before = _controller.offset;
    _controller.scrollBy((towardContentEnd ? scroll : -scroll).toDouble());
    if (_controller.offset == before) return result;
    return SelectionResult.pending;
  }

  /// Re-derives the origin-relative drag edges from the selection geometry
  /// after a boundary event ([SelectAllSelectionEvent],
  /// [SelectWordSelectionEvent]) that positioned the edges without a drag.
  void _updateDragLocationsFromGeometries() {
    final delta = deltaToOrigin;
    if (currentSelectionStartIndex != -1) {
      final start = selectables[currentSelectionStartIndex];
      final point = start.value.startSelectionPoint;
      if (point != null) {
        _currentDragStartRelatedToOrigin =
            start.globalPaintOffset + point.localPosition + delta;
      }
    }
    if (currentSelectionEndIndex != -1) {
      final end = selectables[currentSelectionEndIndex];
      final point = end.value.endSelectionPoint;
      if (point != null) {
        _currentDragEndRelatedToOrigin =
            end.globalPaintOffset + point.localPosition + delta;
      }
    }
  }

  @override
  SelectionResult handleSelectAll(SelectAllSelectionEvent event) {
    final result = super.handleSelectAll(event);
    if (currentSelectionStartIndex != -1) {
      _updateDragLocationsFromGeometries();
    }
    return result;
  }

  @override
  SelectionResult handleSelectWord(SelectWordSelectionEvent event) {
    _selectionStartsInScrollable = globalBounds.contains(event.globalPosition);
    final result = super.handleSelectWord(event);
    _updateDragLocationsFromGeometries();
    return result;
  }

  @override
  SelectionResult handleClearSelection(ClearSelectionEvent event) {
    final result = super.handleClearSelection(event);
    _selectableStartEdgeUpdateRecords.clear();
    _selectableEndEdgeUpdateRecords.clear();
    _currentDragStartRelatedToOrigin = null;
    _currentDragEndRelatedToOrigin = null;
    _selectionStartsInScrollable = false;
    return result;
  }

  @override
  SelectionResult dispatchSelectionEventToChild(
    Selectable selectable,
    SelectionEvent event,
  ) {
    switch (event) {
      case SelectionEdgeUpdateEvent():
        if (event.isEnd) {
          _selectableEndEdgeUpdateRecords[selectable] = _controller.offset;
        } else {
          _selectableStartEdgeUpdateRecords[selectable] = _controller.offset;
        }
        ensureChildUpdated(selectable);
      case ClearSelectionEvent():
        _selectableStartEdgeUpdateRecords.remove(selectable);
        _selectableEndEdgeUpdateRecords.remove(selectable);
      case SelectAllSelectionEvent():
      case SelectWordSelectionEvent():
        _selectableStartEdgeUpdateRecords[selectable] = _controller.offset;
        _selectableEndEdgeUpdateRecords[selectable] = _controller.offset;
    }
    return super.dispatchSelectionEventToChild(selectable, event);
  }

  /// Synthesizes edge events for a child whose record predates the current
  /// scroll offset (or that never received one), replaying each drag edge at
  /// its content position translated into current screen coordinates.
  @override
  void ensureChildUpdated(Selectable selectable) {
    final record = _controller.offset;
    final previousStart = _selectableStartEdgeUpdateRecords[selectable];
    if (_currentDragStartRelatedToOrigin != null && previousStart != record) {
      _selectableStartEdgeUpdateRecords[selectable] = record;
      selectable.dispatchSelectionEvent(SelectionEdgeUpdateEvent.forStart(
          globalPosition: _currentDragStartRelatedToOrigin! - deltaToOrigin));
    }
    final previousEnd = _selectableEndEdgeUpdateRecords[selectable];
    if (_currentDragEndRelatedToOrigin != null && previousEnd != record) {
      _selectableEndEdgeUpdateRecords[selectable] = record;
      selectable.dispatchSelectionEvent(SelectionEdgeUpdateEvent.forEnd(
          globalPosition: _currentDragEndRelatedToOrigin! - deltaToOrigin));
    }
  }

  /// Clips the reported selection rects to the viewport: selected content
  /// that has scrolled out of view must not leak highlight geometry (with
  /// out-of-bounds rows) to the enclosing selection area.
  @override
  SelectionGeometry getSelectionGeometry() {
    final geometry = super.getSelectionGeometry();
    if (geometry.selectionRects.isEmpty) return geometry;
    final bounds = globalBounds;
    final clipped = geometry.selectionRects
        .where((rect) =>
            rect.bottom > 0 &&
            rect.top < bounds.height &&
            rect.right > 0 &&
            rect.left < bounds.width)
        .toList();
    if (clipped.length == geometry.selectionRects.length) return geometry;
    return geometry.copyWith(selectionRects: clipped);
  }

  @override
  void didChangeSelectables() {
    final selectableSet = selectables.toSet();
    _selectableStartEdgeUpdateRecords
        .removeWhere((selectable, _) => !selectableSet.contains(selectable));
    _selectableEndEdgeUpdateRecords
        .removeWhere((selectable, _) => !selectableSet.contains(selectable));
    // Children changed mid-drag (streamed in, culled, remounted): replay
    // both edges at their content positions translated into current screen
    // coordinates so the selection re-resolves against the new child list.
    // Dispatching through super skips the auto-scroll path — a replay must
    // never scroll the view toward an offscreen edge.
    final delta = deltaToOrigin;
    if (_currentDragEndRelatedToOrigin != null) {
      super.handleSelectionEdgeUpdate(SelectionEdgeUpdateEvent.forEnd(
          globalPosition: _currentDragEndRelatedToOrigin! - delta));
    }
    if (_currentDragStartRelatedToOrigin != null) {
      super.handleSelectionEdgeUpdate(SelectionEdgeUpdateEvent.forStart(
          globalPosition: _currentDragStartRelatedToOrigin! - delta));
    }
    super.didChangeSelectables();
  }

  @override
  void dispose() {
    _controller.removeListener(_scheduleLayoutChange);
    _selectableStartEdgeUpdateRecords.clear();
    _selectableEndEdgeUpdateRecords.clear();
    _scheduledLayoutChange = false;
    super.dispose();
  }
}
