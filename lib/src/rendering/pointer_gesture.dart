import '../framework/framework.dart';

/// What becomes of a gesture when the pointer leaves while still held.
enum DragPolicy {
  /// Abandon it — dragging away is how a user takes a click back.
  cancel,

  /// Keep it. The tracker captures the pointer and releases on button up.
  capture,
}

/// One step of a pointer gesture on a single annotation.
///
/// A gesture begins where a button goes down and belongs to that annotation
/// until it comes up, so a drag passing over some other element is never that
/// element's to complete.
sealed class GestureUpdate {
  const GestureUpdate({required this.anchor, required this.position});

  /// Where the button went down.
  final Offset anchor;

  /// Where the pointer is now. May be outside the annotation mid-capture.
  final Offset position;
}

/// The button went down on this annotation.
final class GestureBegan extends GestureUpdate {
  const GestureBegan({required super.anchor}) : super(position: anchor);
}

/// The pointer moved while held, having left [anchor].
final class GestureDragged extends GestureUpdate {
  const GestureDragged({
    required super.anchor,
    required super.position,
    required this.justLeftAnchor,
  });

  /// True on the event that turned this press into a drag.
  final bool justLeftAnchor;
}

/// The button came up and the gesture completed.
final class GestureEnded extends GestureUpdate {
  const GestureEnded({required super.anchor, required super.position});
}

/// The gesture was abandoned — the pointer left a [DragPolicy.cancel]
/// annotation, another took capture, or the mouse left the terminal.
final class GestureCancelled extends GestureUpdate {
  const GestureCancelled({required super.anchor, required super.position});
}
