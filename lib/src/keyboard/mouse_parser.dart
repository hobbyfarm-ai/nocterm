import 'mouse_event.dart';

/// Parses mouse escape sequences from terminal input
class MouseParser {
  /// Parse SGR mouse sequence (ESC [ < button ; x ; y M/m)
  /// Returns null if not a valid mouse sequence
  static MouseEvent? parseSGR(List<int> buffer) {
    if (buffer.length < 9) {
      return null;
    }

    // Check for ESC [ <
    if (buffer[0] != 0x1B || buffer[1] != 0x5B || buffer[2] != 0x3C) {
      return null;
    }

    // Find the terminator (M or m)
    int terminatorIndex = -1;
    for (int i = 3; i < buffer.length; i++) {
      if (buffer[i] == 0x4D || buffer[i] == 0x6D) {
        // 'M' or 'm'
        terminatorIndex = i;
        break;
      }
    }

    if (terminatorIndex == -1) return null;

    // Parse the parameters between < and M/m
    final params = String.fromCharCodes(buffer.sublist(3, terminatorIndex));
    return fromSgrParams(params, pressed: buffer[terminatorIndex] == 0x4D);
  }

  /// Decode an SGR mouse event from its parameter string ("b;x;y") and
  /// terminator ('M' = [pressed], 'm' = release).
  static MouseEvent? fromSgrParams(String params, {required bool pressed}) {
    final parts = params.split(';');
    if (parts.length != 3) return null;

    final buttonCode = int.tryParse(parts[0]);
    final rawX = int.tryParse(parts[1]);
    final rawY = int.tryParse(parts[2]);
    if (buttonCode == null || rawX == null || rawY == null) return null;

    final x = rawX - 1; // Convert to 0-based
    final y = rawY - 1;

    // Decode button from SGR button code
    MouseButton? button;

    // In SGR mode:
    // Bits 0-1: button number (0=left, 1=middle, 2=right, 3=release/none)
    // Bit 5 (32): motion/drag flag
    // Bit 6 (64): shift for wheel (64=up, 65=down)

    // Check for wheel events first (64 and 65)
    if (buttonCode == 64) {
      button = MouseButton.wheelUp;
    } else if (buttonCode == 65) {
      button = MouseButton.wheelDown;
    } else {
      final baseButton = buttonCode & 0x3;
      switch (baseButton) {
        case 0:
          button = MouseButton.left;
          break;
        case 1:
          button = MouseButton.middle;
          break;
        case 2:
          button = MouseButton.right;
          break;
        case 3:
          // Release or motion with no button - use left as placeholder.
          button = MouseButton.left;
          break;
      }
    }

    if (button == null) return null;

    final isMotionEvent = (buttonCode & 0x20) != 0; // Bit 5 indicates motion

    // SGR motion with baseButton=3 indicates hover (no buttons pressed).
    final effectivePressed =
        isMotionEvent && (buttonCode & 0x3) == 3 ? false : pressed;

    return MouseEvent(
      button: button,
      x: x,
      y: y,
      pressed: effectivePressed,
      isMotion: isMotionEvent,
    );
  }

  /// Parse X10 mouse sequence (ESC [ M button x y)
  /// Legacy format, still used by some terminals
  static MouseEvent? parseX10(List<int> buffer) {
    if (buffer.length < 6) return null;

    // Check for ESC [ M
    if (buffer[0] != 0x1B || buffer[1] != 0x5B || buffer[2] != 0x4D) {
      return null;
    }

    if (buffer.length != 6) return null;
    return decodeX10(buffer[3], buffer[4], buffer[5]);
  }

  /// Decode an X10 mouse event from its three raw payload bytes.
  static MouseEvent? decodeX10(int buttonRaw, int xRaw, int yRaw) {
    // X10 encoding: button and coordinates are offset by 32
    final buttonByte = buttonRaw - 32;
    final x = xRaw - 33; // -32 for encoding, -1 for 0-based
    final y = yRaw - 33;

    // Validate coordinates
    if (x < 0 || y < 0) return null;

    // Decode button
    MouseButton? button;
    bool pressed = true;

    // In X10 mode:
    // Bits 0-1: button number (0=left, 1=middle, 2=right, 3=release)
    // Bit 6: wheel flag
    final buttonNum = buttonByte & 0x03;
    final wheelFlag = buttonByte & 0x40;

    if (wheelFlag != 0) {
      // Wheel events (always "pressed")
      if (buttonNum == 0) {
        button = MouseButton.wheelUp;
      } else if (buttonNum == 1) {
        button = MouseButton.wheelDown;
      }
    } else {
      // Regular buttons
      if (buttonNum == 3) {
        // Release event - we don't know which button, default to left
        button = MouseButton.left;
        pressed = false;
      } else {
        pressed = true;
        switch (buttonNum) {
          case 0:
            button = MouseButton.left;
            break;
          case 1:
            button = MouseButton.middle;
            break;
          case 2:
            button = MouseButton.right;
            break;
        }
      }
    }

    if (button == null) return null;

    return MouseEvent(
      button: button,
      x: x,
      y: y,
      pressed: pressed,
    );
  }
}
