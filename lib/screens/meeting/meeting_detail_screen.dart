import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/group.dart';
import '../../models/meeting.dart';
import '../../providers/group_provider.dart';
import '../../providers/meeting_provider.dart';
import '../../ui/ui.dart';

/// DESIGN_PLAN §27 meeting_detail + attendance screens.
class MeetingDetailScreen extends ConsumerStatefulWidget {
  final String meetingId;
  const MeetingDetailScreen({super.key, required this.meetingId});

  @override
  ConsumerState<MeetingDetailScreen> createState() => _MeetingDetailScreenState();
}

class _MeetingDetailScreenState extends ConsumerState<MeetingDetailScreen> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() a, [String? ok]) async {
    setState(() => _busy = true);
    try {
      await a();
      ref.invalidate(meetingProvider(widget.meetingId));
      if (ok != null && mounted) showMessage(context, ok);
    } catch (e) {
      if (mounted) showMessage(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _complete(Meeting meeting, Group group, MeetingListNotifier notifier, int contributed) async {
    final c = TextEditingController(text: (contributed * group.config.contributionAmount).toStringAsFixed(2));
    final n = TextEditingController(text: meeting.notes ?? '');
    final ok = await showAppSheet<bool>(
      context,
      title: 'Complete meeting',
      builder: (ctx, close) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          LabeledField(
            label: 'Total collected (${group.config.currency})',
            child: TextField(controller: c, autofocus: true, keyboardType: const TextInputType.numberWithOptions(decimal: true)),
          ),
          const Gap(16),
          LabeledField(label: 'Notes', child: TextField(controller: n, maxLines: 2)),
          const Gap(24),
          Button.primary(onPressed: () => close(true), child: const Text('Complete')),
          const Gap(8),
          OutlineButton(onPressed: () => close(false), child: const Text('Cancel')),
        ],
      ),
    );
    if (ok != true) return;
    final total = double.tryParse(c.text) ?? 0;
    await _run(
      () => notifier.completeMeeting(meetingId: meeting.id, totalCollected: total, notes: n.text.trim()),
      'Meeting completed',
    );
  }

  static String _statusLabel(MeetingAttendanceStatus s) => switch (s) {
        MeetingAttendanceStatus.present => 'Present',
        MeetingAttendanceStatus.excused => 'Excused',
        MeetingAttendanceStatus.absent => 'Absent',
      };

  @override
  Widget build(BuildContext context) {
    final group = ref.watch(selectedGroupProvider);
    final meetingAsync = ref.watch(meetingProvider(widget.meetingId));
    final canWrite = ref.watch(canWriteProvider);

    return AppPage(
      title: 'Meeting',
      child: meetingAsync.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(e),
        data: (meeting) {
          if (meeting == null || group == null) return const EmptyState(icon: LucideIcons.calendar, title: 'Meeting not found');
          final notifier = ref.read(meetingListProvider(group.id).notifier);
          final editable = canWrite && meeting.status == MeetingStatus.scheduled;
          final members = group.members.where((m) => m.status == MemberStatus.active).toList()
            ..sort((a, b) => a.name.compareTo(b.name));
          final present = meeting.attendance.where((a) => a.status == MeetingAttendanceStatus.present).length;
          final contributed = meeting.attendance.where((a) => a.contributed).length;

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(fmtDateTime(meeting.scheduledAt)).large.semiBold),
                        StatusBadge(
                          meeting.status.name,
                          tone: switch (meeting.status) {
                            MeetingStatus.completed => StatusTone.primary,
                            MeetingStatus.cancelled => StatusTone.destructive,
                            _ => StatusTone.neutral,
                          },
                        ),
                      ],
                    ),
                    const Gap(8),
                    InfoRow('Present', '$present / ${members.length}'),
                    InfoRow('Contributed', '$contributed'),
                    if (meeting.status == MeetingStatus.completed)
                      InfoRow('Collected', fmtMoney(group.config.currency, meeting.totalCollected)),
                    if (meeting.notes != null && meeting.notes!.isNotEmpty) InfoRow('Notes', meeting.notes!),
                  ],
                ),
              ),
              const SectionTitle('Attendance'),
              for (final m in members)
                Builder(builder: (context) {
                  final a = meeting.attendance.where((a) => a.peerId == m.peerId).firstOrNull;
                  final status = a?.status ?? MeetingAttendanceStatus.absent;
                  final paid = a?.contributed ?? false;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Panel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Basic(
                            leading: InitialsAvatar(m.name, size: 36),
                            leadingAlignment: Alignment.center,
                            title: Text(m.name),
                            subtitle: Text('${_statusLabel(status)}${paid ? ' · contributed' : ''}').small.muted,
                            trailing: editable
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Text('Paid').small.muted,
                                      const Gap(6),
                                      Checkbox(
                                        state: paid ? CheckboxState.checked : CheckboxState.unchecked,
                                        onChanged: _busy
                                            ? null
                                            : (v) {
                                                final on = v == CheckboxState.checked;
                                                _run(() => notifier.recordAttendance(
                                                      meetingId: meeting.id,
                                                      peerId: m.peerId,
                                                      status: on ? MeetingAttendanceStatus.present : status,
                                                      contributed: on,
                                                    ));
                                              },
                                      ),
                                    ],
                                  )
                                : null,
                            trailingAlignment: Alignment.center,
                          ),
                          if (editable) ...[
                            const Gap(10),
                            Segmented<MeetingAttendanceStatus>(
                              values: const [
                                MeetingAttendanceStatus.present,
                                MeetingAttendanceStatus.excused,
                                MeetingAttendanceStatus.absent,
                              ],
                              selected: status,
                              label: _statusLabel,
                              onChanged: (s) {
                                if (_busy) return;
                                _run(() => notifier.recordAttendance(
                                    meetingId: meeting.id, peerId: m.peerId, status: s, contributed: paid));
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }),
              const Gap(16),
              if (editable) ...[
                Button.primary(
                  onPressed: _busy ? null : () => _complete(meeting, group, notifier, contributed),
                  leading: const Icon(LucideIcons.checkCheck),
                  child: const Text('Complete meeting'),
                ),
                const Gap(8),
                Button.ghost(
                  onPressed: _busy
                      ? null
                      : () async {
                          final ok = await confirmSheet(context,
                              title: 'Cancel this meeting?',
                              message: 'Members will be told the meeting is cancelled.',
                              confirmLabel: 'Cancel meeting',
                              cancelLabel: 'Keep',
                              destructive: true);
                          if (ok) await _run(() => notifier.cancelMeeting(meeting.id), 'Meeting cancelled');
                        },
                  leading: const Icon(LucideIcons.calendarX),
                  child: const Text('Cancel meeting'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
