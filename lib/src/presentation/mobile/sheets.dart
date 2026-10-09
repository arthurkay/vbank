import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Bottom sheets, the only popup pattern in the app: confirms, menus
/// and pickers all slide up from here — never centered dialogs.
///
/// The sheet reads the live theme (matte dark, paper light), caps at 90%
/// of the screen, pads for the keyboard and honors reduce-motion.
library;

/// Shows [child] in a themed bottom sheet with a drag handle and title.
/// Returns the sheet's result (for pickers) or null when dismissed.
Future<T?> showVBankSheet<T>(
  BuildContext context, {
  required String title,
  required Widget child,
}) {
  final ColorScheme scheme = Theme.of(context).colorScheme;
  final bool reduce =
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: scheme.card,
    barrierColor: scheme.foreground.withAlpha(120),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    transitionAnimationController: reduce
        ? AnimationController(
            vsync: Navigator.of(context),
            duration: Duration.zero,
          )
        : null,
    builder: (BuildContext sheetContext) {
      final double maxHeight =
          MediaQuery.sizeOf(sheetContext).height * 0.9;
      return Padding(
        padding: MediaQuery.viewInsetsOf(sheetContext),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: scheme.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const Gap(12),
                  Text(title).large.semiBold,
                  const Gap(12),
                  child,
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// Confirms an action in a sheet. Returns true when the action button
/// is tapped, false on cancel or dismiss.
Future<bool> confirmSheet(
  BuildContext context, {
  required String title,
  required String body,
  required String actionLabel,
  bool danger = false,
}) async {
  final bool? confirmed = await showVBankSheet<bool>(
    context,
    title: title,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(body).small.muted,
        const Gap(20),
        Row(
          children: [
            Expanded(
              child: OutlineButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
            ),
            const Gap(8),
            Expanded(
              child: danger
                  ? DestructiveButton(
                      onPressed: () =>
                          Navigator.pop(context, true),
                      child: Text(actionLabel),
                    )
                  : PrimaryButton(
                      onPressed: () =>
                          Navigator.pop(context, true),
                      child: Text(actionLabel),
                    ),
            ),
          ],
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
