import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/core/failure.dart';
import '../../domain/meetings.dart';
import '../app_scope.dart';
import '../providers/auth.dart';
import '../providers/ledger.dart';

/// A group's meetings with scheduling and attendance flows on Windows.
final class WindowsMeetingsPage extends ConsumerWidget {
  /// The group meeting.
  final String groupId;

  /// Creates the meetings page.
  const WindowsMeetingsPage({super.key, required this.groupId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Meeting>> meetings =
        ref.watch(meetingListProvider(groupId));
    return NavigationView(
      titleBar: const TitleBar(title: Text('Meetings')),
      content: ScaffoldPage(
        header: PageHeader(
          leading: IconButton(
            icon: const Icon(FluentIcons.back),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text('Meetings'),
          commandBar: CommandBar(
            mainAxisAlignment: MainAxisAlignment.end,
            primaryItems: [
              CommandBarButton(
                key: const ValueKey('schedule-button'),
                icon: const Icon(FluentIcons.add),
                label: const Text('Schedule'),
                onPressed: () => Navigator.push(
                  context,
                  FluentPageRoute<void>(
                    builder: (_) => WindowsSchedulePage(groupId: groupId),
                  ),
                ),
              ),
            ],
          ),
        ),
        content: meetings.when(
          loading: () => const Center(child: ProgressRing()),
          error: (Object error, _) => Center(child: Text('Error: $error')),
          data: (List<Meeting> list) {
            if (list.isEmpty) {
              return const Center(child: Text('No meetings yet'));
            }
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              itemCount: list.length,
              itemBuilder: (BuildContext context, int i) {
                final Meeting meeting = list[i];
                return Card(
                  padding: EdgeInsets.zero,
                  margin: const EdgeInsets.only(bottom: 6),
                  child: ListTile(
                    title: Text(
                      '${meeting.scheduledAt} · ${meeting.status.name}',
                    ),
                    trailing: const Icon(
                      FluentIcons.chevron_right,
                      size: 12,
                    ),
                    onPressed: () => Navigator.push(
                      context,
                      FluentPageRoute<void>(
                        builder: (_) => WindowsMeetingDetailPage(
                          groupId: groupId,
                          meetingId: meeting.id,
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// Schedules a meeting days in the future.
final class WindowsSchedulePage extends ConsumerStatefulWidget {
  /// The group meeting.
  final String groupId;

  /// Creates the schedule page.
  const WindowsSchedulePage({super.key, required this.groupId});

  @override
  ConsumerState<WindowsSchedulePage> createState() =>
      _WindowsScheduleState();
}

final class _WindowsScheduleState
    extends ConsumerState<WindowsSchedulePage> {
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
  Widget build(BuildContext context) => NavigationView(
        titleBar: const TitleBar(title: Text('Schedule meeting')),
        content: ScaffoldPage(
          header: PageHeader(
            leading: IconButton(
              icon: const Icon(FluentIcons.back),
              onPressed: () => Navigator.pop(context),
            ),
            title: const Text('Schedule meeting'),
          ),
          content: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            children: [
              const Text('Days from now'),
              const SizedBox(height: 6),
              TextBox(controller: _days, placeholder: '7'),
              const SizedBox(height: 20),
              if (_error != null) ...[
                Text(_error!),
                const SizedBox(height: 12),
              ],
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Saving…' : 'Schedule'),
              ),
            ],
          ),
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
final class WindowsMeetingDetailPage extends ConsumerStatefulWidget {
  /// The group meeting.
  final String groupId;

  /// The meeting id.
  final String meetingId;

  /// Creates the detail page.
  const WindowsMeetingDetailPage({
    super.key,
    required this.groupId,
    required this.meetingId,
  });

  @override
  ConsumerState<WindowsMeetingDetailPage> createState() =>
      _WindowsMeetingDetailState();
}

final class _WindowsMeetingDetailState
    extends ConsumerState<WindowsMeetingDetailPage> {
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
      return NavigationView(
        titleBar: const TitleBar(title: Text('Meeting')),
        content: ScaffoldPage(
          header: PageHeader(
            leading: IconButton(
              icon: const Icon(FluentIcons.back),
              onPressed: () => Navigator.pop(context),
            ),
            title: const Text('Meeting'),
          ),
          content: const Center(child: ProgressRing()),
        ),
      );
    }
    final Meeting current = meeting;
    final String? me = ref.watch(authProvider).identity?.peerId;
    final bool open = current.status == MeetingStatus.scheduled;
    return NavigationView(
      titleBar: const TitleBar(title: Text('Meeting')),
      content: ScaffoldPage(
        header: PageHeader(
          leading: IconButton(
            icon: const Icon(FluentIcons.back),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text('Meeting'),
        ),
        content: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          children: [
            Text(
              '${current.presentCount} present · ${current.status.name}',
              style: FluentTheme.of(context).typography.subtitle,
            ),
            const SizedBox(height: 14),
            if (_error != null) ...[
              Text(_error!),
              const SizedBox(height: 12),
            ],
            for (final Attendance a in current.attendance)
              ListTile(
                title: Text(a.peerId),
                subtitle: Text(a.status.name),
                trailing: open
                    ? Button(
                        onPressed: () => _attend(
                          current,
                          a.peerId,
                          a.status == MeetingAttendanceStatus.present
                              ? MeetingAttendanceStatus.absent
                              : MeetingAttendanceStatus.present,
                          me!,
                        ),
                        child: const Text('Flip'),
                      )
                    : null,
              ),
            if (open) ...[
              const SizedBox(height: 14),
              const Text('Collected'),
              const SizedBox(height: 6),
              TextBox(
                controller: _collected,
                placeholder: '0.00',
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () => _complete(current),
                child: const Text('Complete meeting'),
              ),
            ],
          ],
        ),
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
