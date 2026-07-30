import 'package:nocterm/nocterm.dart';
import 'package:test/test.dart';

/// Viewport rows for every test terminal.
const double _viewportHeight = 10;

const double _wide = 60;
const double _narrow = 30;

const Size _terminalSize = Size(80, _viewportHeight);

/// One list item: `item N` on its first row, `cont N` on each row after, so
/// every terminal row identifies both its item and whether it is the item's
/// leading edge.
Component _item(int index, int height) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('item $index'),
        for (var row = 1; row < height; row++) Text('cont $index'),
      ],
    );

/// A list pinned to [width] whose item heights are a function of that width,
/// standing in for text that re-wraps taller as its pane narrows.
Component _list({
  required double width,
  required ScrollController controller,
  int itemCount = 30,
  int Function(int index, double width)? height,
  bool lazy = false,
  double cacheExtent = 0,
  EdgeInsets? padding,
  bool reverse = false,
}) {
  final rows = height ?? (index, width) => width <= _narrow ? 2 : 1;
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: width,
        child: ListView.builder(
          controller: controller,
          lazy: lazy,
          cacheExtent: cacheExtent,
          padding: padding,
          reverse: reverse,
          itemCount: itemCount,
          itemBuilder: (context, index) => _item(index, rows(index, width)),
        ),
      ),
      Expanded(child: SizedBox()),
    ],
  );
}

/// An item whose every row names itself, for asserting exactly which row of
/// a tall item sits at the viewport top.
Component _deepItem(int index, int height) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var row = 0; row < height; row++) Text('i$index r$row'),
      ],
    );

/// A list whose first item towers over the viewport — eight rows wide,
/// sixteen narrow — trailed by short filler items.
Component _deepList({
  required double width,
  required ScrollController controller,
  bool lazy = false,
  double cacheExtent = 0,
}) {
  final giant = width <= _narrow ? 16 : 8;
  final small = width <= _narrow ? 2 : 1;
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: width,
        child: ListView.builder(
          controller: controller,
          lazy: lazy,
          cacheExtent: cacheExtent,
          itemCount: 20,
          itemBuilder: (context, index) =>
              _deepItem(index, index == 0 ? giant : small),
        ),
      ),
      Expanded(child: SizedBox()),
    ],
  );
}

/// A list whose first item wraps like 240 columns of prose — its height is
/// `ceil(240 / width)` — so single-column resizes grow it by a whisper at a
/// time, the shape that exposes per-step rounding drift.
Component _proseList({
  required double width,
  required ScrollController controller,
  bool lazy = false,
  double cacheExtent = 0,
  bool reverse = false,
}) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: width,
        child: ListView.builder(
          controller: controller,
          lazy: lazy,
          cacheExtent: cacheExtent,
          reverse: reverse,
          itemCount: 20,
          itemBuilder: (context, index) =>
              _deepItem(index, index == 0 ? (240 / width).ceil() : 1),
        ),
      ),
      Expanded(child: SizedBox()),
    ],
  );
}

/// Resizes the pane and shrinks the list in the same rebuild, the shape of a
/// chat being cleared mid-drag.
class _ShrinkHarness extends StatefulComponent {
  const _ShrinkHarness({required this.controller, super.key});

  final ScrollController controller;

  @override
  State<_ShrinkHarness> createState() => _ShrinkHarnessState();
}

class _ShrinkHarnessState extends State<_ShrinkHarness> {
  double _width = _wide;
  int _itemCount = 30;

  void apply({required double width, required int itemCount}) => setState(() {
        _width = width;
        _itemCount = itemCount;
      });

  @override
  Component build(BuildContext context) => _list(
        width: _width,
        controller: component.controller,
        itemCount: _itemCount,
      );
}

/// Hosts a width-parameterised subtree and resizes it in place via setState,
/// the way a pane splitter would. Replacing the root component instead would
/// remount the tree and hand the viewport a fresh render object with no
/// memory of the previous width.
class _ResizeHarness extends StatefulComponent {
  const _ResizeHarness({
    required this.initialWidth,
    required this.builder,
    super.key,
  });

  final double initialWidth;
  final Component Function(double width) builder;

  @override
  State<_ResizeHarness> createState() => _ResizeHarnessState();
}

class _ResizeHarnessState extends State<_ResizeHarness> {
  late double _width = component.initialWidth;

  void resize(double value) => setState(() => _width = value);

  @override
  Component build(BuildContext context) => component.builder(_width);
}

typedef _Resizable = ({
  GlobalKey<_ResizeHarnessState> key,
  Component component,
});

_Resizable _resizable({
  required double initialWidth,
  required Component Function(double width) builder,
}) {
  final key = GlobalKey<_ResizeHarnessState>();
  return (
    key: key,
    component: _ResizeHarness(
      key: key,
      initialWidth: initialWidth,
      builder: builder,
    ),
  );
}

String _row(NoctermTester tester, int y) =>
    (tester.terminalState.getTextAt(0, y, length: 10) ?? '').trim();

String _topRow(NoctermTester tester) => _row(tester, 0);

String _bottomRow(NoctermTester tester) =>
    _row(tester, _viewportHeight.toInt() - 1);

/// A controller that refuses every correction, simulating a viewport and
/// controller that can never reach consensus on the offset.
class _StubbornController extends ScrollController {
  int corrections = 0;

  @override
  void correctBy(double correction) {
    corrections++;
  }
}

void main() {
  group('ScrollController.correctBy', () {
    test('shifts the offset without notifying listeners', () {
      final controller = ScrollController(initialScrollOffset: 5);
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.correctBy(3);

      expect(controller.offset, 8);
      expect(notifications, 0);
      controller.dispose();
    });

    test('shifts backwards as well as forwards', () {
      final controller = ScrollController(initialScrollOffset: 5);

      controller.correctBy(-3);

      expect(controller.offset, 2);
      controller.dispose();
    });

    test('is not clamped until updateMetrics runs', () {
      final controller = ScrollController();
      controller.updateMetrics(
        minScrollExtent: 0,
        maxScrollExtent: 10,
        viewportDimension: 5,
      );

      controller.correctBy(50);
      expect(controller.offset, 50);

      // The clamping call moves the offset, so the pass is rejected; the
      // re-submission is accepted.
      expect(
        controller.updateMetrics(
          minScrollExtent: 0,
          maxScrollExtent: 10,
          viewportDimension: 5,
        ),
        isFalse,
      );
      expect(controller.offset, 10);
      expect(
        controller.updateMetrics(
          minScrollExtent: 0,
          maxScrollExtent: 10,
          viewportDimension: 5,
        ),
        isTrue,
      );
      controller.dispose();
    });

    test('an accepted correction still notifies once metrics land', () {
      // An offset-only correction with unchanged metrics must not vanish:
      // listeners (scrollbars) show the offset, and it moved.
      final controller = ScrollController(initialScrollOffset: 2);
      controller.updateMetrics(
        minScrollExtent: 0,
        maxScrollExtent: 10,
        viewportDimension: 5,
      );
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.correctBy(3);
      expect(notifications, 0);

      controller.updateMetrics(
        minScrollExtent: 0,
        maxScrollExtent: 10,
        viewportDimension: 5,
      );
      expect(notifications, 1);
      controller.dispose();
    });
  });

  group('eager reflow anchoring', () {
    test('keeps the top item anchored when the pane narrows', () async {
      await testNocterm('narrow anchors', (tester) async {
        final controller = ScrollController();
        final harness = _resizable(
          initialWidth: _wide,
          builder: (width) => _list(width: width, controller: controller),
        );
        await tester.pumpComponent(harness.component);

        controller.jumpTo(5);
        await tester.pump();
        expect(_topRow(tester), 'item 5');

        harness.key.currentState!.resize(_narrow);
        await tester.pump();

        expect(controller.offset, 10);
        expect(_topRow(tester), 'item 5');
        controller.dispose();
      }, size: _terminalSize);
    });

    test('keeps the top item anchored when the pane widens', () async {
      await testNocterm('widen anchors', (tester) async {
        final controller = ScrollController();
        final harness = _resizable(
          initialWidth: _narrow,
          builder: (width) => _list(width: width, controller: controller),
        );
        await tester.pumpComponent(harness.component);

        controller.jumpTo(10);
        await tester.pump();
        expect(_topRow(tester), 'item 5');

        harness.key.currentState!.resize(_wide);
        await tester.pump();

        expect(controller.offset, 5);
        expect(_topRow(tester), 'item 5');
        controller.dispose();
      }, size: _terminalSize);
    });

    test('keeps the scrolled-past rows of the anchor item too', () async {
      // The viewport top sits one row inside a multi-row item. Each fixture
      // row is its own Text, so the anchor holds that very row — 'cont 2'
      // stays the top row at its new position, one row into the item.
      int tallOrTaller(int index, double width) => width <= _narrow ? 4 : 2;

      await testNocterm('mid-item anchor', (tester) async {
        final controller = ScrollController();
        final harness = _resizable(
          initialWidth: _wide,
          builder: (width) => _list(
            width: width,
            controller: controller,
            height: tallOrTaller,
          ),
        );
        await tester.pumpComponent(harness.component);

        controller.jumpTo(5);
        await tester.pump();
        expect(_topRow(tester), 'cont 2');

        harness.key.currentState!.resize(_narrow);
        await tester.pump();

        expect(controller.offset, 9);
        expect(_topRow(tester), 'cont 2');
        controller.dispose();
      }, size: _terminalSize);
    });

    test('clamps the remembered delta when the anchor item shrinks', () async {
      // Two rows into a three-row item, then the reflow shrinks the item to
      // one row: the viewport lands at the item's end, not beyond it.
      int shrinking(int index, double width) => width <= _narrow ? 3 : 1;

      await testNocterm('shrunk anchor', (tester) async {
        final controller = ScrollController();
        final harness = _resizable(
          initialWidth: _narrow,
          builder: (width) => _list(
            width: width,
            controller: controller,
            height: shrinking,
          ),
        );
        await tester.pumpComponent(harness.component);

        controller.jumpTo(8);
        await tester.pump();
        expect(_topRow(tester), 'cont 2');

        harness.key.currentState!.resize(_wide);
        await tester.pump();

        expect(controller.offset, 3);
        expect(_topRow(tester), 'item 3');
        controller.dispose();
      }, size: _terminalSize);
    });

    test('holds place inside an item taller than the viewport', () async {
      // A chat message longer than the screen: the viewport top is deep
      // inside item 0. Each fixture row is a distinct Text, so 'i0 r4' is
      // real content — and content-addressed anchoring keeps that very row
      // on top at its unchanged depth. (Genuinely re-wrapping prose, where
      // the same words land on a different row, is covered by the wrapped
      // prose suite.)
      await testNocterm('giant item', (tester) async {
        final controller = ScrollController();
        final harness = _resizable(
          initialWidth: _wide,
          builder: (width) => _deepList(width: width, controller: controller),
        );
        await tester.pumpComponent(harness.component);

        controller.jumpTo(4);
        await tester.pump();
        expect(_topRow(tester), 'i0 r4');

        harness.key.currentState!.resize(_narrow);
        await tester.pump();

        expect(controller.offset, 4);
        expect(_topRow(tester), 'i0 r4');
        controller.dispose();
      }, size: _terminalSize);
    });

    test('a column-by-column drag lands where a single jump does', () async {
      // A real drag resizes one column per frame. The anchored row 'i0 r2'
      // is held by identity and character, neither of which rounds, so a
      // thirty-step drag and a single jump land on the identical offset.
      await testNocterm('stepped drag', (tester) async {
        final controller = ScrollController();
        final harness = _resizable(
          initialWidth: _wide,
          builder: (width) => _proseList(width: width, controller: controller),
        );
        await tester.pumpComponent(harness.component);

        controller.jumpTo(2);
        await tester.pump();
        expect(_topRow(tester), 'i0 r2');

        for (var width = _wide - 1; width >= _narrow; width--) {
          harness.key.currentState!.resize(width);
          await tester.pump();
        }

        expect(controller.offset, 2);
        expect(_topRow(tester), 'i0 r2');
        controller.dispose();
      }, size: _terminalSize);
    });

    test('scrolling between resizes recaptures the anchor', () async {
      await testNocterm('scroll resets gesture', (tester) async {
        final controller = ScrollController();
        final harness = _resizable(
          initialWidth: _wide,
          builder: (width) => _proseList(width: width, controller: controller),
        );
        await tester.pumpComponent(harness.component);

        controller.jumpTo(2);
        await tester.pump();

        harness.key.currentState!.resize(40);
        await tester.pump();
        expect(controller.offset, 2);

        // The user scrolls: the old gesture's anchor no longer describes
        // what they see, so the next resize must anchor afresh.
        controller.jumpTo(5);
        await tester.pump();

        harness.key.currentState!.resize(_narrow);
        await tester.pump();

        // The fresh capture holds row 'i0 r5', not the stale 'i0 r2'.
        expect(controller.offset, 5);
        expect(_topRow(tester), 'i0 r5');
        controller.dispose();
      }, size: _terminalSize);
    });

    test('leaves an unscrolled list at the top', () async {
      await testNocterm('top stays top', (tester) async {
        final controller = ScrollController();
        final harness = _resizable(
          initialWidth: _wide,
          builder: (width) => _list(width: width, controller: controller),
        );
        await tester.pumpComponent(harness.component);

        harness.key.currentState!.resize(_narrow);
        await tester.pump();

        expect(controller.offset, 0);
        expect(_topRow(tester), 'item 0');
        controller.dispose();
      }, size: _terminalSize);
    });

    test('stays glued to the tail when pinned at the bottom', () async {
      await testNocterm('bottom stays pinned', (tester) async {
        final controller = AutoScrollController();
        final harness = _resizable(
          initialWidth: _wide,
          builder: (width) => _list(width: width, controller: controller),
        );
        await tester.pumpComponent(harness.component);

        controller.jumpTo(controller.maxScrollExtent);
        await tester.pump();
        expect(_bottomRow(tester), 'item 29');

        // The bottom pin corrects inside the layout loop: one frame, no
        // adrift paint for the controller to fix up afterwards.
        harness.key.currentState!.resize(_narrow);
        await tester.pump();

        expect(controller.offset, controller.maxScrollExtent);
        expect(_bottomRow(tester), 'cont 29');
        controller.dispose();
      }, size: _terminalSize);
    });

    test('pins a plain controller to the bottom through a reflow', () async {
      // Not just AutoScrollController: any viewport reading the tail keeps
      // reading the tail — a reflow re-wraps the content you were on, and
      // at the bottom that content is the end.
      await testNocterm('plain bottom pinned', (tester) async {
        final controller = ScrollController();
        final harness = _resizable(
          initialWidth: _wide,
          builder: (width) => _list(width: width, controller: controller),
        );
        await tester.pumpComponent(harness.component);

        controller.jumpTo(controller.maxScrollExtent);
        await tester.pump();
        expect(_bottomRow(tester), 'item 29');

        harness.key.currentState!.resize(_narrow);
        await tester.pump();

        expect(controller.offset, controller.maxScrollExtent);
        expect(_bottomRow(tester), 'cont 29');
        controller.dispose();
      }, size: _terminalSize);
    });

    test('does nothing when the width has not changed', () async {
      await testNocterm('same width', (tester) async {
        final controller = ScrollController();
        final harness = _resizable(
          initialWidth: _wide,
          builder: (width) => _list(width: width, controller: controller),
        );
        await tester.pumpComponent(harness.component);

        controller.jumpTo(5);
        await tester.pump();

        harness.key.currentState!.resize(_wide);
        await tester.pump();

        expect(controller.offset, 5);
        expect(_topRow(tester), 'item 5');
        controller.dispose();
      }, size: _terminalSize);
    });

    test('holds the anchor through repeated resizes', () async {
      await testNocterm('resize round trip', (tester) async {
        final controller = ScrollController();
        final harness = _resizable(
          initialWidth: _wide,
          builder: (width) => _list(width: width, controller: controller),
        );
        await tester.pumpComponent(harness.component);

        controller.jumpTo(5);
        await tester.pump();

        for (final width in [_narrow, _wide, _narrow, _wide]) {
          harness.key.currentState!.resize(width);
          await tester.pump();
          expect(_topRow(tester), 'item 5', reason: 'width $width');
        }

        expect(controller.offset, 5);
        controller.dispose();
      }, size: _terminalSize);
    });

    test('survives the anchor item vanishing mid-gesture', () async {
      // A resize and a list shrink land in the same rebuild — the anchored
      // item may no longer exist by the time the reflow lays out. The
      // correction gives up gracefully and the clamp takes over.
      await testNocterm('shrinking list', (tester) async {
        final controller = ScrollController();
        final key = GlobalKey<_ShrinkHarnessState>();
        await tester.pumpComponent(
          _ShrinkHarness(key: key, controller: controller),
        );

        controller.jumpTo(15);
        await tester.pump();
        expect(_topRow(tester), 'item 15');

        key.currentState!.apply(width: _narrow, itemCount: 10);
        await tester.pump();

        expect(
            controller.offset, lessThanOrEqualTo(controller.maxScrollExtent));
        expect(tester.terminalState, containsText('item 9'));
        controller.dispose();
      }, size: _terminalSize);
    });

    test('anchors identically inside a padded list', () async {
      // Padding deflates the viewport and offsets the paint, but layout
      // offsets and the scroll offset both live in content space — the
      // anchor must not mix the two up.
      await testNocterm('padded anchors', (tester) async {
        final controller = ScrollController();
        final harness = _resizable(
          initialWidth: _wide,
          builder: (width) => _list(
            width: width,
            controller: controller,
            padding: const EdgeInsets.all(1),
          ),
        );
        await tester.pumpComponent(harness.component);

        controller.jumpTo(5);
        await tester.pump();
        expect(tester.terminalState.getTextAt(1, 1, length: 6), 'item 5');

        harness.key.currentState!.resize(_narrow);
        await tester.pump();

        expect(controller.offset, 10);
        expect(tester.terminalState.getTextAt(1, 1, length: 6), 'item 5');
        controller.dispose();
      }, size: _terminalSize);
    });

    test('a widening drag that runs out of content yields to the clamp',
        () async {
      // Widening halves every item: the offset the anchor wants no longer
      // exists, so the metrics clamp wins and the viewport lands at the new
      // bottom rather than in blank space.
      await testNocterm('widen past the end', (tester) async {
        final controller = ScrollController();
        final harness = _resizable(
          initialWidth: _narrow,
          builder: (width) => _list(width: width, controller: controller),
        );
        await tester.pumpComponent(harness.component);

        controller.jumpTo(45);
        await tester.pump();

        harness.key.currentState!.resize(_wide);
        await tester.pump();

        expect(controller.offset, controller.maxScrollExtent);
        expect(_bottomRow(tester), 'item 29');
        controller.dispose();
      }, size: _terminalSize);
    });

    test('a resize of an empty list is a no-op', () async {
      await testNocterm('empty list', (tester) async {
        final controller = ScrollController();
        final harness = _resizable(
          initialWidth: _wide,
          builder: (width) => _list(
            width: width,
            controller: controller,
            itemCount: 0,
          ),
        );
        await tester.pumpComponent(harness.component);

        harness.key.currentState!.resize(_narrow);
        await tester.pump();

        expect(controller.offset, 0);
        controller.dispose();
      }, size: _terminalSize);
    });

    test('a resize of a list that fits stays put', () async {
      await testNocterm('fitting list', (tester) async {
        final controller = ScrollController();
        final harness = _resizable(
          initialWidth: _wide,
          builder: (width) => _list(
            width: width,
            controller: controller,
            itemCount: 3,
          ),
        );
        await tester.pumpComponent(harness.component);

        harness.key.currentState!.resize(_narrow);
        await tester.pump();

        expect(controller.offset, 0);
        expect(_topRow(tester), 'item 0');
        controller.dispose();
      }, size: _terminalSize);
    });

    test('anchors through a separator sitting at the viewport top', () async {
      // The viewport top is a separator row: the anchor falls back to the
      // item above it, and the overrun depth clamps to that item's end —
      // which is exactly where its separator starts.
      await testNocterm('separator on top', (tester) async {
        final controller = ScrollController();
        final harness = _resizable(
          initialWidth: _wide,
          builder: (width) => Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: width,
                child: ListView.separated(
                  controller: controller,
                  itemCount: 30,
                  itemBuilder: (context, index) =>
                      _item(index, width <= _narrow ? 2 : 1),
                  separatorBuilder: (context, index) => const Text('---'),
                ),
              ),
              Expanded(child: SizedBox()),
            ],
          ),
        );
        await tester.pumpComponent(harness.component);

        controller.jumpTo(11);
        await tester.pump();
        expect(_topRow(tester), '---');

        harness.key.currentState!.resize(_narrow);
        await tester.pump();

        expect(controller.offset, 17);
        expect(_topRow(tester), '---');
        controller.dispose();
      }, size: _terminalSize);
    });

    test('anchors a separated list across its separators', () async {
      await testNocterm('separated anchors', (tester) async {
        final controller = ScrollController();
        final harness = _resizable(
          initialWidth: _wide,
          builder: (width) => Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: width,
                child: ListView.separated(
                  controller: controller,
                  itemCount: 30,
                  itemBuilder: (context, index) =>
                      _item(index, width <= _narrow ? 2 : 1),
                  separatorBuilder: (context, index) => const Text('---'),
                ),
              ),
              Expanded(child: SizedBox()),
            ],
          ),
        );
        await tester.pumpComponent(harness.component);

        // One item row plus one separator row per item wide: row 10 is item 5.
        controller.jumpTo(10);
        await tester.pump();
        expect(_topRow(tester), 'item 5');

        harness.key.currentState!.resize(_narrow);
        await tester.pump();

        expect(_topRow(tester), 'item 5');
        controller.dispose();
      }, size: _terminalSize);
    });

  });

  group('reversed reflow anchoring', () {
    // In a reversed viewport the scroll offset is measured from the painted
    // bottom, so the anchor edge — and every expectation here — is the
    // bottom row. Layout depth d inside an item of extent E paints at row
    // E - 1 - d from the item's own top; the anchor holds content through
    // that mirror.
    test('keeps the bottom-edge item anchored when the pane narrows',
        () async {
      await testNocterm('reversed narrow anchors', (tester) async {
        final controller = ScrollController();
        final harness = _resizable(
          initialWidth: _wide,
          builder: (width) => _list(
            width: width,
            controller: controller,
            reverse: true,
          ),
        );
        await tester.pumpComponent(harness.component);

        controller.jumpTo(5);
        await tester.pump();
        expect(_bottomRow(tester), 'item 5');

        harness.key.currentState!.resize(_narrow);
        await tester.pump();

        // Item 5 now spans layout [10, 12); its 'item 5' row is depth 1.
        expect(controller.offset, 11);
        expect(_bottomRow(tester), 'item 5');
        controller.dispose();
      }, size: _terminalSize);
    });

    test('offset zero glues the newest item to the bottom for free', () async {
      // The paint mirror itself pins item 0's tail to the bottom edge at
      // offset zero — anchoring must stand aside and let it.
      await testNocterm('reversed zero glued', (tester) async {
        final controller = ScrollController();
        final harness = _resizable(
          initialWidth: _wide,
          builder: (width) => _list(
            width: width,
            controller: controller,
            reverse: true,
          ),
        );
        await tester.pumpComponent(harness.component);
        expect(_bottomRow(tester), 'item 0');

        harness.key.currentState!.resize(_narrow);
        await tester.pump();

        expect(controller.offset, 0);
        expect(_row(tester, 8), 'item 0');
        expect(_bottomRow(tester), 'cont 0');
        controller.dispose();
      }, size: _terminalSize);
    });

    test('pins the oldest item to the top at maximum extent', () async {
      // The far edge of a reversed viewport is the painted top: scrolled all
      // the way back, the oldest item's first line holds the top row.
      await testNocterm('reversed max pinned', (tester) async {
        final controller = ScrollController();
        final harness = _resizable(
          initialWidth: _wide,
          builder: (width) => _list(
            width: width,
            controller: controller,
            reverse: true,
          ),
        );
        await tester.pumpComponent(harness.component);

        controller.jumpTo(controller.maxScrollExtent);
        await tester.pump();
        expect(_topRow(tester), 'item 29');

        harness.key.currentState!.resize(_narrow);
        await tester.pump();

        expect(controller.offset, controller.maxScrollExtent);
        expect(_topRow(tester), 'item 29');
        controller.dispose();
      }, size: _terminalSize);
    });

    test('a column-by-column drag holds the bottom row', () async {
      // The gesture anchor and the row mirror together: the held row
      // 'i0 r1' is content-addressed, so thirty single-column reflows land
      // it exactly where one jump would.
      await testNocterm('reversed stepped drag', (tester) async {
        final controller = ScrollController();
        final harness = _resizable(
          initialWidth: _wide,
          builder: (width) => _proseList(
            width: width,
            controller: controller,
            reverse: true,
          ),
        );
        await tester.pumpComponent(harness.component);

        controller.jumpTo(2);
        await tester.pump();
        expect(_bottomRow(tester), 'i0 r1');

        for (var width = _wide - 1; width >= _narrow; width--) {
          harness.key.currentState!.resize(width);
          await tester.pump();
        }

        // Narrow, item 0 is 8 rows: row 1 from its top is layout depth 6.
        expect(controller.offset, 6);
        expect(_bottomRow(tester), 'i0 r1');
        controller.dispose();
      }, size: _terminalSize);
    });

    test('keeps the bottom-edge item anchored in lazy mode', () async {
      await testNocterm('reversed lazy anchors', (tester) async {
        final controller = ScrollController();
        final harness = _resizable(
          initialWidth: _wide,
          builder: (width) => _list(
            width: width,
            controller: controller,
            itemCount: 40,
            lazy: true,
            cacheExtent: 5,
            reverse: true,
          ),
        );
        await tester.pumpComponent(harness.component);

        controller.jumpTo(15);
        await tester.pump();
        expect(_bottomRow(tester), 'item 15');

        harness.key.currentState!.resize(_narrow);
        await tester.pump();

        expect(controller.offset, 16);
        expect(_bottomRow(tester), 'item 15');
        controller.dispose();
      }, size: _terminalSize);
    });
  });

  group('lazy reflow anchoring', () {
    test('a column-by-column drag lands where a single jump does', () async {
      // The gesture-held anchor and the lazy seed together: every step
      // re-seeds the anchor item at the position it was first captured at,
      // and the held row 'i0 r2' resolves exactly with nothing to round.
      await testNocterm('lazy stepped drag', (tester) async {
        final controller = ScrollController();
        final harness = _resizable(
          initialWidth: _wide,
          builder: (width) => _proseList(
            width: width,
            controller: controller,
            lazy: true,
            cacheExtent: 5,
          ),
        );
        await tester.pumpComponent(harness.component);

        controller.jumpTo(2);
        await tester.pump();
        expect(_topRow(tester), 'i0 r2');

        for (var width = _wide - 1; width >= _narrow; width--) {
          harness.key.currentState!.resize(width);
          await tester.pump();
        }

        expect(controller.offset, 2);
        expect(_topRow(tester), 'i0 r2');
        controller.dispose();
      }, size: _terminalSize);
    });

    test('keeps the top item anchored when the pane narrows', () async {
      await testNocterm('lazy narrow anchors', (tester) async {
        final controller = ScrollController();
        final harness = _resizable(
          initialWidth: _wide,
          builder: (width) => _list(
            width: width,
            controller: controller,
            itemCount: 40,
            lazy: true,
            cacheExtent: 5,
          ),
        );
        await tester.pumpComponent(harness.component);

        controller.jumpTo(15);
        await tester.pump();
        expect(_topRow(tester), 'item 15');

        harness.key.currentState!.resize(_narrow);
        await tester.pump();

        // Lazy offsets are dead reckoning: the layout is seeded so the
        // anchored item keeps its old position, and the offset never moves.
        expect(_topRow(tester), 'item 15');
        expect(controller.offset, 15);
        controller.dispose();
      }, size: _terminalSize);
    });

    test('anchors across a reflow that triples every item', () async {
      // Tripling every item would push the anchor far outside anything a
      // stale-offset search could build; seeding the pass at the anchor
      // makes the size of the reflow irrelevant.
      int oneOrThree(int index, double width) => width <= _narrow ? 3 : 1;

      await testNocterm('lazy long jump', (tester) async {
        final controller = ScrollController();
        final harness = _resizable(
          initialWidth: _wide,
          builder: (width) => _list(
            width: width,
            controller: controller,
            itemCount: 100,
            height: oneOrThree,
            lazy: true,
            cacheExtent: 10,
          ),
        );
        await tester.pumpComponent(harness.component);

        controller.jumpTo(20);
        await tester.pump();
        expect(_topRow(tester), 'item 20');

        harness.key.currentState!.resize(_narrow);
        await tester.pump();

        expect(_topRow(tester), 'item 20');
        expect(controller.offset, 20);
        controller.dispose();
      }, size: _terminalSize);
    });

    test('holds place inside an item taller than the viewport', () async {
      // The lazy seed pins the giant item's top; the anchored row 'i0 r4'
      // — a distinct Text at both widths — then resolves at its unchanged
      // depth inside it.
      await testNocterm('lazy giant item', (tester) async {
        final controller = ScrollController();
        final harness = _resizable(
          initialWidth: _wide,
          builder: (width) => _deepList(
            width: width,
            controller: controller,
            lazy: true,
            cacheExtent: 5,
          ),
        );
        await tester.pumpComponent(harness.component);

        controller.jumpTo(4);
        await tester.pump();
        expect(_topRow(tester), 'i0 r4');

        harness.key.currentState!.resize(_narrow);
        await tester.pump();

        expect(controller.offset, 4);
        expect(_topRow(tester), 'i0 r4');
        controller.dispose();
      }, size: _terminalSize);
    });

    test('stays glued to the tail when pinned at the bottom', () async {
      await testNocterm('lazy bottom pinned', (tester) async {
        final controller = AutoScrollController();
        final harness = _resizable(
          initialWidth: _wide,
          builder: (width) => _list(
            width: width,
            controller: controller,
            itemCount: 40,
            lazy: true,
            cacheExtent: 5,
          ),
        );
        await tester.pumpComponent(harness.component);

        controller.jumpTo(controller.maxScrollExtent);
        await tester.pump();
        expect(_bottomRow(tester), 'item 39');

        // The bottom pin re-reads each lazy pass's own extent estimate, so
        // even dead-reckoned metrics land the tail in a single frame.
        harness.key.currentState!.resize(_narrow);
        await tester.pump();

        expect(controller.offset, controller.maxScrollExtent);
        expect(_bottomRow(tester), 'cont 39');
        controller.dispose();
      }, size: _terminalSize);
    });
  });

  group('layout cycle cap', () {
    test('a controller that refuses corrections cannot loop layout', () async {
      // A refused correction can never converge: the cap ends the layout
      // with the offset as the controller left it, and — mirroring
      // Flutter's viewport — the missing consensus is a reported error in
      // debug builds, not a silent shrug.
      final reported = <Object>[];
      final previousHandler = NoctermError.onError;
      NoctermError.onError = (details) => reported.add(details.exception);
      try {
        await testNocterm('stubborn controller', (tester) async {
          final controller = _StubbornController();
          final harness = _resizable(
            initialWidth: _wide,
            builder: (width) => _list(width: width, controller: controller),
          );
          await tester.pumpComponent(harness.component);

          controller.jumpTo(5);
          await tester.pump();

          harness.key.currentState!.resize(_narrow);
          await tester.pump();

          expect(controller.corrections, greaterThan(0));
          expect(controller.corrections, lessThan(10));
          expect(controller.offset, 5);
          final errors = reported.whereType<FlutterError>().toList();
          expect(errors.length, greaterThan(0));
          expect(
            errors.first.toString(),
            contains('maximum number of layout cycles'),
          );
          controller.dispose();
        }, size: _terminalSize);
      } finally {
        NoctermError.onError = previousHandler;
      }
    });
  });
}
