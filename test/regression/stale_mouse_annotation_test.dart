import 'package:nocterm/nocterm.dart';
import 'package:nocterm/src/rendering/mouse_hit_test.dart';
import 'package:nocterm/src/rendering/mouse_region.dart';
import 'package:nocterm/src/rendering/mouse_tracker.dart';
import 'package:test/test.dart';

/// A row that tracks hover through its State, as any setState-on-hover
/// component does. Every build hands [MouseRegion] fresh closures.
class _HoverRow extends StatefulComponent {
  const _HoverRow({
    required this.label,
    required this.onHover,
    required this.onTap,
  });

  final String label;
  final void Function({required bool hovered}) onHover;
  final void Function() onTap;

  @override
  State<_HoverRow> createState() => _HoverRowState();
}

class _HoverRowState extends State<_HoverRow> {
  bool _hovered = false;

  void _setHovered({required bool value}) {
    if (_hovered == value) return;
    setState(() => _hovered = value);
    component.onHover(hovered: value);
  }

  @override
  Component build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => _setHovered(value: true),
      onExit: (_) => _setHovered(value: false),
      child: GestureDetector(
        onTap: component.onTap,
        child: SizedBox(
          width: 20,
          height: 1,
          child: Text('${component.label}${_hovered ? '*' : ''}'),
        ),
      ),
    );
  }
}

/// The screen the row lives on. Changing it rebuilds the row in place or
/// unmounts it, the way any list rebuilding on new data does.
class _Screen extends StatefulComponent {
  const _Screen();

  @override
  State<_Screen> createState() => _ScreenState();
}

class _ScreenState extends State<_Screen> {
  bool _withRow = true;
  String _label = 'row';
  void Function({required bool hovered}) _onHover = ({required hovered}) {};
  void Function() _onTap = () {};

  void show({
    required String label,
    void Function({required bool hovered})? onHover,
    void Function()? onTap,
  }) {
    setState(() {
      _withRow = true;
      _label = label;
      _onHover = onHover ?? ({required hovered}) {};
      _onTap = onTap ?? () {};
    });
  }

  void hide() => setState(() => _withRow = false);

  @override
  Component build(BuildContext context) {
    return Container(
      width: 40,
      height: 5,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_withRow)
            _HoverRow(label: _label, onHover: _onHover, onTap: _onTap),
          const Text('other'),
        ],
      ),
    );
  }
}

MouseEvent _moveTo(int x, int y) => MouseEvent(
      button: MouseButton.left,
      x: x,
      y: y,
      pressed: false,
    );

void main() {
  test(
    'a region rebuilt while hovered, then unmounted, does not take the mouse '
    'down with it',
    () async {
      await testNocterm('stale annotation', (tester) async {
        final hovers = <bool>[];
        var taps = 0;

        await tester.pumpComponent(const _Screen());
        await tester.pump();
        final screen = tester.findState<_ScreenState>();

        // 1. Hover the row: the tracker now remembers its annotation.
        await tester.hover(2, 0);
        expect(tester.terminalState, hasTextAt(0, 0, 'row*'));

        // 2. Rebuild it without an intervening mouse event: the render
        //    object swaps in a new annotation; the tracker still holds the
        //    old one.
        screen.show(label: 'row2');
        await tester.pump();
        expect(tester.terminalState, hasTextAt(0, 0, 'row2*'));

        // 3. Unmount it. Only the current annotation is invalidated; the
        //    one the tracker holds still points at the dead State.
        screen.hide();
        await tester.pump();
        expect(tester.terminalState, hasTextAt(0, 0, 'other'));

        // 4. The next mouse event exits the dead annotation. This must not
        //    throw, and must not leave the tracker wedged.
        await tester.hover(2, 0);

        // 5. A fresh row still gets its hover and its click.
        screen.show(
          label: 'fresh',
          onHover: ({required hovered}) => hovers.add(hovered),
          onTap: () => taps++,
        );
        await tester.pump();
        await tester.hover(3, 0);
        expect(hovers, [true]);
        expect(tester.terminalState, hasTextAt(0, 0, 'fresh*'));
        await tester.tap(3, 0);
        expect(taps, 1);
        await tester.hover(3, 3);
        expect(hovers, [true, false]);
      });
    },
  );

  group('MouseTracker', () {
    test('forgets an exited annotation even when its onExit throws', () {
      final tracker = MouseTracker();
      var exits = 0;
      final region = RenderMouseRegion(
        onExit: (_) {
          exits++;
          throw StateError('dead state');
        },
      );
      MouseHitTestResult over({required bool region$}) {
        final result = MouseHitTestResult();
        if (region$) {
          result.addWithPosition(target: region, localPosition: Offset.zero);
        }
        return result;
      }

      tracker.updateAnnotations(over(region$: true), _moveTo(0, 0));
      expect(
        () => tracker.updateAnnotations(over(region$: false), _moveTo(5, 5)),
        throwsStateError,
      );
      expect(exits, 1);

      tracker.updateAnnotations(over(region$: false), _moveTo(6, 6));
      expect(exits, 1, reason: 'the exit was dispatched once and forgotten');
    });

    test('dispatches to a fresh annotation after another one threw', () {
      final tracker = MouseTracker();
      final broken = RenderMouseRegion(onExit: (_) => throw StateError('x'));
      var entered = 0;
      final fresh = RenderMouseRegion(onEnter: (_) => entered++);
      MouseHitTestResult over(RenderMouseRegion? region) {
        final result = MouseHitTestResult();
        if (region != null) {
          result.addWithPosition(target: region, localPosition: Offset.zero);
        }
        return result;
      }

      tracker.updateAnnotations(over(broken), _moveTo(0, 0));
      expect(
        () => tracker.updateAnnotations(over(null), _moveTo(1, 1)),
        throwsStateError,
      );

      tracker.updateAnnotations(over(fresh), _moveTo(2, 2));
      expect(entered, 1);
    });
  });

  group('RenderMouseRegion', () {
    test('invalidates the annotation a new callback replaces', () {
      final region = RenderMouseRegion(onEnter: (_) {});
      final before = region.annotation!;

      region.onEnter = (_) {};

      expect(region.annotation, isNot(same(before)));
      expect(before.validForMouseTracker, isFalse);
      expect(region.annotation!.validForMouseTracker, isTrue);
    });
  });
}
