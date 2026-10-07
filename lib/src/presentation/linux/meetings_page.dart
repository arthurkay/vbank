import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaru/yaru.dart';

import '../../domain/core/failure.dart';
import '../../domain/meetings.dart';
import '../app_scope.dart';
import '../providers/auth.dart';
import '../providers/ledger.dart';

/// A group's meetings with scheduling and attendance flows on Linux.
final class LinuxMeetingsPage extends ConsumerWidget {
  /// The group meeting.
  final String groupId;

  /// Creates the meetings page.
  const LinuxMeetingsPage({super.key, required this.groupId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Meeting>> meetings =
        ref.watch(meetingListProvider(groupId));
    return YaruDetailPage(
      appBar: AppBar(
        leading: YaruBackButton(onPressed: () => Navigator.pop(context)),
        title: const Text('Meetings'),
        actions: [
          IconButton(
            key: const ValueKey('schedule-button'),
            tooltip: 'Schedule meeting',
            icon: const Icon(YaruIcons.plus),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => LinuxSchedulePage(groupId: groupId),
              ),
            ),
          ),
        ],
      ),
      body: meetings.when(
        loading: () => const Center(child: YaruCircularProgressIndicator()),
        error: (Object error, _) => Center(child: Text('Error: $error')),
        data: (List<Meeting> list) {
          if (list.isEmpty) {
            return const Center(child: Text('No meetings yet'));
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            itemCount: list.length,
            itemBuilder: (BuildContext context, int i) {
              final Meeting meeting = list[i];
              return YaruListTile(
                title: Text(
                  '${meeting.scheduledAt} · ${meeting.status.name}',
                ),
                trailing: const Icon(YaruIcons.pan_end),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => LinuxMeetingDetailPage(
                      groupId: groupId,
                      meetingId: meeting.id,
                    ),
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
final class LinuxSchedulePage extends ConsumerStatefulWidget {
  /// The group meeting.
  final String groupId;

  /// Creates the schedule page.
  const LinuxSchedulePage({super.key, required this.groupId});

  @override
  ConsumerState<LinuxSchedulePage> createState() => _LinuxScheduleState();
}

final class _LinuxScheduleState extends ConsumerState<LinuxSchedulePage> {
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
  Widget build(BuildContext context) => YaruDetailPage(
        appBar: AppBar(
          leading: YaruBackButton(onPressed: () => Navigator.pop(context)),
          title: const Text('Schedule meeting'),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          children: [
            const Text('Days from now'),
            TextField(
              controller: _days,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(hintText: '7'),
            ),
            const SizedBox(height: 20),
            if (_error != null) ...[
              Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 12),
            ],
            FilledButton(
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
              scheduledAt: DateTime.now().toUtc().add(Duration(days: days)),
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
final class LinuxMeetingDetailPage extends ConsumerStatefulWidget {
  /// The group meeting.
  final String groupId;

  /// The meeting id.
  final String meetingId;

  /// Creates the detail page.
  const LinuxMeetingDetailPage({
    super.key,
    required this.groupId,
    required this.meetingId,
  });

  @override
  ConsumerState<LinuxMeetingDetailPage> createState() =>
      _LinuxMeetingDetailState();
}

final class _LinuxMeetingDetailState
    extends ConsumerState<LinuxMeetingDetailPage> {
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
    final List<Meeting> meetings =
        ref.watch(meetingListProvider(widget.groupId)).valueOrNull ?? [];
    Meeting? meeting;
    for (final Meeting m in meetings) {
      if (m.id == widget.meetingId) {
        meeting = m;
      }
    }
    if (meeting == null) {
      return YaruDetailPage(
        appBar: AppBar(
          leading: YaruBackButton(onPressed: () => Navigator.pop(context)),
          title: const Text('Meeting'),
        ),
        body: const Center(child: YaruCircularProgressIndicator()),
      );
    }
    final Meeting current = meeting;
    final String? me = ref.watch(authProvider).identity?.peerId;
    final bool open = current.status == MeetingStatus.scheduled;
    return YaruDetailPage(
      appBar: AppBar(
        leading: YaruBackButton(onPressed: () => Navigator.pop(context)),
        title: const Text('Meeting'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        children: [
          Text(
            '${current.presentCount} present · ${current.status.name}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 16),
          if (_error != null) ...[
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
          ],
          for (final Attendance a in current.attendance)
            YaruListTile(
              title: Text(a.peerId),
              trailing: open
                  ? FilledButton.tonal(
                      onPressed: () => _attend(
                        current,
                        a.peerId,
                        a.status == MeetingAttendanceStatus.present
                            ? MeetingAttendanceStatus.absent
                            : MeetingAttendanceStatus.present,
                        me!,
                      ),
                      child: Text(a.status.name),
                    )
                  : Text(a.status.name),
            ),
          if (open) ...[
            const SizedBox(height: 16),
            const Text('Collected'),
            TextField(
              controller: _collected,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(hintText: '0.00'),
            ),
            const SizedBox(height: 8),
            FilledButton(
              key: const ValueKey('complete-button'),
              onPressed: () => _complete(current),
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
