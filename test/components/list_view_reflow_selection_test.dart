import 'package:nocterm/nocterm.dart';
import 'package:test/test.dart';

/// A hundred numbered four-column words: any selected slice identifies
/// exactly which part of the prose it came from.
final String _prose = List.generate(
  100,
  (index) => 'w${index.toString().padLeft(2, '0')}',
).join(' ');

const double _wide = 60;
const double _narrow = 30;

const Size _terminalSize = Size(80, 10);

/// Resizes a selectable list in place, the way a pane splitter would.
class _Harness extends StatefulComponent {
  const _Harness({
    required this.controller,
    required this.onSelectionCompleted,
    this.lazy = false,
    super.key,
  });

  final ScrollController controller;
  final void Function(String) onSelectionCompleted;
  final bool lazy;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  double _width = _wide;

  void resize(double value) => setState(() => _width = value);

  @override
  Component build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: _width,
          child: SelectionArea(
            onSelectionCompleted: component.onSelectionCompleted,
            child: ListView.builder(
              controller: component.controller,
              lazy: component.lazy,
              cacheExtent: 5,
              itemCount: 30,
              itemBuilder: (context, index) => Text('alpha$index bravo$index'),
            ),
          ),
        ),
        Expanded(child: SizedBox()),
      ],
    );
  }
}

Future<void> _selectRows(NoctermTester tester, {required int rows}) async {
  await tester.press(1, 0);
  await tester.sendMouseEvent(
    MouseEvent(
      button: MouseButton.left,
      x: 12,
      y: rows,
      pressed: true,
      isMotion: true,
    ),
  );
  await tester.release(12, rows);
}

/// Resizes a pane holding one long wrapping paragraph under selection.
class _ProseHarness extends StatefulComponent {
  const _ProseHarness({
    required this.onSelectionChanged,
    required this.textKey,
    super.key,
  });

  final void Function(String) onSelectionChanged;
  final GlobalKey textKey;

  @override
  State<_ProseHarness> createState() => _ProseHarnessState();
}

class _ProseHarnessState extends State<_ProseHarness> {
  double _width = _wide;

  void resize(double value) => setState(() => _width = value);

  @override
  Component build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: _width,
          child: SelectionArea(
            onSelectionChanged: component.onSelectionChanged,
            child: Text(_prose, key: component.textKey),
          ),
        ),
        Expanded(child: SizedBox()),
      ],
    );
  }
}

/// The first render object at or beneath [element].
RenderObject? _renderObjectOf(Element element) {
  if (element is RenderObjectElement) return element.renderObject;
  RenderObject? found;
  element.visitChildren((child) => found ??= _renderObjectOf(child));
  return found;
}

void main() {
  group('selection across a reflow', () {
    test('a held selection still covers the same words after a resize',
        () async {
      // The report from the field: after a reflow the selection keeps its
      // length but slides to different text. Edges are character indexes
      // into selectableText, so plain prose — whose text is identical at
      // every width — must keep the exact same words selected.
      await testNocterm('selection text stable', (tester) async {
        final changes = <String>[];
        final textKey = GlobalKey();
        final key = GlobalKey<_ProseHarnessState>();
        await tester.pumpComponent(
          _ProseHarness(
            key: key,
            textKey: textKey,
            onSelectionChanged: changes.add,
          ),
        );

        await tester.press(4, 1);
        await tester.sendMouseEvent(
          const MouseEvent(
            button: MouseButton.left,
            x: 20,
            y: 2,
            pressed: true,
            isMotion: true,
          ),
        );
        await tester.release(20, 2);
        expect(changes.length, greaterThan(0));
        final before = changes.last;
        expect(before, contains('w'));

        key.currentState!.resize(_narrow);
        await tester.pump();

        final paragraph = _renderObjectOf(textKey.currentContext! as Element);
        final content = (paragraph as dynamic).getSelectedContent();
        expect(content?.plainText, before);
      }, size: _terminalSize);
    });

    for (final lazy in [false, true]) {
      test('selection still completes after a resize (lazy: $lazy)', () async {
        await testNocterm('reselect after resize', (tester) async {
          final controller = ScrollController();
          final completions = <String>[];
          final key = GlobalKey<_HarnessState>();
          await tester.pumpComponent(
            _Harness(
              key: key,
              controller: controller,
              onSelectionCompleted: completions.add,
              lazy: lazy,
            ),
          );

          controller.jumpTo(5);
          await tester.pump();

          await _selectRows(tester, rows: 2);
          expect(completions, hasLength(1));
          expect(completions.single, contains('alpha'));

          key.currentState!.resize(_narrow);
          await tester.pump();

          await _selectRows(tester, rows: 2);
          expect(completions, hasLength(2));
          expect(completions.last, contains('alpha'));
          controller.dispose();
        }, size: _terminalSize);
      });

      test('a drag selection survives a mid-drag resize (lazy: $lazy)',
          () async {
        // The pane resizes while the mouse is still down and selecting —
        // the reflow relayouts and (lazy) purges children under an active
        // selection, and the drag must carry on without losing its grip.
        await testNocterm('resize mid-selection', (tester) async {
          final controller = ScrollController();
          final completions = <String>[];
          final key = GlobalKey<_HarnessState>();
          await tester.pumpComponent(
            _Harness(
              key: key,
              controller: controller,
              onSelectionCompleted: completions.add,
              lazy: lazy,
            ),
          );

          controller.jumpTo(5);
          await tester.pump();

          await tester.press(1, 0);
          await tester.sendMouseEvent(
            MouseEvent(
              button: MouseButton.left,
              x: 12,
              y: 2,
              pressed: true,
              isMotion: true,
            ),
          );
          await tester.pump();

          key.currentState!.resize(_narrow);
          await tester.pump();

          await tester.sendMouseEvent(
            MouseEvent(
              button: MouseButton.left,
              x: 12,
              y: 4,
              pressed: true,
              isMotion: true,
            ),
          );
          await tester.release(12, 4);

          expect(completions, hasLength(1));
          expect(completions.single, contains('alpha'));
          controller.dispose();
        }, size: _terminalSize);
      });
    }
  });
}
