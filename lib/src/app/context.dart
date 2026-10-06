import 'dart:typed_data';

import 'package:uuid/uuid.dart';

/// Signs a canonical payload with the device identity key. The key itself
/// never leaves the platform keystore; this callback is the only way to
/// use it. Tests pass a throwaway in-memory signer.
typedef SignPayload = Future<Uint8List> Function(List<int> payload);

/// Clock for timestamps. Production passes `DateTime.now`; tests pin time.
/// All stored timestamps are truncated to milliseconds (see `signedInstant`
/// in signing payloads: what is signed is what is stored).
typedef AppClock = DateTime Function();

/// Record ids. Production generates UUID v7 (time-ordered); tests count.
typedef IdGenerator = String Function();

/// Production id generation: time-ordered UUID v7.
String uuidV7() => const Uuid().v7();

/// Who this device acts as. Services take the acting peer id per call and
/// sign through [sign]; this is the ambient identity providers hold.
final class AppContext {
  /// This device's peer id.
  final String peerId;

  /// The name groups know this device by.
  final String displayName;

  /// Signs canonical payloads with the identity key.
  final SignPayload sign;

  /// Creates the device identity context.
  const AppContext({
    required this.peerId,
    required this.displayName,
    required this.sign,
  });
}
