import 'dart:convert';

import '../../models/group.dart';
import '../storage/settings_dao.dart';

/// A join that could not fetch the group because nobody holding it was
/// reachable. Everything needed to finish it later is kept here — including
/// the passphrase-derived group key, so the ~1 s PBKDF2 is not repeated and the
/// passphrase itself is never stored — and `SyncManager` retries it at the end
/// of every sync round until a member comes online.
///
/// The key deliberately lives in this record rather than in `group_keys`: a
/// key for a group we are not in would make the node advertise an inventory
/// for it. (Backups carry `group_keys`, not this table, so a parked join does
/// not survive a restore — acceptable; the invite link can be opened again.)
class PendingJoin {
  final String groupId;
  final String groupCid;
  final String inviteId;
  final String inviteNonceB64;
  final String? inviterPeerId;
  final List<String> addrs;
  final String keyB64;
  final Member self;
  final DateTime createdAt;
  final int attempts;
  final String? lastError;

  /// Set when the fetch succeeded but the join failed for a reason retrying
  /// cannot fix (wrong passphrase, expired or invalid invite).
  final bool permanent;

  const PendingJoin({
    required this.groupId,
    required this.groupCid,
    required this.inviteId,
    required this.inviteNonceB64,
    required this.inviterPeerId,
    required this.addrs,
    required this.keyB64,
    required this.self,
    required this.createdAt,
    this.attempts = 0,
    this.lastError,
    this.permanent = false,
  });

  List<int> get keyBytes => base64Decode(keyB64);

  Set<String> get peerIds => addrs.map((a) => a.split('/p2p/').last).toSet();

  bool get wrongPassphrase => lastError == 'Wrong group passphrase';

  /// One line for the Groups list.
  String get statusText {
    if (permanent) return lastError ?? 'Could not join';
    final base = 'Waiting for a member to come online';
    return attempts == 0 ? base : '$base · tried $attempts×';
  }

  /// Worth a try this round: not permanently failed and at least one address
  /// is not sitting in dial backoff.
  bool shouldAttempt(DateTime now, Map<String, DateTime> addrBackoffUntil) {
    if (permanent) return false;
    if (addrs.isEmpty) return true;
    return addrs.any((a) {
      final until = addrBackoffUntil[a];
      return until == null || !now.isBefore(until);
    });
  }

  PendingJoin copyWith({
    String? keyB64,
    int? attempts,
    String? lastError,
    bool clearError = false,
    bool? permanent,
    List<String>? addrs,
  }) =>
      PendingJoin(
        groupId: groupId,
        groupCid: groupCid,
        inviteId: inviteId,
        inviteNonceB64: inviteNonceB64,
        inviterPeerId: inviterPeerId,
        addrs: addrs ?? this.addrs,
        keyB64: keyB64 ?? this.keyB64,
        self: self,
        createdAt: createdAt,
        attempts: attempts ?? this.attempts,
        lastError: clearError ? null : (lastError ?? this.lastError),
        permanent: permanent ?? this.permanent,
      );

  Map<String, dynamic> toJson() => {
        'groupId': groupId,
        'groupCid': groupCid,
        'inviteId': inviteId,
        'inviteNonceB64': inviteNonceB64,
        'inviterPeerId': inviterPeerId,
        'addrs': addrs,
        'key': keyB64,
        'self': self.toJson(),
        'createdAt': createdAt.toIso8601String(),
        'attempts': attempts,
        'lastError': lastError,
        'permanent': permanent,
      };

  factory PendingJoin.fromJson(Map<String, dynamic> j) => PendingJoin(
        groupId: j['groupId'] as String,
        groupCid: j['groupCid'] as String,
        inviteId: j['inviteId'] as String,
        inviteNonceB64: j['inviteNonceB64'] as String,
        inviterPeerId: j['inviterPeerId'] as String?,
        addrs: ((j['addrs'] as List?) ?? const []).cast<String>(),
        keyB64: j['key'] as String,
        self: Member.fromJson(j['self'] as Map<String, dynamic>),
        createdAt: DateTime.parse(j['createdAt'] as String),
        attempts: (j['attempts'] as int?) ?? 0,
        lastError: j['lastError'] as String?,
        permanent: (j['permanent'] as bool?) ?? false,
      );
}

/// Persistent list of [PendingJoin]s (settings key `pendingJoins`), oldest
/// first. Same shape as `SyncLedger` / `PeerBook`.
class PendingJoinBook {
  final SettingsDao _settings;
  PendingJoinBook([SettingsDao? settings]) : _settings = settings ?? SettingsDao();

  Future<List<PendingJoin>> all() async {
    final raw = await _settings.get<String>(SettingKeys.pendingJoins);
    if (raw == null || raw.isEmpty) return const [];
    try {
      return (jsonDecode(raw) as List).map((e) => PendingJoin.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<PendingJoin?> get(String groupId) async => (await all()).where((p) => p.groupId == groupId).firstOrNull;

  /// Adds or replaces the record for its group.
  Future<void> put(PendingJoin join) async {
    final rest = (await all()).where((p) => p.groupId != join.groupId);
    await _write([...rest, join]);
  }

  Future<void> remove(String groupId) async {
    final current = await all();
    final rest = current.where((p) => p.groupId != groupId).toList();
    if (rest.length == current.length) return;
    await _write(rest);
  }

  Future<void> _write(List<PendingJoin> joins) => joins.isEmpty
      ? _settings.delete(SettingKeys.pendingJoins)
      : _settings.set(SettingKeys.pendingJoins, jsonEncode([for (final j in joins) j.toJson()]));
}
