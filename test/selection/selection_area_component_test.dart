import 'package:nocterm/nocterm.dart'
    hide Selectable, SelectionArea, RenderSelectionArea;
import 'package:nocterm/src/selection/selection_area.dart';
import 'package:test/test.dart';

import 'test_text_render.dart';

class _RebuildHarness extends StatefulComponent {
  const _RebuildHarness();

  @override
  State<_RebuildHarness> createState() => _RebuildHarnessState();
}

class _RebuildHarnessState extends State<_RebuildHarness> {
  static _RebuildHarnessState? instance;

  String _secondLine = 'World';

  void setSecondLine(String value) => setState(() => _secondLine = value);

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
        const SelectableTestText('Hello'),
        SelectableTestText(_secondLine),
      ],
    );
  }
}

void main() {
  group('SelectionArea component', () {
    test('drag across two texts selects and completes with joined text',
        () async {
      await testNocterm(
        'drag across texts',
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
                    SelectableTestText('Hello'),
                    SelectableTestText('World'),
                  ],
                ),
              ),
            ),
          );

          await tester.press(1, 0);
          await tester.sendMouseEvent(const MouseEvent(
            button: MouseButton.left,
            x: 3,
            y: 1,
            pressed: true,
            isMotion: true,
          ));
          await tester.release(3, 1);

          expect(lastChanged, 'ello\nWor');
          expect(completed, 'ello\nWor');
        },
      );
    });

    test('selection survives a rebuild that changes other content', () async {
      await testNocterm(
        'selection survives rebuild',
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

          await tester.press(1, 0);
          await tester.sendMouseEvent(const MouseEvent(
            button: MouseButton.left,
            x: 4,
            y: 0,
            pressed: true,
            isMotion: true,
          ));
          await tester.release(4, 0);
          expect(lastChanged, 'ell');

          _RebuildHarnessState.instance!.setSecondLine('Changed');
          await tester.pump();
          await tester.pump();

          expect(lastChanged, 'ell');
        },
      );
    });

    test('selection clamps when the selected text itself shrinks', () async {
      await testNocterm(
        'selection clamps on content change',
        (tester) async {
          Component build(String text) {
            return Container(
              width: 20,
              height: 4,
              child: SelectionArea(
                child: SelectableTestText(text),
              ),
            );
          }

          await tester.pumpComponent(build('Hello world'));

          await tester.press(0, 0);
          await tester.sendMouseEvent(const MouseEvent(
            button: MouseButton.left,
            x: 11,
            y: 0,
            pressed: true,
            isMotion: true,
          ));
          await tester.release(11, 0);

          await tester.pumpComponent(build('Hi'));
          await tester.pump();
        },
      );
    });

    test('double click selects the word under the pointer', () async {
      await testNocterm(
        'double click selects word',
        (tester) async {
          String? lastChanged;

          await tester.pumpComponent(
            Container(
              width: 20,
              height: 4,
              child: SelectionArea(
                onSelectionChanged: (text) => lastChanged = text,
                child: const SelectableTestText('Hello world'),
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
  });
}
