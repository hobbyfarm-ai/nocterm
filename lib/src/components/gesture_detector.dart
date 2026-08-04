import '../framework/framework.dart';
import '../gestures/events.dart';
import '../gestures/hit_test.dart';
import '../gestures/tap.dart';
import '../gestures/long_press.dart';
import '../rendering/mouse_tracker.dart';
import '../rendering/pointer_gesture.dart';
import 'package:nocterm/src/rendering/mouse_region.dart';

/// A widget that detects gestures.
///
/// Attempts to recognize gestures that correspond to its non-null callbacks.
///
/// If this widget has a child, it defers to that child for sizing behavior.
/// If it does not have a child, it grows to fit the parent instead.
///
/// By default, [GestureDetector] uses [HitTestBehavior.deferToChild] for
/// determining hit test behavior.
///
/// Example:
/// ```dart
/// GestureDetector(
///   onTap: () => print('Tapped!'),
///   onDoubleTap: () => print('Double tapped!'),
///   onLongPress: () => print('Long pressed!'),
///   child: Container(
///     width: 20,
///     height: 5,
///     child: Text('Click me'),
///   ),
/// )
/// ```
class GestureDetector extends StatefulComponent {
  const GestureDetector({
    super.key,
    this.onTap,
    this.onTapDown,
    this.onTapUp,
    this.onTapCancel,
    this.onDoubleTap,
    this.onLongPress,
    this.onLongPressStart,
    this.onLongPressEnd,
    this.behavior = HitTestBehavior.deferToChild,
    this.child,
  });

  /// Called when a tap occurs.
  final GestureTapCallback? onTap;

  /// Called when a tap down has been detected.
  final GestureTapDownCallback? onTapDown;

  /// Called when a tap up has been detected.
  final GestureTapUpCallback? onTapUp;

  /// Called when a tap has been cancelled.
  final GestureTapCancelCallback? onTapCancel;

  /// Called when a double tap occurs.
  final GestureTapCallback? onDoubleTap;

  /// Called when a long press is detected.
  final GestureLongPressCallback? onLongPress;

  /// Called when a long press starts.
  final GestureLongPressStartCallback? onLongPressStart;

  /// Called when a long press ends.
  final GestureLongPressEndCallback? onLongPressEnd;

  /// How to behave during hit testing.
  final HitTestBehavior behavior;

  /// The child widget.
  final Component? child;

  @override
  State<GestureDetector> createState() => _GestureDetectorState();
}

class _GestureDetectorState extends State<GestureDetector> {
  TapGestureRecognizer? _tapRecognizer;
  DoubleTapGestureRecognizer? _doubleTapRecognizer;
  LongPressGestureRecognizer? _longPressRecognizer;

  @override
  void initState() {
    super.initState();
    _syncRecognizers();
  }

  @override
  void didUpdateComponent(GestureDetector oldComponent) {
    super.didUpdateComponent(oldComponent);
    _syncRecognizers();
  }

  @override
  void dispose() {
    _tapRecognizer?.dispose();
    _doubleTapRecognizer?.dispose();
    _longPressRecognizer?.dispose();
    super.dispose();
  }

  void _syncRecognizers() {
    // Tap recognizer
    if (component.onTap != null ||
        component.onTapDown != null ||
        component.onTapUp != null ||
        component.onTapCancel != null) {
      _tapRecognizer ??= TapGestureRecognizer();
      _tapRecognizer!
        ..onTap = component.onTap
        ..onTapDown = component.onTapDown
        ..onTapUp = component.onTapUp
        ..onTapCancel = component.onTapCancel;
    } else {
      _tapRecognizer?.dispose();
      _tapRecognizer = null;
    }

    // Double tap recognizer
    if (component.onDoubleTap != null) {
      _doubleTapRecognizer ??= DoubleTapGestureRecognizer();
      _doubleTapRecognizer!.onDoubleTap = component.onDoubleTap;
    } else {
      _doubleTapRecognizer?.dispose();
      _doubleTapRecognizer = null;
    }

    // Long press recognizer
    if (component.onLongPress != null ||
        component.onLongPressStart != null ||
        component.onLongPressEnd != null) {
      _longPressRecognizer ??= LongPressGestureRecognizer();
      _longPressRecognizer!
        ..onLongPress = component.onLongPress
        ..onLongPressStart = component.onLongPressStart
        ..onLongPressEnd = component.onLongPressEnd;
    } else {
      _longPressRecognizer?.dispose();
      _longPressRecognizer = null;
    }
  }

  void _handlePointerDown(Offset position) {
    _tapRecognizer?.addPointer(position);
    _doubleTapRecognizer?.addPointer(position);
    _longPressRecognizer?.addPointer(position);
  }

  void _handlePointerUp(Offset position) {
    _tapRecognizer?.handlePointerUp(position);
    _doubleTapRecognizer?.handlePointerUp(position);
    _longPressRecognizer?.handlePointerUp(position);
  }

  void _handlePointerMove(Offset position) {
    _tapRecognizer?.handlePointerMove(position);
    _doubleTapRecognizer?.handlePointerMove(position);
    _longPressRecognizer?.handlePointerMove(position);
  }

  void _handlePointerCancel() {
    _tapRecognizer?.rejectGesture();
    _doubleTapRecognizer?.rejectGesture();
    _longPressRecognizer?.rejectGesture();
  }

  @override
  Component build(BuildContext context) {
    // Use MouseRegion to capture mouse events
    return _GestureDetectorMouseRegion(
      onPointerDown: _handlePointerDown,
      onPointerUp: _handlePointerUp,
      onPointerMove: _handlePointerMove,
      onPointerCancel: _handlePointerCancel,
      behavior: component.behavior,
      child: component.child,
    );
  }
}

/// Internal widget that wraps the child and handles mouse events.
class _GestureDetectorMouseRegion extends SingleChildRenderObjectComponent {
  const _GestureDetectorMouseRegion({
    required this.onPointerDown,
    required this.onPointerUp,
    required this.onPointerMove,
    required this.onPointerCancel,
    required this.behavior,
    super.child,
  });

  final void Function(Offset) onPointerDown;
  final void Function(Offset) onPointerUp;
  final void Function(Offset) onPointerMove;
  final void Function() onPointerCancel;
  final HitTestBehavior behavior;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderGestureDetector(
      onPointerDown: onPointerDown,
      onPointerUp: onPointerUp,
      onPointerMove: onPointerMove,
      onPointerCancel: onPointerCancel,
      behavior: behavior,
    );
  }

  @override
  void updateRenderObject(
      BuildContext context, _RenderGestureDetector renderObject) {
    renderObject
      ..onPointerDown = onPointerDown
      ..onPointerUp = onPointerUp
      ..onPointerMove = onPointerMove
      ..onPointerCancel = onPointerCancel
      ..behavior = behavior;
  }
}

/// Render object for GestureDetector that tracks mouse events.
class _RenderGestureDetector extends RenderMouseRegion {
  _RenderGestureDetector({
    required void Function(Offset) onPointerDown,
    required void Function(Offset) onPointerUp,
    required void Function(Offset) onPointerMove,
    required void Function() onPointerCancel,
    required HitTestBehavior behavior,
  })  : _onPointerDown = onPointerDown,
        _onPointerUp = onPointerUp,
        _onPointerMove = onPointerMove,
        _onPointerCancel = onPointerCancel,
        _behavior = behavior,
        super(
          onEnter: null,
          onExit: null,
          onHover: null,
          opaque: behavior == HitTestBehavior.opaque,
        );

  void Function(Offset) _onPointerDown;
  void Function(Offset) get onPointerDown => _onPointerDown;
  set onPointerDown(void Function(Offset) value) {
    if (_onPointerDown == value) return;
    _onPointerDown = value;
    _updateGestureAnnotation();
  }

  void Function(Offset) _onPointerUp;
  void Function(Offset) get onPointerUp => _onPointerUp;
  set onPointerUp(void Function(Offset) value) {
    if (_onPointerUp == value) return;
    _onPointerUp = value;
    _updateGestureAnnotation();
  }

  void Function(Offset) _onPointerMove;
  void Function(Offset) get onPointerMove => _onPointerMove;
  set onPointerMove(void Function(Offset) value) {
    if (_onPointerMove == value) return;
    _onPointerMove = value;
    _updateGestureAnnotation();
  }

  void Function() _onPointerCancel;
  void Function() get onPointerCancel => _onPointerCancel;
  set onPointerCancel(void Function() value) {
    if (_onPointerCancel == value) return;
    _onPointerCancel = value;
    _updateGestureAnnotation();
  }

  HitTestBehavior _behavior;
  HitTestBehavior get behavior => _behavior;
  set behavior(HitTestBehavior value) {
    if (_behavior == value) return;
    _behavior = value;
    // Update opaque based on behavior
    opaque = value == HitTestBehavior.opaque;
  }

  // Store gesture detector annotation separately from mouse region annotation
  MouseTrackerAnnotation? _gestureAnnotation;

  @override
  MouseTrackerAnnotation? get annotation =>
      _gestureAnnotation ?? super.annotation;

  void _updateGestureAnnotation() {
    _gestureAnnotation = MouseTrackerAnnotation(
      dragPolicy: DragPolicy.cancel,
      onGesture: (update) => switch (update) {
        GestureBegan(:final anchor) => _onPointerDown(anchor),
        GestureDragged(:final position) => _onPointerMove(position),
        GestureEnded(:final position) => _onPointerUp(position),
        GestureCancelled() => _onPointerCancel(),
      },
      renderObject: this,
    );
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _updateGestureAnnotation();
  }

  @override
  bool hitTestSelf(Offset position) {
    // GestureDetector should always be hittable within its bounds when it has
    // gesture callbacks registered. This ensures taps work even when child
    // content is offset (e.g., by Center widget).
    //
    // The HitTestBehavior controls whether hits pass through to widgets
    // behind (via hitTest returning early for opaque), not whether this
    // GestureDetector itself is hittable.
    return true;
  }
}
