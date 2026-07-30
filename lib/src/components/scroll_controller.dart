import 'package:meta/meta.dart';
import 'package:nocterm/nocterm.dart';

/// Controls a scrollable widget.
///
/// Manages the scroll position and provides methods to programmatically
/// control scrolling.
class ScrollController extends ChangeNotifier {
  ScrollController({
    double initialScrollOffset = 0.0,
  }) : _offset = initialScrollOffset;

  double _offset;
  double _minScrollExtent = 0.0;
  double _maxScrollExtent = 0.0;
  double _viewportDimension = 0.0;
  AxisDirection _axisDirection = AxisDirection.down;

  /// Offsets this close to [maxScrollExtent] count as reading the tail when
  /// deciding whether a cross-axis reflow should keep the view pinned to the
  /// end of the content. One terminal cell.
  static const double endReflowTolerance = 1.0;

  /// Cross-axis extent reported by the last [updateMetrics] call, used to
  /// detect reflows. Null until a viewport reports one.
  double? _lastCrossAxisExtent;

  /// Whether a reflow started while the view was reading the tail. Stays set
  /// across [updateMetrics] calls until the offset settles on the end —
  /// lazily-measured content revises its extent estimate over several layout
  /// passes, and each revision moves the end the pin is chasing.
  bool _pinnedToEndByReflow = false;

  /// Set by [correctBy]; makes the next accepted [updateMetrics] notify even
  /// when the metrics themselves are unchanged, so listeners hear about
  /// layout-time offset corrections. Mirrors Flutter's
  /// `_didChangeViewportDimensionOrReceiveCorrection`.
  bool _receivedCorrection = false;

  /// Whether a metrics notification is already scheduled for the end of the
  /// current frame.
  bool _notificationScheduled = false;

  /// The attached render object (used for index-based scrolling)
  Object? _attachedRenderObject;

  /// The current scroll offset.
  double get offset => _offset;

  /// The minimum in-range value for [offset].
  double get minScrollExtent => _minScrollExtent;

  /// The maximum in-range value for [offset].
  double get maxScrollExtent => _maxScrollExtent;

  /// The extent of the viewport in the scrolling direction.
  double get viewportDimension => _viewportDimension;

  /// The axis direction of scrolling.
  AxisDirection get axisDirection => _axisDirection;

  /// Whether scrolling is reversed (up for vertical, left for horizontal).
  bool get isReversed =>
      _axisDirection == AxisDirection.up ||
      _axisDirection == AxisDirection.left;

  /// Whether the [offset] is at the minimum value.
  bool get atStart => offset <= minScrollExtent;

  /// Whether the [offset] is at the maximum value.
  bool get atEnd => offset >= maxScrollExtent;

  /// The total scrollable extent.
  double get scrollExtent => maxScrollExtent - minScrollExtent;

  /// Applies a layout-time correction to [offset].
  ///
  /// Changes [offset] by [correction] without notifying listeners. Following
  /// Flutter's `ViewportOffset.correctBy` pattern, this may only be called
  /// during layout, by the viewport render object that owns this controller,
  /// after which the viewport must lay out again against the corrected value.
  /// The correction is remembered so the accepting [updateMetrics] call still
  /// notifies listeners even when the metrics themselves are unchanged.
  void correctBy(double correction) {
    _offset += correction;
    _receivedCorrection = true;
  }

  /// Changes [offset] to [value] without notifying listeners and without
  /// honoring the normal conventions for changing the scroll offset.
  ///
  /// Following Flutter's `ScrollPosition.correctPixels` pattern, this is for
  /// subclasses adjusting their own position during layout — typically from
  /// inside [updateMetrics] before returning false to reject the pass.
  @protected
  void correctPixels(double value) {
    _offset = value;
    _receivedCorrection = true;
  }

  /// Updates the scroll metrics from a layout pass and reports whether the
  /// pass is acceptable.
  ///
  /// Called by scrollable render objects during layout. Returns true when the
  /// metrics are accepted as-is. Returns false when the controller corrected
  /// [offset] in response — the pass was laid out against a stale offset, and
  /// the caller must lay out again with the corrected value, mirroring
  /// Flutter's `ViewportOffset.applyContentDimensions` contract.
  ///
  /// [crossAxisExtent] is the viewport's extent perpendicular to the scroll
  /// axis. A change in it means variable-extent content re-wrapped — the same
  /// content now occupies different offsets — which is the one fact that
  /// distinguishes a reflow from an append. When it changes while the view is
  /// reading the tail, the offset is pinned to the end of the content: after
  /// a re-wrap the end is still what the reader was reading. Null means the
  /// caller doesn't track a cross axis; detection is skipped.
  ///
  /// Listeners are not notified synchronously — layout is too early for them
  /// to usefully react, and reacting mid-layout would re-enter the pipeline.
  /// A notification is coalesced and delivered after the frame completes.
  bool updateMetrics({
    required double minScrollExtent,
    required double maxScrollExtent,
    required double viewportDimension,
    AxisDirection? axisDirection,
    double? crossAxisExtent,
  }) {
    final oldMin = _minScrollExtent;
    final oldMax = _maxScrollExtent;
    final oldViewport = _viewportDimension;
    final oldAxisDirection = _axisDirection;

    // Judged against the old metrics: whether the view was reading the tail
    // before this update moved the goalposts. An unscrolled view is not
    // "reading the tail" even when the old extent was zero.
    final wasNearEnd =
        _offset > 0 && _offset >= _maxScrollExtent - endReflowTolerance;

    final reflowed = crossAxisExtent != null &&
        _lastCrossAxisExtent != null &&
        crossAxisExtent != _lastCrossAxisExtent;
    if (crossAxisExtent != null) {
      _lastCrossAxisExtent = crossAxisExtent;
    }
    // A correction this frame means a viewport is already steering the
    // offset somewhere deliberate — a content anchor, which only exists when
    // the view was *not* reading the tail — so [wasNearEnd], judged against
    // the mid-negotiation offset, is meaningless and the pin stands down.
    if (reflowed && wasNearEnd && !_receivedCorrection) {
      _pinnedToEndByReflow = true;
    }

    _minScrollExtent = minScrollExtent;
    _maxScrollExtent = maxScrollExtent;
    _viewportDimension = viewportDimension;
    if (axisDirection != null) {
      _axisDirection = axisDirection;
    }

    // Reflow end-pin. Re-applied every pass until the offset and the end
    // agree, because estimated extents move the end between passes.
    if (_pinnedToEndByReflow) {
      if (_offset != maxScrollExtent) {
        _offset = maxScrollExtent;
        _scheduleNotification();
        return false;
      }
      _pinnedToEndByReflow = false;
    }

    // The caller laid out against the unclamped offset, so a clamp that
    // moves it invalidates the pass.
    final clamped = _offset.clamp(minScrollExtent, maxScrollExtent);
    if (clamped != _offset) {
      _offset = clamped;
      _scheduleNotification();
      return false;
    }

    if (oldMin != _minScrollExtent ||
        oldMax != _maxScrollExtent ||
        oldViewport != _viewportDimension ||
        oldAxisDirection != _axisDirection ||
        _receivedCorrection) {
      _receivedCorrection = false;
      _scheduleNotification();
    }
    return true;
  }

  /// Schedules a coalesced listener notification for the end of the frame.
  ///
  /// Flutter's pattern: by layout time the frame's listeners have already
  /// built, so a synchronous notification is at best useless and at worst
  /// re-enters the pipeline. Without a binding (bare unit tests) the
  /// notification is delivered synchronously instead.
  void _scheduleNotification() {
    if (_notificationScheduled) return;
    _notificationScheduled = true;
    try {
      TerminalBinding.instance.addPostFrameCallback((_) {
        _notificationScheduled = false;
        notifyListeners();
      });
    } catch (_) {
      _notificationScheduled = false;
      notifyListeners();
    }
  }

  /// Jumps the scroll position to the given value.
  void jumpTo(double value) {
    _offset = value.clamp(minScrollExtent, maxScrollExtent);
    _pinnedToEndByReflow = false;
    notifyListeners();
  }

  /// Scrolls by the given delta.
  void scrollBy(double delta) {
    jumpTo(offset + delta);
  }

  /// Scrolls up by one line (for TUI).
  void scrollUp([double lines = 1.0]) {
    scrollBy(-lines);
  }

  /// Scrolls down by one line (for TUI).
  void scrollDown([double lines = 1.0]) {
    scrollBy(lines);
  }

  /// Scrolls up by one page.
  void pageUp() {
    scrollBy(-viewportDimension);
  }

  /// Scrolls down by one page.
  void pageDown() {
    scrollBy(viewportDimension);
  }

  /// Scrolls to the start.
  void scrollToStart() {
    jumpTo(minScrollExtent);
  }

  /// Scrolls to the end.
  void scrollToEnd() {
    jumpTo(maxScrollExtent);
  }

  /// Ensures that an item at the given position is visible in the viewport.
  ///
  /// This method scrolls the viewport only if necessary to make the item
  /// visible. If the item is already fully visible, no scrolling occurs.
  ///
  /// Parameters:
  /// - [itemOffset]: The offset of the item from the start of the scrollable content.
  /// - [itemExtent]: The extent (height for vertical, width for horizontal) of the item.
  ///
  /// The method performs minimal scrolling:
  /// - If the item is below the viewport, scrolls down to show it at the bottom.
  /// - If the item is above the viewport, scrolls up to show it at the top.
  /// - If the item is already fully visible, does not scroll.
  /// - If the item is larger than the viewport, scrolls to show the start of the item.
  void ensureVisible({
    required double itemOffset,
    required double itemExtent,
  }) {
    final itemStart = itemOffset;
    final itemEnd = itemOffset + itemExtent;
    final viewportStart = offset;
    final viewportEnd = offset + viewportDimension;

    // Item is fully visible - no need to scroll
    if (itemStart >= viewportStart && itemEnd <= viewportEnd) {
      return;
    }

    // Item is larger than viewport - show the start
    if (itemExtent > viewportDimension) {
      jumpTo(itemStart);
      return;
    }

    // Item is below viewport - scroll down to show it at the bottom
    if (itemEnd > viewportEnd) {
      final targetOffset = itemEnd - viewportDimension;
      jumpTo(targetOffset);
      return;
    }

    // Item is above viewport - scroll up to show it at the top
    if (itemStart < viewportStart) {
      jumpTo(itemStart);
      return;
    }
  }

  /// Attaches a render object to this controller.
  ///
  /// This is called by render objects (like RenderListViewport) when they
  /// are created with this controller. It allows the controller to query
  /// the render object for operations like [ensureIndexVisible].
  void attach(Object renderObject) {
    _attachedRenderObject = renderObject;
  }

  /// Detaches a render object from this controller.
  ///
  /// This is called by render objects when they are disposed.
  void detach(Object renderObject) {
    if (_attachedRenderObject == renderObject) {
      _attachedRenderObject = null;
    }
  }

  /// Ensures that an item at the given index is visible in the viewport.
  ///
  /// This method queries the attached [RenderListViewport] to get the item's
  /// position and then scrolls the viewport to make it visible using [ensureVisible].
  ///
  /// Parameters:
  /// - [index]: The index of the item to make visible.
  ///
  /// If the item's position cannot be determined (e.g., the item hasn't been
  /// laid out yet in lazy mode, or there's no attached RenderListViewport),
  /// this method does nothing.
  ///
  /// Example:
  /// ```dart
  /// scrollController.ensureIndexVisible(index: selectedIndex);
  /// ```
  void ensureIndexVisible({required int index}) {
    // Import is needed at the top of the file
    final renderViewport = _attachedRenderObject;

    if (renderViewport is! RenderListViewport) {
      // No ListView attached or wrong type
      return;
    }

    // Query the render object for the item's position
    final itemInfo = renderViewport.getItemOffsetAndExtent(index);

    if (itemInfo == null) {
      // Item position unknown (not laid out yet, or doesn't exist)
      return;
    }

    final (itemOffset, itemExtent) = itemInfo;

    // Use the existing ensureVisible logic
    ensureVisible(
      itemOffset: itemOffset,
      itemExtent: itemExtent,
    );
  }
}

/// Base class for change notification.
abstract class ChangeNotifier implements Listenable {
  final List<VoidCallback> _listeners = [];

  /// Register a closure to be called when the object notifies its listeners.
  @override
  void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  /// Remove a previously registered listener.
  @override
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  /// Call all registered listeners.
  void notifyListeners() {
    for (final listener in _listeners) {
      listener();
    }
  }

  /// Discards any resources used by the object.
  void dispose() {
    _listeners.clear();
  }
}
