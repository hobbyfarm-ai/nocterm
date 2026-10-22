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

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
