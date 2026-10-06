import 'package:flutter_test/flutter_test.dart';
import 'package:vbank/src/domain/core/failure.dart';
import 'package:vbank/src/domain/core/result.dart';
import 'package:vbank/src/domain/meeting_time.dart';

void main() {
  group('MeetingTime', () {
    test('parses HH:MM', () {
      final Result<MeetingTime> r = MeetingTime.parse('09:00');

      expect(r.isOk, isTrue);
      expect(r.value, const MeetingTime(hour: 9, minute: 0));
    });

    test('rejects bad shapes and ranges', () {
      for (final String raw in [
        '9:00',
        '09:0',
        '0900',
        '09:00:00',
        '',
        '24:00',
        '09:60',
        'ab:cd',
      ]) {
        expect(
          MeetingTime.parse(raw).failure,
          isA<ValidationFailure>(),
          reason: raw,
        );
      }
    });

    test('formats back to the wire representation', () {
      expect(
        const MeetingTime(hour: 9, minute: 5).format(),
        '09:05',
      );
      expect(
        MeetingTime.parse('18:30').value.format(),
        '18:30',
      );
    });
  });
}
