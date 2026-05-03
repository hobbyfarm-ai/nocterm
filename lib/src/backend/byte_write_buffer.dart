import 'dart:convert';
import 'dart:typed_data';

/// Append-only byte buffer used by [Terminal] to accumulate frame output.
///
/// Replaces the per-frame `StringBuffer` so the diff renderer accumulates
/// raw UTF-8 bytes directly. At flush time, [takeBytes] hands a `Uint8List`
/// to the backend without String materialization or whole-buffer UTF-8
/// encoding — the two operations that dominated the previous flush path.
///
/// The hot win is the ASCII fast path: every ANSI escape sequence and
/// every plain-text character is < 0x80, so [write] avoids the UTF-8
/// encoder for the common case and does a tight `codeUnit -> byte` copy
/// directly into the backing store.
///
/// The backing buffer grows geometrically and is reused across frames
/// (zero-fill is unnecessary; only the live prefix is consumed).
class ByteWriteBuffer {
  ByteWriteBuffer({int initialCapacity = 8192})
      : _buf = Uint8List(initialCapacity);

  Uint8List _buf;
  int _len = 0;

  int get length => _len;
  bool get isEmpty => _len == 0;
  bool get isNotEmpty => _len > 0;

  /// Appends [text] as UTF-8. Single pass over the string's code units —
  /// copy each ASCII unit (< 0x80) directly into the buffer; on the first
  /// non-ASCII unit, discard the partial write and fall back to a full
  /// `utf8.encode`. Wins big for ANSI escape codes and ASCII text (the
  /// common case); only pays the encoder cost for actual wide chars.
  void write(String text) {
    final n = text.length;
    if (n == 0) return;

    _ensureCapacity(_len + n);
    var pos = _len;
    for (var i = 0; i < n; i++) {
      final u = text.codeUnitAt(i);
      if (u >= 0x80) {
        // Non-ASCII: drop whatever we partially wrote past `_len`, encode
        // the full string, and copy the encoded form. The partial bytes
        // sitting past `_len` are harmless (overwritten by `setRange`).
        final encoded = utf8.encode(text);
        _ensureCapacity(_len + encoded.length);
        _buf.setRange(_len, _len + encoded.length, encoded);
        _len += encoded.length;
        return;
      }
      _buf[pos++] = u;
    }
    _len = pos;
  }

  /// Returns the accumulated bytes as a freshly-allocated `Uint8List` and
  /// resets the buffer. Allocates once per flush — much cheaper than the
  /// previous `StringBuffer.toString()` + `utf8.encode` pair.
  Uint8List takeBytes() {
    if (_len == 0) return Uint8List(0);
    final result = Uint8List(_len);
    result.setRange(0, _len, _buf);
    _len = 0;
    return result;
  }

  /// Clears the buffer without producing output.
  void clear() {
    _len = 0;
  }

  void _ensureCapacity(int needed) {
    if (needed <= _buf.length) return;
    var cap = _buf.length;
    while (cap < needed) {
      cap *= 2;
    }
    final newBuf = Uint8List(cap);
    newBuf.setRange(0, _len, _buf);
    _buf = newBuf;
  }
}
