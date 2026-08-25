import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/meeting.dart';
import '../../providers/group_provider.dart';
import '../../providers/meeting_provider.dart';
import '../../ui/ui.dart';
import 'meeting_detail_screen.dart';

/// Meetings of the selected group.
class MeetingListScreen extends ConsumerWidget {
  const MeetingListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final group = ref.watch(selectedGroupProvider);
    if (group == null) {
      return const AppPage(title: 'Meetings', child: EmptyState(icon: LucideIcons.calendar, title: 'No group selected'));
    }
    final meetings = ref.watch(meetingListProvider(group.id));
    return AppPage(
      title: '${group.name} · meetings',
      child: meetings.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(e),
        data: (list) {
          if (list.isEmpty) return const EmptyState(icon: LucideIcons.calendar, title: 'No meetings scheduled');
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              for (final m in list)
                ListRow(
                  leading: Icon(m.status == MeetingStatus.completed ? LucideIcons.circleCheck : LucideIcons.calendar),
                  title: Text(fmtDateTime(m.scheduledAt)),
                  subtitle: Text(m.status.name).small.muted,
                  trailing: const Icon(LucideIcons.chevronRight),
                  onTap: () => pushScreen(context, MeetingDetailScreen(meetingId: m.id)),
                ),
            ],
          );
        },
      ),
    );
  }
}
