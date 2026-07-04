import 'package:nocterm/src/framework/framework.dart';
import 'package:nocterm/src/selection/selection.dart';
import 'package:nocterm/src/selection/selection_container_delegate.dart';
import 'package:nocterm/src/selection/text_selectable.dart';
import 'package:nocterm/src/size.dart';
import 'package:nocterm/src/text/text_layout_engine.dart';
import 'package:test/test.dart';

class _TestTextRender extends RenderObject
    with Selectable, SelectionRegistrant, TextSelectable {
  _TestTextRender(this._text);

  final String _text;
  TextLayoutResult? _layoutResult;

  @override
  String get selectableText => _text;

  @override
  TextLayoutResult? get selectableLayout => _layoutResult;

  @override
  void performLayout() {
    _layoutResult = TextLayoutEngine.layout(
      _text,
      TextLayoutConfig(maxWidth: constraints.maxWidth.toInt()),
    );
    size = constraints.constrain(Size(
      _layoutResult!.actualWidth.toDouble(),
      _layoutResult!.actualHeight.toDouble(),
    ));
    didLayoutSelectableText();
  }
}

class _GeometryCountingDelegate extends StaticSelectionContainerDelegate {
  _GeometryCountingDelegate({super.schedulePostFrame});

  int geometryBuilds = 0;

  @override
  SelectionGeometry getSelectionGeometry() {
    geometryBuilds++;
    return super.getSelectionGeometry();
  }
}

class _Harness {
  _Harness({
    StaticSelectionContainerDelegate Function(PostFrameScheduler)?
        createDelegate,
  }) {
    delegate = createDelegate?.call(_pending.add) ??
        StaticSelectionContainerDelegate(schedulePostFrame: _pending.add);
  }

  late final StaticSelectionContainerDelegate delegate;
  final _pending = <void Function()>[];

  /// Runs scheduled selectable updates, as the end of a frame would.
  void flush() {
    while (_pending.isNotEmpty) {
      final callbacks = List.of(_pending);
      _pending.clear();
      for (final callback in callbacks) {
        callback();
      }
    }
  }

  _TestTextRender addBlock(String text, {required double row}) {
    final render = _TestTextRender(text);
    render.parentData = BoxParentData()..offset = Offset(0, row);
    render.layout(const BoxConstraints(maxWidth: 80));
    render.registrar = delegate;
    return render;
  }

  void selectFromTo(Offset start, Offset end) {
    delegate.dispatchSelectionEvent(
        SelectionEdgeUpdateEvent.forStart(globalPosition: start));
    delegate.dispatchSelectionEvent(
        SelectionEdgeUpdateEvent.forEnd(globalPosition: start));
    delegate.dispatchSelectionEvent(
        SelectionEdgeUpdateEvent.forEnd(globalPosition: end));
  }
}

void main() {
  group('MultiSelectableSelectionContainerDelegate', () {
    test('registers selectables via post-frame flush in screen order', () {
      final harness = _Harness();
      final b = harness.addBlock('foo bar', row: 1);
      final a = harness.addBlock('hello world', row: 0);
      expect(harness.delegate.selectables, isEmpty);

      harness.flush();
      expect(harness.delegate.selectables, [a, b]);
    });

    test('selects within a single child', () {
      final harness = _Harness();
      final a = harness.addBlock('hello world', row: 0);
      final b = harness.addBlock('foo bar', row: 1);
      harness.flush();

      harness.selectFromTo(const Offset(3, 0), const Offset(8, 0));

      expect(a.getSelectedContent()?.plainText, 'lo wo');
      expect(b.hasSelection, isFalse);
      expect(harness.delegate.getSelectedContent()?.plainText, 'lo wo');
      expect(harness.delegate.value.status, SelectionStatus.uncollapsed);
    });

    test('drag across children selects through the middle child', () {
      final harness = _Harness();
      final a = harness.addBlock('hello world', row: 0);
      final b = harness.addBlock('foo bar', row: 1);
      final c = harness.addBlock('baz qux quux', row: 2);
      harness.flush();

      harness.selectFromTo(const Offset(6, 0), const Offset(3, 2));

      expect(a.getSelectedContent()?.plainText, 'world');
      expect(b.getSelectedContent()?.plainText, 'foo bar');
      expect(c.getSelectedContent()?.plainText, 'baz');
      expect(harness.delegate.getSelectedContent()?.plainText,
          'world\nfoo bar\nbaz');
    });

    test('reversed drag selects the same content', () {
      final harness = _Harness();
      final a = harness.addBlock('hello world', row: 0);
      final b = harness.addBlock('foo bar', row: 1);
      final c = harness.addBlock('baz qux quux', row: 2);
      harness.flush();

      harness.selectFromTo(const Offset(3, 2), const Offset(6, 0));

      expect(a.getSelectedContent()?.plainText, 'world');
      expect(b.getSelectedContent()?.plainText, 'foo bar');
      expect(c.getSelectedContent()?.plainText, 'baz');
      expect(harness.delegate.getSelectedContent()?.plainText,
          'world\nfoo bar\nbaz');
    });

    test('dragging an edge back shrinks the selection and clears children', () {
      final harness = _Harness();
      final a = harness.addBlock('hello world', row: 0);
      final b = harness.addBlock('foo bar', row: 1);
      final c = harness.addBlock('baz qux quux', row: 2);
      harness.flush();

      harness.selectFromTo(const Offset(6, 0), const Offset(3, 2));
      harness.delegate.dispatchSelectionEvent(
        const SelectionEdgeUpdateEvent.forEnd(globalPosition: Offset(3, 1)),
      );

      expect(a.getSelectedContent()?.plainText, 'world');
      expect(b.getSelectedContent()?.plainText, 'foo');
      expect(c.hasSelection, isFalse);
      expect(harness.delegate.getSelectedContent()?.plainText, 'world\nfoo');
    });

    test('select all selects every child', () {
      final harness = _Harness();
      harness.addBlock('hello world', row: 0);
      harness.addBlock('foo bar', row: 1);
      harness.flush();

      harness.delegate.dispatchSelectionEvent(const SelectAllSelectionEvent());
      expect(harness.delegate.getSelectedContent()?.plainText,
          'hello world\nfoo bar');
    });

    test('clear removes selection from every child', () {
      final harness = _Harness();
      final a = harness.addBlock('hello world', row: 0);
      final b = harness.addBlock('foo bar', row: 1);
      harness.flush();

      harness.selectFromTo(const Offset(0, 0), const Offset(3, 1));
      harness.delegate.dispatchSelectionEvent(const ClearSelectionEvent());

      expect(a.hasSelection, isFalse);
      expect(b.hasSelection, isFalse);
      expect(harness.delegate.getSelectedContent(), isNull);
      expect(harness.delegate.value.status, SelectionStatus.none);
    });

    test('select word delegates to the child at the position', () {
      final harness = _Harness();
      harness.addBlock('hello world', row: 0);
      final b = harness.addBlock('foo bar', row: 1);
      harness.flush();

      harness.delegate.dispatchSelectionEvent(
        const SelectWordSelectionEvent(globalPosition: Offset(5, 1)),
      );
      expect(b.getSelectedContent()?.plainText, 'bar');
      expect(harness.delegate.getSelectedContent()?.plainText, 'bar');
    });

    test('same-row children join with a space', () {
      final harness = _Harness();
      final left = _TestTextRender('foo');
      left.parentData = BoxParentData()..offset = const Offset(0, 0);
      left.layout(const BoxConstraints(maxWidth: 80));
      left.registrar = harness.delegate;

      final right = _TestTextRender('bar');
      right.parentData = BoxParentData()..offset = const Offset(3, 0);
      right.layout(const BoxConstraints(maxWidth: 80));
      right.registrar = harness.delegate;
      harness.flush();

      harness.selectFromTo(const Offset(0, 0), const Offset(6, 0));
      expect(harness.delegate.getSelectedContent()?.plainText, 'foo bar');
    });
  });

  group('StaticSelectionContainerDelegate content changes', () {
    test('child added inside an active selection is integrated', () {
      final harness = _Harness();
      final a = harness.addBlock('hello world', row: 0);
      final c = harness.addBlock('baz qux quux', row: 4);
      harness.flush();

      harness.selectFromTo(const Offset(6, 0), const Offset(3, 4));
      expect(harness.delegate.getSelectedContent()?.plainText, 'world\nbaz');

      final b = harness.addBlock('foo bar', row: 2);
      harness.flush();

      expect(b.getSelectedContent()?.plainText, 'foo bar');
      expect(harness.delegate.getSelectedContent()?.plainText,
          'world\nfoo bar\nbaz');
      expect(a.getSelectedContent()?.plainText, 'world');
      expect(c.getSelectedContent()?.plainText, 'baz');
    });

    test('child added after the selection stays unselected', () {
      final harness = _Harness();
      harness.addBlock('hello world', row: 0);
      harness.addBlock('foo bar', row: 2);
      harness.flush();

      harness.selectFromTo(const Offset(6, 0), const Offset(3, 2));

      final late = harness.addBlock('later content', row: 4);
      harness.flush();

      expect(late.hasSelection, isFalse);
      expect(harness.delegate.getSelectedContent()?.plainText, 'world\nfoo');
    });

    test('child removed mid-selection drops out of the selection', () {
      final harness = _Harness();
      final a = harness.addBlock('hello world', row: 0);
      final b = harness.addBlock('foo bar', row: 2);
      final c = harness.addBlock('baz qux quux', row: 4);
      harness.flush();

      harness.selectFromTo(const Offset(6, 0), const Offset(3, 4));
      expect(harness.delegate.getSelectedContent()?.plainText,
          'world\nfoo bar\nbaz');

      b.registrar = null;
      harness.flush();

      expect(harness.delegate.getSelectedContent()?.plainText, 'world\nbaz');
      expect(a.getSelectedContent()?.plainText, 'world');
      expect(c.getSelectedContent()?.plainText, 'baz');
    });

    test('removing the edge-owning child re-resolves the edge', () {
      final harness = _Harness();
      final a = harness.addBlock('hello world', row: 0);
      final b = harness.addBlock('foo bar', row: 2);
      harness.flush();

      harness.selectFromTo(const Offset(6, 0), const Offset(3, 2));

      b.registrar = null;
      harness.flush();

      expect(harness.delegate.getSelectedContent()?.plainText, 'world');
      expect(a.getSelectedContent()?.plainText, 'world');
    });

    test('selectable churn rebuilds the combined geometry once per flush', () {
      late _GeometryCountingDelegate counting;
      final harness = _Harness(
        createDelegate: (schedule) => counting =
            _GeometryCountingDelegate(schedulePostFrame: schedule),
      );
      final a = harness.addBlock('hello world', row: 0);
      final b = harness.addBlock('foo bar', row: 1);
      final c = harness.addBlock('baz qux quux', row: 2);
      harness.flush();

      harness.selectFromTo(const Offset(6, 0), const Offset(3, 2));
      expect(harness.delegate.getSelectedContent()?.plainText,
          'world\nfoo bar\nbaz');

      // A block streams in above the selected region, pushing the blocks
      // below it down a row; the edge replay then re-resolves both edges
      // against the shifted children, changing their geometries.
      (b.parentData as BoxParentData).offset = const Offset(0, 2);
      (c.parentData as BoxParentData).offset = const Offset(0, 3);
      harness.addBlock('streamed', row: 1);
      counting.geometryBuilds = 0;
      harness.flush();

      expect(counting.geometryBuilds, 1,
          reason: 'child geometry notifications during the replay must not '
              'each rebuild the combined geometry');
      expect(harness.delegate.getSelectedContent()?.plainText,
          'world\nstreamed\nfoo');
      expect(a.getSelectedContent()?.plainText, 'world');
      expect(c.hasSelection, isFalse);
    });

    test('selection persists after mouse up while content streams in', () {
      final harness = _Harness();
      harness.addBlock('hello world', row: 0);
      final c = harness.addBlock('baz qux quux', row: 4);
      harness.flush();

      // Drag completes; edges are no longer moving.
      harness.selectFromTo(const Offset(6, 0), const Offset(3, 4));

      // A block streams in afterwards, inside the selected region.
      final b = harness.addBlock('foo bar', row: 2);
      harness.flush();

      expect(b.getSelectedContent()?.plainText, 'foo bar');
      expect(harness.delegate.getSelectedContent()?.plainText,
          'world\nfoo bar\nbaz');
      expect(c.getSelectedContent()?.plainText, 'baz');
    });
  });
}
