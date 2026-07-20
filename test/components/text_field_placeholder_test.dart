import 'package:nocterm/nocterm.dart';
import 'package:test/test.dart';

class _StringNotifier extends ValueListenable<String> {
  _StringNotifier(this._value);

  String _value;
  final _listeners = <VoidCallback>[];

  @override
  String get value => _value;

  set value(String next) {
    if (_value == next) return;
    _value = next;
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }

  @override
  void addListener(VoidCallback listener) => _listeners.add(listener);

  @override
  void removeListener(VoidCallback listener) => _listeners.remove(listener);
}

void main() {
  group('TextField placeholder', () {
    test('re-lays-out when the placeholder changes on an empty field',
        () async {
      await testNocterm(
        'placeholder update',
        (tester) async {
          final placeholder = _StringNotifier('Type a message...');

          await tester.pumpComponent(
            ValueListenableBuilder<String>(
              valueListenable: placeholder,
              builder: (context, value, child) => TextField(
                width: 40,
                placeholder: value,
              ),
            ),
          );

          expect(tester.terminalState, containsText('Type a message...'));

          placeholder.value = 'Generating...';
          await tester.pump();

          expect(tester.terminalState, containsText('Generating...'));
          expect(
            tester.terminalState,
            isNot(containsText('Type a message...')),
          );
        },
        debugPrintAfterPump: false,
      );
    });
  });
}
