import 'dart:math';

import 'package:nocterm/nocterm.dart';
import 'package:test/test.dart';

late _HostState _host;

class _Host extends StatefulComponent {
  const _Host();

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  int shape = 0;
  int generation = 0;

  void show(int shape) => setState(() {
        this.shape = shape;
        generation++;
      });

  @override
  Component build(BuildContext context) {
    _host = this;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _row(shape),
        SizedBox(key: ValueKey(generation), child: _row(shape)),
      ],
    );
  }
}

Component _row(int shape) {
  final leader = shape & 1 == 1;
  final fact = shape & 2 == 2;
  final bar = shape & 4 == 4;
  return Row(
    children: [
      const SizedBox(width: 1, child: Text('>')),
      SizedBox(width: 1),
      if (leader) ...[
        const Text('LABEL'),
        const SizedBox(width: 1),
        Expanded(
            child: bar ? const Text('####') : SizedBox(child: Text('----'))),
      ] else
        Expanded(child: Text('LABEL')),
      if (fact) ...[
        const SizedBox(width: 1),
        const Text('F'),
      ],
    ],
  );
}

void main() {
  test('a reused row keeps its children in order', () async {
    await testNocterm('row order', size: const Size(30, 2), (tester) async {
      await tester.pumpComponent(const _Host());
      final random = Random(1);
      for (var step = 0; step < 200; step++) {
        final previous = _host.shape;
        final shape = random.nextInt(8);
        _host.show(shape);
        await tester.pump();
        final lines = tester.terminalState.getText().split('\n');
        expect(lines[0], lines[1], reason: 'shape $previous to $shape');
      }
    });
  });
}
