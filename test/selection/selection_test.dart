import 'package:nocterm/src/framework/framework.dart';
import 'package:nocterm/src/rectangle.dart';
import 'package:nocterm/src/selection/selection.dart';
import 'package:test/test.dart';

class _FakeRegistrar implements SelectionRegistrar {
  final added = <Selectable>[];
  final removed = <Selectable>[];

  @override
  void add(Selectable selectable) => added.add(selectable);

  @override
  void remove(Selectable selectable) => removed.add(selectable);
}

class _TestSelectable extends RenderObject
    with Selectable, SelectionRegistrant {
  @override
  void performLayout() {}

  @override
  Offset get globalPaintOffset => Offset.zero;

  @override
  Rect get globalBounds => const Rect.fromLTWH(0, 0, 0, 0);

  @override
  SelectionResult dispatchSelectionEvent(SelectionEvent event) =>
      SelectionResult.none;

  @override
  SelectedContent? getSelectedContent() => null;

  @override
  int get contentLength => 0;

  void setGeometry(SelectionGeometry geometry) =>
      updateSelectionGeometry(geometry);
}

const _emptyGeometry = SelectionGeometry(
  status: SelectionStatus.none,
  hasContent: false,
);

const _contentGeometry = SelectionGeometry(
  status: SelectionStatus.none,
  hasContent: true,
);

void main() {
  group('SelectionUtils.getResultBasedOnRect', () {
    // Covers rows 1-2, columns 2-6.
    const rect = Rect.fromLTWH(2, 1, 5, 2);

    test('point inside returns end', () {
      expect(SelectionUtils.getResultBasedOnRect(rect, const Offset(3, 1)),
          SelectionResult.end);
      expect(SelectionUtils.getResultBasedOnRect(rect, const Offset(6, 2)),
          SelectionResult.end);
    });

    test('point above returns previous', () {
      expect(SelectionUtils.getResultBasedOnRect(rect, const Offset(3, 0)),
          SelectionResult.previous);
    });

    test('point below returns next', () {
      expect(SelectionUtils.getResultBasedOnRect(rect, const Offset(3, 3)),
          SelectionResult.next);
    });

    test('point right of rect on same rows returns next', () {
      expect(SelectionUtils.getResultBasedOnRect(rect, const Offset(7, 1)),
          SelectionResult.next);
      expect(SelectionUtils.getResultBasedOnRect(rect, const Offset(10, 2)),
          SelectionResult.next);
    });

    test('point left of rect on same rows returns previous', () {
      expect(SelectionUtils.getResultBasedOnRect(rect, const Offset(1, 2)),
          SelectionResult.previous);
      expect(SelectionUtils.getResultBasedOnRect(rect, const Offset(0, 1)),
          SelectionResult.previous);
    });
  });

  group('SelectionUtils.adjustDragOffset', () {
    const rect = Rect.fromLTWH(2, 1, 5, 2);

    test('point inside is unchanged', () {
      expect(SelectionUtils.adjustDragOffset(rect, const Offset(4, 2)),
          const Offset(4, 2));
    });

    test('a point above the element maps to its start', () {
      expect(SelectionUtils.adjustDragOffset(rect, const Offset(4, 0)),
          const Offset(2, 1));
      // Above and to the left is still "before the start".
      expect(SelectionUtils.adjustDragOffset(rect, const Offset(0, 0)),
          const Offset(2, 1));
    });

    test('a point below the element maps to its end', () {
      expect(SelectionUtils.adjustDragOffset(rect, const Offset(4, 5)),
          const Offset(7, 2));
      // Below and to the right is still "past the end".
      expect(SelectionUtils.adjustDragOffset(rect, const Offset(9, 9)),
          const Offset(7, 2));
    });

    test('a point beside the element keeps the row it is level with', () {
      // Left of the element at row 2 → start of row 2, not the top corner.
      expect(SelectionUtils.adjustDragOffset(rect, const Offset(0, 2)),
          const Offset(2, 2));
      // Right of the element at row 1 → end of row 1, not the bottom corner.
      expect(SelectionUtils.adjustDragOffset(rect, const Offset(9, 1)),
          const Offset(7, 1));
    });
  });

  group('SelectionGeometry', () {
    test('equality includes selection rects', () {
      const a = SelectionGeometry(
        status: SelectionStatus.uncollapsed,
        hasContent: true,
        selectionRects: [Rect.fromLTWH(0, 0, 3, 1)],
      );
      const b = SelectionGeometry(
        status: SelectionStatus.uncollapsed,
        hasContent: true,
        selectionRects: [Rect.fromLTWH(0, 0, 3, 1)],
      );
      const c = SelectionGeometry(
        status: SelectionStatus.uncollapsed,
        hasContent: true,
        selectionRects: [Rect.fromLTWH(0, 0, 4, 1)],
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });

    test('copyWith preserves unspecified fields', () {
      const original = SelectionGeometry(
        status: SelectionStatus.collapsed,
        hasContent: true,
        startSelectionPoint: SelectionPoint(localPosition: Offset(1, 0)),
      );
      final copy = original.copyWith(status: SelectionStatus.uncollapsed);
      expect(copy.status, SelectionStatus.uncollapsed);
      expect(copy.hasContent, isTrue);
      expect(copy.startSelectionPoint,
          const SelectionPoint(localPosition: Offset(1, 0)));
    });
  });

  group('Selectable geometry notifications', () {
    test('notifies listeners when geometry changes', () {
      final selectable = _TestSelectable();
      var notifications = 0;
      selectable.addListener(() => notifications++);

      selectable.setGeometry(_contentGeometry);
      expect(notifications, 1);
      expect(selectable.value, _contentGeometry);
    });

    test('does not notify when geometry is unchanged', () {
      final selectable = _TestSelectable();
      var notifications = 0;
      selectable.addListener(() => notifications++);

      selectable.setGeometry(_contentGeometry);
      selectable.setGeometry(_contentGeometry);
      expect(notifications, 1);
    });

    test('removed listeners are not notified', () {
      final selectable = _TestSelectable();
      var notifications = 0;
      void listener() => notifications++;
      selectable.addListener(listener);
      selectable.removeListener(listener);

      selectable.setGeometry(_contentGeometry);
      expect(notifications, 0);
    });
  });

  group('SelectionRegistrant', () {
    test('does not register while there is no content', () {
      final registrar = _FakeRegistrar();
      final selectable = _TestSelectable();

      selectable.registrar = registrar;
      expect(registrar.added, isEmpty);
    });

    test('registers when content appears and unregisters when it goes', () {
      final registrar = _FakeRegistrar();
      final selectable = _TestSelectable();
      selectable.registrar = registrar;

      selectable.setGeometry(_contentGeometry);
      expect(registrar.added, [selectable]);

      selectable.setGeometry(_emptyGeometry);
      expect(registrar.removed, [selectable]);
    });

    test('registers immediately when set while content exists', () {
      final registrar = _FakeRegistrar();
      final selectable = _TestSelectable();
      selectable.setGeometry(_contentGeometry);

      selectable.registrar = registrar;
      expect(registrar.added, [selectable]);
    });

    test('does not register twice for repeated geometry updates', () {
      final registrar = _FakeRegistrar();
      final selectable = _TestSelectable();
      selectable.registrar = registrar;

      selectable.setGeometry(_contentGeometry);
      selectable.setGeometry(_contentGeometry.copyWith(
        status: SelectionStatus.uncollapsed,
        selectionRects: const [Rect.fromLTWH(0, 0, 1, 1)],
      ));
      expect(registrar.added, [selectable]);
    });

    test('unregisters when the registrar is cleared', () {
      final registrar = _FakeRegistrar();
      final selectable = _TestSelectable();
      selectable.registrar = registrar;
      selectable.setGeometry(_contentGeometry);

      selectable.registrar = null;
      expect(registrar.removed, [selectable]);
    });

    test('moves registration when the registrar is replaced', () {
      final first = _FakeRegistrar();
      final second = _FakeRegistrar();
      final selectable = _TestSelectable();
      selectable.registrar = first;
      selectable.setGeometry(_contentGeometry);

      selectable.registrar = second;
      expect(first.removed, [selectable]);
      expect(second.added, [selectable]);
    });

    test('unregisters on dispose', () {
      final registrar = _FakeRegistrar();
      final selectable = _TestSelectable();
      selectable.registrar = registrar;
      selectable.setGeometry(_contentGeometry);

      selectable.dispose();
      expect(registrar.removed, [selectable]);
    });
  });
}
