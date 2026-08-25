import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/ipfs/sync_manager.dart';
import '../models/meeting.dart';
import '../services/meeting_service.dart';
import 'auth_provider.dart';
import 'group_provider.dart' show groupServiceProvider;
import 'ipfs_provider.dart';
import 'notification_provider.dart';
import 'data_version.dart';
import 'transaction_provider.dart' show syncTickProvider;

final meetingServiceProvider = Provider<MeetingService>((ref) {
  return MeetingService(groupService: ref.watch(groupServiceProvider));
});

class MeetingListNotifier extends StateNotifier<AsyncValue<List<Meeting>>> {
  final Ref _ref;
  final MeetingService _service;
  final String groupId;
  StreamSubscription<SyncChange>? _changesSub;

  MeetingListNotifier(this._ref, this._service, this.groupId) : super(const AsyncValue.loading()) {
    loadMeetings();
    _changesSub = _ref.read(syncManagerProvider).changes.listen((change) {
      if (change.groupId == groupId && change.type == SyncChangeType.meeting) loadMeetings();
    });
  }

  @override
  void dispose() {
    _changesSub?.cancel();
    super.dispose();
  }

  Future<void> loadMeetings() async {
    state = const AsyncValue.loading();
    try {
      state = AsyncValue.data(await _service.getByGroupId(groupId));
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  String get _me => _ref.read(authProvider.notifier).requireIdentity().peerId;

  Future<void> _publish(String meetingId) async {
    final m = await _service.getById(meetingId);
    if (m == null) return;
    try {
      await _ref.read(syncManagerProvider).publishSignedMeeting(m);
    } catch (_) {}
  }

  Future<Meeting> createMeeting({required DateTime scheduledAt, String? notes}) async {
    final meeting = await _service.createMeeting(
        groupId: groupId, actingPeerId: _me, scheduledAt: scheduledAt, notes: notes);
    await loadMeetings();
    unawaited(_publish(meeting.id));

    final group = await _ref.read(groupServiceProvider).getGroup(groupId);
    if (group != null) {
      await _ref.read(notificationSchedulerProvider).scheduleForMeeting(
        meetingId: meeting.id,
        groupId: groupId,
        groupName: group.name,
        meetingTime: meeting.scheduledAt,
        contributionAmount: group.config.contributionAmount,
        currency: group.config.currency,
      );
    }
    return meeting;
  }

  Future<void> recordAttendance({
    required String meetingId,
    required String peerId,
    required MeetingAttendanceStatus status,
    bool contributed = false,
  }) async {
    await _service.recordAttendance(
      groupId: groupId, actingPeerId: _me, meetingId: meetingId, peerId: peerId, status: status, contributed: contributed);
    await loadMeetings();
    unawaited(_publish(meetingId));
  }

  Future<void> completeMeeting({required String meetingId, required double totalCollected, String? notes}) async {
    await _service.completeMeeting(
        groupId: groupId, actingPeerId: _me, meetingId: meetingId, totalCollected: totalCollected, notes: notes);
    await loadMeetings();
    bumpDataVersion(_ref);
    unawaited(_publish(meetingId));
    await _ref.read(notificationSchedulerProvider).cancelForMeeting(meetingId);
  }

  Future<void> cancelMeeting(String meetingId) async {
    await _service.cancelMeeting(groupId: groupId, actingPeerId: _me, meetingId: meetingId);
    await loadMeetings();
    bumpDataVersion(_ref);
    unawaited(_publish(meetingId));
    await _ref.read(notificationSchedulerProvider).cancelForMeeting(meetingId);
  }

  Future<void> refresh() => loadMeetings();
}

final meetingListProvider =
    StateNotifierProvider.family<MeetingListNotifier, AsyncValue<List<Meeting>>, String>((ref, groupId) {
  return MeetingListNotifier(ref, ref.watch(meetingServiceProvider), groupId);
});

final upcomingMeetingsProvider = FutureProvider<List<Meeting>>((ref) async {
  ref.watch(syncTickProvider);
  return ref.watch(meetingServiceProvider).getUpcoming();
});

final meetingProvider = FutureProvider.family<Meeting?, String>((ref, meetingId) async {
  ref.watch(syncTickProvider);
  return ref.watch(meetingServiceProvider).getById(meetingId);
});
