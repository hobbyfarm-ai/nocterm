import 'package:nocterm/nocterm.dart';
import 'package:test/test.dart';

import '../selection/test_text_render.dart';

class _CountingTextRender extends TestTextRender {
  _CountingTextRender(super.text);

  static int hitTests = 0;

  @override
  bool hitTest(HitTestResult result, {required Offset position}) {
    hitTests++;
    return super.hitTest(result, position: position);
  }
}

class _CountingText extends SingleChildRenderObjectComponent {
  const _CountingText(this.text, {this.registrar});

  final String text;
  final SelectionRegistrar? registrar;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _CountingTextRender(text)..registrar = registrar;
  }

  @override
  void updateRenderObject(
      BuildContext context, covariant _CountingTextRender renderObject) {
    renderObject
      ..text = text
      ..registrar = registrar;
  }
}

MouseEvent _motion(int x, int y) => MouseEvent(
      button: MouseButton.left,
      x: x,
      y: y,
      pressed: true,
      isMotion: true,
    );

void main() {
  group('mouse capture', () {
    test('captured drags route events without per-event hit testing', () async {
      await testNocterm(
        'capture skips hit testing',
        (tester) async {
          _CountingTextRender.hitTests = 0;
          String? completed;

          await tester.pumpComponent(
            SelectionArea(
              onSelectionCompleted: (text) => completed = text,
              child: Builder(
                builder: (context) => _CountingText(
                  'abcdefghijklmnopqrstuvwxyz',
                  registrar: SelectionRegistrarScope.maybeOf(context),
                ),
              ),
            ),
          );

          // The press hit-tests and starts a captured drag.
          await tester.press(0, 0);
          final baseline = _CountingTextRender.hitTests;

          final binding = NoctermTestBinding.instance;
          for (var i = 0; i < 40; i++) {
            binding.routeMouseEvent(_motion(1 + (i % 20), 0));
          }
          expect(_CountingTextRender.hitTests, baseline,
              reason: 'capture routes events straight to the captured '
                  'annotation; hit testing per motion event is pure waste');

          // Selection still tracks the drag and completes normally.
          await tester.release(9, 0);
          expect(completed, 'abcdefghi');

          // With the capture released, hit testing resumes.
          await tester.hover(5, 0);
          expect(_CountingTextRender.hitTests, greaterThan(baseline));
        },
      );
    });
  });
}
