import 'dart:convert';
import 'dart:typed_data';

import 'package:cbor/cbor.dart';

import '../domain/repositories.dart';

/// A shareable invite link: everything the joiner needs to fetch the
/// snapshot and unwrap the group key, with no network round trip to
/// build it.
///
/// `vbank://join?<base64url(cbor)>` where the CBOR map holds the group
/// location, the inviter, the ticket and the one-time secret. The secret
/// never touches storage on either side: it rides this link only.
final class InviteLink {
  /// Invite format version.
  static const int version = 1;

  /// Link scheme + action.
  static const String prefix = 'vbank://join?';

  /// Group id.
  final String groupId;

  /// Snapshot CID the invite was cut against (stale but openable).
  final String groupCid;

  /// PubSub topic for announcements.
  final String groupTopic;

  /// Peer id of the inviter.
  final String inviterPeerId;

  /// Name the group knows the inviter by.
  final String inviterName;

  /// Ticket id (spends on first join).
  final String inviteId;

  /// One-time secret unwrapping the group key.
  final Uint8List secret;

  /// Ticket nonce, returned with the join.
  final Uint8List nonce;

  /// Ticket expiry, milliseconds since epoch, UTC.
  final DateTime expiresAt;

  /// Creates link parts.
  const InviteLink({
    required this.groupId,
    required this.groupCid,
    required this.groupTopic,
    required this.inviterPeerId,
    required this.inviterName,
    required this.inviteId,
    required this.secret,
    required this.nonce,
    required this.expiresAt,
  });

  /// True past [at] (default now).
  bool isExpiredAt(DateTime at) => !expiresAt.isAfter(at);

  /// Encodes these parts as a shareable link.
  String encode() {
    final Map<String, Object?> map = {
      'v': version,
      'groupId': groupId,
      'groupCid': groupCid,
      'groupTopic': groupTopic,
      'inviterPeerId': inviterPeerId,
      'inviterName': inviterName,
      'inviteId': inviteId,
      'secret': secret,
      'nonce': nonce,
      'expiresAt': expiresAt.toUtc().millisecondsSinceEpoch,
    };
    final Uint8List bytes = Uint8List.fromList(
      cborEncode(CborValue(map)),
    );
    return '$prefix${base64Url.encode(bytes)}';
  }

  /// Settings key holding the shareable link for [inviteId].
  ///
  /// The link carries the one-time secret, so it lives here — inside the
  /// encrypted database — from creation until the ticket is used or
  /// expires. Stored rows alone can never rebuild it.
  static String storageKey(String inviteId) => 'invite.link.$inviteId';

  /// Stores [link] for later re-sharing.
  static Future<void> storeLink(
    SettingsRepository settings,
    String inviteId,
    String link,
  ) async {
    await settings.set(
      storageKey(inviteId),
      Uint8List.fromList(utf8.encode(link)),
    );
  }

  /// The stored link for [inviteId], or null when never saved or already
  /// cleared.
  static Future<String?> loadLink(
    SettingsRepository settings,
    String inviteId,
  ) async {
    final result = await settings.get(storageKey(inviteId));
    if (result.isErr || result.value == null) {
      return null;
    }
    try {
      return utf8.decode(result.value!);
    } catch (_) {
      return null;
    }
  }

  /// Forgets the stored link for [inviteId].
  static Future<void> clearLink(
    SettingsRepository settings,
    String inviteId,
  ) async {
    await settings.remove(storageKey(inviteId));
  }

  /// Parses a link, or null when malformed. Expiry is the caller's check.
  static InviteLink? tryParse(String link) {
    if (!link.startsWith(prefix)) {
      return null;
    }
    try {
      final Uint8List bytes = Uint8List.fromList(
        base64Url.decode(link.substring(prefix.length).trim()),
      );
      final Object? decoded = cborDecode(bytes).toObject();
      if (decoded is! Map) {
        return null;
      }
      final Map<String, dynamic> map = decoded.cast<String, dynamic>();
      if (map['v'] != version) {
        return null;
      }
      String str(String key) {
        final Object? value = map[key];
        if (value is! String || value.isEmpty) {
          throw const FormatException('bad invite link');
        }
        return value;
      }

      Uint8List raw(String key) {
        final Object? value = map[key];
        // CBOR byte strings decode as Uint8Buffer (a List<int>).
        if (value is! List<int> || value.isEmpty) {
          throw const FormatException('bad invite link');
        }
        return Uint8List.fromList(value);
      }

      final Object? expires = map['expiresAt'];
      if (expires is! int) {
        return null;
      }
      return InviteLink(
        groupId: str('groupId'),
        groupCid: str('groupCid'),
        groupTopic: str('groupTopic'),
        inviterPeerId: str('inviterPeerId'),
        inviterName: str('inviterName'),
        inviteId: str('inviteId'),
        secret: raw('secret'),
        nonce: raw('nonce'),
        expiresAt: DateTime.fromMillisecondsSinceEpoch(expires, isUtc: true),
      );
    } catch (_) {
      return null;
    }
  }
}
