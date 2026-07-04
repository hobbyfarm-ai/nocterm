import 'package:nocterm/nocterm.dart';
import 'package:test/test.dart' hide isEmpty;

class _StreamHarness extends StatefulComponent {
  const _StreamHarness({required this.controller});

  final ScrollController controller;

  @override
  State<_StreamHarness> createState() => _StreamHarnessState();
}

class _StreamHarnessState extends State<_StreamHarness> {
  static _StreamHarnessState? instance;
  int generation = 0;

  void tick() => setState(() => generation++);

  @override
  void initState() {
    super.initState();
    instance = this;
  }

  @override
  Component build(BuildContext context) {
    final itemText = 'The quick brown fox jumps over the lazy dog. ' * 4;
    return ListView.builder(
      controller: component.controller,
      lazy: true,
      cacheExtent: 20,
      itemCount: 500,
      itemBuilder: (context, index) {
        if (index == 499) {
          // The streaming tail message: grows every tick and re-parses into
          // a structurally new subtree (key change defeats canUpdate), the
          // way a markdown view rebuilds while tokens stream in.
          return Text(
            'tail ${'token ' * (20 + generation)}',
            key: ValueKey('tail-$generation'),
          );
        }
        return Text('$index $itemText');
      },
    );
  }
}

void main() {
  group('SelectionArea with a streaming ListView', () {
    test('drag selection survives structural rebuilds of the tail item',
        () async {
      await testNocterm(
        'stream rebuild selection',
        (tester) async {
          String? completed;
          final controller = ScrollController();

          await tester.pumpComponent(
            SelectionArea(
              onSelectionCompleted: (text) => completed = text,
              child: _StreamHarness(controller: controller),
            ),
          );

          controller.jumpTo(999999);
          await tester.pump();
          await tester.pump();

          // Select upward from the streaming tail while it keeps rebuilding
          // and the list scrolls under the drag.
          await tester.press(2, 23);
          for (var i = 0; i < 30; i++) {
            controller.jumpTo(controller.offset - 20);
            _StreamHarnessState.instance!.tick();
            await tester.pump();
            await tester.pump();
            await tester.sendMouseEvent(MouseEvent(
              button: MouseButton.left,
              x: 20,
              y: 2 + (i % 3),
              pressed: true,
              isMotion: true,
            ));
          }
          await tester.release(21, 2);

          // The anchor sits in the tail: its content must be present even
          // though the render object it was created against was replaced
          // thirty times, along with every message swept over on the way up.
          expect(completed, contains('tail'));
          expect(completed!.length, greaterThan(10000));
        },
      );
    });
  });
}
