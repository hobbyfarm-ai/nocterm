/// How the terminal draws its cursor.
enum CursorShape { block, underline, bar }

/// The terminal cursor a frame asks for: where it is and how it is drawn.
///
/// A frame without one leaves the cursor hidden.
class TerminalCursor {
  const TerminalCursor({
    required this.x,
    required this.y,
    this.shape = CursorShape.block,
    this.blinking = true,
  });

  /// The column, from the left of the screen.
  final int x;

  /// The row, from the top of the screen.
  final int y;

  final CursorShape shape;

  /// Whether the terminal blinks it.
  final bool blinking;

  @override
  bool operator ==(Object other) =>
      other is TerminalCursor &&
      other.x == x &&
      other.y == y &&
      other.shape == shape &&
      other.blinking == blinking;

  @override
  int get hashCode => Object.hash(x, y, shape, blinking);

  @override
  String toString() =>
      'TerminalCursor($x, $y, ${shape.name}${blinking ? ', blinking' : ''})';
}
