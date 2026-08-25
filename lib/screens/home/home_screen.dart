import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/ipfs/sync_manager.dart' show SyncState;
import '../../models/group.dart';
import '../../models/meeting.dart';
import '../../models/transaction.dart';
import '../../providers/auth_provider.dart';
import '../../providers/group_provider.dart';
import '../../providers/ipfs_provider.dart';
import '../../providers/meeting_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../ui/ui.dart';
import '../../widgets/sync_status_indicator.dart';
import '../../widgets/transaction_tile.dart';
import '../meeting/meeting_detail_screen.dart';
import '../transaction/transaction_detail_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _index = 0;

  static const _titles = ['My Groups', 'Recent activity', 'Upcoming Meetings', 'Settings'];

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    if (!auth.isLoggedIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pushReplacementNamed(context, '/');
      });
      return const Scaffold(child: LoadingView());
    }

    return AppPage(
      title: _titles[_index],
      showBack: false,
      trailing: [
        if (_index != 3) const _SyncIndicator(),
      ],
      footers: [
        const Divider(),
        NavigationBar(
          // Each destination gets an equal-width cell so the icons sit on even
          // centres; shadcn's default sizes items to their label width.
          alignment: NavigationBarAlignment.spaceEvenly,
          labelType: NavigationLabelType.all,
          selectedKey: ValueKey(_index),
          onSelected: (key) => setState(() => _index = (key as ValueKey<int>).value),
          children: const [
            Expanded(child: NavigationItem(key: ValueKey(0), label: Text('Groups'), child: Icon(LucideIcons.users))),
            Expanded(child: NavigationItem(key: ValueKey(1), label: Text('Activity'), child: Icon(LucideIcons.receipt))),
            Expanded(child: NavigationItem(key: ValueKey(2), label: Text('Meetings'), child: Icon(LucideIcons.calendar))),
            Expanded(child: NavigationItem(key: ValueKey(3), label: Text('Settings'), child: Icon(LucideIcons.settings))),
          ],
        ),
      ],
      floating: _index == 0
          ? Button.primary(
              onPressed: () => Navigator.pushNamed(context, '/create-group'),
              leading: const Icon(LucideIcons.plus),
              child: const Text('New group'),
            )
          : null,
      child: IndexedStack(
        index: _index,
        children: const [_GroupsTab(), _TransactionsTab(), _MeetingsTab(), _SettingsTab()],
      ),
    );
  }
}

class _SyncIndicator extends ConsumerWidget {
  const _SyncIndicator();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final node = ref.watch(ipfsNodeStateProvider).value ?? ref.read(ipfsServiceProvider).state;
    final sync = ref.watch(syncStateProvider).value ?? ref.read(syncManagerProvider).state;
    return SyncStatusIndicator(
      status: syncStatusFrom(node, sync),
      onTap: () => Navigator.pushNamed(context, '/sync-status'),
    );
  }
}

class _GroupsTab extends ConsumerWidget {
  const _GroupsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupsAsync = ref.watch(groupListProvider);
    final me = ref.watch(authProvider).identity?.peerId;

    return groupsAsync.when(
      loading: () => const LoadingView(),
      error: (e, _) => ErrorView(e),
      data: (groups) {
        if (groups.isEmpty) {
          return EmptyState(
            icon: LucideIcons.userPlus,
            title: 'No groups yet',
            subtitle: 'Create a new group or join an existing one',
            action: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Button.primary(
                  onPressed: () => Navigator.pushNamed(context, '/create-group'),
                  leading: const Icon(LucideIcons.plus),
                  child: const Text('Create Group'),
                ),
                const Gap(8),
                Button.outline(
                  onPressed: () => Navigator.pushNamed(context, '/join-group'),
                  leading: const Icon(LucideIcons.scanLine),
                  child: const Text('Join Group'),
                ),
              ],
            ),
          );
        }
        return FilterableList<Group>(
          items: groups,
          searchPlaceholder: 'Search groups',
          searchText: (g) => '${g.name} ${g.status.name} ${g.config.currency}',
          builder: (context, visible) => RefreshTrigger(
            onRefresh: () => ref.read(groupListProvider.notifier).refresh(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
              children: [
                for (final group in visible)
                  _GroupRow(group: group, me: me),
                const Gap(4),
                Button.outline(
                  onPressed: () => Navigator.pushNamed(context, '/join-group'),
                  leading: const Icon(LucideIcons.scanLine),
                  child: const Text('Join another group'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _GroupRow extends ConsumerWidget {
  final Group group;
  final String? me;
  const _GroupRow({required this.group, required this.me});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final my = group.members.where((m) => m.peerId == me).firstOrNull;
    final pending = group.members.where((m) => m.status == MemberStatus.pending).length;
    final subtitle = [
      '${group.memberCount} members',
      if (my?.status == MemberStatus.pending) 'awaiting approval',
      if (pending > 0 && my != null && my.role != MemberRole.member) '$pending to approve',
      if (group.status == GroupStatus.dissolved) 'dissolved',
    ].join(' · ');
    return ListRow(
      leading: InitialsAvatar(group.name),
      title: Text(group.name),
      subtitle: Text(subtitle).small.muted,
      trailing: const Icon(LucideIcons.chevronRight),
      onTap: () {
        ref.read(selectedGroupProvider.notifier).state = group;
        Navigator.pushNamed(context, '/group-detail');
      },
    );
  }
}

class _TransactionsTab extends ConsumerWidget {
  const _TransactionsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txs = ref.watch(allTransactionsProvider);
    final groups = ref.watch(groupListProvider).value ?? const <Group>[];
    return txs.when(
      loading: () => const LoadingView(),
      error: (e, _) => ErrorView(e),
      data: (list) {
        if (list.isEmpty) return const EmptyState(icon: LucideIcons.receipt, title: 'No transactions yet');
        Group? groupOf(Transaction tx) => groups.where((g) => g.id == tx.groupId).firstOrNull;
        return FilterableList<Transaction>(
          items: list,
          filters: txFilters(),
          searchPlaceholder: 'Search activity',
          searchText: (tx) => txHaystack(tx, group: groupOf(tx)),
          builder: (context, visible) => RefreshTrigger(
            onRefresh: () => ref.refresh(allTransactionsProvider.future),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              itemCount: visible.length,
              itemBuilder: (context, i) {
                final tx = visible[i];
                final group = groupOf(tx);
                return TransactionTile(
                  transaction: tx,
                  onTap: () {
                    if (group != null) ref.read(selectedGroupProvider.notifier).state = group;
                    pushScreen(context, TransactionDetailScreen(transaction: tx));
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _MeetingsTab extends ConsumerWidget {
  const _MeetingsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meetings = ref.watch(upcomingMeetingsProvider);
    final groups = ref.watch(groupListProvider).value ?? const <Group>[];
    return meetings.when(
      loading: () => const LoadingView(),
      error: (e, _) => ErrorView(e),
      data: (list) {
        if (list.isEmpty) {
          return const EmptyState(
            icon: LucideIcons.calendar,
            title: 'No meetings scheduled',
            subtitle: 'Admins schedule meetings from a group\'s Meetings tab',
          );
        }
        String nameOfGroup(Meeting m) => groups.where((g) => g.id == m.groupId).firstOrNull?.name ?? 'Meeting';
        return FilterableList<Meeting>(
          items: list,
          searchPlaceholder: 'Search meetings',
          searchText: (m) => '${nameOfGroup(m)} ${fmtDateTime(m.scheduledAt)} ${m.status.name}',
          builder: (context, visible) => RefreshTrigger(
          onRefresh: () => ref.refresh(upcomingMeetingsProvider.future),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            children: [
              for (final m in visible)
                ListRow(
                  leading: Icon(
                    m.status == MeetingStatus.completed ? LucideIcons.circleCheck : LucideIcons.calendar,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: Text(groups.where((g) => g.id == m.groupId).firstOrNull?.name ?? 'Meeting'),
                  subtitle: Text(fmtDateTime(m.scheduledAt)).small.muted,
                  trailing: const Icon(LucideIcons.chevronRight),
                  onTap: () {
                    final g = groups.where((g) => g.id == m.groupId).firstOrNull;
                    if (g != null) ref.read(selectedGroupProvider.notifier).state = g;
                    pushScreen(context, MeetingDetailScreen(meetingId: m.id));
                  },
                ),
            ],
          ),
          ),
        );
      },
    );
  }
}

class _SettingsTab extends ConsumerWidget {
  const _SettingsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = ref.watch(authProvider).identity;
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Panel(
          child: Basic(
            leading: InitialsAvatar(identity?.displayName ?? '?', size: 44),
            title: Text(identity?.displayName ?? 'User'),
            subtitle: Text(identity?.peerId ?? '').xSmall.muted,
            leadingAlignment: Alignment.center,
          ),
        ),
        const Gap(12),
        ListRow(
          leading: const Icon(LucideIcons.bell),
          title: const Text('Notifications'),
          trailing: const Icon(LucideIcons.chevronRight),
          onTap: () => Navigator.pushNamed(context, '/notification-settings'),
        ),
        ListRow(
          leading: const Icon(LucideIcons.cloudUpload),
          title: const Text('Backup & Restore'),
          subtitle: const Text('Encrypted backups of your identity and groups').small.muted,
          trailing: const Icon(LucideIcons.chevronRight),
          onTap: () => Navigator.pushNamed(context, '/identity-backup'),
        ),
        ListRow(
          leading: const Icon(LucideIcons.cloudUpload),
          title: const Text('Sync status'),
          trailing: const Icon(LucideIcons.chevronRight),
          onTap: () => Navigator.pushNamed(context, '/sync-status'),
        ),
        ListRow(
          leading: Icon(LucideIcons.refreshCw, color: scheme.primary),
          title: const Text('Sync now'),
          onTap: () async {
            final sm = ref.read(syncManagerProvider);
            await sm.startManualSync();
            if (context.mounted) {
              final failed = sm.state == SyncState.error;
              showMessage(context, failed ? (sm.lastError ?? 'Sync failed') : 'Sync completed', error: failed);
            }
          },
        ),
        const Gap(16),
        Button.destructive(
          onPressed: () async {
            final ok = await confirmSheet(
              context,
              title: 'Log out?',
              message: 'This removes your identity from this phone. Make sure you have an exported backup — '
                  'without it you cannot sign as this identity again.',
              confirmLabel: 'Log out',
              destructive: true,
            );
            if (ok && context.mounted) {
              await ref.read(authProvider.notifier).logout();
              if (context.mounted) Navigator.pushReplacementNamed(context, '/');
            }
          },
          leading: const Icon(LucideIcons.logOut),
          child: const Text('Log out'),
        ),
      ],
    );
  }
}

/// Searchable text for a transaction: type, note, amount, date, and the names
/// of the people and group involved.
String txHaystack(Transaction tx, {Group? group}) {
  String nameOf(String peerId) => peerId == 'group'
      ? 'group fund'
      : group?.members.where((m) => m.peerId == peerId).firstOrNull?.name ?? '';
  return [
    tx.type.name,
    tx.status.name,
    tx.note ?? '',
    tx.currency,
    tx.amount.toStringAsFixed(2),
    fmtDate(tx.timestamp),
    nameOf(tx.fromPeerId),
    nameOf(tx.toPeerId),
    group?.name ?? '',
  ].join(' ');
}

/// Type filters shared by the Activity tab, the group Transactions tab and the
/// standalone transaction list.
List<FilterOption<Transaction>> txFilters() => [
      FilterOption.all<Transaction>(),
      FilterOption('Contributions', (t) => t.type == TransactionType.contribution),
      FilterOption('Loans', (t) => t.type == TransactionType.loan),
      FilterOption('Repayments', (t) => t.type == TransactionType.repayment),
      FilterOption('Penalties', (t) => t.type == TransactionType.penalty),
      FilterOption('Withdrawals', (t) => t.type == TransactionType.withdrawal),
      FilterOption('Reversed', (t) => t.status == TransactionStatus.reversed || t.type == TransactionType.reversal),
    ];
