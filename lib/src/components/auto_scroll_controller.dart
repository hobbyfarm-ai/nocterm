import 'package:nocterm/nocterm.dart';

/// A ScrollController that automatically scrolls to the bottom when new content
/// is added, but preserves scroll position when the user scrolls up.
/// Useful for chat interfaces, logs, and other auto-scrolling content.
class AutoScrollController extends ScrollController {
  AutoScrollController({
    super.initialScrollOffset,
    this.autoScrollThreshold = ScrollController.endReflowTolerance,
  });

  /// The distance from the bottom within which auto-scroll is enabled.
  /// If the user is within this distance from the bottom, new content
  /// will trigger auto-scroll. Defaults to one terminal cell.
  final double autoScrollThreshold;

  /// Whether auto-scroll is currently enabled based on scroll position.
  bool _isAutoScrollEnabled = true;

  /// Whether auto-scroll is currently enabled.
  bool get isAutoScrollEnabled => _isAutoScrollEnabled;

  /// Track the previous max scroll extent to detect content changes.
  double _previousMaxScrollExtent = 0.0;

  @override
  bool updateMetrics({
    required double minScrollExtent,
    required double maxScrollExtent,
    required double viewportDimension,
    AxisDirection? axisDirection,
    double? crossAxisExtent,
  }) {
    // Judged before super moves the goalposts: whether the view was reading
    // the tail, and whether this update brought new content.
    final wasNearBottom = _isNearBottom();
    final contentGrew = maxScrollExtent > _previousMaxScrollExtent;
    _previousMaxScrollExtent = maxScrollExtent;

    final accepted = super.updateMetrics(
      minScrollExtent: minScrollExtent,
      maxScrollExtent: maxScrollExtent,
      viewportDimension: viewportDimension,
      axisDirection: axisDirection,
      crossAxisExtent: crossAxisExtent,
    );
    if (!accepted) return false;

    // Follow new content while the view is reading the tail. The offset is
    // corrected synchronously and the pass rejected, so the viewport lays
    // out again and the tail is on screen this frame — never a frame late.
    if (_isAutoScrollEnabled && wasNearBottom && contentGrew) {
      final target = isReversed ? minScrollExtent : maxScrollExtent;
      if (offset != target) {
        correctPixels(target);
        return false;
      }
    }
    return true;
  }

  /// Check if the scroll position is near the bottom.
  bool _isNearBottom() {
    if (maxScrollExtent == 0) return true; // No scrolling needed

    if (isReversed) {
      // In reverse mode, "bottom" is at offset 0
      return offset <= autoScrollThreshold;
    } else {
      // In normal mode, "bottom" is at maxScrollExtent
      return offset >= maxScrollExtent - autoScrollThreshold;
    }
  }

  /// Update auto-scroll state based on current position.
  void _updateAutoScrollState() {
    final wasEnabled = _isAutoScrollEnabled;
    _isAutoScrollEnabled = _isNearBottom();

    if (wasEnabled != _isAutoScrollEnabled) {
      notifyListeners();
    }
  }

  @override
  void jumpTo(double value) {
    super.jumpTo(value);
    _updateAutoScrollState();
  }

  @override
  void scrollBy(double delta) {
    super.scrollBy(delta);
    _updateAutoScrollState();
  }

  /// Manually enable auto-scroll and scroll to bottom.
  void enableAutoScroll() {
    _isAutoScrollEnabled = true;
    if (isReversed) {
      scrollToStart(); // In reverse mode, "bottom" is at start
    } else {
      scrollToEnd(); // In normal mode, "bottom" is at end
    }
    notifyListeners();
  }

  /// Manually disable auto-scroll.
  void disableAutoScroll() {
    _isAutoScrollEnabled = false;
    notifyListeners();
  }

  /// Scroll to bottom with auto-scroll enabled.
  void scrollToBottom() {
    enableAutoScroll();
  }
}
