import 'package:nocterm/nocterm.dart';
import 'package:test/test.dart';

void main() {
  group('ProgressBar', () {
    test('visual development - basic progress bar', () async {
      await testNocterm(
        'basic progress bar at different values',
        (tester) async {
          print('Progress at 0%:');
          await tester.pumpComponent(
            SizedBox(
              width: 30,
              height: 1,
              child: ProgressBar(
                value: 0.0,
                valueColor: Colors.green,
                backgroundColor: Colors.grey,
              ),
            ),
          );

          print('\nProgress at 25%:');
          await tester.pumpComponent(
            SizedBox(
              width: 30,
              height: 1,
              child: ProgressBar(
                value: 0.25,
                valueColor: Colors.green,
                backgroundColor: Colors.grey,
              ),
            ),
          );

          print('\nProgress at 50%:');
          await tester.pumpComponent(
            SizedBox(
              width: 30,
              height: 1,
              child: ProgressBar(
                value: 0.5,
                valueColor: Colors.blue,
                backgroundColor: Colors.grey,
              ),
            ),
          );

          print('\nProgress at 75%:');
          await tester.pumpComponent(
            SizedBox(
              width: 30,
              height: 1,
              child: ProgressBar(
                value: 0.75,
                valueColor: Colors.yellow,
                backgroundColor: Colors.grey,
              ),
            ),
          );

          print('\nProgress at 100%:');
          await tester.pumpComponent(
            SizedBox(
              width: 30,
              height: 1,
              child: ProgressBar(
                value: 1.0,
                valueColor: Colors.green,
                backgroundColor: Colors.grey,
              ),
            ),
          );
        },
        debugPrintAfterPump: true,
      );
    });

    test('visual development - progress bar with borders', () async {
      await testNocterm(
        'progress bars with different border styles',
        (tester) async {
          print('Single border:');
          await tester.pumpComponent(
            SizedBox(
              width: 30,
              height: 3,
              child: ProgressBar(
                value: 0.6,
                borderStyle: ProgressBarBorderStyle.single,
                valueColor: Colors.cyan,
                backgroundColor: Colors.grey,
              ),
            ),
          );

          print('\nDouble border:');
          await tester.pumpComponent(
            SizedBox(
              width: 30,
              height: 3,
              child: ProgressBar(
                value: 0.6,
                borderStyle: ProgressBarBorderStyle.double,
                valueColor: Colors.magenta,
                backgroundColor: Colors.grey,
              ),
            ),
          );

          print('\nRounded border:');
          await tester.pumpComponent(
            SizedBox(
              width: 30,
              height: 3,
              child: ProgressBar(
                value: 0.6,
                borderStyle: ProgressBarBorderStyle.rounded,
                valueColor: Colors.green,
                backgroundColor: Colors.grey,
              ),
            ),
          );

          print('\nBold border:');
          await tester.pumpComponent(
            SizedBox(
              width: 30,
              height: 3,
              child: ProgressBar(
                value: 0.6,
                borderStyle: ProgressBarBorderStyle.bold,
                valueColor: Colors.red,
                backgroundColor: Colors.grey,
              ),
            ),
          );
        },
        debugPrintAfterPump: true,
      );
    });

    test('visual development - progress bar with percentage', () async {
      await testNocterm(
        'progress bar showing percentage',
        (tester) async {
          print('Progress bar with percentage display:');
          await tester.pumpComponent(
            Column(
              children: [
                SizedBox(
                  width: 40,
                  height: 3,
                  child: ProgressBar(
                    value: 0.33,
                    showPercentage: true,
                    borderStyle: ProgressBarBorderStyle.single,
                    valueColor: Colors.green,
                    backgroundColor: Colors.grey,
                  ),
                ),
                SizedBox(height: 1),
                SizedBox(
                  width: 40,
                  height: 3,
                  child: ProgressBar(
                    value: 0.67,
                    showPercentage: true,
                    borderStyle: ProgressBarBorderStyle.rounded,
                    valueColor: Colors.blue,
                    backgroundColor: Colors.grey,
                  ),
                ),
              ],
            ),
          );
        },
        debugPrintAfterPump: true,
      );
    });

    test('visual development - custom characters', () async {
      await testNocterm(
        'progress bar with custom fill characters',
        (tester) async {
          print('Custom characters:');
          await tester.pumpComponent(
            Column(
              children: [
                Text('Using = and -'),
                SizedBox(
                  width: 30,
                  height: 1,
                  child: ProgressBar(
                    value: 0.7,
                    fillCharacter: '=',
                    emptyCharacter: '-',
                    valueColor: Colors.cyan,
                    backgroundColor: Colors.grey,
                  ),
                ),
                SizedBox(height: 1),
                Text('Using # and .'),
                SizedBox(
                  width: 30,
                  height: 1,
                  child: ProgressBar(
                    value: 0.4,
                    fillCharacter: '#',
                    emptyCharacter: '.',
                    valueColor: Colors.yellow,
                    backgroundColor: Colors.grey,
                  ),
                ),
                SizedBox(height: 1),
                Text('Using ▓ and ░'),
                SizedBox(
                  width: 30,
                  height: 1,
                  child: ProgressBar(
                    value: 0.85,
                    fillCharacter: '▓',
                    emptyCharacter: '░',
                    valueColor: Colors.magenta,
                    backgroundColor: Colors.grey,
                  ),
                ),
              ],
            ),
          );
        },
        debugPrintAfterPump: true,
      );
    });

    test('visual development - progress bar with labels', () async {
      await testNocterm(
        'progress bar with custom labels',
        (tester) async {
          print('Progress bars with labels:');
          await tester.pumpComponent(
            Column(
              children: [
                SizedBox(
                  width: 40,
                  height: 3,
                  child: ProgressBar(
                    value: 0.45,
                    label: 'Loading...',
                    borderStyle: ProgressBarBorderStyle.single,
                    valueColor: Colors.green,
                    backgroundColor: Colors.grey,
                  ),
                ),
                SizedBox(height: 1),
                SizedBox(
                  width: 40,
                  height: 3,
                  child: ProgressBar(
                    value: 0.75,
                    label: 'Processing',
                    borderStyle: ProgressBarBorderStyle.double,
                    valueColor: Colors.blue,
                    backgroundColor: Colors.grey,
                  ),
                ),
                SizedBox(height: 1),
                SizedBox(
                  width: 40,
                  height: 1,
                  child: ProgressBar(
                    value: 0.9,
                    label: 'Done!',
                    valueColor: Colors.green,
                    backgroundColor: Colors.grey,
                  ),
                ),
              ],
            ),
          );
        },
        debugPrintAfterPump: true,
      );
    });

    test('indeterminate pulse slides as a pure rotation with no snap', () {
      // The band must advance exactly one cell per animation step and wrap
      // seamlessly.
      for (final width in [3, 4, 5, 12, 20, 40]) {
        // Sample the middle of each cell so floating-point rounding never
        // lands on a cell boundary.
        List<bool> at(int lead) => indeterminatePulse(width, lead + 0.5);

        final litCount = at(0).where((lit) => lit).length;
        expect(litCount, greaterThan(0));

        for (int lead = 0; lead < width; lead++) {
          final current = at(lead);
          final previous = at((lead - 1 + width) % width);

          expect(current.where((lit) => lit).length, litCount,
              reason: 'band size changed at lead=$lead (width=$width)');

          final rotatedPrevious = [
            for (int x = 0; x < width; x++) previous[(x - 1 + width) % width]
          ];
          expect(current, rotatedPrevious,
              reason:
                  'lead=$lead is not previous rotated by one (width=$width)');
        }
      }
    });

    test('indeterminate bar self-animates over elapsed time', () async {
      await testNocterm(
        'indeterminate self-animation',
        (tester) async {
          await tester.pumpComponent(
            SizedBox(
              width: 40,
              height: 1,
              child: ProgressBar(
                indeterminate: true,
                valueColor: Colors.cyan,
                backgroundColor: Colors.grey,
              ),
            ),
          );

          // No external state changes the tree — only wall-clock time passes.
          final frames = <String>{tester.terminalState.getText()};
          for (int i = 0; i < 4; i++) {
            await tester.pump(const Duration(milliseconds: 120));
            frames.add(tester.terminalState.getText());
          }

          expect(frames.length, greaterThan(1),
              reason: 'indeterminate bar did not animate on its own');
        },
      );
    });

    test('indeterminate animation survives a rebuild that recreates its State',
        () async {
      await testNocterm(
        'indeterminate rebuild keeps phase',
        (tester) async {
          // A differing key fails canUpdate, so the old State is disposed and a
          // fresh one is created — the same thing that happens when an item in
          // a list rebuilds and loses its State.
          ProgressBar bar(String key) => ProgressBar(
                key: ValueKey(key),
                indeterminate: true,
                valueColor: Colors.cyan,
                backgroundColor: Colors.grey,
              );

          await tester.pumpComponent(
            SizedBox(width: 40, height: 1, child: bar('a')),
          );

          // Let the band slide well past its starting position.
          for (int i = 0; i < 3; i++) {
            await tester.pump(const Duration(milliseconds: 120));
          }
          final beforeRebuild = tester.terminalState.getText();

          // Rebuild with a new key: State (and the ticker) restart, but almost
          // no wall-clock time passes.
          await tester.pumpComponent(
            SizedBox(width: 40, height: 1, child: bar('b')),
          );
          final afterRebuild = tester.terminalState.getText();

          // The band must sit where the absolute clock says, not snap back to
          // the start as it would if the phase were ticker-relative.
          expect(afterRebuild, equals(beforeRebuild),
              reason: 'recreating the State restarted the animation');
        },
      );
    });

    test('renders correctly', () async {
      await testNocterm(
        'correct rendering',
        (tester) async {
          await tester.pumpComponent(
            SizedBox(
              width: 20,
              height: 1,
              child: ProgressBar(
                value: 0.5,
              ),
            ),
          );

          // Check that the progress bar contains filled and unfilled parts
          final terminalContent = tester.terminalState.getText();
          expect(terminalContent, contains('█'));
          expect(terminalContent, contains('░'));
        },
      );
    });

    test('handles different sizes', () async {
      await testNocterm(
        'different sizes',
        (tester) async {
          // Small progress bar
          await tester.pumpComponent(
            SizedBox(
              width: 10,
              height: 1,
              child: ProgressBar(value: 0.5),
            ),
          );

          expect(tester.terminalState.getText().length, greaterThan(0));

          // Large progress bar
          await tester.pumpComponent(
            SizedBox(
              width: 50,
              height: 5,
              child: ProgressBar(
                value: 0.5,
                borderStyle: ProgressBarBorderStyle.single,
              ),
            ),
          );

          final content = tester.terminalState.getText();
          expect(content, contains('─'));
          expect(content, contains('│'));
        },
      );
    });
  });
}
