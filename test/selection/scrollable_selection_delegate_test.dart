import 'package:nocterm/src/components/scroll_controller.dart';
import 'package:nocterm/src/framework/framework.dart';
import 'package:nocterm/src/selection/scrollable_selection_delegate.dart';
import 'package:nocterm/src/selection/selection.dart';
import 'package:nocterm/src/size.dart';
import 'package:test/test.dart';

import 'test_text_render.dart';

class _ViewportRender extends RenderObject {
  @override
  void performLayout() {
    size = constraints.constrain(Size.zero);
  }
}

/// Drives a [ScrollableSelectionContainerDelegate] the way a lazy viewport
/// would: children sit at fixed content rows and their parent data offsets
/// are re-derived from the scroll offset, one content row per screen cell.
class _Harness {
  _Harness({double viewportHeight = 8, double contentHeight = 16}) {
    controller.updateMetrics(
      minScrollExtent: 0,
      maxScrollExtent: contentHeight - viewportHeight,
      viewportDimension: viewportHeight,
    );
    delegate = ScrollableSelectionContainerDelegate(
      controller: controller,
      schedulePostFrame: _pending.add,
      // A virtual clock that ticks one second per pump-tick moveEnd, so
      // auto-scroll velocity (rows/sec) resolves to whole rows per tick.
      clock: () => _now,
    );
    container = _ViewportRender()
      ..parentData = (BoxParentData()..offset = Offset.zero)
      ..layout(BoxConstraints(
        minWidth: 80,
        maxWidth: 80,
        minHeight: viewportHeight,
        maxHeight: viewportHeight,
      ));
    delegate.container = container;
  }

  final controller = ScrollController();
  late final ScrollableSelectionContainerDelegate delegate;
  late final _ViewportRender container;
  final _pending = <void Function()>[];
  final _contentRows = <TestTextRender, double>{};
  Duration _now = Duration.zero;

  void flush() {
    while (_pending.isNotEmpty) {
      final callbacks = List.of(_pending);
      _pending.clear();
      for (final callback in callbacks) {
        callback();
      }
    }
  }

  TestTextRender addBlock(String text, {required double contentRow}) {
    final render = TestTextRender(text);
    _contentRows[render] = contentRow;
    render.parentData = BoxParentData()
      ..offset = Offset(0, contentRow - controller.offset);
    render.layout(const BoxConstraints(maxWidth: 80));
    render.registrar = delegate;
    return render;
  }

  void removeBlock(TestTextRender render) {
    _contentRows.remove(render);
    render.registrar = null;
  }

  void scrollTo(double offset) {
    controller.jumpTo(offset);
    for (final entry in _contentRows.entries) {
      (entry.key.parentData as BoxParentData).offset =
          Offset(0, entry.value - controller.offset);
    }
    flush();
  }

  SelectionResult startSelection(Offset position) {
    delegate.dispatchSelectionEvent(const ClearSelectionEvent());
    delegate.dispatchSelectionEvent(
        SelectionEdgeUpdateEvent.forStart(globalPosition: position));
    return delegate.dispatchSelectionEvent(
        SelectionEdgeUpdateEvent.forEnd(globalPosition: position));
  }

  SelectionResult moveEnd(Offset position) {
    _now += const Duration(seconds: 1);
    return delegate.dispatchSelectionEvent(
        SelectionEdgeUpdateEvent.forEnd(globalPosition: position));
  }
}

void main() {
  group('ScrollableSelectionContainerDelegate', () {
    test('selection works like a static delegate while unscrolled', () {
      final harness = _Harness();
      final a = harness.addBlock('hello world', contentRow: 0);
      final b = harness.addBlock('foo bar', contentRow: 1);
      harness.flush();

      harness.startSelection(const Offset(6, 0));
      harness.moveEnd(const Offset(3, 1));

      expect(a.getSelectedContent()?.plainText, 'world');
      expect(b.getSelectedContent()?.plainText, 'foo');
    });

    test('anchor stays pinned to content across a scroll', () {
      final harness = _Harness();
      final a = harness.addBlock('hello world', contentRow: 0);
      final b = harness.addBlock('foo bar', contentRow: 1);
      final c = harness.addBlock('baz qux', contentRow: 2);
      harness.flush();

      harness.startSelection(const Offset(6, 0));
      harness.moveEnd(const Offset(80, 0));
      expect(a.getSelectedContent()?.plainText, 'world');

      // Content moves up one row under the unmoving pointer; the same
      // screen position now reads one content row further.
      harness.scrollTo(1);
      harness.moveEnd(const Offset(80, 0));

      expect(a.getSelectedContent()?.plainText, 'world');
      expect(b.getSelectedContent()?.plainText, 'foo bar');
      expect(c.hasSelection, isFalse);

      harness.scrollTo(2);
      harness.moveEnd(const Offset(80, 0));

      expect(a.getSelectedContent()?.plainText, 'world');
      expect(b.getSelectedContent()?.plainText, 'foo bar');
      expect(c.getSelectedContent()?.plainText, 'baz qux');
      expect(harness.delegate.getSelectedContent()?.plainText,
          'world\nfoo bar\nbaz qux');
    });

    test('a child mounting mid-drag receives the synthesized edges', () {
      final harness = _Harness();
      final a = harness.addBlock('hello world', contentRow: 0);
      harness.flush();

      harness.startSelection(const Offset(6, 0));
      harness.moveEnd(const Offset(80, 2));

      final b = harness.addBlock('foo bar', contentRow: 1);
      harness.flush();

      expect(a.getSelectedContent()?.plainText, 'world');
      expect(b.getSelectedContent()?.plainText, 'foo bar');
    });

    test('a child remounting after scroll re-integrates at its new position',
        () {
      final harness = _Harness();
      final a = harness.addBlock('hello world', contentRow: 0);
      final b = harness.addBlock('foo bar', contentRow: 4);
      harness.flush();

      harness.startSelection(const Offset(2, 0));
      harness.moveEnd(const Offset(80, 3));
      expect(a.getSelectedContent()?.plainText, 'llo world');
      expect(b.hasSelection, isFalse);

      // The anchor block scrolls out and is culled mid-drag.
      harness.removeBlock(a);
      harness.scrollTo(4);
      harness.flush();

      // The pointer keeps selecting rows; b now sits at screen row 0.
      harness.moveEnd(const Offset(3, 0));
      expect(b.getSelectedContent()?.plainText, 'foo');

      // The culled block scrolls back in and re-registers; the synthesized
      // start edge lands at the original content position, not the original
      // screen position.
      harness.scrollTo(0);
      final aAgain = harness.addBlock('hello world', contentRow: 0);
      harness.flush();

      expect(aAgain.getSelectedContent()?.plainText, 'llo world');
    });

    test(
        'selection starting before the viewport pins the start to the '
        'content origin', () {
      final harness = _Harness();
      final a = harness.addBlock('hello world', contentRow: 0);
      harness.scrollTo(1);
      harness.flush();

      // The outer area dispatches a start edge above this scrollable, as
      // when a drag begins on a component above the list.
      harness.startSelection(const Offset(4, -2));
      harness.moveEnd(const Offset(3, 1));

      // Start clamps to the scrollable's origin: all content from the very
      // first character is selected even though it is scrolled offscreen.
      expect(a.getSelectedContent()?.plainText, 'hello world');
    });

    test(
        'selection starting after the viewport pins the end past the '
        'content end', () {
      final harness = _Harness();
      final a = harness.addBlock('hello world', contentRow: 0);
      final b = harness.addBlock('foo bar', contentRow: 5);
      harness.flush();

      harness.startSelection(const Offset(3, 0));
      harness.moveEnd(const Offset(0, 99));

      expect(a.getSelectedContent()?.plainText, 'lo world');
      expect(b.getSelectedContent()?.plainText, 'foo bar');
    });

    test('dragging past the viewport auto-scrolls and reports pending', () {
      final harness = _Harness();
      harness.addBlock('hello world', contentRow: 0);
      harness.addBlock('foo bar', contentRow: 6);
      harness.flush();

      harness.startSelection(const Offset(2, 1));
      final result = harness.moveEnd(const Offset(2, 6));

      expect(result, SelectionResult.pending);
      expect(harness.controller.offset, greaterThan(0));
    });

    test('auto-scroll stops reporting pending at the end of the extent', () {
      final harness = _Harness();
      harness.addBlock('hello world', contentRow: 0);
      harness.flush();

      harness.startSelection(const Offset(2, 1));
      var result = harness.moveEnd(const Offset(2, 6));
      var guard = 0;
      while (result == SelectionResult.pending && guard < 100) {
        harness.scrollTo(harness.controller.offset);
        result = harness.moveEnd(const Offset(2, 6));
        guard += 1;
      }

      expect(result, isNot(SelectionResult.pending));
      expect(harness.controller.offset, harness.controller.maxScrollExtent);
    });

    test('selection starting outside the viewport never auto-scrolls', () {
      final harness = _Harness();
      harness.addBlock('hello world', contentRow: 0);
      harness.flush();

      harness.startSelection(const Offset(2, -3));
      final result = harness.moveEnd(const Offset(2, 6));

      expect(result, isNot(SelectionResult.pending));
      expect(harness.controller.offset, 0);
    });

    test('clearing the selection resets drag state', () {
      final harness = _Harness();
      final a = harness.addBlock('hello world', contentRow: 0);
      harness.flush();

      harness.startSelection(const Offset(0, 0));
      harness.moveEnd(const Offset(5, 0));
      expect(a.hasSelection, isTrue);

      harness.delegate.dispatchSelectionEvent(const ClearSelectionEvent());
      expect(a.hasSelection, isFalse);

      // A fresh drag after clearing re-evaluates where it starts.
      harness.startSelection(const Offset(2, 0));
      harness.moveEnd(const Offset(7, 0));
      expect(a.getSelectedContent()?.plainText, 'llo w');
    });

    test('select word inside the scrollable pins edges to content', () {
      final harness = _Harness();
      final a = harness.addBlock('hello world', contentRow: 0);
      final b = harness.addBlock('foo bar', contentRow: 1);
      harness.flush();

      harness.delegate.dispatchSelectionEvent(
          const SelectWordSelectionEvent(globalPosition: Offset(2, 0)));
      expect(a.getSelectedContent()?.plainText, 'hello');

      // Extending the drag after a scroll keeps the word-selection anchor
      // glued to the content it was selected on.
      harness.scrollTo(1);
      harness.moveEnd(const Offset(3, 0));

      expect(a.getSelectedContent()?.plainText, 'hello world');
      expect(b.getSelectedContent()?.plainText, 'foo');
    });

    test('swapping controllers moves the scroll listener', () {
      final harness = _Harness();
      final replacement = ScrollController();
      replacement.updateMetrics(
        minScrollExtent: 0,
        maxScrollExtent: 8,
        viewportDimension: 4,
      );

      harness.delegate.controller = replacement;
      harness.addBlock('hello world', contentRow: 0);
      harness.flush();

      harness.startSelection(const Offset(0, 0));
      final result = harness.moveEnd(const Offset(2, 6));

      expect(result, SelectionResult.pending);
      expect(replacement.offset, greaterThan(0));
      expect(harness.controller.offset, 0);
    });
  });
}
