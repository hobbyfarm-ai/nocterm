import '../binding/mouse_router.dart';
import '../binding/scheduler_binding.dart';
import '../framework/framework.dart';
import '../keyboard/mouse_event.dart';
import '../rendering/mouse_region.dart';
import '../rendering/mouse_tracker.dart';
import '../style.dart';
import '../theme/tui_theme.dart';
import 'selection.dart';
import 'selection_container.dart';
import 'selection_container_delegate.dart';

/// The colors used to paint selected text, provided by [SelectionArea].
///
/// Selectable text components read this during build and apply the colors to
/// their render objects, so highlight styling reaches every selectable in the
/// subtree regardless of which registrar it registered with.
class SelectionStyle extends InheritedComponent {
  const SelectionStyle({
    super.key,
    required this.selection,
    required this.onSelection,
    required super.child,
  });

  /// Background color used to highlight selected text.
  final Color selection;

  /// Foreground color for text drawn on top of [selection].
  final Color onSelection;

  /// The style of the closest enclosing [SelectionArea], if any.
  static SelectionStyle? maybeOf(BuildContext context) {
    return context.dependOnInheritedComponentOfExactType<SelectionStyle>();
  }

  @override
  bool updateShouldNotify(SelectionStyle oldComponent) {
    return selection != oldComponent.selection ||
        onSelection != oldComponent.onSelection;
  }
}

/// Enables mouse text selection across all selectable descendants.
///
/// Wrap a subtree to allow click-and-drag selection spanning multiple
/// components:
///
/// ```dart
/// SelectionArea(
///   child: Column(children: [
///     Text('First paragraph'),
///     Text('Second paragraph'),
///   ]),
/// )
/// ```
///
/// Descendant selectables register with this area's [SelectionRegistrar];
/// pointer gestures are translated into [SelectionEvent]s dispatched through
/// a [StaticSelectionContainerDelegate], which owns the selection as a pair
/// of child indices plus per-child character ranges. Content that rebuilds,
/// streams in, or disappears mid-selection is re-integrated by the delegate
/// rather than invalidating the selection; scrollables nest their own
/// scroll-aware delegate via [SelectionContainer].
class SelectionArea extends StatefulComponent {
  const SelectionArea({
    super.key,
    required this.child,
    this.selection,
    this.onSelection,
    this.onSelectionChanged,
    this.onSelectionCompleted,
  });

  /// The subtree in which text can be selected.
  final Component child;

  /// Background color used to highlight selected text.
  /// If null, defaults to [TuiThemeData.selection].
  final Color? selection;

  /// Foreground color for text drawn on top of [selection].
  /// If null, defaults to [TuiThemeData.onSelection].
  final Color? onSelection;

  /// Called with the currently selected text whenever the selection
  /// changes, or an empty string when it is cleared.
  ///
  /// Notifications are coalesced to at most one per frame.
  final void Function(String)? onSelectionChanged;

  /// Called with the selected text when a drag selection completes.
  final void Function(String)? onSelectionCompleted;

  @override
  State<SelectionArea> createState() => _SelectionAreaState();
}

class _SelectionAreaState extends State<SelectionArea> {
  final _delegate = StaticSelectionContainerDelegate();
  String? _lastNotifiedText;
  bool _notificationScheduled = false;

  @override
  void initState() {
    super.initState();
    _delegate.addListener(_handleSelectionGeometryChanged);
  }

  // Selected content is rebuilt from every selected child, which is too
  // expensive to do per geometry change during a drag; notifications are
  // coalesced to one per frame.
  void _handleSelectionGeometryChanged() {
    if (component.onSelectionChanged == null) return;
    if (_notificationScheduled) return;
    _notificationScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _notificationScheduled = false;
      if (!mounted) return;
      final onSelectionChanged = component.onSelectionChanged;
      if (onSelectionChanged == null) return;
      final text = _delegate.getSelectedContent()?.plainText ?? '';
      if (text == _lastNotifiedText) return;
      _lastNotifiedText = text;
      onSelectionChanged(text);
    });
  }

  @override
  void dispose() {
    _delegate.removeListener(_handleSelectionGeometryChanged);
    _delegate.dispose();
    super.dispose();
  }

  @override
  Component build(BuildContext context) {
    final theme = TuiTheme.of(context);
    return SelectionRegistrarScope(
      registrar: _delegate,
      child: SelectionStyle(
        selection: component.selection ?? theme.selection,
        onSelection: component.onSelection ?? theme.onSelection,
        child: _SelectionAreaRenderComponent(
          delegate: _delegate,
          onSelectionCompleted: component.onSelectionCompleted,
          child: component.child,
        ),
      ),
    );
  }
}

class _SelectionAreaRenderComponent extends SingleChildRenderObjectComponent {
  const _SelectionAreaRenderComponent({
    required this.delegate,
    required this.onSelectionCompleted,
    required super.child,
  });

  final StaticSelectionContainerDelegate delegate;
  final void Function(String)? onSelectionCompleted;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderSelectionArea(
      delegate: delegate,
      onSelectionCompleted: onSelectionCompleted,
    );
  }

  @override
  void updateRenderObject(
      BuildContext context, covariant RenderSelectionArea renderObject) {
    renderObject
      ..delegate = delegate
      ..onSelectionCompleted = onSelectionCompleted;
  }
}

/// Captures pointer gestures for a [SelectionArea] and translates them into
/// [SelectionEvent]s on the delegate.
class RenderSelectionArea extends RenderMouseRegion {
  RenderSelectionArea({
    required StaticSelectionContainerDelegate delegate,
    this.onSelectionCompleted,
  }) : _delegate = delegate {
    _delegate.container = this;
  }

  static const _doubleClickWindow = Duration(milliseconds: 400);

  StaticSelectionContainerDelegate _delegate;
  StaticSelectionContainerDelegate get delegate => _delegate;
  set delegate(StaticSelectionContainerDelegate value) {
    if (identical(_delegate, value)) return;
    if (identical(_delegate.container, this)) _delegate.container = null;
    _delegate = value;
    _delegate.container = this;
  }

  void Function(String)? onSelectionCompleted;

  bool _isLeftButtonPressed = false;
  bool _isDragging = false;
  Offset _lastPointerPosition = Offset.zero;
  DateTime? _lastPressTime;
  Offset? _lastPressPosition;
  bool _postFrameEdgeUpdateScheduled = false;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _updateSelectionAnnotation();
  }

  @override
  void detach() {
    _selectionAnnotation?.validForMouseTracker = false;
    super.detach();
  }

  @override
  void dispose() {
    _selectionAnnotation?.validForMouseTracker = false;
    if (_isDragging) _mouseTracker?.releaseCapture();
    if (identical(_delegate.container, this)) _delegate.container = null;
    super.dispose();
  }

  /// The binding's mouse tracker, used for pointer capture during drags.
  MouseTracker? get _mouseTracker {
    final binding = NoctermBinding.instance;
    return binding is MouseRouter ? binding.mouseTracker : null;
  }

  MouseTrackerAnnotation? _selectionAnnotation;

  @override
  MouseTrackerAnnotation? get annotation =>
      _selectionAnnotation ?? super.annotation;

  void _updateSelectionAnnotation() {
    _selectionAnnotation = MouseTrackerAnnotation(
      onEnter: (event) {
        if (event.button != MouseButton.left) return;
        final leftDown = event.pressed || event.isPrimaryButtonDown;
        if (leftDown && !_isLeftButtonPressed) {
          _isLeftButtonPressed = true;
          _handlePointerDown(event);
        } else if (!leftDown) {
          _isLeftButtonPressed = false;
        }
      },
      // While a drag is active the tracker's pointer capture routes all
      // events here as hovers, so exit is only seen outside a drag.
      onExit: (event) {
        _isLeftButtonPressed = false;
      },
      onHover: (event) {
        if (event.button == MouseButton.wheelUp ||
            event.button == MouseButton.wheelDown) {
          if (_isDragging || event.isPrimaryButtonDown) {
            // Content shifts under the unmoving pointer; re-resolve the end
            // edge after the scroll has been laid out.
            _scheduleDragEdgeUpdate();
          }
          return;
        }

        if (event.button != MouseButton.left) return;
        final leftDown = event.pressed || event.isPrimaryButtonDown;
        if (leftDown && !_isLeftButtonPressed) {
          _isLeftButtonPressed = true;
          _handlePointerDown(event);
        } else if (!leftDown && _isLeftButtonPressed) {
          _isLeftButtonPressed = false;
          _handlePointerUp(event);
        } else if (leftDown && _isLeftButtonPressed) {
          _handlePointerMove(event);
        }
      },
      renderObject: this,
    );
  }

  void _handlePointerDown(MouseEvent event) {
    final position = Offset(event.x.toDouble(), event.y.toDouble());
    final now = DateTime.now();
    final isDoubleClick = _lastPressTime != null &&
        now.difference(_lastPressTime!) < _doubleClickWindow &&
        _lastPressPosition == position;
    _lastPressTime = now;
    _lastPressPosition = position;
    _lastPointerPosition = position;
    _isDragging = true;
    final annotation = _selectionAnnotation;
    if (annotation != null) _mouseTracker?.capture(annotation);

    if (isDoubleClick) {
      _delegate.dispatchSelectionEvent(
          SelectWordSelectionEvent(globalPosition: position));
      return;
    }
    _delegate.dispatchSelectionEvent(const ClearSelectionEvent());
    _delegate.dispatchSelectionEvent(
        SelectionEdgeUpdateEvent.forStart(globalPosition: position));
    _dispatchEndEdgeUpdate(position);
  }

  void _handlePointerMove(MouseEvent event) {
    if (!_isDragging) return;
    final position = Offset(event.x.toDouble(), event.y.toDouble());
    _lastPointerPosition = position;
    _dispatchEndEdgeUpdate(position);
  }

  void _handlePointerUp(MouseEvent event) {
    if (!_isDragging) return;
    _mouseTracker?.releaseCapture();
    final position = Offset(event.x.toDouble(), event.y.toDouble());
    if (position != _lastPointerPosition) {
      _lastPointerPosition = position;
      _dispatchEndEdgeUpdate(position);
    }
    _isDragging = false;
    onSelectionCompleted?.call(_delegate.getSelectedContent()?.plainText ?? '');
  }

  // A pending result means a scrollable is auto-scrolling toward the
  // pointer; keep re-dispatching the edge each frame until it settles.
  void _dispatchEndEdgeUpdate(Offset position) {
    final result = _delegate.dispatchSelectionEvent(
        SelectionEdgeUpdateEvent.forEnd(globalPosition: position));
    if (result == SelectionResult.pending) _scheduleDragEdgeUpdate();
  }

  void _scheduleDragEdgeUpdate() {
    if (_postFrameEdgeUpdateScheduled) return;
    _postFrameEdgeUpdateScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _postFrameEdgeUpdateScheduled = false;
      if (!_isDragging) return;
      _dispatchEndEdgeUpdate(_lastPointerPosition);
    });
  }

  @override
  bool hitTestSelf(Offset position) => true;
}
