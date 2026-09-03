import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../core/codec/wire_codec.dart';
import '../core/crypto/encryption.dart';
import '../core/crypto/key_derivation.dart';
import '../core/storage/backup_dao.dart';
import '../core/storage/group_dao.dart';
import '../core/storage/group_key_dao.dart';
import '../core/storage/invite_dao.dart';
import '../core/storage/loan_dao.dart';
import '../core/storage/meeting_dao.dart';
import '../core/storage/member_dao.dart';
import '../core/storage/repayment_schedule_dao.dart';
import '../core/storage/reversal_dao.dart';
import '../core/storage/transaction_dao.dart';
import '../models/repayment_schedule.dart';
import '../models/transaction_reversal.dart';
import '../core/storage/user_identity_dao.dart';
import '../models/app_backup.dart';

/// Everything needed to decrypt a backup besides the user's secret:
/// the KDF salt, the AEAD nonce and the MAC travel with the ciphertext.
class BackupEnvelope {
  static const currentVersion = 2;

  final int version;
  final int iterations;
  final List<int> salt;
  final List<int> nonce;
  final List<int> mac;
  final List<int> ciphertext;

  const BackupEnvelope({
    this.version = currentVersion,
    required this.iterations,
    required this.salt,
    required this.nonce,
    required this.mac,
    required this.ciphertext,
  });

  /// CBOR (DESIGN_PLAN §5). v2 files written before the CBOR switch were
  /// JSON with base64 fields; [tryDecode] still reads them.
  Uint8List encode() => WireCodec.encode({
        'app': 'vbank-backup',
        'v': version,
        'kdf': 'pbkdf2-hmac-sha256',
        'iterations': iterations,
        'salt': Uint8List.fromList(salt),
        'nonce': Uint8List.fromList(nonce),
        'mac': Uint8List.fromList(mac),
        'ciphertext': Uint8List.fromList(ciphertext),
      });

  /// Returns null if [bytes] is not a recognisable envelope.
  static BackupEnvelope? tryDecode(Uint8List bytes) {
    try {
      final json = WireCodec.tryDecodeMap(bytes);
      if (json == null || json['kdf'] != 'pbkdf2-hmac-sha256') return null;
      List<int> b(Object? v) => v is String ? base64Decode(v) : (v as List).cast<int>();
      return BackupEnvelope(
        version: json['v'] as int? ?? currentVersion,
        iterations: json['iterations'] as int,
        salt: b(json['salt']),
        nonce: b(json['nonce']),
        mac: b(json['mac']),
        ciphertext: b(json['ciphertext']),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Result of decrypting and parsing a full backup, before it is applied.
class RestoredBackup {
  final UserIdentityData identity;
  final List<GroupData> groups;
  final List<MemberData> members;

  /// Group symmetric keys by group id. Without these the restored device
  /// could not decrypt any of its groups' IPFS data.
  final Map<String, Uint8List> groupKeys;

  /// Every key version per group (rotation), v3+ backups; `{groupId: {version: key}}`.
  final Map<String, Map<int, Uint8List>> groupKeyHistory;

  /// Records (payload v3+). Older backups have none; the device re-syncs them
  /// from members and the relay after the restore.
  final List<TransactionData> transactions;
  final List<LoanData> loans;
  final List<RepaymentSchedule> schedules;
  final List<MeetingData> meetings;
  final List<TransactionReversal> reversals;
  final List<InviteData> invites;
  final DateTime? createdAt;

  const RestoredBackup({
    required this.identity,
    required this.groups,
    required this.members,
    this.groupKeys = const {},
    this.groupKeyHistory = const {},
    this.transactions = const [],
    this.loans = const [],
    this.schedules = const [],
    this.meetings = const [],
    this.reversals = const [],
    this.invites = const [],
    this.createdAt,
  });

  int get recordCount => transactions.length + loans.length + meetings.length + reversals.length;
}

class BackupService {
  final BackupDao _backupDao = BackupDao();
  final UserIdentityDao _identityDao = UserIdentityDao();
  final GroupDao _groupDao = GroupDao();
  final MemberDao _memberDao = MemberDao();
  final GroupKeyDao _groupKeyDao = GroupKeyDao();
  final TransactionDao _transactionDao = TransactionDao();
  final LoanDao _loanDao = LoanDao();
  final RepaymentScheduleDao _scheduleDao = RepaymentScheduleDao();
  final MeetingDao _meetingDao = MeetingDao();
  final ReversalDao _reversalDao = ReversalDao();
  final InviteDao _inviteDao = InviteDao();
  static const _uuid = Uuid();

  /// v3 adds the group records (transactions, loans, schedules, meetings,
  /// reversals, invites); v2 files are still read.
  static const _payloadVersion = 3;
  static const minPinLength = 6;
  static const fileExtension = 'vbankbackup';

  static String? validatePin(String pin) {
    if (pin.trim().length < minPinLength) return 'PIN must be at least $minPinLength characters';
    return null;
  }

  // ---------------------------------------------------------------------------
  // Envelope helpers
  // ---------------------------------------------------------------------------

  Future<Uint8List> _seal(List<int> plaintext, String secret) async {
    final salt = KeyDerivation.randomSalt();
    final key = await KeyDerivation.deriveFromPassphrase(secret, salt);
    final encrypted = await EncryptionService.encrypt(plaintext, key);
    return BackupEnvelope(
      iterations: KeyDerivation.pbkdf2Iterations,
      salt: salt,
      nonce: encrypted.nonce,
      mac: encrypted.mac,
      ciphertext: encrypted.ciphertext,
    ).encode();
  }

  /// Returns null on a wrong secret or an unreadable/legacy envelope.
  Future<Uint8List?> _open(Uint8List sealed, String secret) async {
    final envelope = BackupEnvelope.tryDecode(sealed);
    if (envelope == null) return null;
    try {
      final key = await KeyDerivation.deriveFromPassphrase(secret, envelope.salt, iterations: envelope.iterations);
      final plaintext = await EncryptionService.decrypt(
        EncryptedData(ciphertext: envelope.ciphertext, nonce: envelope.nonce, mac: envelope.mac),
        key,
      );
      return Uint8List.fromList(plaintext);
    } on SecretBoxAuthenticationError {
      return null;
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Identity-only backup (DESIGN_PLAN §22 step 1-2)
  // ---------------------------------------------------------------------------

  Future<IdentityBackup> createIdentityBackup({
    required Uint8List privateKey,
    required String peerId,
    required String pin,
  }) async {
    return IdentityBackup(
      encryptedPrivateKey: await _seal(privateKey, pin),
      peerId: peerId,
      backedUpAt: DateTime.now().toUtc(),
    );
  }

  Future<Uint8List?> restoreIdentityBackup({
    required Uint8List encryptedPrivateKey,
    required String pin,
  }) =>
      _open(encryptedPrivateKey, pin);

  // ---------------------------------------------------------------------------
  // Full backup
  // ---------------------------------------------------------------------------

  /// Builds and encrypts the payload; returns the sealed bytes without
  /// storing them.
  Future<Uint8List> buildFullBackup(String passphrase) async {
    final pinError = validatePin(passphrase);
    if (pinError != null) throw ArgumentError(pinError);
    final identity = await _identityDao.get();
    if (identity == null) throw StateError('No identity to back up');
    final groups = await _groupDao.getAll();
    final members = <Map<String, dynamic>>[];
    for (final g in groups) {
      for (final m in await _memberDao.getByGroupId(g.id)) {
        members.add(_bytesToBase64(m.toMap(), ['public_key', 'enc_key']));
      }
    }
    final groupKeys = await _groupKeyDao.getAll();
    final transactions = <Map<String, dynamic>>[];
    final loans = <Map<String, dynamic>>[];
    final schedules = <Map<String, dynamic>>[];
    final meetings = <Map<String, dynamic>>[];
    final reversals = <Map<String, dynamic>>[];
    final invites = <Map<String, dynamic>>[];
    for (final g in groups) {
      for (final t in await _transactionDao.getByGroupId(g.id)) {
        transactions.add(_bytesToBase64(t.toMap(), ['sender_signature']));
      }
      for (final l in await _loanDao.getByGroupId(g.id)) {
        loans.add(_bytesToBase64(l.toMap(), ['borrower_signature', 'approver_signature']));
        for (final sch in await _scheduleDao.getByLoanId(l.id)) {
          schedules.add(sch.toJson());
        }
      }
      for (final m in await _meetingDao.getByGroupId(g.id)) {
        meetings.add(m.toMap());
      }
      for (final r in await _reversalDao.getByGroupId(g.id)) {
        reversals.add(r.toJson());
      }
      for (final i in await _inviteDao.getByGroupId(g.id)) {
        invites.add(_bytesToBase64(i.toMap(), ['nonce', 'inviter_signature', 'wrapped_key']));
      }
    }

    final payload = {
      'version': _payloadVersion,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'identity': _bytesToBase64(identity.toMap(), ['public_key', 'private_key']),
      'groups': groups.map((g) => _bytesToBase64(g.toMap(), ['data', 'config_data'])).toList(),
      'members': members,
      'groupKeys': {for (final e in groupKeys.entries) e.key: base64Encode(e.value)},
      'groupKeyHistory': {
        for (final g in (await _groupKeyDao.allVersions()).entries)
          g.key: {for (final v in g.value.entries) '${v.key}': base64Encode(v.value)},
      },
      'transactions': transactions,
      'loans': loans,
      'schedules': schedules,
      'meetings': meetings,
      'reversals': reversals,
      'invites': invites,
    };
    return _seal(WireCodec.encode(payload), passphrase);
  }

  /// Creates a full backup and stores it locally. Returns the backup id.
  Future<String> createFullBackup({required String passphrase}) async {
    final sealed = await buildFullBackup(passphrase);
    final backupId = _uuid.v4();
    await _backupDao.insert(BackupData(
      id: backupId,
      encryptedPayload: sealed,
      createdAt: DateTime.now().toUtc(),
      version: _payloadVersion,
      backupType: BackupType.full.name,
    ));
    return backupId;
  }

  /// Writes a stored backup to a shareable file (DESIGN_PLAN §22 step 3:
  /// "exported as … file"). The file is the encrypted envelope; it is safe
  /// to move through WhatsApp/Drive/USB.
  Future<File> exportBackupToFile(String backupId) async {
    final data = await _backupDao.getById(backupId);
    if (data == null) throw StateError('Backup not found');
    final dir = await getTemporaryDirectory();
    final stamp = data.createdAt.toIso8601String().replaceAll(':', '-').split('.').first;
    final file = File(p.join(dir.path, 'vbank-backup-$stamp.$fileExtension'));
    await file.writeAsBytes(data.encryptedPayload, flush: true);
    return file;
  }

  /// Decrypts and parses a full backup (from the local table or an imported
  /// file). Returns null on wrong passphrase or a corrupted payload.
  Future<RestoredBackup?> decryptBackup({
    required Uint8List encryptedPayload,
    required String passphrase,
  }) async {
    final plaintext = await _open(encryptedPayload, passphrase);
    if (plaintext == null) return null;

    try {
      final json = WireCodec.tryDecodeMap(plaintext);
      if (json == null) return null;
      final identityJson = json['identity'] as Map<String, dynamic>?;
      if (identityJson == null) return null;

      final identity = UserIdentityData.fromMap(_base64ToBytes(identityJson, ['public_key', 'private_key']));
      final groups = ((json['groups'] as List?) ?? const [])
          .map((g) => GroupData.fromMap(_base64ToBytes(g as Map<String, dynamic>, ['data', 'config_data'])))
          .toList();
      final members = ((json['members'] as List?) ?? const [])
          .map((m) => MemberData.fromMap(_base64ToBytes(m as Map<String, dynamic>, ['public_key', 'enc_key'])))
          .toList();
      final groupKeys = <String, Uint8List>{
        for (final e in ((json['groupKeys'] as Map?) ?? const {}).entries)
          e.key as String: Uint8List.fromList(base64Decode(e.value as String)),
      };

      List<Map<String, dynamic>> maps(String key) =>
          ((json[key] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      return RestoredBackup(
        identity: identity,
        groups: groups,
        members: members,
        groupKeys: groupKeys,
        groupKeyHistory: {
          for (final g in ((json['groupKeyHistory'] as Map?) ?? const {}).entries)
            g.key as String: {
              for (final v in (g.value as Map).entries) int.parse(v.key as String): Uint8List.fromList(base64Decode(v.value as String)),
            },
        },
        transactions: maps('transactions').map((m) => TransactionData.fromMap(_base64ToBytes(m, ['sender_signature']))).toList(),
        loans: maps('loans').map((m) => LoanData.fromMap(_base64ToBytes(m, ['borrower_signature', 'approver_signature']))).toList(),
        schedules: maps('schedules').map(RepaymentSchedule.fromJson).toList(),
        meetings: maps('meetings').map(MeetingData.fromMap).toList(),
        reversals: maps('reversals').map(TransactionReversal.fromJson).toList(),
        invites: maps('invites').map((m) => InviteData.fromMap(_base64ToBytes(m, ['nonce', 'inviter_signature', 'wrapped_key']))).toList(),
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      );
    } catch (_) {
      return null;
    }
  }

  /// Stores an imported backup file locally so it appears in the list and
  /// can be restored; returns its id. Throws if the file is not a vBank
  /// backup envelope.
  Future<String> importBackupFile(Uint8List bytes) async {
    if (BackupEnvelope.tryDecode(bytes) == null) {
      throw ArgumentError('This file is not a vBank backup');
    }
    final id = _uuid.v4();
    await _backupDao.insert(BackupData(
      id: id,
      encryptedPayload: bytes,
      createdAt: DateTime.now().toUtc(),
      version: _payloadVersion,
      backupType: BackupType.full.name,
    ));
    return id;
  }

  /// Writes a decrypted backup into the local database, replacing any
  /// existing identity/group rows with the same keys.
  Future<void> applyBackup(RestoredBackup backup) async {
    await _identityDao.insert(backup.identity);
    for (final g in backup.groups) {
      await _groupDao.upsert(g);
    }
    for (final m in backup.members) {
      await _memberDao.upsert(m);
    }
    for (final e in backup.groupKeys.entries) {
      await _groupKeyDao.upsert(e.key, e.value);
    }
    for (final g in backup.groupKeyHistory.entries) {
      for (final v in g.value.entries) {
        await _groupKeyDao.upsertVersion(g.key, v.key, v.value);
      }
    }
    for (final t in backup.transactions) {
      await _transactionDao.upsert(t);
    }
    for (final l in backup.loans) {
      await _loanDao.upsert(l);
    }
    for (final s in backup.schedules) {
      await _scheduleDao.upsert(s);
    }
    for (final m in backup.meetings) {
      await _meetingDao.upsert(m);
    }
    for (final r in backup.reversals) {
      await _reversalDao.upsert(r);
    }
    for (final i in backup.invites) {
      await _inviteDao.upsert(i);
    }
  }

  // ---------------------------------------------------------------------------
  // Listing
  // ---------------------------------------------------------------------------

  Future<AppBackup?> getBackup(String id) async {
    final data = await _backupDao.getById(id);
    return data == null ? null : _toModel(data);
  }

  Future<List<AppBackup>> getAllBackups() async => (await _backupDao.getAll()).map(_toModel).toList();

  Future<void> deleteBackup(String id) => _backupDao.delete(id);

  AppBackup _toModel(BackupData d) => AppBackup(
        id: d.id,
        encryptedPayload: d.encryptedPayload,
        groupIds: const [],
        createdAt: d.createdAt,
        version: d.version,
        type: BackupType.values.firstWhere((t) => t.name == d.backupType, orElse: () => BackupType.full),
      );

  static Map<String, dynamic> _bytesToBase64(Map<String, dynamic> map, List<String> keys) {
    final out = Map<String, dynamic>.from(map);
    for (final k in keys) {
      final v = out[k];
      if (v is List<int>) out[k] = base64Encode(v);
    }
    return out;
  }

  static Map<String, dynamic> _base64ToBytes(Map<String, dynamic> map, List<String> keys) {
    final out = Map<String, dynamic>.from(map);
    for (final k in keys) {
      final v = out[k];
      if (v is String) out[k] = Uint8List.fromList(base64Decode(v));
    }
    return out;
  }
}
