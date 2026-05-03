import 'dart:math' as math;
import 'package:meta/meta.dart';

/// Returns the xterm 256-color palette index for [red], [green], [blue]
/// **only if the RGB values match a palette entry exactly** — otherwise
/// returns null. Used by the renderer to emit the shorter `\x1b[38;5;Nm`
/// (9-11 bytes) escape instead of `\x1b[38;2;R;G;Bm` (17-19 bytes) when
/// no quality loss is incurred.
///
/// The palette has two regions worth checking:
///   * 6×6×6 RGB cube (indices 16-231): each channel must be one of the
///     six discrete cube values {0, 95, 135, 175, 215, 255}.
///   * 24-step grayscale ramp (indices 232-255): r==g==b and the value
///     equals 8 + n*10 for some n in [0, 23].
///
/// Standard ANSI colors (indices 0-15) are skipped because their actual
/// RGB rendering is terminal-theme-dependent — emitting `\x1b[38;5;1m`
/// when the user wrote `Color.fromRGB(231, 97, 112)` could change colors
/// across themes. The cube/grayscale entries above are part of the
/// xterm spec and should render identically across compliant terminals.
int? exactAnsi256Index(int red, int green, int blue) {
  final ri = _cubeChannelIndex(red);
  final gi = _cubeChannelIndex(green);
  final bi = _cubeChannelIndex(blue);
  if (ri != null && gi != null && bi != null) {
    return 16 + 36 * ri + 6 * gi + bi;
  }
  if (red == green && green == blue) {
    if (red >= 8 && red <= 238 && (red - 8) % 10 == 0) {
      return 232 + (red - 8) ~/ 10;
    }
  }
  return null;
}

int? _cubeChannelIndex(int v) {
  switch (v) {
    case 0:
      return 0;
    case 95:
      return 1;
    case 135:
      return 2;
    case 175:
      return 3;
    case 215:
      return 4;
    case 255:
      return 5;
    default:
      return null;
  }
}

/// Quantizes RGB colors to the xterm 256-color palette.
int quantizeRgbToAnsi256(int red, int green, int blue) {
  final cacheKey = (red << 16) | (green << 8) | blue;
  final cached = _ansi256Cache[cacheKey];
  if (cached != null) {
    _ansi256Touch(cacheKey);
    return cached;
  }

  final lr = _srgb8ToLinear(red);
  final lg = _srgb8ToLinear(green);
  final lb = _srgb8ToLinear(blue);

  var bestIndex = 16;
  var bestDistance = double.infinity;

  for (final entry in _ansi256Palette) {
    final dr = lr - entry.lr;
    final dg = lg - entry.lg;
    final db = lb - entry.lb;
    final distance = dr * dr + dg * dg + db * db;
    if (distance < bestDistance) {
      bestDistance = distance;
      bestIndex = entry.index;
    }
  }

  _ansi256Cache[cacheKey] = bestIndex;
  _ansi256Touch(cacheKey);
  _ansi256PruneCache();
  return bestIndex;
}

@visibleForTesting
void resetAnsi256CacheForTesting() {
  _ansi256Cache.clear();
  _ansi256CacheOrder.clear();
  _ansi256CacheMaxEntries = _defaultCacheMaxEntries;
}

@visibleForTesting
void setAnsi256CacheMaxEntriesForTesting(int maxEntries) {
  _ansi256CacheMaxEntries = math.max(1, maxEntries);
  _ansi256PruneCache();
}

@visibleForTesting
int ansi256CacheSizeForTesting() => _ansi256Cache.length;

double _srgb8ToLinear(int value) {
  final v = value / 255.0;
  if (v <= 0.04045) {
    return v / 12.92;
  }
  return math.pow((v + 0.055) / 1.055, 2.4).toDouble();
}

const int _defaultCacheMaxEntries = 512;
int _ansi256CacheMaxEntries = _defaultCacheMaxEntries;
final Map<int, int> _ansi256Cache = <int, int>{};
final List<int> _ansi256CacheOrder = <int>[];

void _ansi256Touch(int key) {
  _ansi256CacheOrder.remove(key);
  _ansi256CacheOrder.add(key);
}

void _ansi256PruneCache() {
  while (_ansi256CacheOrder.length > _ansi256CacheMaxEntries) {
    final oldest = _ansi256CacheOrder.removeAt(0);
    _ansi256Cache.remove(oldest);
  }
}

final List<_AnsiColorEntry> _ansi256Palette = _buildAnsi256Palette();

List<_AnsiColorEntry> _buildAnsi256Palette() {
  final entries = <_AnsiColorEntry>[];

  for (int r = 0; r < 6; r++) {
    for (int g = 0; g < 6; g++) {
      for (int b = 0; b < 6; b++) {
        final index = 16 + (36 * r) + (6 * g) + b;
        final rr = _ansiCubeValue(r);
        final gg = _ansiCubeValue(g);
        final bb = _ansiCubeValue(b);
        entries.add(_AnsiColorEntry(
          index,
          _srgb8ToLinear(rr),
          _srgb8ToLinear(gg),
          _srgb8ToLinear(bb),
        ));
      }
    }
  }

  for (int i = 0; i < 24; i++) {
    final index = 232 + i;
    final value = 8 + (i * 10);
    final linear = _srgb8ToLinear(value);
    entries.add(_AnsiColorEntry(index, linear, linear, linear));
  }

  return entries;
}

int _ansiCubeValue(int index) {
  if (index == 0) return 0;
  return 55 + (index * 40);
}

class _AnsiColorEntry {
  final int index;
  final double lr;
  final double lg;
  final double lb;

  const _AnsiColorEntry(this.index, this.lr, this.lg, this.lb);
}
