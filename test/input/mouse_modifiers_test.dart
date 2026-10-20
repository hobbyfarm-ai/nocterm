import 'package:nocterm/nocterm.dart';
import 'package:nocterm/src/keyboard/mouse_parser.dart';
import 'package:nocterm/src/rendering/mouse_hit_test.dart';
import 'package:nocterm/src/rendering/mouse_tracker.dart';
import 'package:test/test.dart';

/// Leaf render object that reports every gesture step on its whole area.
class _RenderGestureSink extends RenderObject
    with MouseTrackerAnnotationProvider {
  _RenderGestureSink(this.onGesture) {
    _annotation = MouseTrackerAnnotation(
      onGesture: onGesture,
      renderObject: this,
    );
  }

  final GestureUpdateCallback onGesture;
  late final MouseTrackerAnnotation _annotation;

  @override
  MouseTrackerAnnotation? get annotation => _annotation;

  @override
  void performLayout() {
    size = constraints.constrain(
      Size(constraints.maxWidth, constraints.maxHeight),
    );
  }

  @override
  bool hitTest(HitTestResult result, {required Offset position}) {
    if (!Rect.fromLTWH(0, 0, size.width, size.height).contains(position)) {
      return false;
    }
    if (result is MouseHitTestResult) {
      result.addWithPosition(target: this, localPosition: position);
    }
    return true;
  }
}

class _GestureSink extends SingleChildRenderObjectComponent {
  const _GestureSink({required this.onGesture});

  final GestureUpdateCallback onGesture;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderGestureSink(onGesture);
}

void main() {
  group('mouse modifiers', () {
    test('SGR button codes carry shift, meta and control', () {
      final shifted = MouseParser.fromSgrParams('4;3;2', pressed: true)!;
      expect(shifted.button, MouseButton.left);
      expect(shifted.modifiers, const ModifierKeys(shift: true));
      expect(shifted.x, 2);
      expect(shifted.y, 1);

      final chord = MouseParser.fromSgrParams('26;1;1', pressed: true)!;
      expect(chord.button, MouseButton.right);
      expect(chord.modifiers, const ModifierKeys(alt: true, ctrl: true));

      final plain = MouseParser.fromSgrParams('0;1;1', pressed: true)!;
      expect(plain.modifiers, const ModifierKeys());
      expect(plain.modifiers.hasAnyModifier, isFalse);
    });

    test('a modified wheel or drag is still a wheel or drag', () {
      final wheel = MouseParser.fromSgrParams('68;1;1', pressed: true)!;
      expect(wheel.button, MouseButton.wheelUp);
      expect(wheel.modifiers.shift, isTrue);

      final drag = MouseParser.fromSgrParams('36;5;5', pressed: true)!;
      expect(drag.button, MouseButton.left);
      expect(drag.isMotion, isTrue);
      expect(drag.modifiers.shift, isTrue);

      final hover = MouseParser.fromSgrParams('51;5;5', pressed: true)!;
      expect(hover.isMotion, isTrue);
      expect(hover.pressed, isFalse);
      expect(hover.modifiers.ctrl, isTrue);
    });

    test('X10 button bytes carry the same bits', () {
      final event = MouseParser.decodeX10(32 + 16 + 1, 33, 34)!;
      expect(event.button, MouseButton.middle);
      expect(event.pressed, isTrue);
      expect(event.modifiers, const ModifierKeys(ctrl: true));
      expect(event.y, 1);
    });

    test('toString names the modifiers only when some are held', () {
      const plain = MouseEvent(
        button: MouseButton.left,
        x: 0,
        y: 0,
        pressed: true,
      );
      expect(plain.toString(), isNot(contains('modifiers')));
      const shifted = MouseEvent(
        button: MouseButton.left,
        x: 0,
        y: 0,
        pressed: true,
        modifiers: ModifierKeys(shift: true),
      );
      expect(shifted.toString(), contains('modifiers=Shift'));
    });

    test('a gesture begins with the modifiers of its press', () async {
      await testNocterm('gesture modifiers', (tester) async {
        final updates = <GestureUpdate>[];
        await tester.pumpComponent(_GestureSink(onGesture: updates.add));
        await tester.sendMouseEvent(const MouseEvent(
          button: MouseButton.left,
          x: 2,
          y: 1,
          pressed: true,
          modifiers: ModifierKeys(shift: true),
        ));
        await tester.sendMouseEvent(const MouseEvent(
          button: MouseButton.left,
          x: 2,
          y: 1,
          pressed: false,
        ));
        expect(updates, hasLength(2));
        final began = updates.first as GestureBegan;
        expect(began.anchor, const Offset(2, 1));
        expect(began.modifiers, const ModifierKeys(shift: true));
        expect(updates.last, isA<GestureEnded>());
      });
    });
  });
}
