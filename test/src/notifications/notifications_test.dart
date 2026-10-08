import 'package:flutter_test/flutter_test.dart';
import 'package:vbank/src/app/sync_coordinator.dart';
import 'package:vbank/src/notifications/notification_texts.dart';
import 'package:vbank/src/notifications/notifier.dart';
import 'package:vbank/src/notifications/reminder_scheduler.dart';
import 'package:vbank/src/notifications/reminder_sink.dart';
import 'package:vbank/src/notifications/sync_notifications.dart';

import '../app/harness.dart';

void main() {
  group('notification texts', () {
    test('transaction names who and how much', () {
      const change = SyncChange(
        SyncChangeType.transaction,
        'g1',
        recordId: 'tx1',
      );
      final text = notificationTextFor(
        change,
        groupName: 'Savings',
        memberName: 'Amina',
        amount: 'contributed ZK 100.00',
      )!;
      expect(text.title, 'New transaction in Savings');
      expect(text.body, 'Amina recorded contributed ZK 100.00');
    });

    test('member join welcomes', () {
      const change = SyncChange(
        SyncChangeType.member,
        'g1',
        recordId: 'peer2',
      );
      final text = notificationTextFor(
        change,
        groupName: 'Savings',
        memberName: 'Brian',
      )!;
      expect(text.title, 'New member in Savings');
      expect(text.body, 'Brian joined the group.');
    });

    test('ids are stable per change', () {
      const a = SyncChange(SyncChangeType.loan, 'g1', recordId: 'l1');
      const b = SyncChange(SyncChangeType.loan, 'g1', recordId: 'l1');
      const c = SyncChange(SyncChangeType.loan, 'g1', recordId: 'l2');
      expect(notificationIdFor(a), notificationIdFor(b));
      expect(notificationIdFor(a) == notificationIdFor(c), isFalse);
    });
  });

  group('sync notifications', () {
    test("others' records notify, own echo stays silent", () async {
      final AppHarness h = AppHarness();
      await h.init();
      final String gid = await h.seedGroup();
      final MemoryNotifier notifier = MemoryNotifier();

      final txs =
          (await h.stackFor('owner').transactions.listByGroup(gid)).value;
      final String txId = txs.first.id;

      // Another member's contribution notifies.
      await notifySyncChange(
        SyncChange(SyncChangeType.transaction, gid, recordId: txId),
        groups: h.stackFor('owner').groups,
        transactions: h.transactionRepo,
        loans: h.loanRepo,
        meetings: h.meetingRepo,
        notifier: notifier,
        selfPeerId: 'member',
      );
      expect(notifier.shown, hasLength(1));
      expect(notifier.shown.first.$2, contains('Test Group'));
      expect(notifier.shown.first.$3, contains('ZK'));

      // Our own publish echo stays silent.
      await notifySyncChange(
        SyncChange(SyncChangeType.transaction, gid, recordId: txId),
        groups: h.stackFor('owner').groups,
        transactions: h.transactionRepo,
        loans: h.loanRepo,
        meetings: h.meetingRepo,
        notifier: notifier,
        selfPeerId: 'owner',
      );
      expect(notifier.shown, hasLength(1));
    });

    test('joins notify everyone but the joiner', () async {
      final AppHarness h = AppHarness();
      await h.init();
      final String gid = await h.seedGroup();
      final MemoryNotifier notifier = MemoryNotifier();

      await notifySyncChange(
        const SyncChange(SyncChangeType.member, 'gid-x', recordId: 'member'),
        groups: h.stackFor('owner').groups,
        transactions: h.transactionRepo,
        loans: h.loanRepo,
        meetings: h.meetingRepo,
        notifier: notifier,
        selfPeerId: 'owner',
      );
      // Unknown group id: fallback words, still shown.
      expect(notifier.shown, hasLength(1));
      expect(notifier.shown.first.$2, 'New member in Your group');

      await notifySyncChange(
        SyncChange(SyncChangeType.member, gid, recordId: 'member'),
        groups: h.stackFor('owner').groups,
        transactions: h.transactionRepo,
        loans: h.loanRepo,
        meetings: h.meetingRepo,
        notifier: notifier,
        selfPeerId: 'owner',
      );
      expect(notifier.shown, hasLength(2));
      expect(notifier.shown.last.$3, contains('joined'));

      await notifySyncChange(
        SyncChange(SyncChangeType.member, gid, recordId: 'member'),
        groups: h.stackFor('owner').groups,
        transactions: h.transactionRepo,
        loans: h.loanRepo,
        meetings: h.meetingRepo,
        notifier: notifier,
        selfPeerId: 'member',
      );
      expect(notifier.shown, hasLength(2));
    });
  });

  group('reminder scheduler', () {
    test('schedules a meeting reminder a day before', () async {
      final AppHarness h = AppHarness();
      await h.init();
      final String gid = await h.seedGroup();
      final DateTime at = DateTime.utc(2026, 1, 7, 9);
      final created = await h
          .stackFor('owner')
          .meetings
          .createMeeting(
            groupId: gid,
            actingPeerId: 'owner',
            scheduledAt: at,
          );
      expect(created.isOk, isTrue);

      final MemoryReminderSink sink = MemoryReminderSink();
      await scheduleGroupReminders(
        groups: h.stackFor('owner').groups,
        loans: h.loanRepo,
        meetings: h.meetingRepo,
        sink: sink,
        groupId: gid,
        now: DateTime.utc(2026, 1, 5, 9),
      );

      expect(sink.scheduled, hasLength(1));
      expect(sink.scheduled.first.$2, contains('Meeting tomorrow'));
      expect(
        sink.scheduled.first.$4,
        DateTime.utc(2026, 1, 6, 9),
      );
    });

    test('skips distant meetings and distant dues', () async {
      final AppHarness h = AppHarness();
      await h.init();
      final String gid = await h.seedGroup();
      await h.stackFor('owner').meetings.createMeeting(
            groupId: gid,
            actingPeerId: 'owner',
            scheduledAt: DateTime.utc(2026, 3, 1, 9),
          );

      final MemoryReminderSink sink = MemoryReminderSink();
      await scheduleGroupReminders(
        groups: h.stackFor('owner').groups,
        loans: h.loanRepo,
        meetings: h.meetingRepo,
        sink: sink,
        groupId: gid,
        now: DateTime.utc(2026, 1, 5, 9),
      );

      expect(sink.scheduled, isEmpty);
    });
  });
}
