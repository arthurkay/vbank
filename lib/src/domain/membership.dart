import 'dart:typed_data';

import 'core/bytes.dart';
import 'core/failure.dart';
import 'core/result.dart';

/// A member's rank. `owner` created the group and cannot be removed;
/// `admin` is promoted by the owner; `member` joins via invite.
enum MemberRole {
  /// Created the group; full rights, cannot be removed.
  owner,

  /// Promoted by the owner; reads and writes.
  admin,

  /// Joined via invite; read-only.
  member,
}

/// A member's standing. `pending` awaits admin approval in groups with
/// `requireApproval`; `suspended` keeps history but blocks activity;
/// `removed` is out for good.
enum MemberStatus {
  /// Fully participating.
  active,

  /// Kept out for now; history stays.
  suspended,

  /// Out for good.
  removed,

  /// Joined a group with `requireApproval`; awaiting an admin.
  pending,
}

/// True when [role] may record transactions, approve loans and run meetings.
bool canWrite(MemberRole role) =>
    role == MemberRole.owner || role == MemberRole.admin;

/// True when [role] may approve joins and suspend members.
bool canManageMembers(MemberRole role) =>
    role == MemberRole.owner || role == MemberRole.admin;

/// True when [role] may promote members and transfer ownership.
bool canPromote(MemberRole role) => role == MemberRole.owner;

/// True when [role] may demote admins.
bool canDemote(MemberRole role) => role == MemberRole.owner;

/// True when [role] may remove members.
bool canRemove(MemberRole role) => role == MemberRole.owner;

/// True when [role] may dissolve the group.
bool canDissolve(MemberRole role) => role == MemberRole.owner;

/// One person in a group.
final class Member {
  /// Ed25519 public key, also the IPFS peer id.
  final String peerId;

  /// The name the group knows this person by.
  final String name;

  /// Rank; defaults to plain member.
  final MemberRole role;

  /// When they joined (or requested to join).
  final DateTime joinedAt;

  /// Ed25519 public key bytes.
  final Uint8List publicKey;

  /// Standing; defaults to active.
  final MemberStatus status;

  /// True while a loan of theirs is still being repaid.
  final bool hasOutstandingLoan;

  /// X25519 public key for receiving rotated group keys; null until the
  /// member's device has published it.
  final Uint8List? encKey;

  /// Creates a member.
  const Member({
    required this.peerId,
    required this.name,
    this.role = MemberRole.member,
    required this.joinedAt,
    required this.publicKey,
    this.status = MemberStatus.active,
    this.hasOutstandingLoan = false,
    this.encKey,
  });

  /// Structural checks: identifiers present.
  Result<Unit> validate() {
    if (peerId.isEmpty) {
      return const Err(ValidationFailure('memberPeerIdEmpty'));
    }
    if (name.trim().isEmpty) {
      return const Err(ValidationFailure('memberNameEmpty'));
    }
    return const Ok(unit);
  }

  /// Copies this member, replacing the given fields.
  Member copyWith({
    String? name,
    MemberRole? role,
    MemberStatus? status,
    bool? hasOutstandingLoan,
    Uint8List? encKey,
  }) =>
      Member(
        peerId: peerId,
        name: name ?? this.name,
        role: role ?? this.role,
        joinedAt: joinedAt,
        publicKey: publicKey,
        status: status ?? this.status,
        hasOutstandingLoan: hasOutstandingLoan ?? this.hasOutstandingLoan,
        encKey: encKey ?? this.encKey,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Member &&
          peerId == other.peerId &&
          name == other.name &&
          role == other.role &&
          joinedAt == other.joinedAt &&
          bytesEqual(publicKey, other.publicKey) &&
          status == other.status &&
          hasOutstandingLoan == other.hasOutstandingLoan &&
          (encKey == null || other.encKey == null
              ? encKey == other.encKey
              : bytesEqual(encKey!, other.encKey!));

  @override
  int get hashCode => Object.hash(
        peerId,
        name,
        role,
        joinedAt,
        bytesHash(publicKey),
        status,
        hasOutstandingLoan,
        encKey == null ? null : bytesHash(encKey!),
      );
}
