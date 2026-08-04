import 'package:nocterm/nocterm.dart' hide isEmpty;
import 'package:test/test.dart';

/// A press, then a motion, then a release — the shape of every gesture that
/// starts on one cell and ends on another.
Future<void> _pressDragRelease(
  NoctermTester tester, {
  required (int, int) from,
  required List<(int, int)> via,
  (int, int)? releaseAt,
}) async {
  await tester.press(from.$1, from.$2);
  for (final point in via) {
    await tester.sendMouseEvent(MouseEvent(
      button: MouseButton.left,
      x: point.$1,
      y: point.$2,
      pressed: true,
      isMotion: true,
    ));
  }
  final end = releaseAt ?? via.last;
  await tester.release(end.$1, end.$2);
}

/// Two stacked one-line targets, each 5 cells wide, at rows 0 and 1.
Component _twoTargets({
  required void Function(String) onTap,
  bool selectable = false,
}) {
  Component target(String id) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onTap(id),
        child: Text('$id....'),
      );

  final column = Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [target('a'), target('b')],
  );

  return selectable ? SelectionArea(child: column) : column;
}

void main() {
  group('tap fires on release while still over', () {
    test('a press and release on the same cell taps', () async {
      await testNocterm('plain tap', (tester) async {
        final taps = <String>[];
        await tester.pumpComponent(_twoTargets(onTap: taps.add));

        await tester.tap(1, 0);

        expect(taps, ['a']);
      }, size: const Size(20, 6));
    });

    test('a press with no release has not tapped yet', () async {
      await testNocterm('press only', (tester) async {
        final taps = <String>[];
        await tester.pumpComponent(_twoTargets(onTap: taps.add));

        await tester.press(1, 0);

        expect(taps, isEmpty,
            reason: 'the press is only half the gesture — until the button '
                'comes up the user can still take it back');
      }, size: const Size(20, 6));
    });

    test('dragging off the target and releasing does not tap', () async {
      await testNocterm('drag off', (tester) async {
        final taps = <String>[];
        await tester.pumpComponent(_twoTargets(onTap: taps.add));

        await _pressDragRelease(tester, from: (1, 0), via: [(1, 1)]);

        expect(taps, isEmpty,
            reason: 'pressing and dragging away is how a user cancels');
      }, size: const Size(20, 6));
    });

    test('dragging off does not tap the target released over', () async {
      await testNocterm('drag off no cross-tap', (tester) async {
        final taps = <String>[];
        await tester.pumpComponent(_twoTargets(onTap: taps.add));

        await _pressDragRelease(tester, from: (1, 0), via: [(1, 1)]);

        expect(taps, isNot(contains('b')),
            reason: 'the release belongs to the gesture that started on a, '
                'not to whatever happens to be underneath at the end');
      }, size: const Size(20, 6));
    });

    test('dragging off and back before releasing does not tap', () async {
      await testNocterm('drag off and back', (tester) async {
        final taps = <String>[];
        await tester.pumpComponent(_twoTargets(onTap: taps.add));

        await _pressDragRelease(
          tester,
          from: (1, 0),
          via: [(1, 1), (1, 0)],
          releaseAt: (1, 0),
        );

        expect(taps, isEmpty,
            reason: 'leaving abandons the gesture; coming back does not '
                'resurrect it');
      }, size: const Size(20, 6));
    });
  });

  group('tap inside a SelectionArea', () {
    test('a click still taps the target under it', () async {
      await testNocterm('selectable tap', (tester) async {
        final taps = <String>[];
        await tester.pumpComponent(
          _twoTargets(onTap: taps.add, selectable: true),
        );

        await tester.tap(1, 0);

        expect(taps, ['a'],
            reason: 'a selectable region must not swallow plain clicks — '
                'capturing on the bare press would starve the target of '
                'the release it needs to complete the tap');
      }, size: const Size(20, 6));
    });

    test('a drag selects instead of tapping', () async {
      await testNocterm('selectable drag', (tester) async {
        final taps = <String>[];
        await tester.pumpComponent(
          _twoTargets(onTap: taps.add, selectable: true),
        );

        await _pressDragRelease(tester, from: (0, 0), via: [(3, 0)]);

        expect(taps, isEmpty,
            reason: 'once the pointer moves off the pressed cell the drag '
                'is a selection, and the target it started on is disarmed');
      }, size: const Size(20, 6));
    });
  });
}
