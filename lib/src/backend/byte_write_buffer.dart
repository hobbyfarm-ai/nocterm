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

  /// Appends a single ASCII byte directly. The caller is responsible for
  /// passing a value in the range [0, 0x7F]; no validation is performed
  /// because this is used in the SGR-encoder hot path.
  void writeAsciiByte(int byte) {
    if (_len == _buf.length) _ensureCapacity(_len + 1);
    _buf[_len++] = byte;
  }

  /// Appends [value] as an ASCII decimal integer. Hot path for color
  /// components and palette indices — both fall in [0, 999], so the
  /// inlined branches below avoid a divmod loop entirely. Negative or
  /// larger values fall through to a general routine.
  void writeAsciiInt(int value) {
    if (value < 0) {
      _writeAsciiIntGeneral(value);
      return;
    }
    if (value < 10) {
      if (_len == _buf.length) _ensureCapacity(_len + 1);
      _buf[_len++] = 0x30 + value;
      return;
    }
    if (value < 100) {
      _ensureCapacity(_len + 2);
      _buf[_len++] = 0x30 + (value ~/ 10);
      _buf[_len++] = 0x30 + (value % 10);
      return;
    }
    if (value < 1000) {
      _ensureCapacity(_len + 3);
      _buf[_len++] = 0x30 + (value ~/ 100);
      _buf[_len++] = 0x30 + ((value ~/ 10) % 10);
      _buf[_len++] = 0x30 + (value % 10);
      return;
    }
    _writeAsciiIntGeneral(value);
  }

  void _writeAsciiIntGeneral(int value) {
    // Fall-through for values outside the 0-999 fast path.
    final s = value.toString();
    final n = s.length;
    _ensureCapacity(_len + n);
    for (var i = 0; i < n; i++) {
      _buf[_len + i] = s.codeUnitAt(i);
    }
    _len += n;
  }

  /// Appends bytes from a `Uint8List` directly via `setRange`. Intended
  /// for precomputed escape-sequence prefixes — no encoding work happens.
  void writeAsciiBytes(Uint8List bytes) {
    final n = bytes.length;
    if (n == 0) return;
    _ensureCapacity(_len + n);
    _buf.setRange(_len, _len + n, bytes);
    _len += n;
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
