import 'dart:typed_data';

/// Row primitives shared by every DTO.
///
/// A row is `Map<String, Object?>` straight from sqflite. Readers throw on
/// malformed data; each `fromRow` catches everything and returns
/// `Err(StorageFailure)` — a corrupt row is a storage problem, never a
/// domain one. Writers never throw.
abstract final class Dto {
  /// Reads a non-null [int] column.
  static int integer(Map<String, Object?> row, String column) =>
      row[column]! as int;

  /// Reads a [double] column (SQLite may hand back an int for whole values).
  static double real(Map<String, Object?> row, String column) {
    final Object? value = row[column];
    if (value is int) {
      return value.toDouble();
    }
    return value! as double;
  }

  /// Reads a nullable [double] column.
  static double? realOrNull(Map<String, Object?> row, String column) {
    final Object? value = row[column];
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value.toDouble();
    }
    return value as double;
  }

  /// Reads a non-null text column.
  static String text(Map<String, Object?> row, String column) =>
      row[column]! as String;

  /// Reads a nullable text column.
  static String? textOrNull(Map<String, Object?> row, String column) =>
      row[column] as String?;

  /// Reads a 0/1 boolean column.
  static bool flag(Map<String, Object?> row, String column) =>
      (row[column]! as int) == 1;

  /// Writes a boolean as 0/1.
  static int flagValue(bool value) => value ? 1 : 0;

  /// Reads a millis-UTC timestamp column.
  static DateTime instant(Map<String, Object?> row, String column) =>
      DateTime.fromMillisecondsSinceEpoch(
        row[column]! as int,
        isUtc: true,
      );

  /// Reads a nullable millis-UTC timestamp column.
  static DateTime? instantOrNull(Map<String, Object?> row, String column) {
    final int? millis = row[column] as int?;
    if (millis == null) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
  }

  /// Writes a timestamp as millis UTC.
  static int instantValue(DateTime value) =>
      value.toUtc().millisecondsSinceEpoch;

  /// Reads a non-null blob column.
  static Uint8List bytes(Map<String, Object?> row, String column) =>
      row[column]! as Uint8List;

  /// Reads a nullable blob column.
  static Uint8List? bytesOrNull(Map<String, Object?> row, String column) =>
      row[column] as Uint8List?;

  /// Reads an enum stored as its `.name`; throws on unknown values so
  /// newer-than-us data fails loudly instead of silently defaulting.
  static T enumeration<T extends Enum>(
    Map<String, Object?> row,
    String column,
    List<T> values,
  ) =>
      values.byName(row[column]! as String);
}
