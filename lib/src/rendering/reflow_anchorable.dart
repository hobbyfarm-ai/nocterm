import '../framework/framework.dart';

/// A render object whose rows can be content-addressed by character index
/// across reflows.
///
/// Character indexes are width-independent while rows are not: when the
/// cross axis changes and wrapped content re-flows, a held row means nothing
/// but a held character can be looked up again. Anyone holding a position
/// through a layout change — scroll anchoring, most notably — stores the
/// character and re-reads its row after relayout.
///
/// Follows Flutter's `RenderAbstractViewport` pattern: an interface
/// implemented by render objects and tested with `is`, living in the
/// rendering layer so consumers need not know which concrete component
/// (text, paragraph, …) provides the capability.
abstract interface class ReflowAnchorable implements RenderObject {
  /// The character index at [position] in the current layout.
  int getCharacterIndexAtLocalPosition(Offset position);

  /// The local cell position (column, row) of [offset] in the current
  /// layout, clamped to the content bounds.
  ///
  /// The inverse of [getCharacterIndexAtLocalPosition].
  Offset localPositionForCharacterIndex(int offset);
}
