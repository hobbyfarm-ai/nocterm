import 'package:nocterm/nocterm.dart';
import 'package:nocterm/src/components/render_text.dart';
import 'package:test/test.dart' hide isEmpty;

Future<void> _drag(
  NoctermTester tester,
  (int, int) from,
  (int, int) to,
) async {
  await tester.press(from.$1, from.$2);
  await tester.sendMouseEvent(MouseEvent(
    button: MouseButton.left,
    x: to.$1,
    y: to.$2,
    pressed: true,
    isMotion: true,
  ));
  await tester.release(to.$1, to.$2);
}

class _RebuildHarness extends StatefulComponent {
  const _RebuildHarness();

  @override
  State<_RebuildHarness> createState() => _RebuildHarnessState();
}

class _RebuildHarnessState extends State<_RebuildHarness> {
  static _RebuildHarnessState? instance;

  String _firstLine = 'Hello';
  String _secondLine = 'World';

  void setLines({String? first, String? second}) => setState(() {
        _firstLine = first ?? _firstLine;
        _secondLine = second ?? _secondLine;
      });

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_firstLine),
        Text(_secondLine),
      ],
    );
  }
}

class _CapturingText extends Text {
  const _CapturingText(super.data, {required this.onRender});

  final void Function(RenderText) onRender;

  @override
  RenderObject createRenderObject(BuildContext context) {
    final renderObject = super.createRenderObject(context) as RenderText;
    onRender(renderObject);
    return renderObject;
  }
}

void main() {
  group('SelectionArea', () {
    test('selection completion inserts newline when moving to a new row',
        () async {
      await testNocterm(
        'selection completion',
        (tester) async {
          String? lastChanged;
          String? completed;

          await tester.pumpComponent(
            Container(
              width: 20,
              height: 4,
              child: SelectionArea(
                onSelectionChanged: (text) => lastChanged = text,
                onSelectionCompleted: (text) => completed = text,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('Hello'),
                    Text('World'),
                  ],
                ),
              ),
            ),
          );

          await tester.press(1, 0);
          await tester.sendMouseEvent(const MouseEvent(
            button: MouseButton.left,
            x: 2,
            y: 0,
            pressed: true,
            isMotion: true,
          ));
          await tester.sendMouseEvent(const MouseEvent(
            button: MouseButton.left,
            x: 3,
            y: 1,
            pressed: true,
            isMotion: true,
          ));
          await tester.release(3, 1);

          expect(lastChanged, equals('ello\nWor'));
          expect(completed, equals('ello\nWor'));
        },
      );
    });

    test('selection persists when sibling content changes', () async {
      await testNocterm(
        'selection persists across rebuild',
        (tester) async {
          String? lastChanged;

          await tester.pumpComponent(
            Container(
              width: 20,
              height: 4,
              child: SelectionArea(
                onSelectionChanged: (text) => lastChanged = text,
                child: const _RebuildHarness(),
              ),
            ),
          );

          await _drag(tester, (1, 0), (4, 0));
          expect(lastChanged, 'ell');

          _RebuildHarnessState.instance!.setLines(second: 'Changed');
          await tester.pump();
          await tester.pump();

          expect(lastChanged, 'ell');
        },
      );
    });

    test('selection clamps when the selected text shrinks', () async {
      await testNocterm(
        'selection clamps on shrink',
        (tester) async {
          await tester.pumpComponent(
            Container(
              width: 20,
              height: 4,
              child: const SelectionArea(
                child: _RebuildHarness(),
              ),
            ),
          );

          await _drag(tester, (0, 0), (5, 0));

          _RebuildHarnessState.instance!.setLines(first: 'Hi');
          await tester.pump();
          await tester.pump();
        },
      );
    });

    test('anchor survives leaving and re-entering the area mid-drag', () async {
      await testNocterm(
        'drag out and back',
        size: const Size(20, 4),
        (tester) async {
          String? completed;

          await tester.pumpComponent(
            SelectionArea(
              onSelectionCompleted: (text) => completed = text,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('Hello'),
                  Text('World'),
                ],
              ),
            ),
          );

          await tester.press(1, 0);
          // Drag beyond the terminal bounds: no annotation is hit out
          // here, which used to end the drag and drop the anchor.
          await tester.sendMouseEvent(const MouseEvent(
            button: MouseButton.left,
            x: 30,
            y: 9,
            pressed: true,
            isMotion: true,
          ));
          // Re-enter and keep dragging from the original anchor.
          await tester.sendMouseEvent(const MouseEvent(
            button: MouseButton.left,
            x: 3,
            y: 1,
            pressed: true,
            isMotion: true,
          ));
          await tester.release(3, 1);

          expect(completed, 'ello\nWor');
        },
      );
    });

    test('starts selection when pressing on whitespace and dragging into text',
        () async {
      await testNocterm(
        'whitespace press',
        (tester) async {
          String? completed;

          await tester.pumpComponent(
            Container(
              width: 20,
              height: 4,
              child: SelectionArea(
                onSelectionCompleted: (text) => completed = text,
                child: const Align(
                  alignment: Alignment.topLeft,
                  child: Text('Hello'),
                ),
              ),
            ),
          );

          await _drag(tester, (10, 2), (2, 0));
          expect(completed, 'llo');
        },
      );
    });

    test('selection crosses a non-selectable gap between widgets', () async {
      await testNocterm(
        'gap crossing',
        (tester) async {
          String? completed;

          await tester.pumpComponent(
            Container(
              width: 20,
              height: 5,
              child: SelectionArea(
                onSelectionCompleted: (text) => completed = text,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Hello'),
                    Container(height: 1),
                    const Text('World'),
                  ],
                ),
              ),
            ),
          );

          await _drag(tester, (1, 0), (3, 2));
          expect(completed, 'ello\nWor');
        },
      );
    });

    test('selection updates on mouse release position', () async {
      await testNocterm(
        'release position',
        (tester) async {
          String? completed;

          await tester.pumpComponent(
            Container(
              width: 20,
              height: 4,
              child: SelectionArea(
                onSelectionCompleted: (text) => completed = text,
                child: const Text('Hello world'),
              ),
            ),
          );

          await tester.press(0, 0);
          await tester.sendMouseEvent(const MouseEvent(
            button: MouseButton.left,
            x: 3,
            y: 0,
            pressed: true,
            isMotion: true,
          ));
          await tester.release(8, 0);

          expect(completed, 'Hello wo');
        },
      );
    });

    test('drag below last line clamps selection to end', () async {
      await testNocterm(
        'drag below clamps',
        (tester) async {
          String? completed;

          await tester.pumpComponent(
            Container(
              width: 20,
              height: 4,
              child: SelectionArea(
                onSelectionCompleted: (text) => completed = text,
                child: const Align(
                  alignment: Alignment.topLeft,
                  child: Text('Hello'),
                ),
              ),
            ),
          );

          await _drag(tester, (0, 0), (10, 3));
          expect(completed, 'Hello');
        },
      );
    });

    test('backward selection across three widgets', () async {
      await testNocterm(
        'backward selection',
        (tester) async {
          String? completed;

          await tester.pumpComponent(
            Container(
              width: 20,
              height: 4,
              child: SelectionArea(
                onSelectionCompleted: (text) => completed = text,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('One'),
                    Text('Two'),
                    Text('Three'),
                  ],
                ),
              ),
            ),
          );

          await _drag(tester, (3, 2), (1, 0));
          expect(completed, 'ne\nTwo\nThr');
        },
      );
    });

    test('same-row widgets join with a space', () async {
      await testNocterm(
        'same-row join',
        (tester) async {
          String? completed;

          await tester.pumpComponent(
            Container(
              width: 20,
              height: 3,
              child: SelectionArea(
                onSelectionCompleted: (text) => completed = text,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Text('foo'),
                        Text('bar'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );

          await _drag(tester, (0, 0), (6, 0));
          expect(completed, 'foo bar');
        },
      );
    });

    test('hard newlines in a single Text are preserved', () async {
      await testNocterm(
        'hard newlines',
        (tester) async {
          String? completed;

          await tester.pumpComponent(
            Container(
              width: 20,
              height: 4,
              child: SelectionArea(
                onSelectionCompleted: (text) => completed = text,
                child: const Text('AA\nBB'),
              ),
            ),
          );

          await _drag(tester, (0, 0), (2, 1));
          expect(completed, 'AA\nBB');
        },
      );
    });

    test('soft-wrapped text copies as logical text without wrap newlines',
        () async {
      await testNocterm(
        'wrapped copies logical',
        size: const Size(6, 4),
        (tester) async {
          String? completed;

          await tester.pumpComponent(
            SelectionArea(
              onSelectionCompleted: (text) => completed = text,
              child: const Text('hello world'),
            ),
          );

          await _drag(tester, (0, 0), (5, 1));
          expect(completed, 'hello world');
        },
      );
    });

    test('null onSelectionCompleted callback does not crash', () async {
      await testNocterm(
        'null completed callback',
        (tester) async {
          await tester.pumpComponent(
            Container(
              width: 10,
              height: 2,
              child: const SelectionArea(
                child: Text('Hello'),
              ),
            ),
          );

          await _drag(tester, (0, 0), (4, 0));
        },
      );
    });

    test('drag in an area with no selectable children does not crash',
        () async {
      await testNocterm(
        'no selectables',
        (tester) async {
          await tester.pumpComponent(
            Container(
              width: 10,
              height: 3,
              child: SelectionArea(
                child: Container(width: 5, height: 1),
              ),
            ),
          );

          await _drag(tester, (1, 1), (4, 1));
        },
      );
    });

    test('double click selects the word under the pointer', () async {
      await testNocterm(
        'double click word',
        (tester) async {
          String? lastChanged;

          await tester.pumpComponent(
            Container(
              width: 20,
              height: 3,
              child: SelectionArea(
                onSelectionChanged: (text) => lastChanged = text,
                child: const Text('Hello world'),
              ),
            ),
          );

          await tester.press(7, 0);
          await tester.release(7, 0);
          await tester.press(7, 0);
          await tester.release(7, 0);

          expect(lastChanged, 'world');
        },
      );
    });

    test('selection color change propagates without disturbing selection',
        () async {
      await testNocterm(
        'color change',
        (tester) async {
          String? lastChanged;

          Component build(Color color) {
            return Container(
              width: 20,
              height: 3,
              child: SelectionArea(
                selection: color,
                onSelectionChanged: (text) => lastChanged = text,
                child: const _RebuildHarness(),
              ),
            );
          }

          await tester.pumpComponent(build(Colors.red));
          await _drag(tester, (1, 0), (4, 0));
          expect(lastChanged, 'ell');

          await tester.pumpComponent(build(Colors.green));
        },
      );
    });
  });

  group('SelectionArea with ListView', () {
    test('selection spans multiple list items', () async {
      await testNocterm(
        'list selection',
        (tester) async {
          String? completed;
          final controller = ScrollController();

          await tester.pumpComponent(
            Container(
              width: 20,
              height: 3,
              child: SelectionArea(
                onSelectionCompleted: (text) => completed = text,
                child: ListView.builder(
                  controller: controller,
                  itemCount: 3,
                  itemBuilder: (context, index) => Text('item $index'),
                ),
              ),
            ),
          );

          await _drag(tester, (0, 0), (6, 2));
          expect(completed, 'item 0\nitem 1\nitem 2');
        },
      );
    });

    test(
        'new selection lands on visible items after scrolling away from '
        'a kept-alive selection', () async {
      await testNocterm(
        'select after scroll',
        (tester) async {
          String? completed;
          final controller = ScrollController();

          await tester.pumpComponent(
            Container(
              width: 20,
              // Tall enough that row 5 sits in the neutral middle and the
              // drags there don't trip edge auto-scroll.
              height: 10,
              child: SelectionArea(
                onSelectionCompleted: (text) => completed = text,
                child: ListView.builder(
                  controller: controller,
                  lazy: true,
                  cacheExtent: 0,
                  itemExtent: 1,
                  itemCount: 100,
                  itemBuilder: (context, index) => Text('item $index'),
                ),
              ),
            ),
          );

          // Select item 5, then scroll it far out of view (kept alive).
          await _drag(tester, (0, 5), (6, 5));
          expect(completed, 'item 5');

          controller.jumpTo(50);
          await tester.pump();
          await tester.pump();

          // A new selection at screen row 5 must land on the item actually
          // rendered there (item 55), not on the kept-alive item 5 whose
          // bounds used to cover this row.
          await _drag(tester, (0, 5), (7, 5));
          expect(completed, 'item 55');
        },
      );
    });

    test('anchor stays pinned to content while scrolling mid-drag', () async {
      await testNocterm(
        'scroll mid-drag',
        (tester) async {
          String? completed;
          final controller = ScrollController();

          await tester.pumpComponent(
            Container(
              width: 20,
              // Tall enough that the drag rows sit in the neutral middle and
              // don't trip edge auto-scroll while we scroll manually.
              height: 10,
              child: SelectionArea(
                onSelectionCompleted: (text) => completed = text,
                child: ListView.builder(
                  controller: controller,
                  lazy: true,
                  cacheExtent: 5,
                  itemExtent: 1,
                  itemCount: 100,
                  itemBuilder: (context, index) => Text('item $index'),
                ),
              ),
            ),
          );

          // Anchor the selection on item 5 at screen row 5.
          await tester.press(0, 5);
          await tester.sendMouseEvent(const MouseEvent(
            button: MouseButton.left,
            x: 6,
            y: 5,
            pressed: true,
            isMotion: true,
          ));

          // Content scrolls three rows under the held pointer.
          controller.jumpTo(3);
          await tester.pump();
          await tester.pump();

          // The next motion event lands on item 9 (screen row 6), and the
          // anchor must still be item 5, not whatever sits at screen row 5.
          await tester.sendMouseEvent(const MouseEvent(
            button: MouseButton.left,
            x: 6,
            y: 6,
            pressed: true,
            isMotion: true,
          ));
          await tester.release(6, 6);

          expect(completed, 'item 5\nitem 6\nitem 7\nitem 8\nitem 9');
        },
      );
    });

    test('wheel scroll mid-drag extends the selection under the pointer',
        () async {
      await testNocterm(
        'wheel mid-drag',
        (tester) async {
          String? completed;
          final controller = ScrollController();

          await tester.pumpComponent(
            Container(
              width: 20,
              // Tall enough that row 5 sits in the neutral middle, so the
              // wheel scroll (not edge auto-scroll) drives the extension.
              height: 10,
              child: SelectionArea(
                onSelectionCompleted: (text) => completed = text,
                child: ListView.builder(
                  controller: controller,
                  lazy: true,
                  cacheExtent: 5,
                  itemExtent: 1,
                  itemCount: 100,
                  itemBuilder: (context, index) => Text('item $index'),
                ),
              ),
            ),
          );

          // Anchor the selection on item 5 at screen row 5.
          await tester.press(0, 5);
          await tester.sendMouseEvent(const MouseEvent(
            button: MouseButton.left,
            x: 6,
            y: 5,
            pressed: true,
            isMotion: true,
          ));

          // Wheel scrolls the list by three rows mid-drag; the end edge is
          // re-resolved at the pointer's screen position after layout.
          await tester.sendMouseEvent(const MouseEvent(
            button: MouseButton.wheelDown,
            x: 6,
            y: 5,
            pressed: true,
          ));
          await tester.pump();
          await tester.pump();
          await tester.release(6, 5);

          expect(completed, 'item 5\nitem 6\nitem 7\nitem 8');
        },
      );
    });

    test('dragging past the list auto-scrolls until the pointer is reached',
        () async {
      await testNocterm(
        'auto-scroll drag',
        (tester) async {
          // A virtual clock that ticks one second per pump, so auto-scroll
          // velocity (rows/sec) resolves to whole rows per tick — this test
          // exercises reaching the end, not the ramp (covered by unit tests).
          var vnow = Duration.zero;
          SelectionAutoScroller.debugClockOverride = () => vnow;
          addTearDown(() => SelectionAutoScroller.debugClockOverride = null);
          String? completed;
          final controller = ScrollController();

          await tester.pumpComponent(
            Container(
              width: 20,
              height: 5,
              child: SelectionArea(
                onSelectionCompleted: (text) => completed = text,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 3,
                      child: ListView.builder(
                        controller: controller,
                        lazy: true,
                        cacheExtent: 0,
                        itemExtent: 1,
                        itemCount: 6,
                        itemBuilder: (context, index) => Text('item $index'),
                      ),
                    ),
                    Text('footer'),
                  ],
                ),
              ),
            ),
          );

          await tester.press(0, 0);
          // The pointer crosses out of the list onto the footer while the
          // list still has unrevealed content; the list auto-scrolls to its
          // end and the selection continues onto the footer.
          await tester.sendMouseEvent(const MouseEvent(
            button: MouseButton.left,
            x: 5,
            y: 3,
            pressed: true,
            isMotion: true,
          ));
          for (var i = 0; i < 10; i++) {
            vnow += const Duration(seconds: 1);
            await tester.pump();
          }
          await tester.release(5, 3);

          expect(controller.offset, controller.maxScrollExtent);
          expect(
            completed,
            'item 0\nitem 1\nitem 2\nitem 3\nitem 4\nitem 5\nfoote',
          );
        },
      );
    });

    test('drag starting above the list selects list content from its start',
        () async {
      await testNocterm(
        'cross into list',
        (tester) async {
          String? completed;
          final controller = ScrollController();

          await tester.pumpComponent(
            Container(
              width: 20,
              height: 5,
              child: SelectionArea(
                onSelectionCompleted: (text) => completed = text,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('header'),
                    SizedBox(
                      height: 3,
                      child: ListView.builder(
                        controller: controller,
                        lazy: true,
                        cacheExtent: 5,
                        itemExtent: 1,
                        itemCount: 100,
                        itemBuilder: (context, index) => Text('item $index'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );

          // Scroll the list before selecting so its first visible item is
          // not its first content item.
          controller.jumpTo(2);
          await tester.pump();

          await _drag(tester, (0, 0), (6, 2));

          // The selection crosses the list boundary from above: everything
          // from the list's scrolled-away beginning through the pointer is
          // included, not just what happens to be on screen.
          expect(completed, 'header\nitem 0\nitem 1\nitem 2\nitem 3');
        },
      );
    });

    test('lazy list keeps selected items alive across scrolling', () async {
      await testNocterm(
        'keep alive if selected',
        (tester) async {
          final captured = <int, RenderText>{};
          final controller = ScrollController();

          await tester.pumpComponent(
            Container(
              width: 20,
              height: 5,
              child: SelectionArea(
                child: ListView.builder(
                  controller: controller,
                  lazy: true,
                  cacheExtent: 0,
                  itemExtent: 1,
                  itemCount: 100,
                  itemBuilder: (context, index) => _CapturingText(
                    'item $index',
                    onRender: (renderObject) => captured[index] = renderObject,
                  ),
                ),
              ),
            ),
          );

          await _drag(tester, (0, 0), (6, 0));
          expect(captured[0]!.hasSelection, isTrue);
          final selectedRender = captured[0];
          final unselectedRender = captured[2];

          controller.jumpTo(50);
          await tester.pump();
          controller.jumpTo(0);
          await tester.pump();

          // The selected item survived scrolling out of the build window
          // (same render object, selection intact); the unselected neighbor
          // was rebuilt from scratch.
          expect(identical(captured[0], selectedRender), isTrue);
          expect(captured[0]!.hasSelection, isTrue);
          expect(identical(captured[2], unselectedRender), isFalse);
        },
      );
    });

    // --- Edge auto-scroll during selection drag (PR #81) ---
    //
    // Container height does not constrain the scroll viewport in the test
    // harness (it fills the full 24-row terminal), so these use 40 rows of
    // content to guarantee a scrollable extent and target the real viewport
    // edge at row 23.

    test(
        'drag to the bottom edge auto-scrolls the viewport; mid-viewport '
        'motion does not', () async {
      await testNocterm(
        'edge auto-scroll bottom',
        (tester) async {
          // Virtual clock so one second of auto-scroll resolves to whole rows;
          // speed itself is unit-tested on SelectionAutoScroller.
          var vnow = Duration.zero;
          SelectionAutoScroller.debugClockOverride = () => vnow;
          addTearDown(() => SelectionAutoScroller.debugClockOverride = null);
          final controller = ScrollController();

          await tester.pumpComponent(
            SelectionArea(
              child: SingleChildScrollView(
                controller: controller,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (int i = 0; i < 40; i++)
                      Text('Line${i.toString().padLeft(2, '0')}'),
                  ],
                ),
              ),
            ),
          );

          // 40 rows of content in the 24-row viewport leaves room to scroll.
          expect(controller.maxScrollExtent, greaterThan(0));
          expect(controller.offset, equals(0));

          // Begin a drag in the neutral middle of the viewport.
          await tester.press(0, 10);

          // Motion that stays in the neutral middle must NOT auto-scroll.
          await tester.sendMouseEvent(const MouseEvent(
            button: MouseButton.left,
            x: 4,
            y: 10,
            pressed: true,
            isMotion: true,
          ));
          expect(controller.offset, equals(0),
              reason: 'no auto-scroll while the pointer is away from an edge');

          // Motion to the bottom edge row arms edge auto-scroll (this tick
          // seeds the clock); the next frame, one virtual second later, scrolls.
          await tester.sendMouseEvent(const MouseEvent(
            button: MouseButton.left,
            x: 4,
            y: 23,
            pressed: true,
            isMotion: true,
          ));
          vnow += const Duration(seconds: 1);
          await tester.pump();
          expect(controller.offset, greaterThan(0),
              reason: 'dragging to the bottom edge should auto-scroll down');

          await tester.release(4, 23);
        },
      );
    });

    test('edge auto-scroll stops once the drag is released', () async {
      await testNocterm(
        'edge auto-scroll stops on release',
        (tester) async {
          var vnow = Duration.zero;
          SelectionAutoScroller.debugClockOverride = () => vnow;
          addTearDown(() => SelectionAutoScroller.debugClockOverride = null);
          final controller = ScrollController();

          await tester.pumpComponent(
            SelectionArea(
              child: SingleChildScrollView(
                controller: controller,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (int i = 0; i < 40; i++)
                      Text('Row${i.toString().padLeft(2, '0')}'),
                  ],
                ),
              ),
            ),
          );

          await tester.press(0, 10);
          await tester.sendMouseEvent(const MouseEvent(
            button: MouseButton.left,
            x: 4,
            y: 23,
            pressed: true,
            isMotion: true,
          ));
          vnow += const Duration(seconds: 1);
          await tester.pump();
          expect(controller.offset, greaterThan(0));

          // Releasing ends the drag and must cancel the auto-scroll loop.
          await tester.release(4, 23);
          final offsetAtRelease = controller.offset;

          // Further frames must not keep scrolling now that the drag is over.
          await tester.pump();
          await tester.pump();
          await tester.pump();

          expect(controller.offset, equals(offsetAtRelease),
              reason: 'auto-scroll must not run after the drag ends');
        },
      );
    });

    test(
        'a drag begun in the edge zone does not auto-scroll until the pointer '
        'leaves and re-enters it', () async {
      await testNocterm(
        'edge auto-scroll suppressed at start',
        (tester) async {
          var vnow = Duration.zero;
          SelectionAutoScroller.debugClockOverride = () => vnow;
          addTearDown(() => SelectionAutoScroller.debugClockOverride = null);
          final controller = ScrollController();

          await tester.pumpComponent(
            SelectionArea(
              child: SingleChildScrollView(
                controller: controller,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (int i = 0; i < 40; i++)
                      Text('Line${i.toString().padLeft(2, '0')}'),
                  ],
                ),
              ),
            ),
          );

          // Begin the drag inside the bottom edge zone.
          await tester.press(0, 23);
          await tester.sendMouseEvent(const MouseEvent(
            button: MouseButton.left,
            x: 4,
            y: 23,
            pressed: true,
            isMotion: true,
          ));
          vnow += const Duration(seconds: 1);
          await tester.pump();
          expect(controller.offset, equals(0),
              reason: 'a drag begun in the edge zone must not auto-scroll');

          // Move up out of the zone (neutral middle): still no scrolling, but
          // this re-arms auto-scroll.
          await tester.sendMouseEvent(const MouseEvent(
            button: MouseButton.left,
            x: 4,
            y: 10,
            pressed: true,
            isMotion: true,
          ));
          vnow += const Duration(seconds: 1);
          await tester.pump();
          expect(controller.offset, equals(0),
              reason: 'no auto-scroll away from an edge');

          // Re-enter the bottom edge zone: now it auto-scrolls.
          await tester.sendMouseEvent(const MouseEvent(
            button: MouseButton.left,
            x: 4,
            y: 23,
            pressed: true,
            isMotion: true,
          ));
          vnow += const Duration(seconds: 1);
          await tester.pump();
          expect(controller.offset, greaterThan(0),
              reason: 're-entering the edge zone should auto-scroll');

          await tester.release(4, 23);
        },
      );
    });
  });
}
