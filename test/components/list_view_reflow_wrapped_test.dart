import 'package:nocterm/nocterm.dart';
import 'package:test/test.dart';

/// Viewport rows for every test terminal.
const double _viewportHeight = 10;

const double _wide = 60;
const double _narrow = 30;

const Size _terminalSize = Size(80, _viewportHeight);

/// Numbered prose whose word lengths change halfway through: sixty short
/// words then sixty long ones. Wrap growth is non-uniform — the long half
/// gains far more rows as the pane narrows than the short half — which is
/// exactly the shape a proportional depth estimate misjudges and
/// content-addressed anchoring holds.
final String _prose = List.generate(
  120,
  (index) {
    final word = 'w${index.toString().padLeft(3, '0')}';
    return index < 60 ? word : '${word}xxxxxx';
  },
).join(' ');

/// The wall-of-text item shape: one giant wrapping paragraph, trailed by
/// short filler items.
Component _wallList({
  required double width,
  required ScrollController controller,
  bool lazy = false,
  double cacheExtent = 0,
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
          itemCount: 6,
          itemBuilder: (context, index) =>
              index == 0 ? Text(_prose) : Text('tail $index'),
        ),
      ),
      Expanded(child: SizedBox()),
    ],
  );
}

/// The details pane's shape: a padded item holding a short label paragraph
/// above the giant wrapping value paragraph.
Component _detailList({
  required double width,
  required ScrollController controller,
}) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: width,
        child: ListView.builder(
          controller: controller,
          itemCount: 4,
          itemBuilder: (context, index) => index == 0
              ? Padding(
                  padding: const EdgeInsets.only(left: 1),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Output'),
                      Text(_prose),
                    ],
                  ),
                )
              : Text('tail $index'),
        ),
      ),
      Expanded(child: SizedBox()),
    ],
  );
}

/// An item with a blank spacer row between two paragraphs, the markdown
/// block-gap shape; the first paragraph re-wraps taller as the pane narrows.
Component _gapList({
  required double width,
  required ScrollController controller,
}) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: width,
        child: ListView.builder(
          controller: controller,
          // Enough tail rows that the gap row can reach the viewport top.
          itemCount: 16,
          itemBuilder: (context, index) => index == 0
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_prose),
                    const SizedBox(height: 1),
                    Text('below the gap'),
                  ],
                )
              : Text('tail $index'),
        ),
      ),
      Expanded(child: SizedBox()),
    ],
  );
}

/// The first `wNNN` word on terminal row [y], or null.
String? _wordAt(NoctermTester tester, int y) {
  final text = tester.terminalState.getTextAt(0, y, length: 40) ?? '';
  return RegExp(r'w\d\d\d').firstMatch(text)?.group(0);
}

/// The full text of terminal row [y].
String _rowText(NoctermTester tester, int y) =>
    tester.terminalState.getTextAt(0, y, length: 40) ?? '';

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
  double? _width;

  void resize(double value) => setState(() => _width = value);

  @override
  Component build(BuildContext context) {
    return component.builder(_width ?? component.initialWidth);
  }
}

({GlobalKey<_ResizeHarnessState> key, Component component}) _resizable({
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

/// Swaps the wall item for entirely different content mid-gesture.
class _SwapHarness extends StatefulComponent {
  const _SwapHarness({required this.controller, super.key});

  final ScrollController controller;

  @override
  State<_SwapHarness> createState() => _SwapHarnessState();
}

class _SwapHarnessState extends State<_SwapHarness> {
  double _width = _wide;
  bool _swapped = false;

  void resizeAndSwap(double width) => setState(() {
        _width = width;
        _swapped = true;
      });

  @override
  Component build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: _width,
          child: ListView.builder(
            controller: component.controller,
            itemCount: 6,
            itemBuilder: (context, index) => index == 0
                ? (_swapped
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var row = 0; row < 12; row++)
                            Text('swapped $row'),
                        ],
                      )
                    : Text(_prose))
                : Text('tail $index'),
          ),
        ),
        Expanded(child: SizedBox()),
      ],
    );
  }
}

void main() {
  group('wrapped prose anchoring', () {
    for (final lazy in [false, true]) {
      test('holds the words at the top of a re-wrapping wall (lazy: $lazy)',
          () async {
        // The field case: a wall of text far taller than the viewport whose
        // wrap growth is non-uniform. The words at the viewport top must
        // still be on the top row after the reflow — the anchored character
        // is looked up in the new layout, not extrapolated.
        await testNocterm('wall anchor', (tester) async {
          final controller = ScrollController();
          final harness = _resizable(
            initialWidth: _wide,
            builder: (width) => _wallList(
              width: width,
              controller: controller,
              lazy: lazy,
              cacheExtent: lazy ? 5 : 0,
            ),
          );
          await tester.pumpComponent(harness.component);

          controller.jumpTo(9);
          await tester.pump();
          final word = _wordAt(tester, 0);
          expect(word, isNotNull);

          harness.key.currentState!.resize(_narrow);
          await tester.pump();

          expect(_rowText(tester, 0), contains(word!));
          controller.dispose();
        }, size: _terminalSize);
      });

      test(
          'a column-by-column drag over the wall never slides '
          '(lazy: $lazy)', () async {
        // Thirty single-column steps, each a full reflow: the held anchor
        // carries a character, which never rounds, so the top row still
        // shows the anchored words after the whole gesture — and after
        // dragging back out again.
        await testNocterm('wall stepped drag', (tester) async {
          final controller = ScrollController();
          final harness = _resizable(
            initialWidth: _wide,
            builder: (width) => _wallList(
              width: width,
              controller: controller,
              lazy: lazy,
              cacheExtent: lazy ? 5 : 0,
            ),
          );
          await tester.pumpComponent(harness.component);

          controller.jumpTo(9);
          await tester.pump();
          final word = _wordAt(tester, 0);
          expect(word, isNotNull);

          for (var width = _wide - 1; width >= _narrow; width--) {
            harness.key.currentState!.resize(width);
            await tester.pump();
          }
          expect(_rowText(tester, 0), contains(word!));

          for (var width = _narrow + 1; width <= _wide; width++) {
            harness.key.currentState!.resize(width);
            await tester.pump();
          }
          expect(_rowText(tester, 0), contains(word));
          controller.dispose();
        }, size: _terminalSize);
      });
    }

    test('anchors through padding and a label to the value paragraph',
        () async {
      // The details pane's exact shape: the leaf under the viewport top is
      // the second paragraph of a padded Column. The descent crosses the
      // Padding (whose offset is constant) and the label row.
      await testNocterm('detail shape', (tester) async {
        final controller = ScrollController();
        final harness = _resizable(
          initialWidth: _wide,
          builder: (width) => _detailList(width: width, controller: controller),
        );
        await tester.pumpComponent(harness.component);

        controller.jumpTo(8);
        await tester.pump();
        final word = _wordAt(tester, 0);
        expect(word, isNotNull);

        harness.key.currentState!.resize(_narrow);
        await tester.pump();

        expect(_rowText(tester, 0), contains(word!));
        controller.dispose();
      }, size: _terminalSize);
    });

    test('holds a block gap at the top via the paragraph above it', () async {
      // The viewport top sits on the spacer row between two paragraphs.
      // The anchor holds the last line of the paragraph above plus one
      // stable row — after the reflow the gap is still the top row and the
      // second paragraph still starts on the row below.
      await testNocterm('gap anchor', (tester) async {
        final controller = ScrollController();
        final harness = _resizable(
          initialWidth: _wide,
          builder: (width) => _gapList(width: width, controller: controller),
        );
        await tester.pumpComponent(harness.component);

        // Bring the tail of the prose on screen, then locate the gap — the
        // row just above 'below the gap' — and scroll it to the very top.
        controller.jumpTo(12);
        await tester.pump();
        final settled = controller.offset.toInt();
        var gapRow = 0;
        for (var y = 0; y < _viewportHeight; y++) {
          if (_rowText(tester, y).startsWith('below the gap')) {
            gapRow = settled + y - 1;
            break;
          }
        }
        expect(gapRow, greaterThan(0));
        controller.jumpTo(gapRow.toDouble());
        await tester.pump();
        expect(_rowText(tester, 0).trim(), '');
        expect(_rowText(tester, 1), startsWith('below the gap'));

        harness.key.currentState!.resize(_narrow);
        await tester.pump();

        expect(_rowText(tester, 0).trim(), '');
        expect(_rowText(tester, 1), startsWith('below the gap'));
        controller.dispose();
      }, size: _terminalSize);
    });

    test('pins the bottom of the wall through a single-frame reflow', () async {
      // The reported jank: scrolled to the very bottom of a wall, a
      // tightening resize painted one frame adrift before the controller
      // snapped back. The bottom pin corrects inside the layout loop, so
      // the tail is the tail on the first frame — with a plain controller.
      await testNocterm('wall bottom', (tester) async {
        final controller = ScrollController();
        final harness = _resizable(
          initialWidth: _wide,
          builder: (width) => _wallList(width: width, controller: controller),
        );
        await tester.pumpComponent(harness.component);

        controller.jumpTo(controller.maxScrollExtent);
        await tester.pump();
        expect(
          _rowText(tester, _viewportHeight.toInt() - 1),
          startsWith('tail 5'),
        );

        harness.key.currentState!.resize(_narrow);
        await tester.pump();

        expect(controller.offset, controller.maxScrollExtent);
        expect(
          _rowText(tester, _viewportHeight.toInt() - 1),
          startsWith('tail 5'),
        );
        controller.dispose();
      }, size: _terminalSize);
    });

    test('falls back cleanly when the anchored paragraph is replaced',
        () async {
      // The resize rebuilds the anchor item with entirely different
      // content: the held leaf is gone, the anchor falls back to its raw
      // clamped depth, and nothing crashes or scrolls out of range.
      await testNocterm('leaf swap', (tester) async {
        final controller = ScrollController();
        final harness = GlobalKey<_SwapHarnessState>();
        await tester.pumpComponent(
          _SwapHarness(key: harness, controller: controller),
        );

        controller.jumpTo(9);
        await tester.pump();

        harness.currentState!.resizeAndSwap(_narrow);
        await tester.pump();

        expect(controller.offset, greaterThanOrEqualTo(0));
        expect(controller.offset, lessThanOrEqualTo(9));
        expect(tester.terminalState, containsText('swapped'));
        controller.dispose();
      }, size: _terminalSize);
    });
  });
}
