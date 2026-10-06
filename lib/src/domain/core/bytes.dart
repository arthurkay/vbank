import 'dart:typed_data';

/// Byte-wise equality for [Uint8List].
///
/// `==` on typed lists is identity, so entities holding keys and signatures
/// compare through here instead.
bool bytesEqual(Uint8List a, Uint8List b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

/// Hash consistent with [bytesEqual].
int bytesHash(Uint8List bytes) => Object.hashAll(bytes);
