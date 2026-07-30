import '../framework/framework.dart';

/// An entry in the hit test result representing a render object at a position.
class MouseHitTestEntry {
  MouseHitTestEntry(this.target, {required this.localPosition});

  /// The render object that was hit.
  final RenderObject target;

  /// The position in the local coordinate system of the target.
  final Offset localPosition;

  /// Transform from global to local coordinates.
  Offset globalToLocal(Offset global) => global - localPosition;
}

/// Result of a mouse hit test, containing all render objects hit at a position.
class MouseHitTestResult extends HitTestResult {
  final List<MouseHitTestEntry> _mouseEntries = [];

  bool _absorbed = false;

  /// The mouse-specific hit test entries.
  List<MouseHitTestEntry> get mouseEntries => _mouseEntries;

  /// Stops later (shallower) render objects from adding mouse entries.
  void absorb() => _absorbed = true;

  /// Add a mouse hit test entry to the result.
  void addMouseEntry(MouseHitTestEntry entry) {
    if (_absorbed) return;
    _mouseEntries.add(entry);
  }

  /// Add a render object with position information.
  ///
  /// A no-op once [absorb] has been called.
  void addWithPosition({
    required RenderObject target,
    required Offset localPosition,
  }) {
    if (_absorbed) return;
    _mouseEntries.add(MouseHitTestEntry(target, localPosition: localPosition));
    // Also add to base class for compatibility
    add(target);
  }
}
