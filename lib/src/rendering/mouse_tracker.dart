import '../keyboard/mouse_event.dart';
import '../framework/framework.dart';
import 'mouse_hit_test.dart';
import 'pointer_gesture.dart';

/// Signature for mouse enter/exit/hover callbacks.
typedef MouseEventCallback = void Function(MouseEvent event);

/// Signature for gesture callbacks. See [GestureUpdate].
typedef GestureUpdateCallback = void Function(GestureUpdate update);

/// An annotation that attaches mouse event callbacks to a render object.
class MouseTrackerAnnotation {
  MouseTrackerAnnotation({
    this.onEnter,
    this.onExit,
    this.onHover,
    this.onGesture,
    this.dragPolicy = DragPolicy.cancel,
    required this.renderObject,
  });

  /// Called when the mouse enters the annotated region.
  final MouseEventCallback? onEnter;

  /// Called when the mouse exits the annotated region.
  final MouseEventCallback? onExit;

  /// Called when the mouse moves within the annotated region.
  final MouseEventCallback? onHover;

  /// Called with the press/drag/release steps of a gesture that started here.
  ///
  /// Prefer this over deriving the same from [onEnter] / [onExit] /
  /// [onHover]: button state alone cannot tell a press landing here from a
  /// drag arriving from elsewhere.
  final GestureUpdateCallback? onGesture;

  /// What happens to a gesture when the pointer leaves while still held.
  /// Ignored when [onGesture] is null.
  final DragPolicy dragPolicy;

  /// The render object this annotation is attached to.
  final RenderObject renderObject;

  /// Where the in-flight gesture began, or null when there isn't one.
  Offset? _gestureAnchor;

  /// Whether the in-flight gesture has left [_gestureAnchor] yet.
  bool _gestureDragging = false;

  /// Whether this annotation is valid for mouse tracking.
  ///
  /// This is set to false when the render object is detached to prevent
  /// callbacks from being called on disposed objects during mouse event
  /// dispatching.
  bool validForMouseTracker = true;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MouseTrackerAnnotation &&
        other.renderObject == renderObject;
  }

  @override
  int get hashCode => renderObject.hashCode;
}

/// Tracks mouse annotations and dispatches enter/exit/hover events.
class MouseTracker {
  /// The set of annotations currently under the mouse cursor.
  final Set<MouseTrackerAnnotation> _hoveredAnnotations = {};

  /// The set of mouse buttons currently held down.
  final Set<MouseButton> _pressedButtons = {};

  MouseTrackerAnnotation? _capturedAnnotation;

  /// Routes all mouse events to [annotation] until [releaseCapture],
  /// bypassing hit testing and enter/exit dispatch.
  ///
  /// The terminal equivalent of pointer capture: a drag in progress owns
  /// the pointer, so leaving the annotated region neither ends the drag
  /// nor stops event delivery.
  ///
  /// Annotations using [MouseTrackerAnnotation.onGesture] never call this —
  /// [DragPolicy.capture] takes and releases the pointer for them.
  ///
  /// Every other hovered annotation is exited and has its gesture cancelled:
  /// capture ends their event delivery just as surely as the pointer leaving
  /// would, and without that they hold armed state across the whole drag.
  void capture(MouseTrackerAnnotation annotation, MouseEvent event) {
    final effectiveEvent = _eventWithButtons(event);
    // Claim first, so a cancelled gesture cannot capture back.
    _capturedAnnotation = annotation;
    for (final hovered in _hoveredAnnotations) {
      if (identical(hovered, annotation)) continue;
      if (!hovered.validForMouseTracker) continue;
      hovered.onExit?.call(effectiveEvent);
      _cancelGesture(hovered, effectiveEvent);
    }
    _hoveredAnnotations
      ..clear()
      ..add(annotation);
  }

  /// Ends a [capture], restoring hit-tested dispatch.
  void releaseCapture() {
    _capturedAnnotation = null;
  }

  /// Whether a live capture is routing all events to a single annotation.
  /// While true, [updateAnnotations] ignores hit-test results entirely, so
  /// callers can skip hit testing.
  bool get hasActiveCapture =>
      _capturedAnnotation != null && _capturedAnnotation!.validForMouseTracker;

  /// Update the hovered annotations based on hit test results and dispatch events.
  void updateAnnotations(
    MouseHitTestResult hitTestResult,
    MouseEvent event,
  ) {
    // Read the transition before the held-set absorbs this event.
    final startsPress = _startsPress(event);
    _updatePressedButtons(event);
    final effectiveEvent = _eventWithButtons(event, startsPress: startsPress);

    final captured = _capturedAnnotation;
    if (captured != null) {
      if (captured.validForMouseTracker) {
        captured.onHover?.call(effectiveEvent);
        // A captured drag owns the pointer, so it counts as inside no matter
        // where the pointer has wandered.
        _driveGesture(captured, effectiveEvent, inside: true);
        return;
      }
      _capturedAnnotation = null;
    }

    // Collect all annotations from the hit test result
    final Set<MouseTrackerAnnotation> newAnnotations = {};
    for (final entry in hitTestResult.mouseEntries) {
      if (entry.target is MouseTrackerAnnotationProvider) {
        final annotation =
            (entry.target as MouseTrackerAnnotationProvider).annotation;
        if (annotation != null) {
          newAnnotations.add(annotation);
        }
      }
    }

    // Find annotations that were exited
    final exitedAnnotations = _hoveredAnnotations.difference(newAnnotations);
    for (final annotation in exitedAnnotations) {
      if (annotation.validForMouseTracker) {
        annotation.onExit?.call(effectiveEvent);
        _driveGesture(annotation, effectiveEvent, inside: false);
      }
    }

    // Find annotations that were entered
    final enteredAnnotations = newAnnotations.difference(_hoveredAnnotations);
    for (final annotation in enteredAnnotations) {
      if (annotation.validForMouseTracker) {
        annotation.onEnter?.call(effectiveEvent);
      }
    }

    // Dispatch hover events to all currently hovered annotations
    for (final annotation in newAnnotations) {
      if (annotation.validForMouseTracker) {
        annotation.onHover?.call(effectiveEvent);
        _driveGesture(annotation, effectiveEvent, inside: true);
      }
    }

    // Update the set of hovered annotations.
    if (_capturedAnnotation == null) {
      _hoveredAnnotations.clear();
      _hoveredAnnotations.addAll(newAnnotations);
    }
  }

  /// Clear all hovered annotations (e.g., when mouse leaves the terminal).
  void clear(MouseEvent event) {
    for (final annotation in _hoveredAnnotations) {
      annotation.onExit?.call(event);
      _cancelGesture(annotation, event);
    }
    _hoveredAnnotations.clear();
    _pressedButtons.clear();
  }

  /// Advances [annotation]'s gesture for one event and reports the step.
  ///
  /// [inside] is whether the pointer counts as over the annotation: true for
  /// a hit, and true throughout a capture wherever the pointer has gone.
  void _driveGesture(
    MouseTrackerAnnotation annotation,
    MouseEvent event, {
    required bool inside,
  }) {
    final onGesture = annotation.onGesture;
    if (onGesture == null) return;
    if (event.button == MouseButton.wheelUp ||
        event.button == MouseButton.wheelDown) {
      return;
    }

    final position = Offset(event.x.toDouble(), event.y.toDouble());
    final anchor = annotation._gestureAnchor;

    if (anchor == null) {
      if (inside && event.startsPress) {
        annotation._gestureAnchor = position;
        annotation._gestureDragging = false;
        onGesture(GestureBegan(anchor: position));
      }
      return;
    }

    if (!(event.pressed || event.isPrimaryButtonDown)) {
      _endGesture(annotation);
      onGesture(inside
          ? GestureEnded(anchor: anchor, position: position)
          : GestureCancelled(anchor: anchor, position: position));
      return;
    }

    if (!inside && annotation.dragPolicy == DragPolicy.cancel) {
      _endGesture(annotation);
      onGesture(GestureCancelled(anchor: anchor, position: position));
      return;
    }

    // Cell granularity is the slop separating a click from a drag.
    if (!annotation._gestureDragging && inside && position == anchor) return;

    final justLeftAnchor = !annotation._gestureDragging;
    annotation._gestureDragging = true;
    if (annotation.dragPolicy == DragPolicy.capture) {
      _captureForGesture(annotation, event);
    }
    onGesture(GestureDragged(
      anchor: anchor,
      position: position,
      justLeftAnchor: justLeftAnchor,
    ));
  }

  /// Takes the pointer for a drag, unless another gesture got there first.
  void _captureForGesture(MouseTrackerAnnotation annotation, MouseEvent event) {
    if (_capturedAnnotation != null) return;
    capture(annotation, event);
  }

  void _endGesture(MouseTrackerAnnotation annotation) {
    annotation._gestureAnchor = null;
    annotation._gestureDragging = false;
    if (identical(_capturedAnnotation, annotation)) releaseCapture();
  }

  void _cancelGesture(MouseTrackerAnnotation annotation, MouseEvent event) {
    final anchor = annotation._gestureAnchor;
    if (anchor == null) return;
    _endGesture(annotation);
    annotation.onGesture?.call(GestureCancelled(
      anchor: anchor,
      position: Offset(event.x.toDouble(), event.y.toDouble()),
    ));
  }

  /// Track pressed buttons from press/release and motion events.
  ///
  /// SGR motion events carry authoritative button state: a drag motion
  /// reports the held button, and a no-button motion (code 35) reports that
  /// nothing is held. Using both heals stale state when a release happened
  /// outside the terminal window and was never delivered.
  void _updatePressedButtons(MouseEvent event) {
    if (event.button == MouseButton.wheelUp ||
        event.button == MouseButton.wheelDown) {
      return;
    }

    if (event.isMotion) {
      if (event.pressed) {
        _pressedButtons.add(event.button);
      } else {
        _pressedButtons.clear();
      }
      return;
    }

    if (event.pressed) {
      _pressedButtons.add(event.button);
    } else {
      _pressedButtons.remove(event.button);
    }
  }

  /// Whether [event] takes its button from up to down, rather than carrying
  /// one an earlier event already pressed. Must be read before
  /// [_updatePressedButtons] folds the event into the held set.
  bool _startsPress(MouseEvent event) {
    if (event.button == MouseButton.wheelUp ||
        event.button == MouseButton.wheelDown) {
      return false;
    }
    if (!event.pressed) return false;
    return !_pressedButtons.contains(event.button);
  }

  /// Return a copy of [event] enriched with the current pressed-buttons set.
  MouseEvent _eventWithButtons(MouseEvent event, {bool startsPress = false}) {
    return MouseEvent(
      button: event.button,
      x: event.x,
      y: event.y,
      pressed: event.pressed,
      isMotion: event.isMotion,
      buttons: Set<MouseButton>.of(_pressedButtons),
      startsPress: startsPress,
    );
  }
}

/// Interface for render objects that provide mouse tracker annotations.
mixin MouseTrackerAnnotationProvider {
  MouseTrackerAnnotation? get annotation;
}
