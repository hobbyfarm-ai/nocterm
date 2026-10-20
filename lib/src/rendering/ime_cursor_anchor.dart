import '../framework/framework.dart';

/// A render object that can say where the terminal's IME cursor belongs.
abstract interface class ImeCursorAnchor {
  /// The global cell of the text cursor, or null when there is nothing to
  /// anchor to.
  Offset? getImeCursorPosition();
}
