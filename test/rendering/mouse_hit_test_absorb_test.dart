import 'package:nocterm/nocterm.dart';
import 'package:nocterm/src/framework/terminal_canvas.dart';
import 'package:nocterm/src/rendering/mouse_hit_test.dart';
import 'package:nocterm/src/rendering/mouse_tracker.dart';
import 'package:test/test.dart';

/// Leaf render object that annotates the whole area and absorbs the hit test
/// for positions at or beyond [absorbFromX].
class _RenderAbsorber extends RenderObject with MouseTrackerAnnotationProvider {
  _RenderAbsorber({required this.absorbFromX, required this.onHoverCount}) {
    _annotation = MouseTrackerAnnotation(
      onHover: (_) => onHoverCount(),
      renderObject: this,
    );
  }

  final int absorbFromX;
  final void Function() onHoverCount;
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
  void paint(TerminalCanvas canvas, Offset offset) {}

  @override
  bool hitTest(HitTestResult result, {required Offset position}) {
    if (!Rect.fromLTWH(0, 0, size.width, size.height).contains(position)) {
      return false;
    }
    if (result is MouseHitTestResult) {
      result.addWithPosition(target: this, localPosition: position);
      if (position.dx >= absorbFromX) result.absorb();
    }
    return true;
  }
}

class _Absorber extends SingleChildRenderObjectComponent {
  const _Absorber({required this.absorbFromX, required this.onHoverCount});

  final int absorbFromX;
  final void Function() onHoverCount;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderAbsorber(absorbFromX: absorbFromX, onHoverCount: onHoverCount);
}

void main() {
  group('MouseHitTestResult.absorb', () {
    _RenderAbsorber target() =>
        _RenderAbsorber(absorbFromX: 0, onHoverCount: () {});

    test('entries added before absorb are kept, later ones dropped', () {
      final result = MouseHitTestResult();
      final deep = target();
      final shallow = target();

      result.addWithPosition(target: deep, localPosition: Offset.zero);
      result.absorb();
      result.addWithPosition(target: shallow, localPosition: Offset.zero);

      expect(result.mouseEntries.map((e) => e.target), [deep]);
      expect(result.path, [deep]);
    });

    test('addMouseEntry is also a no-op after absorb', () {
      final result = MouseHitTestResult();
      final deep = target();

      result.absorb();
      result.addMouseEntry(MouseHitTestEntry(deep, localPosition: Offset.zero));

      expect(result.mouseEntries, hasLength(0));
    });

    test('a fresh result is not absorbed', () {
      final result = MouseHitTestResult();
      final deep = target();

      result.addWithPosition(target: deep, localPosition: Offset.zero);

      expect(result.mouseEntries, hasLength(1));
    });
  });

  group('absorb during dispatch', () {
    test(
      'ancestor annotation is dropped on absorbed cells and exits naturally',
      () async {
        await testNocterm('absorb integration', (tester) async {
          var regionEnter = 0;
          var regionExit = 0;
          var regionHover = 0;
          var absorberHover = 0;

          await tester.pumpComponent(
            Container(
              width: 80,
              height: 24,
              child: MouseRegion(
                onEnter: (_) => regionEnter++,
                onExit: (_) => regionExit++,
                onHover: (_) => regionHover++,
                child: _Absorber(
                  absorbFromX: 10,
                  onHoverCount: () => absorberHover++,
                ),
              ),
            ),
          );

          // Off the absorbed range: both the absorber and the ancestor
          // region hear the event.
          await tester.hover(2, 2);
          expect(absorberHover, 1);
          expect(regionEnter, 1);
          expect(regionHover, 1);
          expect(regionExit, 0);

          // Sliding onto an absorbed cell drops the ancestor from the hit
          // test result, so the tracker's normal exit pass fires for it.
          await tester.hover(12, 2);
          expect(absorberHover, 2);
          expect(regionExit, 1);
          expect(regionHover, 1, reason: 'no hover while absorbed');

          // Sliding back re-enters the ancestor normally.
          await tester.hover(2, 2);
          expect(regionEnter, 2);
          expect(regionHover, 2);
        });
      },
    );

    test('ancestor never enters when first hover lands absorbed', () async {
      await testNocterm('absorb first contact', (tester) async {
        var regionEnter = 0;
        var absorberHover = 0;

        await tester.pumpComponent(
          Container(
            width: 80,
            height: 24,
            child: MouseRegion(
              onEnter: (_) => regionEnter++,
              child: _Absorber(
                absorbFromX: 10,
                onHoverCount: () => absorberHover++,
              ),
            ),
          ),
        );

        await tester.hover(12, 2);
        expect(absorberHover, 1);
        expect(regionEnter, 0);
      });
    });
  });
}
