import 'package:nocterm/src/framework/framework.dart';
import 'package:nocterm/src/selection/selection.dart';
import 'package:nocterm/src/selection/selection_container.dart';
import 'package:nocterm/src/selection/text_selectable.dart';
import 'package:nocterm/src/size.dart';
import 'package:nocterm/src/text/text_layout_engine.dart';

/// A minimal selectable text render object for exercising the new selection
/// system without the production Text component.
class TestTextRender extends RenderObject
    with Selectable, SelectionRegistrant, TextSelectable {
  TestTextRender(this._text);

  String _text;
  String get text => _text;
  set text(String value) {
    if (_text == value) return;
    _text = value;
    markNeedsLayout();
  }

  TextLayoutResult? _layoutResult;

  @override
  String get selectableText => _text;

  @override
  TextLayoutResult? get selectableLayout => _layoutResult;

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void performLayout() {
    _layoutResult = TextLayoutEngine.layout(
      _text,
      TextLayoutConfig(maxWidth: constraints.maxWidth.toInt()),
    );
    size = constraints.constrain(Size(
      _layoutResult!.actualWidth.toDouble(),
      _layoutResult!.actualHeight.toDouble(),
    ));
    didLayoutSelectableText();
  }
}

/// A component wrapping [TestTextRender], wired to the enclosing
/// [SelectionRegistrarScope] the way production text components will be.
class SelectableTestText extends StatelessComponent {
  const SelectableTestText(this.text, {super.key});

  final String text;

  @override
  Component build(BuildContext context) {
    return _SelectableTestTextRenderComponent(
      text: text,
      registrar: SelectionRegistrarScope.maybeOf(context),
    );
  }
}

class _SelectableTestTextRenderComponent
    extends SingleChildRenderObjectComponent {
  const _SelectableTestTextRenderComponent({
    required this.text,
    required this.registrar,
  });

  final String text;
  final SelectionRegistrar? registrar;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return TestTextRender(text)..registrar = registrar;
  }

  @override
  void updateRenderObject(
      BuildContext context, covariant TestTextRender renderObject) {
    renderObject
      ..text = text
      ..registrar = registrar;
  }
}
