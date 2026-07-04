import 'package:nocterm/src/framework/framework.dart';
import 'package:nocterm/src/rectangle.dart';
import 'package:nocterm/src/selection/selection.dart';
import 'package:nocterm/src/selection/text_selectable.dart';
import 'package:nocterm/src/size.dart';
import 'package:nocterm/src/text/text_layout_engine.dart';
import 'package:test/test.dart';

class _TestTextRender extends RenderObject
    with Selectable, SelectionRegistrant, TextSelectable {
  _TestTextRender(this._text);

  String _text;
  set text(String value) {
    _text = value;
    markNeedsLayout();
  }

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

_TestTextRender _laidOut(String text, {double maxWidth = 80}) {
  final render = _TestTextRender(text);
  render.layout(BoxConstraints(maxWidth: maxWidth));
  return render;
}

void main() {
  group('TextSelectable edge updates', () {
    test('edge inside bounds maps to a character offset and returns end', () {
      final render = _laidOut('hello world');

      final result = render.dispatchSelectionEvent(
        const SelectionEdgeUpdateEvent.forStart(globalPosition: Offset(6, 0)),
      );
      expect(result, SelectionResult.end);
      expect(render.selectionStart, 6);
      expect(render.hasSelection, isFalse);

      render.dispatchSelectionEvent(
        const SelectionEdgeUpdateEvent.forEnd(globalPosition: Offset(11, 0)),
      );
      expect(render.selectionEnd, 11);
      expect(render.hasSelection, isTrue);
      expect(render.getSelectedContent()?.plainText, 'world');
    });

    test('edge below bounds selects to content end and returns next', () {
      final render = _laidOut('hello');
      render.dispatchSelectionEvent(
        const SelectionEdgeUpdateEvent.forStart(globalPosition: Offset(0, 0)),
      );

      final result = render.dispatchSelectionEvent(
        const SelectionEdgeUpdateEvent.forEnd(globalPosition: Offset(2, 5)),
      );
      expect(result, SelectionResult.next);
      expect(render.selectionEnd, 5);
      expect(render.getSelectedContent()?.plainText, 'hello');
    });

    test('edge above bounds selects to content start and returns previous', () {
      final render = _laidOut('hello');
      render.dispatchSelectionEvent(
        const SelectionEdgeUpdateEvent.forEnd(globalPosition: Offset(3, 0)),
      );

      final result = render.dispatchSelectionEvent(
        const SelectionEdgeUpdateEvent.forStart(globalPosition: Offset(50, -2)),
      );
      expect(result, SelectionResult.previous);
      expect(render.selectionStart, 0);
      expect(render.getSelectedContent()?.plainText, 'hel');
    });

    test('reversed edges normalize in selected content', () {
      final render = _laidOut('hello world');
      render.dispatchSelectionEvent(
        const SelectionEdgeUpdateEvent.forStart(globalPosition: Offset(11, 0)),
      );
      render.dispatchSelectionEvent(
        const SelectionEdgeUpdateEvent.forEnd(globalPosition: Offset(6, 0)),
      );
      expect(render.getSelectedContent()?.plainText, 'world');
    });
  });

  group('TextSelectable geometry', () {
    test('reports content after layout', () {
      final render = _laidOut('hello');
      expect(render.value.hasContent, isTrue);
      expect(render.value.status, SelectionStatus.none);
    });

    test('empty text reports no content', () {
      final render = _laidOut('');
      expect(render.value.hasContent, isFalse);
    });

    test('multi-line selection produces one rect per covered line', () {
      final render = _laidOut('hello\nworld');
      render.dispatchSelectionEvent(
        const SelectionEdgeUpdateEvent.forStart(globalPosition: Offset(2, 0)),
      );
      render.dispatchSelectionEvent(
        const SelectionEdgeUpdateEvent.forEnd(globalPosition: Offset(3, 1)),
      );

      expect(render.value.status, SelectionStatus.uncollapsed);
      expect(render.value.selectionRects, const [
        Rect.fromLTWH(2, 0, 3, 1),
        Rect.fromLTWH(0, 1, 3, 1),
      ]);
      expect(render.value.startSelectionPoint,
          const SelectionPoint(localPosition: Offset(2, 0)));
      expect(render.value.endSelectionPoint,
          const SelectionPoint(localPosition: Offset(3, 1)));
    });

    test('wide characters produce cell-width rects', () {
      final render = _laidOut('你好');
      render.dispatchSelectionEvent(
        const SelectionEdgeUpdateEvent.forStart(globalPosition: Offset(0, 0)),
      );
      render.dispatchSelectionEvent(
        const SelectionEdgeUpdateEvent.forEnd(globalPosition: Offset(4, 0)),
      );
      expect(render.value.selectionRects, const [Rect.fromLTWH(0, 0, 4, 1)]);
      expect(render.getSelectedContent()?.plainText, '你好');
    });
  });

  group('TextSelectable select all / clear / word', () {
    test('select all selects the entire content', () {
      final render = _laidOut('hello world');
      final result =
          render.dispatchSelectionEvent(const SelectAllSelectionEvent());
      expect(result, SelectionResult.none);
      expect(render.getSelectedContent()?.plainText, 'hello world');
    });

    test('clear removes the selection', () {
      final render = _laidOut('hello');
      render.dispatchSelectionEvent(const SelectAllSelectionEvent());
      render.dispatchSelectionEvent(const ClearSelectionEvent());
      expect(render.hasSelection, isFalse);
      expect(render.getSelectedContent(), isNull);
      expect(render.value.status, SelectionStatus.none);
    });

    test('select word selects the word at the position', () {
      final render = _laidOut('hello world');
      final result = render.dispatchSelectionEvent(
        const SelectWordSelectionEvent(globalPosition: Offset(8, 0)),
      );
      expect(result, SelectionResult.end);
      expect(render.getSelectedContent()?.plainText, 'world');
    });

    test('select word on whitespace selects the whitespace run', () {
      final render = _laidOut('a  b');
      render.dispatchSelectionEvent(
        const SelectWordSelectionEvent(globalPosition: Offset(1, 0)),
      );
      expect(render.getSelectedContent()?.plainText, '  ');
    });
  });

  group('TextSelectable content changes', () {
    test('relayout with shorter text clamps the selection', () {
      final render = _laidOut('hello world');
      render.dispatchSelectionEvent(const SelectAllSelectionEvent());
      expect(render.selectionEnd, 11);

      render.text = 'hi';
      render.layout(const BoxConstraints(maxWidth: 80));

      expect(render.selectionStart, 0);
      expect(render.selectionEnd, 2);
      expect(render.getSelectedContent()?.plainText, 'hi');
    });

    test('relayout to empty text drops content and registration', () {
      final registrar = _FakeRegistrar();
      final render = _laidOut('hello');
      render.registrar = registrar;
      expect(registrar.added, [render]);

      render.text = '';
      render.layout(const BoxConstraints(maxWidth: 80));

      expect(render.value.hasContent, isFalse);
      expect(registrar.removed, [render]);
    });
  });
}

class _FakeRegistrar implements SelectionRegistrar {
  final added = <Selectable>[];
  final removed = <Selectable>[];

  @override
  void add(Selectable selectable) => added.add(selectable);

  @override
  void remove(Selectable selectable) => removed.add(selectable);
}
