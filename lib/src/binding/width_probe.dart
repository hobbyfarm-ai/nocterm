import 'dart:async';
import 'dart:io';

import '../backend/terminal.dart';
import '../keyboard/input_event.dart';
import '../utils/unicode_width.dart';

/// A probe cluster and the width each measurement method predicts for it.
class _Probe {
  final String cluster;
  final int graphemeWidth;
  final int legacyWidth;
  const _Probe(this.cluster, this.graphemeWidth, this.legacyWidth);
}

/// Ordered so the trailing entry (a lone wide CJK char) is an anchor that
/// every terminal must render at width 2 — used as a coherence check.
const _probes = <_Probe>[
  _Probe('👍🏽', 2, 4), // emoji + skin tone modifier
  _Probe('❤️', 2, 1), // narrow base + VS16
  _Probe('🇺🇸', 2, 4), // regional indicator pair
  _Probe('中', 2, 2), // lone wide char (anchor)
];

/// Detects how the terminal advances the cursor through grapheme clusters
/// and sets [UnicodeWidth.method] accordingly. Runs once at startup, before
/// the first frame.
///
/// An explicit `NOCTERM_WIDTH_METHOD=grapheme|legacy` env var skips probing.
/// If probing is inconclusive the result falls back to a [TERM_PROGRAM]
/// hint, defaulting to [WidthMethod.grapheme].
Future<void> detectWidthMethod({
  required Terminal terminal,
  required Stream<CursorPositionReport> reports,
  Duration timeout = const Duration(milliseconds: 150),
  Map<String, String>? environment,
}) async {
  final env = environment ?? Platform.environment;

  final override = env['NOCTERM_WIDTH_METHOD']?.trim().toLowerCase();
  if (override == 'legacy') {
    UnicodeWidth.method = WidthMethod.legacy;
    return;
  }
  if (override == 'grapheme') {
    UnicodeWidth.method = WidthMethod.grapheme;
    return;
  }

  final advances = await _measureAdvances(
    terminal: terminal,
    reports: reports,
    timeout: timeout,
  );

  UnicodeWidth.method = classifyWidthMethod(advances, env);
}

/// Writes each probe cluster followed by a DSR (`CSI 6n`) query on a single
/// row, then reads back the cursor columns and returns the per-cluster
/// advance. Returns null if the terminal didn't answer with all reports.
Future<List<int>?> _measureAdvances({
  required Terminal terminal,
  required Stream<CursorPositionReport> reports,
  required Duration timeout,
}) async {
  final columns = <int>[];
  final done = Completer<void>();
  final sub = reports.listen((report) {
    columns.add(report.col);
    if (columns.length >= _probes.length && !done.isCompleted) {
      done.complete();
    }
  });

  terminal.write('\r');
  for (final probe in _probes) {
    terminal.write(probe.cluster);
    terminal.write('\x1b[6n');
  }
  terminal.write('\r\x1b[2K');
  terminal.flush();

  try {
    await done.future.timeout(timeout);
  } on TimeoutException {
    // Fall through with whatever arrived.
  } finally {
    await sub.cancel();
  }

  if (columns.length < _probes.length) return null;

  final advances = <int>[];
  var prev = 1; // probes start at column 1
  for (final col in columns.take(_probes.length)) {
    advances.add(col - prev);
    prev = col;
  }
  return advances;
}

/// Maps measured per-cluster advances to a [WidthMethod]. Exposed for tests.
WidthMethod classifyWidthMethod(List<int>? advances, Map<String, String> env) {
  final fallback = _envHint(env);
  if (advances == null || advances.length != _probes.length) return fallback;

  // The anchor must render at width 2, else the terminal isn't answering
  // coherently (line wrap, partial replies) — trust the env hint.
  if (advances.last != 2) return fallback;

  var grapheme = 0;
  var legacy = 0;
  for (var i = 0; i < _probes.length; i++) {
    if (advances[i] == _probes[i].graphemeWidth) grapheme++;
    if (advances[i] == _probes[i].legacyWidth) legacy++;
  }

  if (grapheme == _probes.length) return WidthMethod.grapheme;
  if (legacy == _probes.length) return WidthMethod.legacy;
  if (grapheme > legacy) return WidthMethod.grapheme;
  if (legacy > grapheme) return WidthMethod.legacy;
  return fallback;
}

WidthMethod _envHint(Map<String, String> env) {
  const legacyPrograms = {'Apple_Terminal'};
  if (legacyPrograms.contains(env['TERM_PROGRAM'])) {
    return WidthMethod.legacy;
  }
  return WidthMethod.grapheme;
}
