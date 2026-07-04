import '../framework/framework.dart';
import '../framework/terminal_canvas.dart';
import '../size.dart';
import 'selection.dart';
import 'selection_container_delegate.dart';

/// Provides a [SelectionRegistrar] to descendant selectable components.
///
/// Selectable render objects find the registrar via [maybeOf] during
/// component wiring and register themselves through [SelectionRegistrant].
class SelectionRegistrarScope extends InheritedComponent {
  const SelectionRegistrarScope({
    super.key,
    required this.registrar,
    required super.child,
  });

  final SelectionRegistrar registrar;

  /// The [SelectionRegistrar] of the closest enclosing scope, if any.
  static SelectionRegistrar? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedComponentOfExactType<SelectionRegistrarScope>()
        ?.registrar;
  }

  @override
  bool updateShouldNotify(SelectionRegistrarScope oldComponent) {
    return registrar != oldComponent.registrar;
  }
}

/// Handles the selection events for the [Selectable]s in a subtree with a
/// custom [SelectionContainerDelegate].
///
/// Descendant selectables register with [delegate] instead of the enclosing
/// registrar; the delegate itself registers with the enclosing registrar (or
/// [registrar], when given) as a single selectable while it has content.
/// This is what allows selection to nest — a scrollable's delegate presents
/// all of its children as one selectable to the [SelectionArea] above it.
///
/// The caller owns the [delegate]'s lifecycle and must dispose it.
class SelectionContainer extends StatelessComponent {
  const SelectionContainer({
    super.key,
    this.registrar,
    required this.delegate,
    required this.child,
  });

  /// The registrar this container reports to, overriding the enclosing
  /// [SelectionRegistrarScope].
  final SelectionRegistrar? registrar;

  /// Receives the selection events for the subtree and presents the combined
  /// result to the parent registrar.
  final SelectionContainerDelegate delegate;

  final Component child;

  @override
  Component build(BuildContext context) {
    return SelectionRegistrarScope(
      registrar: delegate,
      child: _SelectionContainerRenderComponent(
        delegate: delegate,
        registrar: registrar ?? SelectionRegistrarScope.maybeOf(context),
        child: child,
      ),
    );
  }
}

class _SelectionContainerRenderComponent
    extends SingleChildRenderObjectComponent {
  const _SelectionContainerRenderComponent({
    required this.delegate,
    required this.registrar,
    required super.child,
  });

  final SelectionContainerDelegate delegate;
  final SelectionRegistrar? registrar;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderSelectionContainer(delegate: delegate, registrar: registrar);
  }

  @override
  void updateRenderObject(
      BuildContext context, covariant RenderSelectionContainer renderObject) {
    renderObject
      ..delegate = delegate
      ..registrar = registrar;
  }
}

/// Anchors a [SelectionContainerDelegate] in the render tree.
///
/// Serves as the delegate's coordinate frame ([SelectionContainerDelegate
/// .container]) and registers the delegate with the parent [registrar] while
/// the delegate has content, mirroring [SelectionRegistrant].
class RenderSelectionContainer extends RenderObject
    with RenderObjectWithChildMixin<RenderObject> {
  RenderSelectionContainer({
    required SelectionContainerDelegate delegate,
    SelectionRegistrar? registrar,
  })  : _delegate = delegate,
        _registrar = registrar {
    _delegate.container = this;
    _delegate.addListener(_updateRegistration);
    _updateRegistration();
  }

  SelectionContainerDelegate _delegate;
  SelectionContainerDelegate get delegate => _delegate;
  set delegate(SelectionContainerDelegate value) {
    if (identical(_delegate, value)) return;
    _unregister();
    _delegate.removeListener(_updateRegistration);
    if (identical(_delegate.container, this)) _delegate.container = null;
    _delegate = value;
    _delegate.container = this;
    _delegate.addListener(_updateRegistration);
    _updateRegistration();
  }

  SelectionRegistrar? _registrar;
  SelectionRegistrar? get registrar => _registrar;
  set registrar(SelectionRegistrar? value) {
    if (identical(_registrar, value)) return;
    _unregister();
    _registrar = value;
    _updateRegistration();
  }

  bool _registered = false;

  void _updateRegistration() {
    if (_registered && !_delegate.value.hasContent) {
      _registrar!.remove(_delegate);
      _registered = false;
    } else if (!_registered &&
        _registrar != null &&
        _delegate.value.hasContent) {
      _registrar!.add(_delegate);
      _registered = true;
    }
  }

  void _unregister() {
    if (_registered) {
      _registrar!.remove(_delegate);
      _registered = false;
    }
  }

  @override
  void dispose() {
    _unregister();
    _delegate.removeListener(_updateRegistration);
    if (identical(_delegate.container, this)) _delegate.container = null;
    super.dispose();
  }

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! BoxParentData) {
      child.parentData = BoxParentData();
    }
  }

  @override
  void performLayout() {
    if (child != null) {
      child!.layout(constraints, parentUsesSize: true);
      size = child!.size;
    } else {
      size = constraints.constrain(Size.zero);
    }
  }

  @override
  void paint(TerminalCanvas canvas, Offset offset) {
    super.paint(canvas, offset);
    if (child != null) {
      final childParentData = child!.parentData as BoxParentData;
      child!.paint(canvas, offset + childParentData.offset);
    }
  }

  @override
  bool hitTestChildren(HitTestResult result, {required Offset position}) {
    if (child == null) return false;
    final childParentData = child!.parentData as BoxParentData;
    return child!.hitTest(result, position: position - childParentData.offset);
  }
}
