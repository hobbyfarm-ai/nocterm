/// Mouse button types
enum MouseButton {
  left,
  middle,
  right,
  wheelUp,
  wheelDown,
}

/// Mouse event for terminal interactions
class MouseEvent {
  final MouseButton button;
  final int x; // Column position (0-based)
  final int y; // Row position (0-based)
  final bool pressed; // true for press, false for release
  final bool isMotion; // true for motion events (drag), false for press/release

  /// The set of mouse buttons currently held down (enriched by [MouseTracker]).
  final Set<MouseButton> buttons;

  /// Whether this event is [button] going down, as opposed to a report that
  /// merely carries a button pressed by some earlier event.
  final bool startsPress;

  const MouseEvent({
    required this.button,
    required this.x,
    required this.y,
    required this.pressed,
    this.isMotion = false,
    this.buttons = const {},
    this.startsPress = false,
  });

  /// Whether the primary (left) button is currently held down.
  bool get isPrimaryButtonDown => buttons.contains(MouseButton.left);

  @override
  String toString() =>
      'MouseEvent($button at $x,$y pressed=$pressed${isMotion ? ' (motion)' : ''}${buttons.isNotEmpty ? ' buttons=$buttons' : ''})';
}
