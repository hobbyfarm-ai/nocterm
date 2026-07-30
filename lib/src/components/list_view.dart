import 'dart:math' as math;

import 'package:nocterm/nocterm.dart';
import 'package:nocterm/src/framework/terminal_canvas.dart';

import '../rendering/scrollable_render_object.dart';

/// Signature for a function that creates a widget for a given index.
typedef IndexedWidgetBuilder = Component? Function(
    BuildContext context, int index);

/// Signature for a function that provides the item count.
typedef ItemCountGetter = int Function();

/// A scrollable list of widgets arranged linearly.
///
/// ListView is the most commonly used scrolling widget. It displays its
/// children one after another in the scroll direction.
///
/// Set [keyboardScrollable] to true to enable keyboard navigation with
/// arrow keys, Page Up/Down, and Home/End.
class ListView extends StatefulComponent {
  /// Creates a scrollable, linear array of widgets from an explicit [List].
  ListView({
    super.key,
    this.scrollDirection = Axis.vertical,
    this.reverse = false,
    this.controller,
    this.padding,
    this.itemExtent,
    this.lazy = false,
    this.keyboardScrollable = false,
    this.cacheExtent = 5.0,
    List<Component> children = const [],
  })  : itemCount = children.length,
        itemBuilder = ((context, index) => children[index]),
        separatorBuilder = null;

  /// Creates a scrollable, linear array of widgets that are created on demand.
  ///
  /// This constructor is appropriate for list views with a large (or infinite)
  /// number of children because the builder is called only for those children
  /// that are actually visible.
  const ListView.builder({
    super.key,
    this.scrollDirection = Axis.vertical,
    this.reverse = false,
    this.controller,
    this.padding,
    this.itemExtent,
    this.lazy = false,
    this.keyboardScrollable = false,
    this.cacheExtent = 5.0,
    required this.itemBuilder,
    this.itemCount,
  }) : separatorBuilder = null;

  /// Creates a scrollable, linear array of widgets with a separator between each item.
  const ListView.separated({
    super.key,
    this.scrollDirection = Axis.vertical,
    this.reverse = false,
    this.controller,
    this.padding,
    this.lazy = false,
    this.keyboardScrollable = false,
    this.cacheExtent = 5.0,
    required this.itemBuilder,
    required this.separatorBuilder,
    this.itemCount,
  }) : itemExtent = null;

  /// The axis along which the scroll view scrolls.
  final Axis scrollDirection;

  /// Whether the scroll view scrolls in the reading direction.
  ///
  /// For example, if [scrollDirection] is [Axis.horizontal], then the scroll
  /// view scrolls from left to right when [reverse] is false and from right to
  /// left when [reverse] is true.
  ///
  /// Similarly, if [scrollDirection] is [Axis.vertical], then the scroll view
  /// scrolls from top to bottom when [reverse] is false and from bottom to top
  /// when [reverse] is true.
  ///
  /// Defaults to false.
  final bool reverse;

  /// An object that can be used to control the position to which this scroll
  /// view is scrolled.
  final ScrollController? controller;

  /// The amount of space by which to inset the children.
  final EdgeInsets? padding;

  /// If non-null, forces the children to have the given extent in the scroll
  /// direction.
  final double? itemExtent;

  /// Whether to use lazy building of children.
  ///
  /// When false (the default), all children are built during layout to determine
  /// the exact scroll extent, but only visible children are painted.
  /// This provides accurate scroll metrics at the cost of building all children.
  ///
  /// When true, only visible children are built, which is more efficient for
  /// large lists but may result in estimated scroll extents.
  final bool lazy;

  /// Whether to enable keyboard scrolling with arrow keys, Page Up/Down, etc.
  ///
  /// When true, the scroll view will be wrapped in a [Focusable] that handles:
  /// - Arrow Up/Down (or Left/Right for horizontal): scroll by 1 line
  /// - Page Up/Down: scroll by viewport height
  /// - Home/End: scroll to start/end
  final bool keyboardScrollable;

  /// The number of pixels to build before and after the visible area.
  ///
  /// Items within this distance of the visible region will be pre-built,
  /// which makes scrolling smoother by having content ready before it
  /// becomes visible.
  ///
  /// Defaults to 5.0 (appropriate for TUI where 1 unit = 1 row). Higher values mean smoother
  /// scrolling but more memory usage.
  final double cacheExtent;

  /// Called to build children for the list.
  final IndexedWidgetBuilder itemBuilder;

  /// Called to build separators between items (for ListView.separated).
  final IndexedWidgetBuilder? separatorBuilder;

  /// The total number of items. If null, the list is infinite.
  final int? itemCount;

  @override
  State<ListView> createState() => _ListViewState();
}

class _ListViewState extends State<ListView> {
  ScrollController? _controller;
  ScrollableSelectionContainerDelegate? _selectionDelegate;

  ScrollController get _effectiveController =>
      component.controller ?? _controller!;

  @override
  void initState() {
    super.initState();
    if (component.controller == null) {
      _controller = ScrollController();
    }
  }

  @override
  void didUpdateComponent(ListView oldWidget) {
    super.didUpdateComponent(oldWidget);
    if (component.controller != oldWidget.controller) {
      if (oldWidget.controller == null) {
        _controller?.dispose();
        _controller = null;
      }
      if (component.controller == null) {
        _controller = ScrollController();
      }
    }
  }

  @override
  void dispose() {
    _selectionDelegate?.dispose();
    _controller?.dispose();
    super.dispose();
  }

  bool _handleKeyEvent(KeyboardEvent event) {
    final controller = _effectiveController;
    final isVertical = component.scrollDirection == Axis.vertical;

    // Arrow keys for single line scroll
    if (isVertical) {
      if (event.logicalKey == LogicalKey.arrowUp) {
        controller.scrollUp(1.0);
        return true;
      } else if (event.logicalKey == LogicalKey.arrowDown) {
        controller.scrollDown(1.0);
        return true;
      }
    } else {
      if (event.logicalKey == LogicalKey.arrowLeft) {
        controller.scrollUp(1.0);
        return true;
      } else if (event.logicalKey == LogicalKey.arrowRight) {
        controller.scrollDown(1.0);
        return true;
      }
    }

    // Page Up/Down for viewport-sized scroll
    if (event.logicalKey == LogicalKey.pageUp) {
      controller.scrollUp(controller.viewportDimension);
      return true;
    } else if (event.logicalKey == LogicalKey.pageDown) {
      controller.scrollDown(controller.viewportDimension);
      return true;
    }

    // Home/End for scroll to start/end
    if (event.logicalKey == LogicalKey.home) {
      controller.jumpTo(0);
      return true;
    } else if (event.logicalKey == LogicalKey.end) {
      controller.jumpTo(controller.maxScrollExtent);
      return true;
    }

    return false;
  }

  @override
  Component build(BuildContext context) {
    Component viewport = _ListViewport(
      scrollDirection: component.scrollDirection,
      reverse: component.reverse,
      controller: _effectiveController,
      padding: component.padding,
      itemExtent: component.itemExtent,
      lazy: component.lazy,
      cacheExtent: component.cacheExtent,
      itemBuilder: component.itemBuilder,
      separatorBuilder: component.separatorBuilder,
      itemCount: component.itemCount,
    );

    // Scrolled content needs its own scroll-aware selection delegate so an
    // in-progress selection stays pinned to the content while it moves.
    final registrar = SelectionRegistrarScope.maybeOf(context);
    if (registrar != null) {
      final delegate = _selectionDelegate ??=
          ScrollableSelectionContainerDelegate(
              controller: _effectiveController);
      delegate.controller = _effectiveController;
      viewport = SelectionContainer(
        registrar: registrar,
        delegate: delegate,
        child: viewport,
      );
    }

    // Wrap with Focusable for keyboard scrolling if enabled
    if (component.keyboardScrollable) {
      viewport = Focusable(
        focused: true,
        onKeyEvent: _handleKeyEvent,
        child: viewport,
      );
    }

    return viewport;
  }
}

/// Internal widget that handles the viewport and rendering for ListView.
class _ListViewport extends RenderObjectComponent {
  const _ListViewport({
    required this.scrollDirection,
    this.reverse = false,
    required this.controller,
    this.padding,
    this.itemExtent,
    this.lazy = false,
    this.cacheExtent = 5.0,
    required this.itemBuilder,
    this.separatorBuilder,
    this.itemCount,
  });

  final Axis scrollDirection;
  final bool reverse;
  final ScrollController controller;
  final EdgeInsets? padding;
  final double? itemExtent;
  final bool lazy;
  final double cacheExtent;
  final IndexedWidgetBuilder itemBuilder;
  final IndexedWidgetBuilder? separatorBuilder;
  final int? itemCount;

  @override
  Element createElement() => _ListViewportElement(this);

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderListViewport(
      scrollDirection: scrollDirection,
      reverse: reverse,
      controller: controller,
      padding: padding,
      itemExtent: itemExtent,
      lazy: lazy,
      cacheExtent: cacheExtent,
      hasSeparators: separatorBuilder != null,
    );
  }

  @override
  void updateRenderObject(
      BuildContext context, RenderListViewport renderObject) {
    renderObject
      ..scrollDirection = scrollDirection
      ..reverse = reverse
      ..controller = controller
      ..padding = padding
      ..itemExtent = itemExtent
      ..lazy = lazy
      ..cacheExtent = cacheExtent
      ..hasSeparators = separatorBuilder != null;
  }
}

/// Element for ListView that manages building children on demand.
class _ListViewportElement extends RenderObjectElement {
  _ListViewportElement(_ListViewport super.component);

  @override
  _ListViewport get component => super.component as _ListViewport;

  @override
  RenderListViewport get renderObject =>
      super.renderObject as RenderListViewport;

  /// Currently built children indexed by their item index.
  final Map<int, Element> _children = {};

  /// Tracks whether children need to be updated (parent state changed).
  /// When true, buildChild will call itemBuilder and update existing elements.
  /// This is reset after layout completes.
  bool _needsChildUpdate = false;

  /// Tracks which children have been updated during the current layout pass.
  /// This prevents updating the same child multiple times per layout.
  final Set<int> _updatedThisLayout = {};

  @override
  void mount(Element? parent, Object? newSlot) {
    super.mount(parent, newSlot);
    renderObject._element = this;
  }

  @override
  void unmount() {
    renderObject._element = null;
    super.unmount();
  }

  @override
  void update(Component newComponent) {
    super.update(newComponent);

    // Tear down cached children whose item no longer exists in the list, so
    // their render objects are disposed rather than leaked. Items are keyed
    // by index, separators by -index-1; a separator follows every item except
    // the last, so a separator index >= itemCount-1 is stale.
    final newItemCount = (newComponent as _ListViewport).itemCount;
    if (newItemCount != null) {
      final removedKeys = _children.keys.where((key) {
        if (key >= 0) return key >= newItemCount;
        return (-key - 1) >= newItemCount - 1;
      }).toList();
      for (final key in removedKeys) {
        _teardownChild(_children[key]!);
        _children.remove(key);
      }
    }

    // Mark that children need to be updated with new props
    // This is necessary when parent state changes (e.g., selection index)
    _needsChildUpdate = true;
    _updatedThisLayout.clear();

    // update() only runs when the viewport component actually changed
    // (identical components short-circuit in updateChild). Children are
    // built during layout, so the changed component can only take effect
    // if a layout pass happens. Builder identity is no proxy for content -
    // a stable (hoisted) itemBuilder can read state that changed this
    // build pass - so there is no narrower safe gate than always marking.
    // This cannot loop: marking layout dirty never dirties an element, so
    // a frame with no dirty elements goes idle.
    renderObject.markNeedsLayout();
  }

  /// Called by RenderListViewport after layout completes to reset update flags.
  void layoutComplete() {
    _needsChildUpdate = false;
    _updatedThisLayout.clear();
  }

  @override
  void performRebuild() {
    // Render object elements don't rebuild like buildable elements
    // _dirty is handled by the base class
  }

  @override
  void insertRenderObjectChild(RenderObject child, dynamic slot) {
    // ListView manages its own children through buildChild
    // This is not used in our implementation
  }

  @override
  void moveRenderObjectChild(
      RenderObject child, dynamic oldSlot, dynamic newSlot) {
    // ListView doesn't move render object children
  }

  @override
  void removeRenderObjectChild(RenderObject child, dynamic slot) {
    // ListView manages its own children through buildChild
    // This is not used in our implementation
  }

  /// Deactivates and unmounts a child subtree, disposing its render objects.
  ///
  /// Mirrors the build owner's inactive-element finalization; children are
  /// torn down here synchronously (mid-layout) rather than through
  /// [Element.deactivateChild] because the frame's finalize pass has already
  /// run by the time layout culls them. Skipping disposal leaks the render
  /// objects — they stay registered with listeners such as selection
  /// registrars and keep receiving events at stale positions.
  void _teardownChild(Element child) {
    if (!child.mounted) return;
    _deactivateSubtree(child);
    _unmountSubtree(child);
  }

  static void _deactivateSubtree(Element element) {
    element.deactivate();
    element.visitChildren(_deactivateSubtree);
  }

  static void _unmountSubtree(Element element) {
    element.visitChildren(_unmountSubtree);
    if (element is RenderObjectElement) {
      element.renderObject.dispose();
    }
    element.unmount();
  }

  /// Builds or updates a child at the given index.
  Element? buildChild(int index) {
    // Check if index is valid
    if (component.itemCount != null && index >= component.itemCount!) {
      return null;
    }

    final existingChild = _children[index];

    // If we have a cached element and don't need to update, return it directly
    // This avoids redundant itemBuilder calls during the same layout pass
    if (existingChild != null) {
      if (!_needsChildUpdate || _updatedThisLayout.contains(index)) {
        // Either no update needed, or already updated this layout pass
        return existingChild;
      }

      // Need to update this child - call itemBuilder and update element
      _updatedThisLayout.add(index);
      final newChild = component.itemBuilder(this, index);
      if (newChild == null) {
        // Item no longer exists, remove cached element
        _teardownChild(existingChild);
        _children.remove(index);
        return null;
      }

      // Update existing element if possible
      if (Component.canUpdate(existingChild.component, newChild)) {
        if (!identical(existingChild.component, newChild)) {
          existingChild.update(newChild);
        }
        return existingChild;
      } else {
        // Can't update, replace element
        _teardownChild(existingChild);
        // ignore: invalid_use_of_protected_member
        final element = newChild.createElement();
        _children[index] = element;
        element.mount(this, index);
        return element;
      }
    }

    // No cached element - create new one
    final child = component.itemBuilder(this, index);
    if (child == null) return null;

    // ignore: invalid_use_of_protected_member
    final newElement = child.createElement();
    _children[index] = newElement;
    newElement.mount(this, index);
    if (_needsChildUpdate) {
      _updatedThisLayout.add(index);
    }
    return newElement;
  }

  /// Builds a separator at the given index.
  Element? buildSeparator(int index) {
    if (component.separatorBuilder == null) return null;

    final separator = component.separatorBuilder!(this, index);
    if (separator == null) return null;

    final separatorIndex = -index - 1; // Use negative indices for separators
    final oldSeparator = _children[separatorIndex];

    if (oldSeparator != null &&
        Component.canUpdate(oldSeparator.component, separator)) {
      // Respect const separators
      if (!identical(oldSeparator.component, separator)) {
        oldSeparator.update(separator);
      }
      return oldSeparator;
    } else {
      if (oldSeparator != null) _teardownChild(oldSeparator);
      // ignore: invalid_use_of_protected_member
      final newSeparator = separator.createElement();
      _children[separatorIndex] = newSeparator;
      newSeparator.mount(this, separatorIndex);
      return newSeparator;
    }
  }

  /// Removes children that are no longer visible.
  void removeInvisibleChildren(
    int firstIndex,
    int lastIndex, {
    bool Function(Element child)? keepAlive,
  }) {
    final keysToRemove = <int>[];
    for (final key in _children.keys) {
      if (key >= 0) {
        // Regular item
        if (key < firstIndex || key > lastIndex) {
          keysToRemove.add(key);
        }
      } else {
        // Separator
        final separatorIndex = -key - 1;
        if (separatorIndex < firstIndex || separatorIndex >= lastIndex) {
          keysToRemove.add(key);
        }
      }
    }

    for (final key in keysToRemove) {
      final child = _children[key];
      if (child != null) {
        if (keepAlive != null && keepAlive(child)) continue;
        _teardownChild(child);
      }
      _children.remove(key);
    }
  }

  @override
  void visitChildren(ElementVisitor visitor) {
    _children.values.forEach(visitor);
  }
}

/// Render object for ListView viewport.
class RenderListViewport extends RenderObject with ScrollableRenderObjectMixin {
  RenderListViewport({
    required Axis scrollDirection,
    bool reverse = false,
    required ScrollController controller,
    EdgeInsets? padding,
    double? itemExtent,
    bool lazy = false,
    double cacheExtent = 250.0,
    bool hasSeparators = false,
  })  : _scrollDirection = scrollDirection,
        _reverse = reverse,
        _controller = controller,
        _padding = padding,
        _itemExtent = itemExtent,
        _lazy = lazy,
        _cacheExtent = cacheExtent,
        _hasSeparators = hasSeparators {
    _controller.addListener(_handleScrollUpdate);
    _controller.attach(this);
  }

  _ListViewportElement? _element;

  Axis _scrollDirection;
  Axis get scrollDirection => _scrollDirection;
  set scrollDirection(Axis value) {
    if (_scrollDirection != value) {
      _scrollDirection = value;
      markNeedsLayout();
    }
  }

  bool _reverse;
  bool get reverse => _reverse;
  set reverse(bool value) {
    if (_reverse != value) {
      _reverse = value;
      markNeedsLayout();
    }
  }

  ScrollController _controller;
  ScrollController get controller => _controller;
  set controller(ScrollController value) {
    if (_controller != value) {
      _controller.removeListener(_handleScrollUpdate);
      _controller.detach(this);
      _controller = value;
      _controller.addListener(_handleScrollUpdate);
      _controller.attach(this);
      markNeedsLayout();
    }
  }

  EdgeInsets? _padding;
  EdgeInsets? get padding => _padding;
  set padding(EdgeInsets? value) {
    if (_padding != value) {
      _padding = value;
      markNeedsLayout();
    }
  }

  double? _itemExtent;
  double? get itemExtent => _itemExtent;
  set itemExtent(double? value) {
    if (_itemExtent != value) {
      _itemExtent = value;
      markNeedsLayout();
    }
  }

  bool _lazy;
  bool get lazy => _lazy;
  set lazy(bool value) {
    if (_lazy != value) {
      _lazy = value;
      markNeedsLayout();
    }
  }

  double _cacheExtent;
  double get cacheExtent => _cacheExtent;
  set cacheExtent(double value) {
    if (_cacheExtent != value) {
      _cacheExtent = value;
      markNeedsLayout();
    }
  }

  bool _hasSeparators;
  bool get hasSeparators => _hasSeparators;
  set hasSeparators(bool value) {
    if (_hasSeparators != value) {
      _hasSeparators = value;
      markNeedsLayout();
    }
  }

  void _handleScrollUpdate() {
    markNeedsLayout();
  }

  /// Cross-axis extent of the previous layout pass, used to detect reflows.
  ///
  /// When the cross axis changes, variable-extent children re-wrap and every
  /// layout offset after the first changed child moves. Without compensation
  /// the scroll offset — an absolute distance, not a content position — then
  /// points at different content, and the viewport appears to slide.
  double? _lastCrossAxisExtent;

  /// The anchor of the reflow gesture in progress. A drag resizes one column
  /// at a time, and each step's re-pack can pull earlier words up onto the
  /// top row — re-capturing per step would then re-anchor to that earlier
  /// content and creep backward over a long gesture. As long as the offset
  /// is exactly where the previous correction left it, the gesture is still
  /// going and the original anchored character keeps its grip.
  _ReflowAnchor? _gestureAnchor;

  /// Where the last reflow correction settled, used to recognise the next
  /// step of the same gesture. Any other offset means the user scrolled and
  /// the held anchor no longer describes what they are looking at.
  double? _lastAnchoredOffset;

  /// Offsets within this distance of [_lastAnchoredOffset] count as the
  /// continuation of the resize gesture in progress; anything farther means
  /// the user scrolled in between. One half cell — corrections land on whole
  /// cells, scrolls move at least one.
  static const double _gestureContinuityTolerance = 0.5;

  /// Set when [_anchorDepth] discovers the held anchor's leaf no longer
  /// belongs to a live item, so the gesture anchor can be dropped after the
  /// layout loop instead of retaining an unmounted subtree.
  bool _anchorLeafDied = false;

  /// Upper bound on layout passes per frame, mirroring Flutter's viewport
  /// correction cap. Eager layout converges on the second pass; lazy layout
  /// is seeded at the anchor and converges immediately unless the anchor
  /// item shrank; the controller's end pin converges once the extent
  /// estimate settles. Hitting the cap means viewport and controller never
  /// reached consensus — a bug — which throws in debug builds; in release
  /// the safe response in a live terminal is to stop correcting.
  static const int _maxAnchorLayoutCycles = 10;

  @override
  void setupParentData(covariant RenderObject child) {
    if (child.parentData is! ListViewParentData) {
      child.parentData = ListViewParentData();
    }
  }

  @override
  bool handleMouseWheel(MouseEvent event) {
    // Only handle vertical scroll for vertical ScrollViews
    // and horizontal scroll for horizontal ScrollViews
    if (_scrollDirection == Axis.vertical) {
      if (event.button == MouseButton.wheelUp) {
        // In reverse mode, invert the scroll direction
        if (_reverse) {
          _controller.scrollDown(3.0); // Wheel up scrolls down in reverse mode
        } else {
          _controller.scrollUp(3.0); // Normal behavior
        }
        return true;
      } else if (event.button == MouseButton.wheelDown) {
        // In reverse mode, invert the scroll direction
        if (_reverse) {
          _controller.scrollUp(3.0); // Wheel down scrolls up in reverse mode
        } else {
          _controller.scrollDown(3.0); // Normal behavior
        }
        return true;
      }
    } else {
      // For horizontal scroll, we might want to handle horizontal wheel events
      // but for now just handle vertical wheel as horizontal scroll
      if (event.button == MouseButton.wheelUp) {
        if (_reverse) {
          _controller.scrollDown(3.0);
        } else {
          _controller.scrollUp(3.0);
        }
        return true;
      } else if (event.button == MouseButton.wheelDown) {
        if (_reverse) {
          _controller.scrollUp(3.0);
        } else {
          _controller.scrollDown(3.0);
        }
        return true;
      }
    }

    return false;
  }

  @override
  void dispose() {
    _controller.removeListener(_handleScrollUpdate);
    _controller.detach(this);
    super.dispose();
  }

  /// Information about visible children after layout.
  final List<_ChildLayoutInfo> _visibleChildren = [];

  /// All built children, including cache-extent items outside the viewport.
  final List<_ChildLayoutInfo> _allChildren = [];

  /// Render objects already in [_allChildren], used to avoid duplicates.
  final Set<RenderObject> _allChildrenSet = {};

  /// First and last item indices that were built (includes cache area).
  /// Used to clean up children outside the cached range.
  int _firstBuiltIndex = 0;
  int _lastBuiltIndex = 0;

  /// Tracks the average item extent for estimating total scroll extent
  double? _averageItemExtent;

  /// Adds a child to [_allChildren], skipping duplicates.
  void _addToAllChildren(RenderObject renderObject) {
    if (_allChildrenSet.add(renderObject)) {
      _allChildren.add(_ChildLayoutInfo(renderObject: renderObject));
    }
  }

  RenderObject? _buildAndLayoutChild({
    required int index,
    required BoxConstraints childConstraints,
    required double layoutOffset,
    double? extentOverride,
  }) {
    final child = _element!.buildChild(index);
    if (child == null) return null;
    final renderObject = _getRenderObject(child);
    if (renderObject == null) return null;

    renderObject.layout(childConstraints, parentUsesSize: true);
    final childExtent = extentOverride ??
        (scrollDirection == Axis.vertical
            ? renderObject.size.height
            : renderObject.size.width);

    final parentData = renderObject.parentData as ListViewParentData;
    parentData.layoutOffset = layoutOffset;
    parentData.extent = childExtent;
    parentData.index = index;

    return renderObject;
  }

  RenderObject? _buildAndLayoutSeparator({
    required int index,
    required BoxConstraints childConstraints,
    required double layoutOffset,
  }) {
    final separator = _element!.buildSeparator(index);
    if (separator == null) return null;
    final separatorRenderObject = _getRenderObject(separator);
    if (separatorRenderObject == null) return null;

    separatorRenderObject.layout(childConstraints, parentUsesSize: true);
    final separatorExtent = scrollDirection == Axis.vertical
        ? separatorRenderObject.size.height
        : separatorRenderObject.size.width;

    final sepParentData =
        separatorRenderObject.parentData as ListViewParentData;
    sepParentData.layoutOffset = layoutOffset;
    sepParentData.extent = separatorExtent;
    sepParentData.index = -index - 1;

    return separatorRenderObject;
  }

  /// Finds the best starting index for layout given a scroll offset.
  /// Uses parent data on children for O(n) lookup through existing children.
  ///
  /// Searches the element's retained children — not the per-layout child
  /// lists, which have already been cleared when this runs. Their parent
  /// data keeps the content layout offsets from the pass that built them,
  /// so a resumed layout can start at the cache window instead of item 0.
  (int index, double position) _findStartingPosition(double scrollOffset) {
    if (itemExtent != null) {
      // Fixed extent - exact calculation
      final index = (scrollOffset / itemExtent!).floor();
      return (index, index * itemExtent!);
    }

    final element = _element;
    if (element == null) return (0, 0.0);

    // Find the child closest to (but not past) the scroll offset
    int bestIndex = 0;
    double bestOffset = 0.0;

    for (final entry in element._children.entries) {
      if (entry.key < 0) continue; // Separators resolve via their items.
      final renderObject = _getRenderObject(entry.value);
      final parentData = renderObject?.parentData;
      if (parentData is! ListViewParentData) continue;
      if (parentData.layoutOffset == null || parentData.index == null) {
        continue;
      }

      final offset = parentData.layoutOffset!;
      final index = parentData.index!;
      if (offset <= scrollOffset && offset >= bestOffset) {
        bestIndex = index;
        bestOffset = offset;
      }
    }

    return (bestIndex, bestOffset);
  }

  /// Records the content at the viewport's anchor edge ahead of a cross-axis
  /// reflow, or null when no anchoring is wanted for this pass.
  ///
  /// The anchor edge is the edge the scroll offset is measured from: the
  /// painted top normally, the painted bottom when [reverse] is set.
  _ReflowAnchor? _captureReflowAnchor(double crossAxisExtent) {
    final previous = _lastCrossAxisExtent;
    _lastCrossAxisExtent = crossAxisExtent;

    final scrollOffset = _controller.offset;
    final anchoredOffset = _lastAnchoredOffset;
    if (anchoredOffset != null &&
        (scrollOffset - anchoredOffset).abs() >= _gestureContinuityTolerance) {
      // The user scrolled since the last correction: the held anchor no
      // longer describes what they see, and holding it would retain a
      // subtree the gesture is done with.
      _gestureAnchor = null;
      _lastAnchoredOffset = null;
    }

    if (previous == null || previous == crossAxisExtent) return null;
    if (scrollOffset <= 0) return null;
    // Within a cell of the very bottom the controller pins the offset to the
    // content's end itself — it detects the reflow from the cross-axis
    // extent handed to updateMetrics — so no content anchor is wanted.
    if (scrollOffset >=
        _controller.maxScrollExtent - ScrollController.endReflowTolerance) {
      return null;
    }

    final held = _gestureAnchor;
    if (held != null) return held;

    final element = _element;
    if (element == null) return null;

    // Of the children whose previous-pass offsets are still on record, take
    // the one starting closest to the viewport top without passing it: the
    // first item any of whose rows are visible. Separators re-anchor via
    // their neighbouring items. Only the previous pass's built set counts:
    // in lazy mode, children kept alive for a selection carry layout offsets
    // from whenever they were last built, which no longer mean anything.
    int? bestIndex;
    var bestOffset = double.negativeInfinity;
    var bestExtent = 0.0;
    Element? bestElement;
    for (final entry in element._children.entries) {
      if (entry.key < 0) continue;
      final renderObject = _getRenderObject(entry.value);
      if (renderObject == null || !_allChildrenSet.contains(renderObject)) {
        continue;
      }
      final parentData = renderObject.parentData;
      if (parentData is! ListViewParentData) continue;
      final layoutOffset = parentData.layoutOffset;
      final index = parentData.index;
      if (layoutOffset == null || index == null) continue;
      if (layoutOffset <= scrollOffset && layoutOffset > bestOffset) {
        bestOffset = layoutOffset;
        bestExtent = parentData.extent ?? 0.0;
        bestIndex = index;
        bestElement = entry.value;
      }
    }
    if (bestIndex == null) return null;

    final delta = scrollOffset - bestOffset;
    // An edge past the item's content sits on a separator; it anchors to the
    // item's end, not to a line inside it, so no leaf is captured. In a
    // reversed viewport the edge row is content-addressed through the paint
    // mirror.
    final targetRow =
        _reverse ? math.max(0.0, _mirroredRow(delta, bestExtent)) : delta;
    final (leaf, char, rowsAfter) = delta >= bestExtent
        ? (null, null, 0.0)
        : _describeDepth(bestElement, targetRow);

    return _ReflowAnchor(
      index: bestIndex,
      position: bestOffset,
      delta: delta,
      extent: bestExtent,
      leaf: leaf,
      char: char,
      rowsAfter: rowsAfter,
    );
  }

  /// Content-addresses [targetRow] within the anchor item: the paragraph
  /// under it and the character starting its visual line, read from the
  /// previous pass's geometry (children have not been relaid yet).
  ///
  /// A target row on a gap below a paragraph — block spacing, a divider —
  /// anchors to the paragraph's *end* (a null character) plus the
  /// width-stable rows in between: any inner line can re-wrap onto a
  /// different row, but the gap always starts where the paragraph stops.
  /// An item with no paragraph above the target yields no leaf and the
  /// anchor falls back to its raw row depth.
  (RenderObject?, int?, double) _describeDepth(
    Element? itemElement,
    double targetRow,
  ) {
    if (itemElement == null || scrollDirection != Axis.vertical) {
      return (null, null, 0.0);
    }
    final itemRenderObject = _getRenderObject(itemElement);
    if (itemRenderObject == null) return (null, null, 0.0);

    ReflowAnchorable? within;
    var withinTop = 0.0;
    ReflowAnchorable? above;
    var aboveTop = 0.0;
    var aboveHeight = 0.0;
    void walk(Element element) {
      if (within != null) return;
      if (element is RenderObjectElement) {
        final renderObject = element.renderObject;
        if (renderObject is ReflowAnchorable) {
          final top = _rowsBetween(itemRenderObject, renderObject);
          if (top != null) {
            final height =
                renderObject.hasSize ? renderObject.size.height : 0.0;
            if (top <= targetRow && targetRow < top + height) {
              within = renderObject;
              withinTop = top;
            } else if (top + height <= targetRow && top >= aboveTop) {
              above = renderObject;
              aboveTop = top;
              aboveHeight = height;
            }
            return; // Paragraphs don't nest paragraphs.
          }
        }
      }
      element.visitChildren(walk);
    }

    walk(itemElement);

    final inside = within;
    if (inside != null) {
      final char = inside.getCharacterIndexAtLocalPosition(
        Offset(0, targetRow - withinTop),
      );
      return (inside as RenderObject, char, 0.0);
    }
    final nearest = above;
    if (nearest != null) {
      return (
        nearest as RenderObject,
        null,
        targetRow - (aboveTop + aboveHeight),
      );
    }
    return (null, null, 0.0);
  }

  /// Rows between [ancestor]'s top and [descendant]'s top, summed from the
  /// parent-data offsets of the chain between them; null when [descendant]
  /// is not in [ancestor]'s subtree.
  double? _rowsBetween(RenderObject ancestor, RenderObject descendant) {
    RenderObject node = descendant;
    var total = 0.0;
    while (!identical(node, ancestor)) {
      final parentData = node.parentData;
      if (parentData is BoxParentData) total += parentData.offset.dy;
      final parent = node.parent;
      if (parent is! RenderObject || identical(node, this)) return null;
      node = parent;
    }
    return total;
  }

  /// Rows painted between an item's own top and the row at layout depth
  /// [row], in a reversed viewport.
  double _mirroredRow(double row, double extent) => extent - 1 - row;

  /// How far the offset must move so the anchored content is back at the
  /// viewport's anchor edge, judged against the pass that just ran. Zero
  /// when unanchored, converged, or the anchored item no longer exists.
  double _reflowCorrection(_ReflowAnchor? anchor) {
    if (anchor == null) return 0.0;
    final info = getItemOffsetAndExtent(anchor.index);
    if (info == null) return 0.0;
    final (itemOffset, itemExtent) = info;
    final target = itemOffset + _anchorDepth(anchor, itemExtent);
    return target - _controller.offset;
  }

  /// Rows into the anchor item where the anchored content now sits, from the
  /// layout that just ran: the anchored paragraph's fresh position within the
  /// item plus the row its anchored character landed on.
  double _anchorDepth(_ReflowAnchor anchor, double itemExtent) {
    if (anchor.delta >= anchor.extent) {
      return itemExtent + (anchor.delta - anchor.extent);
    }

    final leaf = anchor.leaf;
    if (leaf == null) {
      return math.min(anchor.delta, itemExtent);
    }

    // Walk up to the list item boundary accumulating this pass's offsets.
    // The node found must be the very render object the anchor item's element
    // owns right now.
    RenderObject node = leaf;
    var top = 0.0;
    while (true) {
      final parentData = node.parentData;
      if (parentData is ListViewParentData) {
        final itemElement = _element?._children[anchor.index];
        final liveItem =
            itemElement == null ? null : _getRenderObject(itemElement);
        if (liveItem == null || !identical(liveItem, node)) {
          _anchorLeafDied = true;
          return math.min(anchor.delta, itemExtent);
        }
        break;
      }
      if (parentData is BoxParentData) top += parentData.offset.dy;
      final parent = node.parent;
      if (parent is! RenderObject || identical(node, this)) {
        _anchorLeafDied = true;
        return math.min(anchor.delta, itemExtent);
      }
      node = parent;
    }

    // A char anchors a line inside the paragraph; a charless leaf anchors
    // the gap after it, which starts wherever the paragraph now ends.
    final char = anchor.char;
    final row = char != null
        ? top +
            (leaf as ReflowAnchorable).localPositionForCharacterIndex(char).dy
        : top + (leaf.hasSize ? leaf.size.height : 0.0) + anchor.rowsAfter;
    // The row is measured from the item's own top; in a reversed viewport
    // it mirrors back into layout depth against the item's fresh extent.
    final depth = _reverse ? _mirroredRow(row, itemExtent) : row;
    return depth.clamp(0.0, itemExtent);
  }

  @override
  void performLayout() {
    if (_element == null) {
      _visibleChildren.clear();
      _allChildren.clear();
      _allChildrenSet.clear();
      size = constraints.constrain(Size.zero);
      return;
    }

    // Apply padding
    final effectivePadding = padding ?? EdgeInsets.zero;
    final innerConstraints = constraints.deflate(effectivePadding);

    // Our size is constrained by our parent
    size = constraints.constrain(Size(
      constraints.maxWidth,
      constraints.maxHeight,
    ));

    // Calculate viewport dimensions
    final viewportExtent = scrollDirection == Axis.vertical
        ? innerConstraints.maxHeight
        : innerConstraints.maxWidth;
    final crossAxisExtent = scrollDirection == Axis.vertical
        ? innerConstraints.maxWidth
        : innerConstraints.maxHeight;

    // Build visible children
    final component = _element!.component;
    final itemCount = component.itemCount;

    // Child constraints
    final childConstraints = scrollDirection == Axis.vertical
        ? BoxConstraints(
            minWidth: crossAxisExtent,
            maxWidth: crossAxisExtent,
            minHeight: 0,
            maxHeight: itemExtent ?? double.infinity,
          )
        : BoxConstraints(
            minHeight: crossAxisExtent,
            maxHeight: crossAxisExtent,
            minWidth: 0,
            maxWidth: itemExtent ?? double.infinity,
          );

    // A cross-axis reflow is about to move every layout offset. Record which
    // item sits at the viewport top now — from the offsets of the previous
    // pass, still intact in parent data — so the corrected offset can point
    // at the same content afterwards.
    final anchor = _captureReflowAnchor(crossAxisExtent);

    // Layout is an attempt, in Flutter's viewport-correction sense: a pass
    // both re-measures children and reveals how far the anchored content
    // moved, and the controller may reject the resulting metrics by
    // correcting its own offset (an end pin, a clamp).
    final axisDirection =
        axisToAxisDirection(scrollDirection, reverse: _reverse);
    double totalExtent = 0;
    var layoutCycles = 0;
    var settled = false;
    while (true) {
      _visibleChildren.clear();
      _allChildren.clear();
      _allChildrenSet.clear();

      if (_lazy) {
        // Lazy mode: only build visible children
        totalExtent = _performLazyLayout(
          viewportExtent: viewportExtent,
          childConstraints: childConstraints,
          itemCount: itemCount,
          anchorSeed: anchor == null ? null : (anchor.index, anchor.position),
        );
      } else {
        // Non-lazy mode: build all children for accurate extent
        totalExtent = _performEagerLayout(
          viewportExtent: viewportExtent,
          childConstraints: childConstraints,
          itemCount: itemCount,
        );
      }

      layoutCycles += 1;
      if (layoutCycles < _maxAnchorLayoutCycles) {
        var correction = _reflowCorrection(anchor);
        if (correction != 0.0) {
          // An anchor may want an offset the re-wrapped content no longer
          // reaches (a widening reflow that shrank everything)
          final maxOffset = math.max(0.0, totalExtent - viewportExtent);
          correction = (_controller.offset + correction).clamp(0.0, maxOffset) -
              _controller.offset;
        }
        if (correction.abs() >= precisionErrorTolerance) {
          _controller.correctBy(correction);
          continue;
        }
        settled = _controller.updateMetrics(
          minScrollExtent: 0,
          maxScrollExtent: math.max(0.0, totalExtent - viewportExtent),
          viewportDimension: viewportExtent,
          axisDirection: axisDirection,
          crossAxisExtent: crossAxisExtent,
        );
        if (!settled) continue;
      } else {
        // Out of attempts: take this pass's metrics as they are and stop.
        _controller.updateMetrics(
          minScrollExtent: 0,
          maxScrollExtent: math.max(0.0, totalExtent - viewportExtent),
          viewportDimension: viewportExtent,
          axisDirection: axisDirection,
          crossAxisExtent: crossAxisExtent,
        );
      }
      break;
    }
    assert(() {
      if (!settled) {
        throw FlutterError(
          'RenderListViewport exceeded its maximum number of layout cycles.\n'
          'During layout, the viewport retries when the reflow anchor '
          'corrects the scroll offset or the ScrollController rejects the '
          'resulting metrics, but after $_maxAnchorLayoutCycles passes there '
          'was still no consensus on the scroll offset. This usually means '
          'the anchor and the controller apply opposing corrections, or a '
          'ScrollController subclass corrects the offset unconditionally.',
        );
      }
      return true;
    }());

    // Remember where this reflow settled — post-consensus — so the next
    // step of a continuing resize gesture can pick the same anchor back up
    if (anchor != null) {
      if (_anchorLeafDied) {
        _gestureAnchor = null;
        _lastAnchoredOffset = null;
      } else {
        _gestureAnchor = anchor;
        _lastAnchoredOffset = _controller.offset;
      }
    }
    _anchorLeafDied = false;

    // Clean up children outside the cached range in lazy mode, keeping
    // items that hold part of an active selection alive so the selection
    // survives scrolling and can still be copied.
    if (_lazy) {
      _element!.removeInvisibleChildren(
        _firstBuiltIndex,
        _lastBuiltIndex,
        keepAlive: _keepAliveForSelection,
      );
    }

    // Reset the child update flag after layout completes
    _element?.layoutComplete();

    // Keep parent data offsets in sync for selection/hit testing.
    _updateChildOffsets(
      effectivePadding: effectivePadding,
      viewportExtent: viewportExtent,
    );
  }

  void _updateChildOffsets({
    required EdgeInsets effectivePadding,
    required double viewportExtent,
  }) {
    final scrollOffset = _controller.offset;
    for (final child in _allChildren) {
      _applyViewportOffset(
        child.renderObject,
        scrollOffset: scrollOffset,
        effectivePadding: effectivePadding,
        viewportExtent: viewportExtent,
      );
    }

    // Kept-alive children outside the built range are not painted, but
    // their offsets must stay truthful so selection screen-order sorting
    // and edge resolution don't land on the rows they used to occupy.
    final element = _element;
    if (element == null) return;
    final built = {for (final child in _allChildren) child.renderObject};
    for (final childElement in element._children.values) {
      final renderObject = _getRenderObject(childElement);
      if (renderObject == null || built.contains(renderObject)) continue;
      _applyViewportOffset(
        renderObject,
        scrollOffset: scrollOffset,
        effectivePadding: effectivePadding,
        viewportExtent: viewportExtent,
      );
    }
  }

  void _applyViewportOffset(
    RenderObject renderObject, {
    required double scrollOffset,
    required EdgeInsets effectivePadding,
    required double viewportExtent,
  }) {
    final parentData = renderObject.parentData;
    if (parentData is! ListViewParentData) return;
    final layoutOffset = parentData.layoutOffset ?? 0.0;
    final childExtent = parentData.extent ??
        (scrollDirection == Axis.vertical
            ? renderObject.size.height
            : renderObject.size.width);
    double childPosition = layoutOffset - scrollOffset;

    if (_reverse) {
      childPosition = viewportExtent - childPosition - childExtent;
    }

    parentData.offset = scrollDirection == Axis.vertical
        ? Offset(effectivePadding.left, effectivePadding.top + childPosition)
        : Offset(effectivePadding.left + childPosition, effectivePadding.top);
  }

  /// Performs lazy layout - only builds visible children
  double _performLazyLayout({
    required double viewportExtent,
    required BoxConstraints childConstraints,
    required int? itemCount,
    (int index, double position)? anchorSeed,
  }) {
    final scrollOffset = _controller.offset;

    // Include cache area before and after visible region for smoother scrolling
    final cacheStart =
        (scrollOffset - _cacheExtent).clamp(0.0, double.infinity);
    final cacheEnd = scrollOffset + viewportExtent + _cacheExtent;

    // Find first item to build (including cache before visible area). A
    // reflow anchor overrides the search: lazy offsets are dead reckoning,
    // not absolute truth, so rather than hunting for where the anchored item
    // landed, seed the reckoning so it never moves. The pass builds forward
    // from the anchor at its old position, and the stale offsets of other
    // items — meaningless across a reflow — never enter the frame.
    final (startIndex, startPosition) =
        anchorSeed ?? _findStartingPosition(cacheStart);
    int itemIndex = startIndex;
    double currentPosition = startPosition;

    // Track built range for cleanup
    _firstBuiltIndex = startIndex;
    _lastBuiltIndex = startIndex;

    // Track total extent of measured items for average calculation
    double totalMeasuredExtent = 0;
    int measuredCount = 0;

    // Build items until we've covered the cache area
    while (currentPosition < cacheEnd) {
      if (itemCount != null && itemIndex >= itemCount) break;

      // Build item
      final renderObject = _buildAndLayoutChild(
        index: itemIndex,
        childConstraints: childConstraints,
        layoutOffset: currentPosition,
      );
      if (renderObject == null) break;

      // Track item extent for average calculation
      final childExtent =
          (renderObject.parentData as ListViewParentData).extent!;
      totalMeasuredExtent += childExtent;
      measuredCount++;

      // Store child info if visible (not just in cache area)
      if (currentPosition + childExtent > scrollOffset &&
          currentPosition < scrollOffset + viewportExtent) {
        _visibleChildren.add(_ChildLayoutInfo(
          renderObject: renderObject,
        ));
      }

      // Add to _allChildren for future lookups
      _addToAllChildren(renderObject);

      currentPosition += childExtent;

      // Add separator if needed
      if (hasSeparators && (itemCount == null || itemIndex < itemCount - 1)) {
        final separatorRenderObject = _buildAndLayoutSeparator(
          index: itemIndex,
          childConstraints: childConstraints,
          layoutOffset: currentPosition,
        );
        if (separatorRenderObject != null) {
          final separatorExtent =
              (separatorRenderObject.parentData as ListViewParentData).extent!;

          // Store separator if visible
          if (currentPosition + separatorExtent > scrollOffset &&
              currentPosition < scrollOffset + viewportExtent) {
            _visibleChildren.add(_ChildLayoutInfo(
              renderObject: separatorRenderObject,
            ));
          }

          _addToAllChildren(separatorRenderObject);

          currentPosition += separatorExtent;
        }
      }

      // Update last built index
      _lastBuiltIndex = itemIndex;
      itemIndex++;
    }

    // Update average item extent if we measured any items
    if (measuredCount > 0) {
      final newAverage = totalMeasuredExtent / measuredCount;
      if (_averageItemExtent == null) {
        _averageItemExtent = newAverage;
      } else {
        // Smooth the average to avoid jumps
        _averageItemExtent = (_averageItemExtent! * 0.7) + (newAverage * 0.3);
      }
    }

    // Calculate total extent
    if (itemExtent != null && itemCount != null) {
      // Fixed extent - exact calculation
      return itemExtent! * itemCount + (hasSeparators ? (itemCount - 1) : 0);
    } else if (itemCount != null) {
      // Check if we have the last item in _allChildren - then we know exact extent
      final lastIndex = itemCount - 1;
      for (final child in _allChildren) {
        final parentData = child.renderObject.parentData as ListViewParentData?;
        if (parentData?.index == lastIndex &&
            parentData?.layoutOffset != null &&
            parentData?.extent != null) {
          double extent = parentData!.layoutOffset! + parentData.extent!;
          if (hasSeparators) {
            extent += itemCount - 1; // Add separator heights
          }
          return extent;
        }
      }
      // Fall back to estimate based on average
      if (_averageItemExtent != null) {
        double extent = _averageItemExtent! * itemCount;
        if (hasSeparators) {
          extent += itemCount - 1;
        }
        return extent;
      }
      return currentPosition;
    } else {
      // Unknown count or no measurements yet - use what we've built
      return currentPosition;
    }
  }

  /// Performs eager layout - builds all children for accurate extent
  double _performEagerLayout({
    required double viewportExtent,
    required BoxConstraints childConstraints,
    required int? itemCount,
  }) {
    final scrollOffset = _controller.offset;
    double currentPosition = 0;

    // Build all children to get accurate total extent
    int itemIndex = 0;
    final maxItems = itemCount ?? 1000; // Reasonable limit for non-lazy mode

    while (itemIndex < maxItems) {
      // Build item
      final renderObject = _buildAndLayoutChild(
        index: itemIndex,
        childConstraints: childConstraints,
        layoutOffset: currentPosition,
      );
      if (renderObject == null) break;

      final childExtent =
          (renderObject.parentData as ListViewParentData).extent!;

      // Store all children info
      _addToAllChildren(renderObject);

      // Check if visible
      if (currentPosition < scrollOffset + viewportExtent &&
          currentPosition + childExtent > scrollOffset) {
        _visibleChildren.add(_ChildLayoutInfo(
          renderObject: renderObject,
        ));
      }

      currentPosition += childExtent;

      // Add separator if needed
      if (hasSeparators && (itemCount == null || itemIndex < itemCount - 1)) {
        final separatorRenderObject = _buildAndLayoutSeparator(
          index: itemIndex,
          childConstraints: childConstraints,
          layoutOffset: currentPosition,
        );
        if (separatorRenderObject != null) {
          final separatorExtent =
              (separatorRenderObject.parentData as ListViewParentData).extent!;

          _addToAllChildren(separatorRenderObject);

          if (currentPosition < scrollOffset + viewportExtent &&
              currentPosition + separatorExtent > scrollOffset) {
            _visibleChildren.add(_ChildLayoutInfo(
              renderObject: separatorRenderObject,
            ));
          }

          currentPosition += separatorExtent;
        }
      }

      itemIndex++;
    }

    return currentPosition; // Exact total extent
  }

  bool _keepAliveForSelection(Element child) {
    final renderObject = _getRenderObject(child);
    if (renderObject == null) return false;
    return _subtreeHasSelection(renderObject);
  }

  static bool _subtreeHasSelection(RenderObject node) {
    // Only an uncollapsed selection is worth keeping an item alive for;
    // collapsed edges are re-synthesized if the item ever remounts.
    if (node is Selectable &&
        (node as Selectable).value.status == SelectionStatus.uncollapsed) {
      return true;
    }
    var found = false;
    node.visitChildren((child) {
      found = found || _subtreeHasSelection(child);
    });
    return found;
  }

  /// Helper to get render object from element and attach it to this viewport.
  ///
  /// This ensures child render objects are properly attached to the pipeline
  /// owner, which is necessary for features like GestureDetector that create
  /// their annotations in attach().
  RenderObject? _getRenderObject(Element element) {
    RenderObject? renderObject;
    void findRenderObject(Element el) {
      if (el is RenderObjectElement) {
        renderObject = el.renderObject;
      } else {
        el.visitChildren(findRenderObject);
      }
    }

    findRenderObject(element);

    // Ensure the render object has ListViewParentData
    if (renderObject != null) {
      setupParentData(renderObject!);

      // Attach the render object to this viewport's owner if not already attached
      if (owner != null && renderObject!.owner != owner) {
        renderObject!.parent = this;
        renderObject!.attach(owner!);
      }
    }

    return renderObject;
  }

  @override
  void paint(TerminalCanvas canvas, Offset offset) {
    super.paint(canvas, offset);
    final effectivePadding = padding ?? EdgeInsets.zero;

    // Create clipped canvas for viewport
    final clippedCanvas = canvas.clip(
      Rect.fromLTWH(offset.dx, offset.dy, size.width, size.height),
    );

    // Calculate viewport extent for reverse mode
    final viewportExtent = scrollDirection == Axis.vertical
        ? size.height - effectivePadding.top - effectivePadding.bottom
        : size.width - effectivePadding.left - effectivePadding.right;

    // Paint only visible children
    for (final child in _visibleChildren) {
      final parentData = child.renderObject.parentData as ListViewParentData;
      final layoutOffset = parentData.layoutOffset ?? 0.0;
      double childPosition = layoutOffset - _controller.offset;

      // In reverse mode, flip the position
      if (_reverse) {
        final childExtent = parentData.extent ??
            (scrollDirection == Axis.vertical
                ? child.renderObject.size.height
                : child.renderObject.size.width);
        childPosition = viewportExtent - childPosition - childExtent;
      }

      final childOffset = scrollDirection == Axis.vertical
          ? Offset(effectivePadding.left, effectivePadding.top + childPosition)
          : Offset(effectivePadding.left + childPosition, effectivePadding.top);

      // Keep parent data offset in sync for hit testing and selection.
      parentData.offset = childOffset;

      child.renderObject.paint(clippedCanvas, childOffset);
    }
  }

  @override
  void visitChildren(RenderObjectVisitor visitor) {
    // Use _allChildren so that tree walks (e.g. selection registrars
    // collecting selectables) can discover cache-extent items outside the
    // viewport. Paint and hit-testing iterate _visibleChildren directly, so
    // this does not affect rendering or pointer dispatch.
    for (final child in _allChildren) {
      visitor(child.renderObject);
    }
  }

  @override
  bool hitTest(HitTestResult result, {required Offset position}) {
    // Check if position is within our bounds
    if (!Rect.fromLTWH(0, 0, size.width, size.height).contains(position)) {
      return false;
    }

    // Test children (will add to result if hit)
    bool hitChild = hitTestChildren(result, position: position);

    // Add ourselves if we hit
    if (hitChild || hitTestSelf(position)) {
      result.add(this);
      return true;
    }

    return false;
  }

  @override
  bool hitTestChildren(HitTestResult result, {required Offset position}) {
    final effectivePadding = padding ?? EdgeInsets.zero;
    final scrollOffset = _controller.offset;

    // Calculate viewport extent for reverse mode
    final viewportExtent = scrollDirection == Axis.vertical
        ? size.height - effectivePadding.top - effectivePadding.bottom
        : size.width - effectivePadding.left - effectivePadding.right;

    // Test visible children in reverse order (front to back)
    for (int i = _visibleChildren.length - 1; i >= 0; i--) {
      final child = _visibleChildren[i];
      final parentData = child.renderObject.parentData as ListViewParentData;
      final layoutOffset = parentData.layoutOffset ?? 0.0;
      double childPosition = layoutOffset - scrollOffset;

      // Get child extent (needed for reverse mode and bounds checking)
      final childExtent = parentData.extent ??
          (scrollDirection == Axis.vertical
              ? child.renderObject.size.height
              : child.renderObject.size.width);

      // Apply reverse mode transformation
      if (_reverse) {
        childPosition = viewportExtent - childPosition - childExtent;
      }

      final childOffset = scrollDirection == Axis.vertical
          ? Offset(effectivePadding.left, effectivePadding.top + childPosition)
          : Offset(effectivePadding.left + childPosition, effectivePadding.top);

      // Check if position is within child's bounds before testing
      final childBounds = Rect.fromLTWH(
        childOffset.dx,
        childOffset.dy,
        child.renderObject.size.width,
        child.renderObject.size.height,
      );

      if (!childBounds.contains(position)) {
        continue; // Skip this child
      }

      // Transform position to child's local coordinates
      final localPosition = position - childOffset;

      // Test if this child was hit
      if (child.renderObject.hitTest(result, position: localPosition)) {
        return true;
      }
    }

    return false;
  }

  /// Gets the offset and extent of an item by its index.
  ///
  /// Returns a record with (offset, extent) if the item is found,
  /// or null if the item doesn't exist or hasn't been laid out yet.
  ///
  /// This method works in both lazy and non-lazy modes by reading
  /// from parent data attached to each child render object.
  (double, double)? getItemOffsetAndExtent(int index) {
    // Search all children for the item with matching index
    for (final child in _allChildren) {
      final parentData = child.renderObject.parentData as ListViewParentData?;
      if (parentData?.index == index &&
          parentData?.layoutOffset != null &&
          parentData?.extent != null) {
        return (parentData!.layoutOffset!, parentData.extent!);
      }
    }

    // Also check visible children (in case _allChildren is empty in lazy mode)
    for (final child in _visibleChildren) {
      final parentData = child.renderObject.parentData as ListViewParentData?;
      if (parentData?.index == index &&
          parentData?.layoutOffset != null &&
          parentData?.extent != null) {
        return (parentData!.layoutOffset!, parentData.extent!);
      }
    }

    // If item is not found, try to estimate if we have fixed itemExtent
    if (itemExtent != null) {
      // Fixed extent - we can calculate exact position
      final offset = index * itemExtent!;
      return (offset, itemExtent!);
    }

    // If item is not found and we can't estimate, return null
    return null;
  }
}

/// The content position pinned across a cross-axis reflow.
///
/// The item at the viewport top is held by [index] and its pre-reflow
/// [position]; the depth *within* the item is held content-addressed: the
/// paragraph render object under the viewport top ([leaf]) and the character
/// offset of its anchored visual line ([char]). Characters are
/// width-independent, and render objects persist across relayout, so after
/// a reflow the anchored line's new row is read exactly.
///
/// [rowsAfter] carries the width-stable rows between that line and the
/// viewport top when the top sat on a gap (block spacing, a divider) below
/// the paragraph. [delta] and [extent] are the raw pre-reflow row depth and
/// item extent: a top sitting past the item's content (a separator row)
/// anchors to the item's end plus the overshoot, and a leafless or
/// dead-leaf anchor falls back to the raw depth.
class _ReflowAnchor {
  const _ReflowAnchor({
    required this.index,
    required this.position,
    required this.delta,
    required this.extent,
    this.leaf,
    this.char,
    this.rowsAfter = 0.0,
  });

  final int index;
  final double position;
  final double delta;
  final double extent;
  final RenderObject? leaf;
  final int? char;
  final double rowsAfter;
}

/// Information about a child in the viewport.
///
/// Only stores the render object reference. Position data (offset, extent, index)
/// is stored in the render object's [ListViewParentData].
class _ChildLayoutInfo {
  const _ChildLayoutInfo({
    required this.renderObject,
  });

  final RenderObject renderObject;
}
