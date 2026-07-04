import 'package:nocterm/nocterm.dart';
import 'package:test/test.dart';

void main() {
  group('ListView lazy layout', () {
    test('relayout at a deep scroll offset resumes near the viewport',
        () async {
      await testNocterm(
        'lazy layout resume',
        (tester) async {
          final controller = ScrollController();
          final built = <int>{};

          await tester.pumpComponent(
            ListView.builder(
              controller: controller,
              lazy: true,
              cacheExtent: 10,
              itemCount: 2000,
              itemBuilder: (context, index) {
                built.add(index);
                return Text('item $index');
              },
            ),
          );

          controller.jumpTo(500);
          await tester.pump();
          await tester.pump();

          // A frame at a settled deep offset must resume layout from the
          // cache window, not re-create every culled item from index 0.
          built.clear();
          controller.jumpTo(520);
          await tester.pump();

          expect(built.isNotEmpty, isTrue);
          expect(built.every((index) => index > 400), isTrue,
              reason: 'relayout rebuilt culled items far above the viewport: '
                  '${built.where((index) => index <= 400).take(5).toList()}...');
        },
      );
    });
  });
}
