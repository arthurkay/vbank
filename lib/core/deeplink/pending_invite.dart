import 'package:flutter/widgets.dart';
import 'deeplink_handler.dart';

/// An invite link that arrived before the phone had an account.
///
/// Tapping an invite is often the very first thing a new member does, so the
/// join screen parks the link here, sends them through account creation (or a
/// backup restore) and [continuePendingInvite] resumes the join right after.
class PendingInvite {
  PendingInvite._();
  static DeepLinkResult? link;

  static bool get isPending => link != null;

  /// Human description for the onboarding screens.
  static String get description => 'You have been invited to a group. '
      'Create your account and you will join it right after.';
}

/// Opens the parked invite (if any) on top of the current route; returns
/// whether there was one.
bool continuePendingInvite(BuildContext context) {
  final link = PendingInvite.link;
  if (link == null) return false;
  PendingInvite.link = null;
  Navigator.pushNamed(context, '/join-group', arguments: link);
  return true;
}
