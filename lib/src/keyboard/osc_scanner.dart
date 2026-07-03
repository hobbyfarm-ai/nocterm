/// Extracts OSC sequences (`ESC ] ... BEL` or `ESC ] ... ESC \`) from a raw
/// input byte stream before keyboard/mouse parsing.
///
/// Unlike a per-chunk scan, this is a streaming state machine: a sequence
/// split across reads is held here until its terminator arrives, so partial
/// OSC bytes never leak into the input parser (where an `ESC ]` head would
/// otherwise stall parsing).
///
/// A lone `ESC` at the end of a chunk is held (it may be the start of a
/// split `ESC ]`); the next chunk resolves it. If no more bytes arrive, the
/// binding's Escape-ambiguity timer calls [takePendingEsc] to commit it as a
/// standalone Escape keypress.
class OscScanner {
  OscScanner({required this.onOsc});

  /// Called with the content of each complete OSC sequence (without the
  /// `ESC ]` prefix or terminator).
  final void Function(List<int> content) onOsc;

  _OscScanState _state = _OscScanState.ground;
  final List<int> _content = [];

  /// Whether the scanner is holding an unterminated OSC sequence.
  bool get isInOsc =>
      _state == _OscScanState.osc || _state == _OscScanState.oscEsc;

  /// Whether the scanner is holding a chunk-final `ESC` whose meaning is not
  /// yet known (OSC start vs. Escape keypress vs. other sequence).
  bool get hasPendingEsc => _state == _OscScanState.escGuard;

  /// Releases a held chunk-final `ESC`, returning it for the caller to feed
  /// to the input parser. Returns an empty list if none is held.
  List<int> takePendingEsc() {
    if (!hasPendingEsc) return const [];
    _state = _OscScanState.ground;
    return const [0x1b];
  }

  /// Filters [bytes], removing OSC sequences and returning what remains.
  List<int> filter(List<int> bytes) {
    final out = <int>[];

    for (var i = 0; i < bytes.length; i++) {
      final b = bytes[i];
      switch (_state) {
        case _OscScanState.ground:
          if (b == 0x1b) {
            if (i + 1 >= bytes.length) {
              // Chunk-final ESC: hold until the next chunk (or the binding's
              // Escape-ambiguity timeout) resolves it.
              _state = _OscScanState.escGuard;
            } else if (bytes[i + 1] == 0x5d) {
              _content.clear();
              _state = _OscScanState.osc;
              i++; // consume the ']'
            } else {
              out.add(b);
            }
          } else {
            out.add(b);
          }
        case _OscScanState.escGuard:
          if (b == 0x5d) {
            _content.clear();
            _state = _OscScanState.osc;
          } else {
            out.add(0x1b);
            _state = _OscScanState.ground;
            i--; // reprocess this byte in ground
          }
        case _OscScanState.osc:
          if (b == 0x07) {
            _dispatch();
          } else if (b == 0x1b) {
            _state = _OscScanState.oscEsc;
          } else {
            _content.add(b);
          }
        case _OscScanState.oscEsc:
          if (b == 0x5c) {
            // ESC \ (ST) terminator.
            _dispatch();
          } else if (b == 0x5d) {
            // ESC ] — a new OSC started before the old one terminated.
            _dispatch();
            _content.clear();
            _state = _OscScanState.osc;
          } else {
            // ESC followed by anything else aborts the string; hand the new
            // escape sequence to the parser.
            _dispatch();
            out.add(0x1b);
            out.add(b);
          }
      }
    }

    return out;
  }

  void _dispatch() {
    onOsc(List<int>.of(_content));
    _content.clear();
    _state = _OscScanState.ground;
  }

  /// Drops any partially collected sequence.
  void reset() {
    _content.clear();
    _state = _OscScanState.ground;
  }
}

enum _OscScanState { ground, escGuard, osc, oscEsc }
