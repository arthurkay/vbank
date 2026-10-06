import 'package:flutter_test/flutter_test.dart';
import 'package:vbank/src/domain/core/failure.dart';
import 'package:vbank/src/domain/core/result.dart';

void main() {
  group('Result', () {
    test('Ok carries its value', () {
      const r = Ok(42);

      expect(r.isOk, isTrue);
      expect(r.isErr, isFalse);
      expect(r.value, 42);
    });

    test('Err carries its failure', () {
      const r = Err<int>(NotFoundFailure('group:abc'));

      expect(r.isOk, isFalse);
      expect(r.isErr, isTrue);
      expect(r.failure, isA<NotFoundFailure>());
    });

    test('value throws on Err, failure throws on Ok', () {
      const err = Err<int>(NetworkFailure());
      const ok = Ok(1);

      expect(() => err.value, throwsStateError);
      expect(() => ok.failure, throwsStateError);
    });

    test('map transforms Ok and passes Err through', () {
      expect(const Ok(2).map((v) => v * 2).value, 4);

      const err = Err<int>(NetworkFailure());
      final mapped = err.map((v) => v * 2);

      expect(mapped.isErr, isTrue);
      expect(mapped.failure, isA<NetworkFailure>());
    });

    test('flatMap chains fallible operations', () {
      Result<int> parse(String s) {
        final n = int.tryParse(s);
        return n == null ? const Err(ValidationFailure('notAnInt')) : Ok(n);
      }

      expect(const Ok('21').flatMap(parse).value, 21);
      expect(const Ok('xx').flatMap(parse).failure, isA<ValidationFailure>());

      const err = Err<String>(NetworkFailure());
      expect(err.flatMap(parse).failure, isA<NetworkFailure>());
    });

    test('unit is the Unit value', () {
      const Result<Unit> r = Ok(unit);

      expect(r.isOk, isTrue);
      expect(r.value, unit);
    });
  });
}
