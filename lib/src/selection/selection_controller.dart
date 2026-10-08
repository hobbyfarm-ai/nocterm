import '../components/scroll_controller.dart';
import 'selection.dart';
import 'selection_container_delegate.dart';

/// Programmatic access to a [SelectionArea]'s selection.
///
/// Hand one to [SelectionArea.controller]; the area attaches its delegate
/// while mounted. Listeners fire on every change to the selection geometry.
class SelectionController extends ChangeNotifier {
  SelectionContainerDelegate? _delegate;

  /// Whether the area currently shows a non-collapsed selection.
  bool get hasSelection =>
      _delegate?.value.status == SelectionStatus.uncollapsed;

  /// Clears the area's selection.
  void clear() {
    _delegate?.dispatchSelectionEvent(const ClearSelectionEvent());
  }

  /// Binds this controller to [delegate], replacing any earlier binding.
  void attach(SelectionContainerDelegate delegate) {
    detach();
    _delegate = delegate;
    delegate.addListener(notifyListeners);
  }

  /// Releases the current binding, if any.
  void detach() {
    _delegate?.removeListener(notifyListeners);
    _delegate = null;
  }

  @override
  void dispose() {
    detach();
    super.dispose();
  }
}
