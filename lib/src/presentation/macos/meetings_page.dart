import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';

import '../../domain/core/failure.dart';
import '../../domain/meetings.dart';
import '../app_scope.dart';
import '../providers/auth.dart';
import '../providers/ledger.dart';

/// A group's meetings with scheduling and attendance flows on macOS.
final class MacosMeetingsPage extends ConsumerWidget {
  /// The group meeting.
  final String groupId;

  /// Creates the meetings page.
  const MacosMeetingsPage({super.key, required this.groupId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Meeting>> meetings =
        ref.watch(meetingListProvider(groupId));
    return MacosScaffold(
      toolBar: ToolBar(
        leading: MacosBackButton(onPressed: () => Navigator.pop(context)),
        title: const Text('Meetings'),
        actions: [
          ToolBarIconButton(
            key: const ValueKey('schedule-button'),
            label: 'Schedule meeting',
            icon: const MacosIcon(CupertinoIcons.add),
            showLabel: false,
            onPressed: () => Navigator.push(
              context,
              CupertinoPageRoute<void>(
                builder: (_) => MacosSchedulePage(groupId: groupId),
              ),
            ),
          ),
        ],
      ),
      children: [
        ContentArea(
          builder: (BuildContext context, ScrollController controller) =>
              meetings.when(
            loading: () => const Center(child: ProgressCircle()),
            error: (Object error, _) => Center(child: Text('Error: $error')),
            data: (List<Meeting> list) {
              if (list.isEmpty) {
                return const Center(child: Text('No meetings yet'));
              }
              return ListView.builder(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                itemCount: list.length,
                itemBuilder: (BuildContext context, int i) {
                  final Meeting meeting = list[i];
                  return MacosListTile(
                    leading: const MacosIcon(CupertinoIcons.calendar),
                    title: Text(
                      '${meeting.scheduledAt} · ${meeting.status.name}',
                      style: MacosTheme.of(context).typography.headline,
                    ),
                    onClick: () => Navigator.push(
                      context,
                      CupertinoPageRoute<void>(
                        builder: (_) => MacosMeetingDetailPage(
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
        ),
      ],
    );
  }
}

/// Schedules a meeting days in the future.
final class MacosSchedulePage extends ConsumerStatefulWidget {
  /// The group meeting.
  final String groupId;

  /// Creates the schedule page.
  const MacosSchedulePage({super.key, required this.groupId});

  @override
  ConsumerState<MacosSchedulePage> createState() => _MacosScheduleState();
}

final class _MacosScheduleState extends ConsumerState<MacosSchedulePage> {
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
  Widget build(BuildContext context) => MacosScaffold(
        toolBar: ToolBar(
          leading: MacosBackButton(onPressed: () => Navigator.pop(context)),
          title: const Text('Schedule meeting'),
        ),
        children: [
          ContentArea(
            builder: (BuildContext context, ScrollController controller) =>
                ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              children: [
                const Text('Days from now'),
                MacosTextField(
                  controller: _days,
                  placeholder: '7',
                ),
                const SizedBox(height: 20),
                if (_error != null) ...[
                  Text(_error!),
                  const SizedBox(height: 12),
                ],
                PushButton(
                  controlSize: ControlSize.large,
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'Saving…' : 'Schedule'),
                ),
              ],
            ),
          ),
        ],
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
final class MacosMeetingDetailPage extends ConsumerStatefulWidget {
  /// The group meeting.
  final String groupId;

  /// The meeting id.
  final String meetingId;

  /// Creates the detail page.
  const MacosMeetingDetailPage({
    super.key,
    required this.groupId,
    required this.meetingId,
  });

  @override
  ConsumerState<MacosMeetingDetailPage> createState() =>
      _MacosMeetingDetailState();
}

final class _MacosMeetingDetailState
    extends ConsumerState<MacosMeetingDetailPage> {
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
      return MacosScaffold(
        toolBar: ToolBar(
          leading: MacosBackButton(onPressed: () => Navigator.pop(context)),
          title: const Text('Meeting'),
        ),
        children: const [
          ContentArea(builder: _loading),
        ],
      );
    }
    final Meeting current = meeting;
    final String? me = ref.watch(authProvider).identity?.peerId;
    final bool open = current.status == MeetingStatus.scheduled;
    return MacosScaffold(
      toolBar: ToolBar(
        leading: MacosBackButton(onPressed: () => Navigator.pop(context)),
        title: const Text('Meeting'),
      ),
      children: [
        ContentArea(
          builder: (BuildContext context, ScrollController controller) =>
              ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            children: [
              Text(
                '${current.presentCount} present · ${current.status.name}',
                style: MacosTheme.of(context).typography.title1,
              ),
              const SizedBox(height: 16),
              if (_error != null) ...[
                Text(_error!),
                const SizedBox(height: 12),
              ],
              for (final Attendance a in current.attendance)
                MacosListTile(
                  title: Text(a.peerId),
                  subtitle: Text(a.status.name),
                  onClick: !open
                      ? null
                      : () => _attend(
                            current,
                            a.peerId,
                            a.status == MeetingAttendanceStatus.present
                                ? MeetingAttendanceStatus.absent
                                : MeetingAttendanceStatus.present,
                            me!,
                          ),
                ),
              if (open) ...[
                const SizedBox(height: 16),
                const Text('Collected'),
                MacosTextField(
                  controller: _collected,
                  placeholder: '0.00',
                ),
                const SizedBox(height: 8),
                PushButton(
                  key: const ValueKey('complete-button'),
                  controlSize: ControlSize.large,
                  onPressed: () => _complete(current),
                  child: const Text('Complete meeting'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  static Widget _loading(BuildContext context, ScrollController _) =>
      const Center(child: ProgressCircle());

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
