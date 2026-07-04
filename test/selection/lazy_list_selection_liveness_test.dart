import 'package:nocterm/nocterm.dart'
    hide Selectable, SelectionArea, RenderSelectionArea;
import 'package:nocterm/src/selection/selection.dart';
import 'package:nocterm/src/selection/selection_area.dart';
import 'package:nocterm/src/text/text_layout_engine.dart';
import 'package:test/test.dart';

/// Tracks which item render objects are currently alive so a test can tell
/// "kept alive off-screen" apart from "torn down and gone".
final Set<int> liveItems = {};
final Set<int> disposedItems = {};

class _TrackedText extends RenderObject
    with Selectable, SelectionRegistrant, TextSelectable {
  _TrackedText(this._text, this.index) {
    liveItems.add(index);
  }

  final int index;
  String _text;
  @override
  String get selectableText => _text;
  set text(String value) {
    if (_text == value) return;
    _text = value;
    markNeedsLayout();
  }

  TextLayoutResult? _layout;
  @override
  TextLayoutResult? get selectableLayout => _layout;

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void performLayout() {
    _layout = TextLayoutEngine.layout(
      _text,
      TextLayoutConfig(maxWidth: constraints.maxWidth.toInt()),
    );
    size = constraints.constrain(Size(
      _layout!.actualWidth.toDouble(),
      _layout!.actualHeight.toDouble(),
    ));
    didLayoutSelectableText();
  }

  @override
  void dispose() {
    liveItems.remove(index);
    disposedItems.add(index);
    super.dispose();
  }
}

class _TrackedTextComponent extends SingleChildRenderObjectComponent {
  const _TrackedTextComponent(this.index);
  final int index;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _TrackedText('item$index', index)
      ..registrar = SelectionRegistrarScope.maybeOf(context);
  }

  @override
  void updateRenderObject(BuildContext context, _TrackedText renderObject) {
    renderObject
      ..text = 'item$index'
      ..registrar = SelectionRegistrarScope.maybeOf(context);
  }
}

Future<void> _selectFirstFourRows(NoctermTester tester) async {
  await tester.press(0, 0);
  await tester.sendMouseEvent(const MouseEvent(
    button: MouseButton.left,
    x: 5,
    y: 3,
    pressed: true,
    isMotion: true,
  ));
  await tester.release(5, 3);
}

void main() {
  setUp(() {
    liveItems.clear();
    disposedItems.clear();
  });

  test('a selection scrolled off-screen is retained because the items are '
      'kept alive, not because the text is snapshotted', () async {
    await testNocterm(
      'kept-alive liveness',
      // Tall enough that selecting rows 0..3 (y=3) sits in the neutral
      // middle and does not trip edge auto-scroll.
      size: const Size(20, 10),
      (tester) async {
        final controller = ScrollController();
        String? changed;

        await tester.pumpComponent(
          SelectionArea(
            onSelectionChanged: (t) => changed = t,
            child: ListView.builder(
              controller: controller,
              lazy: true,
              cacheExtent: 1,
              itemCount: 500,
              itemBuilder: (context, index) => _TrackedTextComponent(index),
            ),
          ),
        );

        await _selectFirstFourRows(tester);
        expect(changed, 'item0\nitem1\nitem2\nitem3');

        // Scroll the selected items far out of the build+cache window.
        controller.jumpTo(300);
        await tester.pump();
        await tester.pump();

        expect(changed, 'item0\nitem1\nitem2\nitem3');
        // The text survives precisely because the items are still alive.
        expect(liveItems.containsAll({0, 1, 2, 3}), isTrue);
        expect(disposedItems.intersection({0, 1, 2, 3}).isEmpty, isTrue,
            reason: 'a selected item was disposed while its text lingered');

        // Bringing them back leaves the selection intact.
        controller.jumpTo(0);
        await tester.pump();
        await tester.pump();
        expect(changed, 'item0\nitem1\nitem2\nitem3');
      },
    );
  });

  test('items removed from the data are disposed and stop contributing their '
      'text to the selection', () async {
    await testNocterm(
      'itemCount shrink liveness',
      size: const Size(20, 6),
      (tester) async {
        String? changed;

        await tester.pumpComponent(
          SelectionArea(
            onSelectionChanged: (t) => changed = t,
            child: const _ShrinkableList(),
          ),
        );

        await _selectFirstFourRows(tester);
        expect(changed, 'item0\nitem1\nitem2\nitem3');

        // The data shrinks in place so items 2..499 no longer exist. This
        // exercises the itemCount-shrink path in _ListViewportElement.update
        // with a stable element tree (setState only).
        _ShrinkableListState.instance!.shrinkTo(2);
        await tester.pump();
        await tester.pump();

        // The gone items must be disposed (not leaked and kept alive by the
        // selection keep-alive heuristic)...
        expect({2, 3}.where(liveItems.contains).isEmpty, isTrue,
            reason: 'items removed from the data were kept alive');
        expect(disposedItems.containsAll({2, 3}), isTrue);
        // ...and the selection degrades to just the surviving items rather
        // than retaining stale text from items that are no longer around.
        expect(changed, 'item0\nitem1');
      },
    );
  });
}

class _ShrinkableList extends StatefulComponent {
  const _ShrinkableList();
  @override
  State<_ShrinkableList> createState() => _ShrinkableListState();
}

class _ShrinkableListState extends State<_ShrinkableList> {
  static _ShrinkableListState? instance;
  int _count = 500;

  void shrinkTo(int count) => setState(() => _count = count);

  @override
  void initState() {
    super.initState();
    instance = this;
  }

  @override
  void dispose() {
    if (instance == this) instance = null;
    super.dispose();
  }

  @override
  Component build(BuildContext context) {
    return ListView.builder(
      lazy: true,
      cacheExtent: 1,
      itemCount: _count,
      itemBuilder: (context, index) => _TrackedTextComponent(index),
    );
  }
}
