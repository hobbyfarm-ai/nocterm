import 'dart:collection';
import 'dart:convert';

import 'input_event.dart';
import 'keyboard_event.dart';
import 'logical_key.dart';
import 'mouse_parser.dart';

/// Parses raw terminal input bytes into input events (keyboard and mouse).
///
/// Implemented as a streaming state machine: every byte fed via [addBytes]
/// takes exactly one transition and is consumed exactly once, so partial
/// sequences survive chunk boundaries and no byte sequence can wedge the
/// parser. Completed events queue up and are drained with [parseNext].
class InputParser {
  final Queue<InputEvent> _events = Queue<InputEvent>();

  _ParseState _state = _ParseState.ground;

  /// Collected parameter/intermediate bytes of the CSI sequence being read.
  final List<int> _csi = [];

  /// Collected coordinate bytes of an X10 mouse event (button, x, y).
  final List<int> _x10 = [];

  /// Collected bytes of a multi-byte UTF-8 character.
  final List<int> _utf8 = [];
  int _utf8Expected = 0;

  /// Collected bracketed-paste content (may end with a partial end marker).
  final List<int> _paste = [];

  /// Runaway guard: a CSI longer than this is line noise, not a sequence.
  static const _maxCsiLength = 128;

  /// Add bytes to be parsed. Completed events queue for [parseNext].
  void addBytes(List<int> bytes) {
    for (final b in bytes) {
      _feed(b);
    }
  }

  /// Returns the next parsed event, or null if none is complete yet.
  InputEvent? parseNext() => _events.isEmpty ? null : _events.removeFirst();

  /// Convenience: [addBytes] + [parseNext].
  InputEvent? parseBytes(List<int> bytes) {
    addBytes(bytes);
    return parseNext();
  }

  /// Reset all parse state and drop queued events.
  void clear() {
    _events.clear();
    _csi.clear();
    _x10.clear();
    _utf8.clear();
    _utf8Expected = 0;
    _paste.clear();
    _state = _ParseState.ground;
  }

  /// True iff the parser is holding a bare `ESC` — either a standalone
  /// Escape press or the prefix of a sequence whose remainder hasn't
  /// arrived. The binding disambiguates with a short timeout.
  bool get hasPendingLoneEscape =>
      _state == _ParseState.escape && _events.isEmpty;

  /// Commit the deferred lone ESC as a standalone Escape event.
  /// Returns null if the parser is no longer holding one.
  KeyboardEvent? flushLoneEscape() {
    if (_state != _ParseState.escape) return null;
    _state = _ParseState.ground;
    return KeyboardEvent(
      logicalKey: LogicalKey.escape,
      modifiers: const ModifierKeys(),
    );
  }

  // State transitions

  void _feed(int b) {
    switch (_state) {
      case _ParseState.ground:
        _feedGround(b);
      case _ParseState.escape:
        _feedEscape(b);
      case _ParseState.csi:
        _feedCsi(b);
      case _ParseState.ss3:
        _feedSs3(b);
      case _ParseState.x10:
        _feedX10(b);
      case _ParseState.utf8:
        _feedUtf8(b);
      case _ParseState.paste:
        _feedPaste(b);
    }
  }

  void _feedGround(int b) {
    if (b == 0x1B) {
      _state = _ParseState.escape;
      return;
    }

    // Tab
    if (b == 0x09) {
      _emitKey(KeyboardEvent(
        logicalKey: LogicalKey.tab,
        character: '\t',
        modifiers: const ModifierKeys(),
      ));
      return;
    }

    // Enter/Return - 0x0D (CR) and 0x0A (LF).
    // In raw mode most terminals send 0x0D for Enter, but some (e.g. Warp)
    // may send 0x0A. When the kitty keyboard protocol is active, Ctrl+J
    // arrives as a kitty CSI sequence instead, so this doesn't interfere.
    if (b == 0x0D || b == 0x0A) {
      _emitKey(KeyboardEvent(
        logicalKey: LogicalKey.enter,
        character: '\n',
        modifiers: const ModifierKeys(),
      ));
      return;
    }

    // Backspace — both 0x7F and 0x08 (Ctrl+H) per terminal convention.
    if (b == 0x7F || b == 0x08) {
      _emitKey(KeyboardEvent(
        logicalKey: LogicalKey.backspace,
        modifiers: const ModifierKeys(),
      ));
      return;
    }

    // Control characters (Ctrl+A through Ctrl+Z)
    if (b >= 0x01 && b <= 0x1A) {
      final letterCode = b + 0x40;
      final letter = String.fromCharCode(letterCode).toLowerCase();
      final baseKey = LogicalKey.fromCharacter(letter) ??
          LogicalKey(letterCode, 'ctrl+$letter');
      _emitKey(KeyboardEvent(
        logicalKey: baseKey,
        modifiers: const ModifierKeys(ctrl: true),
      ));
      return;
    }

    // Ctrl+\ (backslash) sends 0x1C (File Separator)
    if (b == 0x1C) {
      _emitKey(KeyboardEvent(
        logicalKey: LogicalKey.backslash,
        modifiers: const ModifierKeys(ctrl: true),
      ));
      return;
    }

    // Single-byte character
    if (b < 0x80) {
      _emitCharacter(String.fromCharCode(b));
      return;
    }

    // UTF-8 lead byte
    if (b >= 0xC0 && b < 0xE0) {
      _startUtf8(b, 2);
    } else if (b >= 0xE0 && b < 0xF0) {
      _startUtf8(b, 3);
    } else if (b >= 0xF0) {
      _startUtf8(b, 4);
    } else {
      // Stray continuation byte — emit an unknown key so nothing stalls.
      _emitKey(KeyboardEvent(
        logicalKey: LogicalKey(b, 'unknown'),
        modifiers: const ModifierKeys(),
      ));
    }
  }

  void _feedEscape(int b) {
    if (b == 0x5B) {
      // CSI
      _csi.clear();
      _state = _ParseState.csi;
      return;
    }
    if (b == 0x4F) {
      // SS3
      _state = _ParseState.ss3;
      return;
    }
    if (b >= 0x61 && b <= 0x7A) {
      // Alt+lowercase letter
      final char = String.fromCharCode(b);
      final baseKey =
          LogicalKey.fromCharacter(char) ?? LogicalKey(b, 'unknown');
      _state = _ParseState.ground;
      _emitKey(KeyboardEvent(
        logicalKey: baseKey,
        character: char,
        modifiers: const ModifierKeys(alt: true),
      ));
      return;
    }
    if (b == 0x1B) {
      // ESC ESC: commit the first as Escape, keep holding the second.
      _emitKey(KeyboardEvent(
        logicalKey: LogicalKey.escape,
        modifiers: const ModifierKeys(),
      ));
      return;
    }
    // Anything else: the ESC was a standalone Escape; reprocess this byte.
    _state = _ParseState.ground;
    _emitKey(KeyboardEvent(
      logicalKey: LogicalKey.escape,
      modifiers: const ModifierKeys(),
    ));
    _feed(b);
  }

  void _feedCsi(int b) {
    // X10 mouse: ESC [ M then three raw coordinate bytes.
    if (b == 0x4D && _csi.isEmpty) {
      _x10.clear();
      _state = _ParseState.x10;
      return;
    }

    // A new ESC aborts the sequence — recover instead of garbling.
    if (b == 0x1B) {
      _csi.clear();
      _state = _ParseState.escape;
      return;
    }

    // Parameter and intermediate bytes.
    if (b >= 0x20 && b <= 0x3F) {
      _csi.add(b);
      if (_csi.length > _maxCsiLength) {
        _csi.clear();
        _state = _ParseState.ground;
      }
      return;
    }

    // Final byte: dispatch.
    if (b >= 0x40 && b <= 0x7E) {
      final params = String.fromCharCodes(_csi);
      _csi.clear();
      _state = _ParseState.ground;
      _dispatchCsi(params, b);
      return;
    }

    // C0 controls inside a CSI: ignore.
  }

  void _dispatchCsi(String params, int finalByte) {
    // SGR mouse: ESC [ < b ; x ; y M/m
    if (params.startsWith('<') && (finalByte == 0x4D || finalByte == 0x6D)) {
      final event = MouseParser.fromSgrParams(
        params.substring(1),
        pressed: finalByte == 0x4D,
      );
      if (event != null) _events.add(MouseInputEvent(event));
      return;
    }

    switch (finalByte) {
      case 0x75: // 'u' — kitty keyboard protocol
        final event = _decodeKitty(params);
        if (event != null) _emitKey(event);
        return;
      case 0x7E: // '~'
        _dispatchTilde(params);
        return;
      case 0x41: // A
      case 0x42: // B
      case 0x43: // C
      case 0x44: // D
      case 0x48: // H
      case 0x46: // F
        final event = _decodeCursorKey(params, finalByte);
        if (event != null) _emitKey(event);
        return;
      case 0x5A: // Z — Shift+Tab
        _emitKey(KeyboardEvent(
          logicalKey: LogicalKey.tab,
          modifiers: const ModifierKeys(shift: true),
        ));
        return;
      default:
        // Focus events (I/O), cursor position reports (R), and anything
        // else we don't map: consumed, no event, never a stall.
        return;
    }
  }

  KeyboardEvent? _decodeCursorKey(String params, int finalByte) {
    ModifierKeys modifiers = const ModifierKeys();
    if (params.isNotEmpty) {
      // Modified form: "1;<mod>"
      final parts = params.split(';');
      if (parts.length != 2 || parts[0] != '1') return null;
      final modifierValue = int.tryParse(parts[1]);
      if (modifierValue == null) return null;
      modifiers = _decodeModifiers(modifierValue);
    }
    final key = switch (finalByte) {
      0x41 => LogicalKey.arrowUp,
      0x42 => LogicalKey.arrowDown,
      0x43 => LogicalKey.arrowRight,
      0x44 => LogicalKey.arrowLeft,
      0x48 => LogicalKey.home,
      0x46 => LogicalKey.end,
      _ => null,
    };
    if (key == null) return null;
    return KeyboardEvent(logicalKey: key, modifiers: modifiers);
  }

  void _dispatchTilde(String params) {
    final parts = params.split(';');

    // Bracketed paste start.
    if (parts.length == 1 && parts[0] == '200') {
      _paste.clear();
      _state = _ParseState.paste;
      return;
    }

    // xterm modifyOtherKeys: 27 ; modifier ; charcode ~
    if (parts.length == 3 && parts[0] == '27') {
      final modifierValue = int.tryParse(parts[1]);
      final charCode = int.tryParse(parts[2]);
      if (modifierValue == null || charCode == null) return;
      _emitKey(_codepointToKeyEvent(charCode, _decodeModifiers(modifierValue)));
      return;
    }

    if (parts.length != 1) return;
    final key = switch (parts[0]) {
      '2' => LogicalKey.insert,
      '3' => LogicalKey.delete,
      '5' => LogicalKey.pageUp,
      '6' => LogicalKey.pageDown,
      '15' => LogicalKey.f5,
      '17' => LogicalKey.f6,
      '18' => LogicalKey.f7,
      '19' => LogicalKey.f8,
      '20' => LogicalKey.f9,
      '21' => LogicalKey.f10,
      '23' => LogicalKey.f11,
      '24' => LogicalKey.f12,
      _ => null,
    };
    if (key != null) {
      _emitKey(KeyboardEvent(logicalKey: key, modifiers: const ModifierKeys()));
    }
  }

  /// Kitty keyboard protocol: codepoint[:...] ; modifier[:...] u
  /// A '?'-prefixed params string is a flags query response — consumed.
  KeyboardEvent? _decodeKitty(String params) {
    if (params.startsWith('?')) return null;
    final parts = params.split(';');
    if (parts.isEmpty || parts.length > 3) return null;

    final codepoint = int.tryParse(parts[0].split(':').first);
    if (codepoint == null) return null;

    final modifierStr = parts.length >= 2 ? parts[1].split(':').first : null;
    final modifierValue =
        modifierStr != null ? int.tryParse(modifierStr) : null;
    final modifiers = modifierValue != null
        ? _decodeModifiers(modifierValue)
        : const ModifierKeys();

    return _codepointToKeyEvent(codepoint, modifiers);
  }

  void _feedSs3(int b) {
    _state = _ParseState.ground;
    final key = switch (b) {
      0x50 => LogicalKey.f1,
      0x51 => LogicalKey.f2,
      0x52 => LogicalKey.f3,
      0x53 => LogicalKey.f4,
      _ => null,
    };
    if (key != null) {
      _emitKey(KeyboardEvent(logicalKey: key, modifiers: const ModifierKeys()));
    }
  }

  void _feedX10(int b) {
    _x10.add(b);
    if (_x10.length < 3) return;

    _state = _ParseState.ground;
    final event = MouseParser.decodeX10(_x10[0], _x10[1], _x10[2]);
    _x10.clear();
    if (event != null) _events.add(MouseInputEvent(event));
  }

  void _startUtf8(int lead, int expected) {
    _utf8
      ..clear()
      ..add(lead);
    _utf8Expected = expected;
    _state = _ParseState.utf8;
  }

  void _feedUtf8(int b) {
    if (b < 0x80 || b >= 0xC0) {
      // Not a continuation byte: the sequence is malformed. Emit an unknown
      // key for the lead and reprocess everything else from ground.
      final pending = List<int>.of(_utf8.skip(1));
      final lead = _utf8.first;
      _utf8.clear();
      _state = _ParseState.ground;
      _emitKey(KeyboardEvent(
        logicalKey: LogicalKey(lead, 'unknown'),
        modifiers: const ModifierKeys(),
      ));
      pending.forEach(_feed);
      _feed(b);
      return;
    }

    _utf8.add(b);
    if (_utf8.length < _utf8Expected) return;

    _state = _ParseState.ground;
    try {
      _emitCharacter(utf8.decode(_utf8));
    } catch (_) {
      _emitKey(KeyboardEvent(
        logicalKey: LogicalKey(_utf8.first, 'unknown'),
        modifiers: const ModifierKeys(),
      ));
    }
    _utf8.clear();
  }

  void _feedPaste(int b) {
    _paste.add(b);
    if (!_endsWithPasteTerminator()) return;

    final content = _paste.sublist(0, _paste.length - 6);
    _paste.clear();
    _state = _ParseState.ground;
    _events.add(PasteInputEvent(utf8.decode(content, allowMalformed: true)));
  }

  bool _endsWithPasteTerminator() {
    // ESC [ 2 0 1 ~
    const marker = [0x1B, 0x5B, 0x32, 0x30, 0x31, 0x7E];
    if (_paste.length < marker.length) return false;
    final start = _paste.length - marker.length;
    for (var i = 0; i < marker.length; i++) {
      if (_paste[start + i] != marker[i]) return false;
    }
    return true;
  }

  // Event helpers

  void _emitKey(KeyboardEvent event) {
    _events.add(KeyboardInputEvent(event));
  }

  void _emitCharacter(String char) {
    final key = LogicalKey.fromCharacter(char);
    final code = char.codeUnitAt(0);
    final isUpperCase =
        (code >= 0x41 && code <= 0x5A) || (char != char.toLowerCase());
    _emitKey(KeyboardEvent(
      logicalKey: key ?? LogicalKey(code, 'unknown'),
      character: char,
      modifiers: ModifierKeys(shift: isUpperCase),
    ));
  }

  /// Decode modifier bitmask from kitty/modifyOtherKeys/xterm protocols.
  /// The value sent is 1 + bitmask.
  ModifierKeys _decodeModifiers(int value) {
    final bitmask = value - 1;
    return ModifierKeys(
      shift: (bitmask & 1) != 0,
      alt: (bitmask & 2) != 0,
      ctrl: (bitmask & 4) != 0,
      meta: (bitmask & 8) != 0,
    );
  }

  KeyboardEvent _codepointToKeyEvent(int codepoint, ModifierKeys modifiers) {
    switch (codepoint) {
      case 13:
        return KeyboardEvent(
          logicalKey: LogicalKey.enter,
          character: '\n',
          modifiers: modifiers,
        );
      case 9:
        return KeyboardEvent(
          logicalKey: LogicalKey.tab,
          character: '\t',
          modifiers: modifiers,
        );
      case 27:
        return KeyboardEvent(
          logicalKey: LogicalKey.escape,
          modifiers: modifiers,
        );
      case 127:
        return KeyboardEvent(
          logicalKey: LogicalKey.backspace,
          modifiers: modifiers,
        );
      default:
        final char = String.fromCharCode(codepoint);
        final key = LogicalKey.fromCharacter(char) ??
            LogicalKey(codepoint, 'codepoint($codepoint)');
        return KeyboardEvent(
          logicalKey: key,
          character: char,
          modifiers: modifiers,
        );
    }
  }
}

enum _ParseState { ground, escape, csi, ss3, x10, utf8, paste }
