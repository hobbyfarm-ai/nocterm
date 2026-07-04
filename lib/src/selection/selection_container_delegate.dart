import 'dart:async';
import 'dart:math' as math;

import 'package:meta/meta.dart';

import '../binding/scheduler_binding.dart';
import '../binding/scheduler_phase.dart';
import '../framework/framework.dart';
import '../rectangle.dart';
import 'selection.dart';

/// A [SelectionHandler] that is also a [SelectionRegistrar].
///
/// Presents the [Selectable]s registered with it as a single selectable to
/// its own parent, which is what allows selection containers to nest (a list
/// item with several text blocks looks like one selectable to the outer
/// [SelectionArea]).
abstract class SelectionContainerDelegate
    with Selectable
    implements SelectionRegistrar {
  /// The render object hosting this delegate, used as the coordinate frame
  /// for [globalPaintOffset] and [globalBounds].
  RenderObject? container;

  @override
  Offset get globalPaintOffset =>
      container == null ? Offset.zero : globalPaintOffsetOf(container!);

  @override
  Rect get globalBounds {
    final origin = globalPaintOffset;
    final hasSize = container?.hasSize ?? false;
    return Rect.fromLTWH(
      origin.dx,
      origin.dy,
      hasSize ? container!.size.width : 0,
      hasSize ? container!.size.height : 0,
    );
  }
}

/// Schedules [callback] to run after the current frame.
typedef PostFrameScheduler = void Function(void Function() callback);

void _defaultPostFrameScheduler(void Function() callback) {
  final binding = SchedulerBinding.instance;
  if (binding.schedulerPhase == SchedulerPhase.postFrameCallbacks) {
    scheduleMicrotask(callback);
  } else {
    binding.addPostFrameCallback((_) => callback());
  }
}

/// Handles selection events for multiple [Selectable] children.
///
/// The selection is stored as two indices into [selectables] (kept in screen
/// order) plus each child's own selection state. Selection edge updates walk
/// the child list guided by each child's [SelectionResult] until the child
/// containing the edge is found. Children added or removed mid-selection
/// remap the indices; they never invalidate the selection itself.
abstract class MultiSelectableSelectionContainerDelegate
    extends SelectionContainerDelegate {
  MultiSelectableSelectionContainerDelegate({
    PostFrameScheduler? schedulePostFrame,
  }) : _schedulePostFrame = schedulePostFrame ?? _defaultPostFrameScheduler;

  final PostFrameScheduler _schedulePostFrame;

  /// Schedules work after the current frame; injectable for tests.
  @protected
  PostFrameScheduler get postFrameScheduler => _schedulePostFrame;

  /// The registered selectables, in screen order during a selection.
  List<Selectable> selectables = <Selectable>[];

  /// The index of the [Selectable] containing the selection end edge, or -1.
  @protected
  int currentSelectionEndIndex = -1;

  /// The index of the [Selectable] containing the selection start edge,
  /// or -1.
  @protected
  int currentSelectionStartIndex = -1;

  bool _isHandlingSelectionEvent = false;
  bool _scheduledSelectableUpdate = false;
  bool _selectionInProgress = false;
  Set<Selectable> _additions = <Selectable>{};

  @override
  void add(Selectable selectable) {
    assert(!selectables.contains(selectable));
    _additions.add(selectable);
    _scheduleSelectableUpdate();
  }

  @override
  void remove(Selectable selectable) {
    if (_additions.remove(selectable)) return;
    _removeSelectable(selectable);
    _scheduleSelectableUpdate();
  }

  /// Notifies this delegate that layout of the container changed.
  void layoutDidChange() {
    _updateSelectionGeometry();
  }

  void _scheduleSelectableUpdate() {
    if (_scheduledSelectableUpdate) return;
    _scheduledSelectableUpdate = true;
    _schedulePostFrame(() {
      if (!_scheduledSelectableUpdate) return;
      _scheduledSelectableUpdate = false;
      _updateSelectables();
    });
  }

  // Flushing additions and replaying selection edges dispatch events to many
  // children; each child's geometry notification would otherwise rebuild the
  // combined geometry, so they are suppressed the same way they are during
  // [dispatchSelectionEvent] and the geometry is rebuilt once at the end.
  void _updateSelectables() {
    _isHandlingSelectionEvent = true;
    try {
      if (_additions.isNotEmpty) {
        _flushAdditions();
      }
      didChangeSelectables();
    } finally {
      _isHandlingSelectionEvent = false;
    }
  }

  void _flushAdditions() {
    final merging = _additions.toList()..sort(compareOrder);
    final existing = selectables;
    selectables = <Selectable>[];
    var mergingIndex = 0;
    var existingIndex = 0;
    var selectionStartIndex = currentSelectionStartIndex;
    var selectionEndIndex = currentSelectionEndIndex;

    while (mergingIndex < merging.length || existingIndex < existing.length) {
      if (mergingIndex >= merging.length ||
          (existingIndex < existing.length &&
              compareOrder(existing[existingIndex], merging[mergingIndex]) <
                  0)) {
        if (existingIndex == currentSelectionStartIndex) {
          selectionStartIndex = selectables.length;
        }
        if (existingIndex == currentSelectionEndIndex) {
          selectionEndIndex = selectables.length;
        }
        selectables.add(existing[existingIndex]);
        existingIndex += 1;
        continue;
      }

      final mergingSelectable = merging[mergingIndex];
      // Any child joining during an active selection is brought up to date;
      // one that falls outside the selected region ends up with a harmless
      // collapsed selection at its nearest extremity.
      if (currentSelectionStartIndex != -1 && currentSelectionEndIndex != -1) {
        ensureChildUpdated(mergingSelectable);
      }
      mergingSelectable.addListener(_handleSelectableGeometryChange);
      selectables.add(mergingSelectable);
      mergingIndex += 1;
    }
    currentSelectionEndIndex = selectionEndIndex;
    currentSelectionStartIndex = selectionStartIndex;
    _additions = <Selectable>{};
  }

  void _removeSelectable(Selectable selectable) {
    assert(selectables.contains(selectable),
        'The selectable is not in this registrar.');
    final index = selectables.indexOf(selectable);
    selectables.removeAt(index);
    if (index <= currentSelectionEndIndex) {
      currentSelectionEndIndex -= 1;
    }
    if (index <= currentSelectionStartIndex) {
      currentSelectionStartIndex -= 1;
    }
    selectable.removeListener(_handleSelectableGeometryChange);
  }

  /// Called when this delegate finishes updating [selectables].
  @protected
  @mustCallSuper
  void didChangeSelectables() {
    _updateSelectionGeometry();
  }

  void _updateSelectionGeometry() {
    updateSelectionGeometry(getSelectionGeometry());
  }

  /// The compare function used to keep [selectables] in screen order.
  @protected
  Comparator<Selectable> get compareOrder => _compareScreenOrder;

  static int _compareScreenOrder(Selectable a, Selectable b) {
    final rectA = a.globalBounds;
    final rectB = b.globalBounds;
    final vertical = rectA.top.compareTo(rectB.top);
    if (vertical != 0) return vertical;
    return rectA.left.compareTo(rectB.left);
  }

  void _handleSelectableGeometryChange() {
    // Child geometries change repeatedly while an event is being handled;
    // the combined geometry is rebuilt once afterwards.
    if (_isHandlingSelectionEvent) return;
    _updateSelectionGeometry();
  }

  /// Combines the geometry of the children between the selection edges.
  @protected
  SelectionGeometry getSelectionGeometry() {
    if (currentSelectionEndIndex == -1 ||
        currentSelectionStartIndex == -1 ||
        selectables.isEmpty) {
      return SelectionGeometry(
        status: SelectionStatus.none,
        hasContent: selectables.isNotEmpty,
      );
    }

    currentSelectionStartIndex = _adjustSelectionIndexBasedOnSelectionGeometry(
      currentSelectionStartIndex,
      currentSelectionEndIndex,
    );
    currentSelectionEndIndex = _adjustSelectionIndexBasedOnSelectionGeometry(
      currentSelectionEndIndex,
      currentSelectionStartIndex,
    );

    final forwardSelection =
        currentSelectionEndIndex >= currentSelectionStartIndex;

    var startGeometry = selectables[currentSelectionStartIndex].value;
    var startIndexWalker = currentSelectionStartIndex;
    while (startIndexWalker != currentSelectionEndIndex &&
        startGeometry.startSelectionPoint == null) {
      startIndexWalker += forwardSelection ? 1 : -1;
      startGeometry = selectables[startIndexWalker].value;
    }
    SelectionPoint? startPoint;
    if (startGeometry.startSelectionPoint != null) {
      final childOffset = selectables[startIndexWalker].globalPaintOffset;
      startPoint = SelectionPoint(
        localPosition: startGeometry.startSelectionPoint!.localPosition +
            childOffset -
            globalPaintOffset,
      );
    }

    var endGeometry = selectables[currentSelectionEndIndex].value;
    var endIndexWalker = currentSelectionEndIndex;
    while (endIndexWalker != currentSelectionStartIndex &&
        endGeometry.endSelectionPoint == null) {
      endIndexWalker += forwardSelection ? -1 : 1;
      endGeometry = selectables[endIndexWalker].value;
    }
    SelectionPoint? endPoint;
    if (endGeometry.endSelectionPoint != null) {
      final childOffset = selectables[endIndexWalker].globalPaintOffset;
      endPoint = SelectionPoint(
        localPosition: endGeometry.endSelectionPoint!.localPosition +
            childOffset -
            globalPaintOffset,
      );
    }

    final selectionRects = <Rect>[];
    final origin = globalPaintOffset;
    final start =
        math.min(currentSelectionStartIndex, currentSelectionEndIndex);
    final end = math.max(currentSelectionStartIndex, currentSelectionEndIndex);
    for (var index = start; index <= end; index++) {
      final childOffset = selectables[index].globalPaintOffset;
      for (final rect in selectables[index].value.selectionRects) {
        selectionRects.add(rect.translate(
          childOffset.dx - origin.dx,
          childOffset.dy - origin.dy,
        ));
      }
    }

    return SelectionGeometry(
      startSelectionPoint: startPoint,
      endSelectionPoint: endPoint,
      selectionRects: selectionRects,
      status: startGeometry != endGeometry
          ? SelectionStatus.uncollapsed
          : startGeometry.status,
      hasContent: true,
    );
  }

  // The edge index may point at a selectable whose selection collapsed at a
  // boundary between two selectables. Walk toward the other edge until a
  // selectable with an uncollapsed selection is found.
  int _adjustSelectionIndexBasedOnSelectionGeometry(
    int currentIndex,
    int towardIndex,
  ) {
    final forward = towardIndex > currentIndex;
    while (currentIndex != towardIndex &&
        selectables[currentIndex].value.status != SelectionStatus.uncollapsed) {
      currentIndex += forward ? 1 : -1;
    }
    return currentIndex;
  }

  @override
  int get contentLength =>
      selectables.fold(0, (sum, selectable) => sum + selectable.contentLength);

  @override
  SelectedContent? getSelectedContent() {
    if (currentSelectionStartIndex == -1 || currentSelectionEndIndex == -1) {
      return null;
    }
    final start =
        math.min(currentSelectionStartIndex, currentSelectionEndIndex);
    final end = math.max(currentSelectionStartIndex, currentSelectionEndIndex);
    final buffer = StringBuffer();
    double? lastBottomRow;
    for (var index = start; index <= end; index++) {
      final selectable = selectables[index];
      final content = selectable.getSelectedContent();
      if (content == null) continue;
      final rects = selectable.value.selectionRects;
      final childTop = selectable.globalPaintOffset.dy;
      final firstRow = rects.isEmpty ? childTop : childTop + rects.first.top;
      final bottomRow = rects.isEmpty ? childTop : childTop + rects.last.top;
      if (lastBottomRow != null) {
        buffer.write(firstRow > lastBottomRow ? '\n' : ' ');
      }
      buffer.write(content.plainText);
      lastBottomRow = bottomRow;
    }
    if (buffer.isEmpty) return null;
    return SelectedContent(plainText: buffer.toString());
  }

  // Clears the selection on all selectables outside the range of the two
  // edge indices.
  void _flushInactiveSelections() {
    if (currentSelectionStartIndex == -1 && currentSelectionEndIndex == -1) {
      return;
    }
    if (currentSelectionStartIndex == -1 || currentSelectionEndIndex == -1) {
      final skipIndex = currentSelectionStartIndex == -1
          ? currentSelectionEndIndex
          : currentSelectionStartIndex;
      _clearSelectables(skipIndex: skipIndex);
      return;
    }
    final skipStart =
        math.min(currentSelectionStartIndex, currentSelectionEndIndex);
    final skipEnd =
        math.max(currentSelectionStartIndex, currentSelectionEndIndex);
    for (var index = 0; index < selectables.length; index += 1) {
      if (index >= skipStart && index <= skipEnd) continue;
      dispatchSelectionEventToChild(
          selectables[index], const ClearSelectionEvent());
    }
  }

  void _clearSelectables({int? skipIndex}) {
    for (var i = 0; i < selectables.length; i++) {
      if (i == skipIndex) continue;
      dispatchSelectionEventToChild(
          selectables[i], const ClearSelectionEvent());
    }
  }

  /// Selects all content in every child.
  @protected
  SelectionResult handleSelectAll(SelectAllSelectionEvent event) {
    for (final selectable in selectables) {
      dispatchSelectionEventToChild(selectable, event);
    }
    currentSelectionStartIndex = 0;
    currentSelectionEndIndex = selectables.length - 1;
    return SelectionResult.none;
  }

  /// Selects the word at [SelectWordSelectionEvent.globalPosition].
  @protected
  SelectionResult handleSelectWord(SelectWordSelectionEvent event) {
    var minDistanceSquared = double.infinity;
    var nearestIndex = -1;
    for (var index = 0; index < selectables.length; index += 1) {
      final rect = selectables[index].globalBounds;
      final position = event.globalPosition;
      if (rect.contains(position)) {
        nearestIndex = index;
        minDistanceSquared = 0;
        break;
      }
      final dx = position.dx -
          position.dx.clamp(rect.left, math.max(rect.left, rect.right - 1));
      final dy = position.dy -
          position.dy.clamp(rect.top, math.max(rect.top, rect.bottom - 1));
      final distanceSquared = dx * dx + dy * dy;
      if (distanceSquared < minDistanceSquared) {
        minDistanceSquared = distanceSquared;
        nearestIndex = index;
      }
    }
    if (nearestIndex == -1) return SelectionResult.end;

    final target = selectables[nearestIndex];
    final existingGeometry = target.value;
    dispatchSelectionEventToChild(target, event);
    if (target.value != existingGeometry) {
      _clearSelectables(skipIndex: nearestIndex);
      currentSelectionStartIndex = currentSelectionEndIndex = nearestIndex;
    }
    return SelectionResult.end;
  }

  /// Removes the selection from every child.
  @protected
  SelectionResult handleClearSelection(ClearSelectionEvent event) {
    for (final selectable in selectables) {
      dispatchSelectionEventToChild(selectable, event);
    }
    currentSelectionEndIndex = -1;
    currentSelectionStartIndex = -1;
    return SelectionResult.none;
  }

  /// Updates one selection edge.
  @protected
  SelectionResult handleSelectionEdgeUpdate(SelectionEdgeUpdateEvent event) {
    if (event.isEnd) {
      return currentSelectionEndIndex == -1
          ? _initSelection(event, isEnd: true)
          : _adjustSelection(event, isEnd: true);
    }
    return currentSelectionStartIndex == -1
        ? _initSelection(event, isEnd: false)
        : _adjustSelection(event, isEnd: false);
  }

  @override
  SelectionResult dispatchSelectionEvent(SelectionEvent event) {
    final selectionWillBeInProgress = event is! ClearSelectionEvent;
    if (!_selectionInProgress && selectionWillBeInProgress) {
      selectables.sort(compareOrder);
    }
    _selectionInProgress = selectionWillBeInProgress;
    _isHandlingSelectionEvent = true;
    final result = switch (event) {
      SelectionEdgeUpdateEvent() => handleSelectionEdgeUpdate(event),
      ClearSelectionEvent() => handleClearSelection(event),
      SelectAllSelectionEvent() => handleSelectAll(event),
      SelectWordSelectionEvent() => handleSelectWord(event),
    };
    _isHandlingSelectionEvent = false;
    _updateSelectionGeometry();
    return result;
  }

  @override
  void dispose() {
    for (final selectable in selectables) {
      selectable.removeListener(_handleSelectableGeometryChange);
    }
    selectables = const <Selectable>[];
    _scheduledSelectableUpdate = false;
  }

  /// Brings a child that joined mid-selection up to date.
  ///
  /// Called when a newly added [Selectable] falls inside the existing
  /// selection, and before edge events are dispatched to a child.
  @protected
  void ensureChildUpdated(Selectable selectable);

  /// Dispatches [event] to [selectable].
  @protected
  SelectionResult dispatchSelectionEventToChild(
    Selectable selectable,
    SelectionEvent event,
  ) {
    return selectable.dispatchSelectionEvent(event);
  }

  /// Finds the child containing an edge that has no current index by
  /// sweeping the child list, guided by each child's [SelectionResult].
  SelectionResult _initSelection(
    SelectionEdgeUpdateEvent event, {
    required bool isEnd,
  }) {
    assert((isEnd && currentSelectionEndIndex == -1) ||
        (!isEnd && currentSelectionStartIndex == -1));
    var newIndex = -1;
    var hasFoundEdgeIndex = false;
    SelectionResult? result;
    bool? forward;
    final oppositeEdgeIndex =
        isEnd ? currentSelectionStartIndex : currentSelectionEndIndex;
    var index = math.max(oppositeEdgeIndex, 0);

    while (index >= 0 && index < selectables.length) {
      final childResult =
          dispatchSelectionEventToChild(selectables[index], event);
      switch (childResult) {
        case SelectionResult.next:
          if (forward == false) {
            hasFoundEdgeIndex = true;
            result = SelectionResult.end;
          } else {
            forward = true;
            newIndex = index;
          }
        case SelectionResult.none:
          newIndex = index;
        case SelectionResult.end:
          newIndex = index;
          result = SelectionResult.end;
          hasFoundEdgeIndex = true;
        case SelectionResult.previous:
          if (index == 0) {
            hasFoundEdgeIndex = true;
            newIndex = 0;
            result = SelectionResult.previous;
            break;
          }
          if (forward ?? false) {
            hasFoundEdgeIndex = true;
            result = SelectionResult.end;
          } else {
            forward = false;
            newIndex = index;
          }
        case SelectionResult.pending:
          newIndex = index;
          result = SelectionResult.pending;
          hasFoundEdgeIndex = true;
      }
      if (hasFoundEdgeIndex) break;
      index += (forward ?? true) ? 1 : -1;
    }

    if (newIndex == -1) {
      assert(selectables.isEmpty);
      return SelectionResult.none;
    }
    if (isEnd) {
      currentSelectionEndIndex = newIndex;
    } else {
      currentSelectionStartIndex = newIndex;
    }
    _flushInactiveSelections();
    return result ?? SelectionResult.next;
  }

  /// Moves an edge that already has an index, walking forward or backward
  /// from it as directed by each child's [SelectionResult].
  SelectionResult _adjustSelection(
    SelectionEdgeUpdateEvent event, {
    required bool isEnd,
  }) {
    SelectionResult? finalResult;
    var newIndex =
        isEnd ? currentSelectionEndIndex : currentSelectionStartIndex;
    bool? forward;
    while (
        newIndex < selectables.length && newIndex >= 0 && finalResult == null) {
      final currentResult =
          dispatchSelectionEventToChild(selectables[newIndex], event);
      switch (currentResult) {
        case SelectionResult.end:
        case SelectionResult.pending:
        case SelectionResult.none:
          finalResult = currentResult;
        case SelectionResult.next:
          if (forward == false) {
            newIndex += 1;
            finalResult = SelectionResult.end;
          } else if (newIndex == selectables.length - 1) {
            finalResult = currentResult;
          } else {
            forward = true;
            newIndex += 1;
          }
        case SelectionResult.previous:
          if (forward ?? false) {
            newIndex -= 1;
            finalResult = SelectionResult.end;
          } else if (newIndex == 0) {
            finalResult = currentResult;
          } else {
            forward = false;
            newIndex -= 1;
          }
      }
    }
    if (isEnd) {
      currentSelectionEndIndex = newIndex;
    } else {
      currentSelectionStartIndex = newIndex;
    }
    _flushInactiveSelections();
    return finalResult!;
  }
}

/// A [MultiSelectableSelectionContainerDelegate] for children that stay put
/// while a selection is in progress, with support for children appearing or
/// disappearing mid-selection.
///
/// Remembers the last global position of each selection edge. When a child
/// joins the selected region (streamed content, scroll reveal), the missing
/// edge events are synthesized from those positions so the newcomer
/// integrates into the existing selection; when the set of children changes,
/// both edges are replayed to re-resolve the selection against the new list.
class StaticSelectionContainerDelegate
    extends MultiSelectableSelectionContainerDelegate {
  StaticSelectionContainerDelegate({super.schedulePostFrame});

  final Set<Selectable> _hasReceivedStartEvent = <Selectable>{};
  final Set<Selectable> _hasReceivedEndEvent = <Selectable>{};

  Offset? _lastStartEdgeUpdateGlobalPosition;
  Offset? _lastEndEdgeUpdateGlobalPosition;

  /// Records that [selectable] received a start ([forEnd] false), end
  /// ([forEnd] true), or both ([forEnd] null) edge events.
  @protected
  void didReceiveSelectionEventFor({
    required Selectable selectable,
    bool? forEnd,
  }) {
    switch (forEnd) {
      case true:
        _hasReceivedEndEvent.add(selectable);
      case false:
        _hasReceivedStartEvent.add(selectable);
      case null:
        _hasReceivedStartEvent.add(selectable);
        _hasReceivedEndEvent.add(selectable);
    }
  }

  /// Updates internal state after an event that selects a boundary
  /// ([SelectAllSelectionEvent], [SelectWordSelectionEvent]).
  @protected
  void didReceiveSelectionBoundaryEvents() {
    if (currentSelectionStartIndex == -1 || currentSelectionEndIndex == -1) {
      return;
    }
    final start =
        math.min(currentSelectionStartIndex, currentSelectionEndIndex);
    final end = math.max(currentSelectionStartIndex, currentSelectionEndIndex);
    for (var index = start; index <= end; index += 1) {
      didReceiveSelectionEventFor(selectable: selectables[index]);
    }
    _updateLastSelectionEdgeLocationsFromGeometries();
  }

  void _updateLastSelectionEdgeLocationsFromGeometries() {
    if (currentSelectionStartIndex != -1 &&
        selectables[currentSelectionStartIndex].value.hasSelection) {
      final start = selectables[currentSelectionStartIndex];
      final startPoint = start.value.startSelectionPoint;
      if (startPoint != null) {
        _lastStartEdgeUpdateGlobalPosition =
            start.globalPaintOffset + startPoint.localPosition;
      }
    }
    if (currentSelectionEndIndex != -1 &&
        selectables[currentSelectionEndIndex].value.hasSelection) {
      final end = selectables[currentSelectionEndIndex];
      final endPoint = end.value.endSelectionPoint;
      if (endPoint != null) {
        _lastEndEdgeUpdateGlobalPosition =
            end.globalPaintOffset + endPoint.localPosition;
      }
    }
  }

  /// Resets all internal selection bookkeeping.
  @protected
  void clearInternalSelectionState() {
    _hasReceivedStartEvent.clear();
    _hasReceivedEndEvent.clear();
    _lastStartEdgeUpdateGlobalPosition = null;
    _lastEndEdgeUpdateGlobalPosition = null;
  }

  /// Forgets edge-event bookkeeping for [selectable].
  @protected
  void clearInternalSelectionStateForSelectable(Selectable selectable) {
    _hasReceivedStartEvent.remove(selectable);
    _hasReceivedEndEvent.remove(selectable);
  }

  @override
  void remove(Selectable selectable) {
    clearInternalSelectionStateForSelectable(selectable);
    super.remove(selectable);
  }

  @override
  SelectionResult handleSelectAll(SelectAllSelectionEvent event) {
    final result = super.handleSelectAll(event);
    didReceiveSelectionBoundaryEvents();
    return result;
  }

  @override
  SelectionResult handleSelectWord(SelectWordSelectionEvent event) {
    final result = super.handleSelectWord(event);
    didReceiveSelectionBoundaryEvents();
    return result;
  }

  @override
  SelectionResult handleClearSelection(ClearSelectionEvent event) {
    final result = super.handleClearSelection(event);
    clearInternalSelectionState();
    return result;
  }

  @override
  SelectionResult handleSelectionEdgeUpdate(SelectionEdgeUpdateEvent event) {
    if (event.isEnd) {
      _lastEndEdgeUpdateGlobalPosition = event.globalPosition;
    } else {
      _lastStartEdgeUpdateGlobalPosition = event.globalPosition;
    }
    return super.handleSelectionEdgeUpdate(event);
  }

  @override
  void dispose() {
    clearInternalSelectionState();
    super.dispose();
  }

  @override
  SelectionResult dispatchSelectionEventToChild(
    Selectable selectable,
    SelectionEvent event,
  ) {
    switch (event) {
      case SelectionEdgeUpdateEvent():
        didReceiveSelectionEventFor(
            selectable: selectable, forEnd: event.isEnd);
        ensureChildUpdated(selectable);
      case ClearSelectionEvent():
        clearInternalSelectionStateForSelectable(selectable);
      case SelectAllSelectionEvent():
      case SelectWordSelectionEvent():
        break;
    }
    return super.dispatchSelectionEventToChild(selectable, event);
  }

  /// Synthesizes any missing edge events for [selectable] from the last
  /// known edge positions.
  @override
  void ensureChildUpdated(Selectable selectable) {
    if (_lastEndEdgeUpdateGlobalPosition != null &&
        _hasReceivedEndEvent.add(selectable)) {
      final synthesized = SelectionEdgeUpdateEvent.forEnd(
        globalPosition: _lastEndEdgeUpdateGlobalPosition!,
      );
      if (currentSelectionEndIndex == -1) {
        handleSelectionEdgeUpdate(synthesized);
      }
      selectable.dispatchSelectionEvent(synthesized);
    }
    if (_lastStartEdgeUpdateGlobalPosition != null &&
        _hasReceivedStartEvent.add(selectable)) {
      final synthesized = SelectionEdgeUpdateEvent.forStart(
        globalPosition: _lastStartEdgeUpdateGlobalPosition!,
      );
      if (currentSelectionStartIndex == -1) {
        handleSelectionEdgeUpdate(synthesized);
      }
      selectable.dispatchSelectionEvent(synthesized);
    }
  }

  @override
  void didChangeSelectables() {
    if (_lastEndEdgeUpdateGlobalPosition != null) {
      handleSelectionEdgeUpdate(SelectionEdgeUpdateEvent.forEnd(
        globalPosition: _lastEndEdgeUpdateGlobalPosition!,
      ));
    }
    if (_lastStartEdgeUpdateGlobalPosition != null) {
      handleSelectionEdgeUpdate(SelectionEdgeUpdateEvent.forStart(
        globalPosition: _lastStartEdgeUpdateGlobalPosition!,
      ));
    }
    final selectableSet = selectables.toSet();
    _hasReceivedEndEvent
        .removeWhere((selectable) => !selectableSet.contains(selectable));
    _hasReceivedStartEvent
        .removeWhere((selectable) => !selectableSet.contains(selectable));
    super.didChangeSelectables();
  }
}
