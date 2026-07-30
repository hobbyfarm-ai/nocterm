import 'package:nocterm/nocterm.dart';
import 'package:test/test.dart';

/// Rebuilds a list whose builders return const components — the same
/// instances every call. Updating an element with the identical component
/// trips an assert in Element.update, so the viewport must skip the no-op.
class _RebuildHarness extends StatefulComponent {
  const _RebuildHarness({super.key});

  @override
  State<_RebuildHarness> createState() => _RebuildHarnessState();
}

class _RebuildHarnessState extends State<_RebuildHarness> {
  var _generation = 0;

  void rebuild() => setState(() => _generation++);

  @override
  Component build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('generation $_generation'),
        Expanded(
          child: ListView.separated(
            itemCount: 3,
            itemBuilder: (context, index) => const Text('item'),
            separatorBuilder: (context, index) => const Text('---'),
          ),
        ),
      ],
    );
  }
}

void main() {
  group('ListView const children', () {
    test('const items and separators survive a rebuild', () async {
      await testNocterm('const children rebuild', (tester) async {
        final key = GlobalKey<_RebuildHarnessState>();
        await tester.pumpComponent(_RebuildHarness(key: key));

        expect(tester.terminalState, containsText('item'));
        expect(tester.terminalState, containsText('---'));

        key.currentState!.rebuild();
        await tester.pump();

        expect(tester.terminalState, containsText('generation 1'));
        expect(tester.terminalState, containsText('item'));
        expect(tester.terminalState, containsText('---'));
      }, size: const Size(40, 10));
    });
  });
}
