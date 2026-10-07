import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../domain/core/failure.dart';
import '../../domain/meetings.dart';
import '../app_scope.dart';
import '../providers/auth.dart';
import '../providers/ledger.dart';

/// A group's meetings with scheduling and attendance flows.
final class MobileMeetingsScreen extends ConsumerWidget {
  /// The group meeting.
  final String groupId;

  /// Creates the meetings screen.
  const MobileMeetingsScreen({super.key, required this.groupId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Meeting>> meetings =
        ref.watch(meetingListProvider(groupId));
    return Scaffold(
      headers: [
        AppBar(
          leading: [
            IconButton.ghost(
              icon: const Icon(LucideIcons.arrowLeft),
              onPressed: () => Navigator.pop(context),
            ),
          ],
          title: const Text('Meetings'),
          trailing: [
            IconButton.ghost(
              key: const ValueKey('schedule-button'),
              icon: const Icon(LucideIcons.plus),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => MobileScheduleScreen(groupId: groupId),
                ),
              ),
            ),
          ],
        ),
      ],
      child: meetings.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, _) => Center(child: Text('Error: $error')),
        data: (List<Meeting> list) {
          if (list.isEmpty) {
            return const Center(child: Text('No meetings yet'));
          }
          return ListView.builder(
            itemCount: list.length,
            itemBuilder: (BuildContext context, int i) {
              final Meeting meeting = list[i];
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => MobileMeetingDetailScreen(
                      groupId: groupId,
                      meetingId: meeting.id,
                    ),
                  ),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${meeting.scheduledAt} · ${meeting.status.name}',
                        ).medium,
                      ),
                      const Icon(LucideIcons.chevronRight, size: 16),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Schedules a meeting days in the future.
final class MobileScheduleScreen extends ConsumerStatefulWidget {
  /// The group meeting.
  final String groupId;

  /// Creates the schedule screen.
  const MobileScheduleScreen({super.key, required this.groupId});

  @override
  ConsumerState<MobileScheduleScreen> createState() =>
      _MobileScheduleState();
}

final class _MobileScheduleState
    extends ConsumerState<MobileScheduleScreen> {
  /// Days from now input.
  final TextEditingController _days = TextEditingController(text: '7');

  /// Last failure, shown inline.
  String? _error;

  /// Save in flight.
  bool _saving = false;

  @override
  void dispose() {
    _days.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        headers: [
          AppBar(
            leading: [
              IconButton.ghost(
                icon: const Icon(LucideIcons.arrowLeft),
                onPressed: () => Navigator.pop(context),
              ),
            ],
            title: const Text('Schedule meeting'),
          ),
        ],
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('Days from now').small.semiBold.muted,
            const Gap(8),
            TextField(
              controller: _days,
              keyboardType: TextInputType.number,
              placeholder: const Text('7'),
            ),
            const Gap(20),
            if (_error != null) ...[
              Text(_error!).small,
              const Gap(12),
            ],
            PrimaryButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving…' : 'Schedule'),
            ),
          ],
        ),
      );

  /// Validates locally, schedules through the service, closes on success.
  Future<void> _save() async {
    final int? days = int.tryParse(_days.text.trim());
    final String? me = ref.read(authProvider).identity?.peerId;
    if (me == null) {
      setState(() => _error = 'Sign in first.');
      return;
    }
    if (days == null || days <= 0) {
      setState(() => _error = 'Enter days above zero.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final result =
        await ref.read(appServicesProvider).meetings.createMeeting(
              groupId: widget.groupId,
              actingPeerId: me,
              scheduledAt:
                  DateTime.now().toUtc().add(Duration(days: days)),
            );
    if (!mounted) {
      return;
    }
    if (result.isErr) {
      setState(() {
        _saving = false;
        _error = _explain(result.failure);
      });
      return;
    }
    Navigator.pop(context);
  }

  /// Machine failure codes to human words.
  static String _explain(Failure failure) => switch (failure) {
        PermissionFailure(:final action) => 'Not allowed ($action).',
        ValidationFailure(:final reason) => 'Check the form ($reason).',
        NotFoundFailure(:final subject) => 'Missing $subject.',
        ConflictFailure(:final subject) => 'Conflict on $subject.',
        NetworkFailure() => 'No connection.',
        IntegrityFailure(:final subject) => 'Rejected $subject.',
        StorageFailure() => 'Storage failed.',
      };
}

/// One meeting: attendance toggles and closing.
final class MobileMeetingDetailScreen extends ConsumerStatefulWidget {
  /// The group meeting.
  final String groupId;

  /// The meeting id.
  final String meetingId;

  /// Creates the detail screen.
  const MobileMeetingDetailScreen({
    super.key,
    required this.groupId,
    required this.meetingId,
  });

  @override
  ConsumerState<MobileMeetingDetailScreen> createState() =>
      _MobileMeetingDetailState();
}

final class _MobileMeetingDetailState
    extends ConsumerState<MobileMeetingDetailScreen> {
  /// Collected input.
  final TextEditingController _collected = TextEditingController(text: '0');

  /// Last failure, shown inline.
  String? _error;

  @override
  void dispose() {
    _collected.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<Meeting>> meetings =
        ref.watch(meetingListProvider(widget.groupId));
    final Meeting? meeting = meetings.valueOrNull
        ?.where((Meeting m) => m.id == widget.meetingId)
        .firstOrNull;
    if (meeting == null) {
      return Scaffold(
        headers: [
          AppBar(
            leading: [
              IconButton.ghost(
                icon: const Icon(LucideIcons.arrowLeft),
                onPressed: () => Navigator.pop(context),
              ),
            ],
            title: const Text('Meeting'),
          ),
        ],
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    final String? me = ref.watch(authProvider).identity?.peerId;
    final bool open = meeting.status == MeetingStatus.scheduled;
    return Scaffold(
      headers: [
        AppBar(
          leading: [
            IconButton.ghost(
              icon: const Icon(LucideIcons.arrowLeft),
              onPressed: () => Navigator.pop(context),
            ),
          ],
          title: const Text('Meeting'),
        ),
      ],
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(meeting.status.name).small.semiBold.muted,
          const Gap(8),
          Text('${meeting.presentCount} present').large,
          const Gap(16),
          if (_error != null) ...[
            Text(_error!).small,
            const Gap(12),
          ],
          for (final Attendance a in meeting.attendance)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(child: Text(a.peerId).medium),
                  if (open)
                    OutlineButton(
                      onPressed: () => _attend(
                        meeting,
                        a.peerId,
                        a.status == MeetingAttendanceStatus.present
                            ? MeetingAttendanceStatus.absent
                            : MeetingAttendanceStatus.present,
                        me!,
                      ),
                      child: Text(a.status.name),
                    )
                  else
                    Text(a.status.name).xSmall.muted,
                ],
              ),
            ),
          if (open) ...[
            const Gap(16),
            Text('Collected').small.semiBold.muted,
            const Gap(8),
            TextField(
              controller: _collected,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              placeholder: const Text('0.00'),
            ),
            const Gap(8),
            PrimaryButton(
              key: const ValueKey('complete-button'),
              onPressed: () => _complete(meeting),
              child: const Text('Complete meeting'),
            ),
          ],
        ],
      ),
    );
  }

  /// Flips one attendance record through the service.
  Future<void> _attend(
    Meeting meeting,
    String peerId,
    MeetingAttendanceStatus status,
    String me,
  ) async {
    final result = await ref
        .read(appServicesProvider)
        .meetings
        .recordAttendance(
          groupId: widget.groupId,
          actingPeerId: me,
          meetingId: meeting.id,
          peerId: peerId,
          status: status,
        );
    if (!mounted) {
      return;
    }
    if (result.isErr) {
      setState(() => _error = 'Failed (${result.failure}).');
    }
  }

  /// Closes the meeting with its collected total.
  Future<void> _complete(Meeting meeting) async {
    final String? me = ref.read(authProvider).identity?.peerId;
    final double collected = double.tryParse(_collected.text.trim()) ?? 0;
    if (me == null) {
      setState(() => _error = 'Sign in first.');
      return;
    }
    final result =
        await ref.read(appServicesProvider).meetings.completeMeeting(
              groupId: widget.groupId,
              actingPeerId: me,
              meetingId: meeting.id,
              totalCollected: collected,
            );
    if (!mounted) {
      return;
    }
    if (result.isErr) {
      setState(() => _error = 'Failed (${result.failure}).');
    }
  }
}
