import 'package:nocterm/nocterm.dart';
import 'package:test/test.dart';

Future<void> _drag(NoctermTester tester, int fromX, int toX) async {
  await tester.press(fromX, 0);
  await tester.sendMouseEvent(MouseEvent(
    button: MouseButton.left,
    x: toX,
    y: 0,
    pressed: true,
    isMotion: true,
  ));
  await tester.release(toX, 0);
}

Component _area(SelectionController? controller, List<String> changes) =>
    SelectionArea(
      controller: controller,
      onSelectionChanged: changes.add,
      child: const Text('Hello World'),
    );

void main() {
  group('SelectionController', () {
    test('reports a selection and notifies on changes', () async {
      await testNocterm('controller reports', (tester) async {
        final controller = SelectionController();
        var notified = 0;
        controller.addListener(() => notified++);

        await tester.pumpComponent(_area(controller, []));
        expect(controller.hasSelection, isFalse);

        await _drag(tester, 0, 4);

        expect(controller.hasSelection, isTrue);
        expect(notified, greaterThan(0));
      });
    });

    test('clear() empties the selection', () async {
      await testNocterm('controller clears', (tester) async {
        final controller = SelectionController();
        final changes = <String>[];

        await tester.pumpComponent(_area(controller, changes));
        await _drag(tester, 0, 4);
        await tester.pump();
        expect(changes.last, 'Hell');

        controller.clear();
        await tester.pump();

        expect(controller.hasSelection, isFalse);
        expect(changes.last, '');
      });
    });

    test('a detached controller reports nothing and clears nothing', () {
      final controller = SelectionController();
      expect(controller.hasSelection, isFalse);
      controller.clear();
    });

    test('swapping controllers detaches the old one', () async {
      await testNocterm('controller swap', (tester) async {
        final first = SelectionController();
        final second = SelectionController();
        var firstNotified = 0;
        first.addListener(() => firstNotified++);

        await tester.pumpComponent(_area(first, []));
        final notifiedWhileAttached = firstNotified;
        await tester.pumpComponent(_area(second, []));
        await _drag(tester, 0, 4);

        expect(firstNotified, notifiedWhileAttached);
        expect(first.hasSelection, isFalse);
        expect(second.hasSelection, isTrue);
      });
    });

    test('unmounting the area detaches the controller', () async {
      await testNocterm('controller unmount', (tester) async {
        final controller = SelectionController();

        await tester.pumpComponent(_area(controller, []));
        await _drag(tester, 0, 4);
        expect(controller.hasSelection, isTrue);

        await tester.pumpComponent(const Text('gone'));

        expect(controller.hasSelection, isFalse);
      });
    });
  });
}
