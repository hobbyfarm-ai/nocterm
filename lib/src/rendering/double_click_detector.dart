import '../framework/framework.dart';

/// Recognizes a double click from a series of presses.
///
/// A press completes a double click when it lands within [window] of the
/// previous press, on the same row, and within [tolerance] columns of it.
/// The press that completes a double click starts nothing, so a third press
/// within the window is a fresh first press.
class DoubleClickDetector {
  DoubleClickDetector({
    this.window = const Duration(milliseconds: 400),
    this.tolerance = 1,
    DateTime Function() now = DateTime.now,
  }) : _now = now;

  final Duration window;
  final double tolerance;
  final DateTime Function() _now;

  DateTime? _lastPressTime;
  Offset? _lastPressPosition;

  /// Records a press at [position], in cells; true when it completes a
  /// double click.
  bool press(Offset position) {
    final now = _now();
    final lastTime = _lastPressTime;
    final lastPosition = _lastPressPosition;
    final isDoubleClick = lastTime != null &&
        lastPosition != null &&
        now.difference(lastTime) < window &&
        position.dy == lastPosition.dy &&
        (position.dx - lastPosition.dx).abs() <= tolerance;
    if (isDoubleClick) {
      _lastPressTime = null;
      _lastPressPosition = null;
      return true;
    }
    _lastPressTime = now;
    _lastPressPosition = position;
    return false;
  }
}
