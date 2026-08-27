import 'keyboard_event.dart';
import 'mouse_event.dart';

/// Base class for all input events (keyboard and mouse)
abstract class InputEvent {
  const InputEvent();
}

/// Keyboard input event
class KeyboardInputEvent extends InputEvent {
  final KeyboardEvent event;

  const KeyboardInputEvent(this.event);
}

/// Mouse input event
class MouseInputEvent extends InputEvent {
  final MouseEvent event;

  const MouseInputEvent(this.event);
}

/// Paste input event (from bracketed paste mode)
class PasteInputEvent extends InputEvent {
  final String text;

  const PasteInputEvent(this.text);
}

/// Cursor position report (reply to a DSR `CSI 6n` query): `CSI row;col R`.
/// Rows and columns are 1-based, as the terminal reports them.
class CursorPositionReport extends InputEvent {
  final int row;
  final int col;

  const CursorPositionReport(this.row, this.col);
}
