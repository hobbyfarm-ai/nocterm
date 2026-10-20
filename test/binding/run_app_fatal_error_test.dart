import 'package:nocterm/nocterm.dart';
import 'fake_backend.dart';
import 'package:test/test.dart' hide isEmpty, isNotEmpty;

void main() {
  test(
    'runApp restores the terminal, reports the error, and rethrows '
    'when startup fails',
    () async {
      final backend = FakeBackend(
        size: const Size(20, 5),
        inputFailure: StateError('boom'),
      );

      await expectLater(
        runApp(
          const Text('unreachable'),
          backend: backend,
          enableHotReload: false,
        ),
        throwsA(
          isA<StateError>().having((e) => e.message, 'message', 'boom'),
        ),
      );

      final written = backend.output;
      // Mouse tracking disabled and main buffer restored, so the terminal is
      // usable again.
      expect(written, contains('\x1B[?1000l'));
      expect(written, contains('\x1B[?1006l'));
      expect(written, contains('\x1b[?1049l'));
      // The failure is reported on the restored screen, after the cleanup
      // sequences.
      expect(
        written.indexOf('Unhandled error: Bad state: boom'),
        greaterThan(written.lastIndexOf('\x1b[?1049l')),
      );
      // Everything was drained to the terminal before rethrowing.
      expect(backend.drainedAfterLastWrite, isTrue);
    },
  );
}
