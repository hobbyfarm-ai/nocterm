import 'package:nocterm/nocterm.dart';
import 'package:nocterm/src/navigation/render_theater.dart';
import 'package:nocterm/src/rendering/scrollable_render_object.dart';

import '../rendering/mouse_hit_test.dart';
import '../rendering/mouse_tracker.dart';

/// Routes mouse events through the component tree: wheel events to
/// scrollables, and hit-test results to the [MouseTracker] annotations.
///
/// Shared by the terminal binding and the test binding so tests exercise the
/// exact production routing (including wheel-driven scrolling).
mixin MouseRouter on NoctermBinding {
  MouseTracker get mouseTracker;

  /// Route a mouse event through the component tree.
  void routeMouseEvent(MouseEvent event) {
    final root = rootElement;
    if (root == null) return;

    // Handle wheel events for scrollable widgets
    if (event.button == MouseButton.wheelUp ||
        event.button == MouseButton.wheelDown) {
      dispatchMouseWheelAtPosition(root, event,
          Offset(event.x.toDouble(), event.y.toDouble()), Offset.zero);
    }

    // A captured drag routes every event to the captured annotation and
    // ignores hit-test results, so skip the full-tree hit test — it's the
    // dominant per-event cost when the terminal floods motion reports.
    if (mouseTracker.hasActiveCapture) {
      mouseTracker.updateAnnotations(MouseHitTestResult(), event);
      return;
    }

    // Perform hit test for all mouse events
    final renderObject = findRenderObjectInTree(root);
    if (renderObject != null) {
      final hitTestResult = MouseHitTestResult();
      // Mouse coordinates are already 0-based (converted by MouseParser)
      final position = Offset(event.x.toDouble(), event.y.toDouble());

      renderObject.hitTest(hitTestResult, position: position);

      mouseTracker.updateAnnotations(hitTestResult, event);
    }
  }

  /// Find the first render object in the element tree.
  RenderObject? findRenderObjectInTree(Element element) {
    if (element is RenderObjectElement) {
      return element.renderObject;
    }
    RenderObject? result;
    element.visitChildren((child) {
      result ??= findRenderObjectInTree(child);
    });
    return result;
  }

  /// Dispatch a mouse wheel event to scrollable RenderObjects at a position.
  bool dispatchMouseWheelAtPosition(Element element, MouseEvent event,
      Offset mousePos, Offset currentOffset) {
    // TODO: This is a hack to handle RenderTheater specially for Navigator
    // Should be properly integrated into the render object hierarchy
    if (element.renderObject is RenderTheater) {
      final multiChildRenderObject = element as MultiChildRenderObjectElement;
      if (multiChildRenderObject.children.isNotEmpty) {
        final child = multiChildRenderObject.children.last;
        return dispatchMouseWheelAtPosition(
            child, event, mousePos, currentOffset);
      }
    }

    // Calculate this element's bounds if it has a render object
    Rect? elementBounds;
    RenderObject? renderObject;

    if (element is RenderObjectElement) {
      renderObject = element.renderObject;
      final size = renderObject.size;

      // Get the offset from parent data if available
      Offset localOffset = currentOffset;
      if (renderObject.parentData is BoxParentData) {
        final boxParentData = renderObject.parentData as BoxParentData;
        localOffset = currentOffset + boxParentData.offset;
      }

      elementBounds = Rect.fromLTWH(
        localOffset.dx,
        localOffset.dy,
        size.width,
        size.height,
      );
    }

    // Check if mouse is within this element's bounds
    bool isWithinBounds = elementBounds?.contains(mousePos) ?? true;

    if (!isWithinBounds) {
      return false; // Mouse is outside this element
    }

    // Try to dispatch to children first (depth-first, but only if within their bounds)
    bool handled = false;

    // Calculate offset for children
    Offset childrenOffset = currentOffset;
    if (element is RenderObjectElement && elementBounds != null) {
      // Use the element's actual position for its children
      childrenOffset = Offset(elementBounds.left, elementBounds.top);
    }

    // Visit children in reverse order to respect visual stacking
    // (last child is visually on top in Stack-like containers)
    final children = <Element>[];
    element.visitChildren((child) {
      children.add(child);
    });

    for (final child in children.reversed) {
      if (!handled) {
        handled = dispatchMouseWheelAtPosition(
            child, event, mousePos, childrenOffset);
      }
    }

    // If no child handled it and this element's render object is scrollable, handle it here
    if (!handled &&
        renderObject != null &&
        renderObject is ScrollableRenderObjectMixin) {
      final scrollableRenderObject =
          renderObject as ScrollableRenderObjectMixin;
      handled = scrollableRenderObject.handleMouseWheel(event);
    }

    return handled;
  }
}
