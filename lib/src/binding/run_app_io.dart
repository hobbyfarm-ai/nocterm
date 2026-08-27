import 'dart:async';
import 'dart:io';

import 'package:nocterm/nocterm.dart'
    hide StdioBackend, SocketBackend, WebBackend;
import 'package:nocterm/src/backend/socket_backend.dart';
import 'package:nocterm/src/backend/stdio_backend.dart';
import 'package:nocterm/src/backend/terminal.dart' as term;
import 'package:nocterm/src/binding/width_probe.dart';

(File?, bool) _useShellMode() {
// Check for shell mode
  final shellHandleFile = File(getShellHandlePath());
  if (shellHandleFile.existsSync() case false) {
    return (null, false);
  }

  final socketPath = shellHandleFile.readAsStringSync().trim();
  if (socketPath.isEmpty) {
    return (null, false);
  }

  if (File(socketPath).existsSync()) {
    return (shellHandleFile, true);
  }

  return (null, false);
}

/// Run a TUI application on native platforms (Linux, macOS, Windows).
Future<void> runAppImpl(
  Component app, {
  bool enableHotReload = true,
  TerminalBackend? backend,
}) async {
  // Wrap the user's app with DebugOverlay so Ctrl+G toggle works out of the box
  final wrappedApp = DebugOverlay(child: app);

  // Determine backend and whether we're in shell mode
  final TerminalBackend effectiveBackend;
  final bool isShellMode;

  if (backend != null) {
    effectiveBackend = backend;
    isShellMode = false;
  } else if (_useShellMode() case (final file?, true)) {
    final socketPath = await file.readAsString();
    final socket = await Socket.connect(
      InternetAddress(socketPath.trim(), type: InternetAddressType.unix),
      0,
    );
    effectiveBackend = SocketBackend(socket);
    isShellMode = true;
  } else {
    effectiveBackend = StdioBackend();
    isShellMode = false;
  }

  await _runApp(wrappedApp, effectiveBackend, enableHotReload, isShellMode);
}

Future<void> _runApp(
  Component app,
  TerminalBackend backend,
  bool enableHotReload,
  bool isShellMode,
) async {
  TerminalBinding? binding;
  LogServer? logServer;
  Logger? logger;
  Object? fatalError;
  StackTrace? fatalStackTrace;

  void recordFatal(Object error, StackTrace stackTrace) {
    fatalError ??= error;
    fatalStackTrace ??= stackTrace;
  }

  try {
    logServer = LogServer();
    try {
      await logServer.start();
      logger = Logger(logServer: logServer);
    } catch (e) {
      stderr.writeln('Failed to start log server: $e');
    }

    await runZoned(() async {
      try {
        final terminal = term.Terminal(backend);
        binding = TerminalBinding(terminal);

        binding!.initialize();
        binding!.attachRootComponent(app);

        // Detect the terminal's grapheme-width behavior before the first
        // frame.
        if (!isShellMode && stdout.hasTerminal && stdin.hasTerminal) {
          try {
            await detectWidthMethod(
              terminal: terminal,
              reports: binding!.cursorPositionReports,
            );
          } catch (_) {}
        }

        if (enableHotReload && !bool.fromEnvironment('dart.vm.product')) {
          await binding!.initializeHotReload();
        }

        await binding!.runEventLoop();
      } catch (error, stackTrace) {
        recordFatal(error, stackTrace);
      }
    },
        zoneSpecification: ZoneSpecification(
          print: (Zone self, ZoneDelegate parent, Zone zone, String message) {
            logger?.log(message);
            if (isShellMode) {
              parent.print(zone, message);
            }
          },
          handleUncaughtError: (Zone self, ZoneDelegate parent, Zone zone,
              Object error, StackTrace stackTrace) {
            final errorMessage = 'ERROR: $error\n$stackTrace';
            logger?.log(errorMessage);
            if (isShellMode) {
              stderr.writeln(errorMessage);
            }
          },
        ));
  } catch (error, stackTrace) {
    recordFatal(error, stackTrace);
  } finally {
    if (binding != null && !binding!.shouldExit) {
      binding!.shutdown();
    }
    try {
      await logger?.close();
      await logServer?.close();
    } catch (_) {}
  }

  final error = fatalError;
  if (error != null) {
    final stackTrace = fatalStackTrace ?? StackTrace.empty;
    final report = 'Unhandled error: $error\n$stackTrace\n';
    if (backend.isAvailable) {
      backend.writeRaw(report);
    }
    stderr.write(report);
    await backend.drainOutput();
    try {
      await stderr.flush();
    } catch (_) {}
    Error.throwWithStackTrace(error, stackTrace);
  }
}
