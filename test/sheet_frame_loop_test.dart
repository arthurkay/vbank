import 'package:flutter_test/flutter_test.dart';
import 'package:vbank/ui/ui.dart';

/// A focused text field must not keep the engine rendering frames.
///
/// shadcn's TextField defaults to `cursorOpacityAnimates: true`, which drives
/// the caret fade with a ticker that runs for as long as the field has focus —
/// a permanent ~90 fps render loop. On a low-end phone that saturated the UI
/// thread and ended in "vBank isn't responding" (ANR) while the join-group
/// passphrase sheet was open. Every vBank text field passes
/// `cursorOpacityAnimates: false`; this guards the sheets that autofocus.
void main() {
  Widget host(void Function(BuildContext) open) => ShadcnApp(
        home: DrawerOverlay(
          child: Builder(
            builder: (ctx) => PrimaryButton(onPressed: () => open(ctx), child: const Text('open')),
          ),
        ),
      );

  Future<void> expectSettles(WidgetTester tester, String what) async {
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1)); // entry animation
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.binding.hasScheduledFrame, isFalse, reason: '$what keeps scheduling frames');
  }

  testWidgets('confirmSheet settles', (tester) async {
    await tester.pumpWidget(host((ctx) => confirmSheet(ctx, title: 't', message: 'm')));
    await expectSettles(tester, 'confirmSheet');
  });

  testWidgets('promptSheet (autofocused text field) settles', (tester) async {
    await tester.pumpWidget(host((ctx) => promptSheet(ctx, title: 't', label: 'l', obscure: true)));
    await expectSettles(tester, 'promptSheet');
  });
}
