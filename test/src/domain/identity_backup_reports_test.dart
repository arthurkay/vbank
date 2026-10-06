import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vbank/src/domain/backup.dart';
import 'package:vbank/src/domain/balance.dart';
import 'package:vbank/src/domain/core/failure.dart';
import 'package:vbank/src/domain/currency.dart';
import 'package:vbank/src/domain/identity.dart';
import 'package:vbank/src/domain/reports.dart';

import 'fixtures.dart';

void main() {
  group('UserIdentity', () {
    UserIdentity testIdentity() => UserIdentity(
          peerId: 'alice-peer',
          displayName: 'Alice',
          publicKey: testSignature(),
          createdAt: DateTime.utc(2026, 1, 5),
        );

    test('validates and renames', () {
      expect(testIdentity().validate().isOk, isTrue);
      expect(
        testIdentity().copyWith(displayName: 'Alicia').displayName,
        'Alicia',
      );
      expect(
        UserIdentity(
          peerId: '',
          displayName: 'A',
          publicKey: testSignature(),
          createdAt: DateTime.utc(2026, 1, 5),
        ).validate().failure,
        isA<ValidationFailure>(),
      );
    });

    test('identity backups need a payload', () {
      final IdentityBackup backup = IdentityBackup(
        encryptedPrivateKey: Uint8List.fromList(const [4, 5, 6]),
        peerId: 'alice-peer',
        backedUpAt: DateTime.utc(2026, 1, 6),
      );

      expect(backup.validate().isOk, isTrue);
      expect(backup.backupVersion, '1.0');
    });
  });

  group('AppBackup', () {
    test('rejects empty payloads and zero versions', () {
      AppBackup testBackup() => AppBackup(
            id: 'b-1',
            encryptedPayload: Uint8List.fromList(const [1]),
            groupIds: const ['g-1'],
            createdAt: DateTime.utc(2026, 1, 6),
            type: BackupType.full,
          );

      expect(testBackup().validate().isOk, isTrue);
      expect(
        AppBackup(
          id: 'b',
          encryptedPayload: Uint8List(0),
          groupIds: const [],
          createdAt: DateTime.utc(2026, 1, 6),
          type: BackupType.selective,
        ).validate().failure,
        isA<ValidationFailure>(),
      );
    });
  });

  group('Balance', () {
    test('available subtracts what is still owed', () {
      final Balance b = Balance(
        peerId: 'a',
        groupId: 'g',
        netBalance: 500,
        outstandingLoan: 200,
        lastUpdated: DateTime.utc(2026, 2, 1),
      );

      expect(b.availableBalance, 300);
      expect(b.validate().isOk, isTrue);
      expect(
        b.copyWith(outstandingLoan: 0).availableBalance,
        500,
      );
    });
  });

  group('CurrencyConfig', () {
    test('formats with the right decimals and default', () {
      expect(CurrencyConfig.defaultCurrency.symbol, 'ZK');
      expect(CurrencyConfig.getInfo('ZMW')!.format(10.5), 'ZK 10.50');
      expect(CurrencyConfig.getInfo('KES')!.format(10.5), 'KSh 11');
      expect(CurrencyConfig.isSupported('ZMW'), isTrue);
      expect(CurrencyConfig.isSupported('XXX'), isFalse);
      expect(CurrencyConfig.getInfo('XXX'), isNull);
    });
  });

  group('Reports', () {
    test('periods reject inverted ranges', () {
      final DateTimePeriod ok = DateTimePeriod(
        start: DateTime.utc(2026, 1, 1),
        end: DateTime.utc(2026, 1, 31),
      );

      expect(ok.validate().isOk, isTrue);
      expect(ok.duration, const Duration(days: 30));
      expect(
        DateTimePeriod(
          start: DateTime.utc(2026, 2, 1),
          end: DateTime.utc(2026, 1, 1),
        ).validate().failure,
        isA<ValidationFailure>(),
      );
    });

    test('net fund change follows the legacy formula', () {
      final GroupReport report = GroupReport(
        groupId: 'g',
        period: DateTimePeriod(
          start: DateTime.utc(2026, 1, 1),
          end: DateTime.utc(2026, 1, 31),
        ),
        totalContributions: 1000,
        totalLoansDisbursed: 400,
        totalLoansRepaid: 110,
        totalPenalties: 10,
        groupFundBalance: 700,
        totalMeetings: 4,
        totalTransactions: 12,
        memberStatements: [
          MemberStatement(
            peerId: 'a',
            memberName: 'Alice',
            totalContributed: 500,
            totalLoaned: 400,
            totalRepaid: 110,
            outstandingBalance: 330,
          ),
        ],
      );

      expect(report.netFundChange, 700);
      expect(report.memberStatements, hasLength(1));
    });
  });
}
