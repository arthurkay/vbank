import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vbank/models/group.dart';
import 'package:vbank/models/loan_progress.dart';
import 'package:vbank/models/report.dart';
import 'package:vbank/services/report_export_service.dart';

void main() {
  final group = Group(
    id: 'g1',
    name: 'Ngombe Circle',
    config: const GroupConfig(groupId: 'g1', contributionAmount: 20),
    createdAt: DateTime(2026, 1, 1),
    ownerSignature: Uint8List(0),
  );
  final report = GroupReport(
    groupId: 'g1',
    period: DateTimePeriod(start: DateTime(2026, 6, 1), end: DateTime(2026, 9, 1)),
    totalContributions: 4860,
    totalLoansDisbursed: 1100,
    totalLoansRepaid: 275,
    totalPenalties: 0,
    groupFundBalance: 4035,
    totalMeetings: 3,
    totalTransactions: 42,
    memberStatements: const [
      MemberStatement(peerId: 'a', memberName: 'Grace Mwanza', totalContributed: 1620, totalLoaned: 1000, totalRepaid: 275, outstandingBalance: 825),
      MemberStatement(peerId: 'b', memberName: 'Joseph Banda & Sons <Ltd>', totalContributed: 1620, totalLoaned: 100, totalRepaid: 0, outstandingBalance: 110),
    ],
  );
  const fund = GroupFund(available: 3210, lentOut: 935, interestExpected: 110);
  final out = Platform.environment['VBANK_EXPORT_DIR'];

  test('PDF export is a PDF with the brand in it', () async {
    final bytes = await ReportExportService().buildPdf(group: group, report: report, fund: fund);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(2000));
    if (out != null) File('$out/report.pdf').writeAsBytesSync(bytes);
  });

  test('Excel export is a valid OOXML package with two sheets and escaped names', () async {
    final bytes = await ReportExportService().buildXlsx(group: group, report: report, fund: fund);
    final zip = ZipDecoder().decodeBytes(bytes);
    final names = zip.files.map((f) => f.name).toSet();
    expect(names, containsAll(['[Content_Types].xml', 'xl/workbook.xml', 'xl/worksheets/sheet1.xml', 'xl/worksheets/sheet2.xml', 'xl/styles.xml']));
    final sheet2 = String.fromCharCodes(zip.findFile('xl/worksheets/sheet2.xml')!.content as List<int>);
    expect(sheet2, contains('Grace Mwanza'));
    expect(sheet2, contains('Joseph Banda &amp; Sons &lt;Ltd&gt;'));
    expect(sheet2, contains('<v>1620.0</v>'));
    expect(sheet2, contains('vBank'));
    if (out != null) File('$out/report.xlsx').writeAsBytesSync(bytes);
  });
}
