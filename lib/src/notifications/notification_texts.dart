import '../app/sync_coordinator.dart';

/// A notification's words. Pure data: screens and tests assert on these
/// without touching plugins.
final class NotificationText {
  /// Short title.
  final String title;

  /// One-line body.
  final String body;

  /// Creates the words.
  const NotificationText(this.title, this.body);
}

/// Words for a sync change, with resolved names. Returns null when the
/// change needs no notification (e.g. our own publish echo).
NotificationText? notificationTextFor(
  SyncChange change, {
  required String groupName,
  String? memberName,
  String? amount,
}) {
  final String who = memberName ?? 'A member';
  final String what = amount ?? '';
  switch (change.type) {
    case SyncChangeType.transaction:
      return NotificationText(
        'New transaction in $groupName',
        '$who recorded $what'.trim(),
      );
    case SyncChangeType.member:
      return NotificationText(
        'New member in $groupName',
        '$who joined the group.',
      );
    case SyncChangeType.loan:
      return NotificationText(
        'Loan update in $groupName',
        '$who $what'.trim(),
      );
    case SyncChangeType.meeting:
      return NotificationText(
        'Meeting update in $groupName',
        what.trim().isEmpty ? 'The schedule changed.' : what,
      );
    case SyncChangeType.reversal:
      return NotificationText(
        'Correction in $groupName',
        '$who requested a correction.'.trim(),
      );
    case SyncChangeType.group:
      return NotificationText(
        '$groupName updated',
        'Group details changed.',
      );
  }
}

/// Stable notification id for a change: repeats replace, never stack.
int notificationIdFor(SyncChange change) =>
    Object.hash(
      change.type.index,
      change.groupId,
      change.recordId ?? '',
    ) &
    0x7fffffff;
