import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:icloud_storage/icloud_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/storage/settings_dao.dart';
import 'backup_service.dart';

/// Automatic, encrypted backups to the member's own cloud account — the
/// WhatsApp model, minus the plaintext era:
///
/// * Android → Google Drive's hidden per-app folder (`appDataFolder`), iOS →
///   the app's iCloud container. No vBank server is involved.
/// * The file is the same `BackupEnvelope` the manual export produces
///   (PBKDF2 + AEAD), sealed with a passphrase the member sets once. Google and
///   Apple only ever see ciphertext; without the passphrase the file is noise.
/// * Runs opportunistically when the app starts or comes to the foreground and
///   the last backup is older than the chosen interval (daily / weekly), Wi-Fi
///   only if the member says so. Keeps the newest [keep] copies.
/// * Restore is part of onboarding: sign in, pick the newest backup, type the
///   passphrase.
class CloudBackupService {
  CloudBackupService({
    CloudBackupStore? store,
    BackupService? backups,
    SettingsDao? settings,
    Future<bool> Function()? onWifi,
    PassphraseVault? vault,
    DateTime Function()? now,
  })  : _store = store ?? CloudBackupStore.forPlatform(),
        _backups = backups ?? BackupService(),
        _settings = settings ?? SettingsDao(),
        _onWifi = onWifi ?? _connectedToWifi,
        _vault = vault ?? KeystoreVault(),
        _now = now ?? DateTime.now;

  final CloudBackupStore? _store;
  final BackupService _backups;
  final SettingsDao _settings;
  final Future<bool> Function() _onWifi;
  final PassphraseVault _vault;
  final DateTime Function() _now;

  static const keep = 3;
  static const filePrefix = 'vbank-backup-';

  bool get isSupported => _store != null;
  String get providerName => _store?.name ?? 'Cloud';
  CloudBackupStore? get store => _store;

  // ------------------------------------------------------------- settings --

  Future<bool> enabled() => _settings.getBool(SettingKeys.cloudBackupEnabled, defaultValue: false);
  Future<int> intervalDays() async => (await _settings.get<int>(SettingKeys.cloudBackupIntervalDays)) ?? 1;
  Future<bool> wifiOnly() => _settings.getBool(SettingKeys.cloudBackupWifiOnly, defaultValue: true);
  Future<DateTime?> lastBackupAt() async {
    final raw = await _settings.get<String>(SettingKeys.cloudBackupLastAt);
    return raw == null ? null : DateTime.tryParse(raw);
  }
  Future<int?> lastBackupSize() => _settings.get<int>(SettingKeys.cloudBackupLastSize);
  Future<String?> lastError() => _settings.get<String>(SettingKeys.cloudBackupLastError);
  Future<bool> hasPassphrase() async => (await _vault.read())?.isNotEmpty ?? false;

  Future<void> setIntervalDays(int days) => _settings.set(SettingKeys.cloudBackupIntervalDays, days);
  Future<void> setWifiOnly(bool v) => _settings.set(SettingKeys.cloudBackupWifiOnly, v);

  /// Turns automatic backups on: signs in to the cloud account (interactive)
  /// and remembers the passphrase in the platform keystore so the scheduled
  /// runs can encrypt without asking. Throws on sign-in failure.
  Future<void> enable({required String passphrase}) async {
    final error = BackupService.validatePin(passphrase);
    if (error != null) throw ArgumentError(error);
    final store = _store;
    if (store == null) throw UnsupportedError('Cloud backup is not available on this platform');
    if (!await store.signIn(interactive: true)) throw StateError('Could not sign in to ${store.name}');
    await _vault.write(passphrase);
    await _settings.set(SettingKeys.cloudBackupEnabled, true);
    await _settings.delete(SettingKeys.cloudBackupLastError);
  }

  Future<void> changePassphrase(String passphrase) async {
    final error = BackupService.validatePin(passphrase);
    if (error != null) throw ArgumentError(error);
    await _vault.write(passphrase);
  }

  /// Turns automatic backups off. Files already in the cloud stay (they are
  /// useless without the passphrase); the passphrase is forgotten locally.
  Future<void> disable() async {
    await _settings.set(SettingKeys.cloudBackupEnabled, false);
    await _vault.delete();
  }

  // ------------------------------------------------------------- backing up --

  Future<bool> isDue() async {
    if (!await enabled()) return false;
    final last = await lastBackupAt();
    if (last == null) return true;
    return _now().difference(last) >= Duration(days: await intervalDays());
  }

  /// Backs up if enabled and due (and on Wi-Fi when required). Returns true
  /// when a backup was uploaded. Never throws; failures are recorded in
  /// [lastError] for the settings screen.
  Future<bool> runIfDue({bool force = false}) async {
    if (!force && !await isDue()) return false;
    if (!force && await wifiOnly() && !await _onWifi()) return false;
    try {
      await backupNow();
      return true;
    } catch (e) {
      await _settings.set(SettingKeys.cloudBackupLastError, '$e');
      debugPrint('[cloud-backup] failed: $e');
      return false;
    }
  }

  /// Builds a full backup, uploads it and prunes old copies. Throws on error.
  Future<CloudBackupFile> backupNow() async {
    final store = _store;
    if (store == null) throw UnsupportedError('Cloud backup is not available on this platform');
    final passphrase = await _vault.read();
    if (passphrase == null || passphrase.isEmpty) throw StateError('No backup passphrase set');
    if (!await store.signIn(interactive: false)) throw StateError('Not signed in to ${store.name}');
    final bytes = await _backups.buildFullBackup(passphrase);
    final stamp = _now().toUtc().toIso8601String().replaceAll(':', '-').split('.').first;
    final file = await store.upload('$filePrefix$stamp.${BackupService.fileExtension}', bytes);
    await _settings.set(SettingKeys.cloudBackupLastAt, _now().toUtc().toIso8601String());
    await _settings.set(SettingKeys.cloudBackupLastSize, bytes.length);
    await _settings.delete(SettingKeys.cloudBackupLastError);
    await _prune(store);
    return file;
  }

  Future<void> _prune(CloudBackupStore store) async {
    final files = await store.list();
    files.sort((a, b) => b.modified.compareTo(a.modified));
    for (final old in files.skip(keep)) {
      try {
        await store.delete(old);
      } catch (_) {/* best effort */}
    }
  }

  // --------------------------------------------------------------- restore --

  /// Backups in the cloud account, newest first (signs in interactively).
  Future<List<CloudBackupFile>> listRemote() async {
    final store = _store;
    if (store == null) return const [];
    if (!await store.signIn(interactive: true)) throw StateError('Could not sign in to ${store.name}');
    final files = await store.list();
    files.sort((a, b) => b.modified.compareTo(a.modified));
    return files;
  }

  Future<Uint8List> download(CloudBackupFile file) => _store!.download(file);

  static Future<bool> _connectedToWifi() async {
    try {
      final results = await Connectivity().checkConnectivity();
      return results.contains(ConnectivityResult.wifi) || results.contains(ConnectivityResult.ethernet);
    } catch (_) {
      return true; // no connectivity info: do not block the backup
    }
  }
}

/// Where the backup passphrase sleeps between automatic runs.
abstract class PassphraseVault {
  Future<String?> read();
  Future<void> write(String passphrase);
  Future<void> delete();
}

/// Platform keystore (Android Keystore / iOS Keychain) via flutter_secure_storage.
class KeystoreVault implements PassphraseVault {
  static const _key = 'backup.cloud.passphrase';
  final _storage = const FlutterSecureStorage();
  @override
  Future<String?> read() => _storage.read(key: _key);
  @override
  Future<void> write(String passphrase) => _storage.write(key: _key, value: passphrase);
  @override
  Future<void> delete() => _storage.delete(key: _key);
}

/// In-memory vault for tests.
class MemoryVault implements PassphraseVault {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String passphrase) async => value = passphrase;
  @override
  Future<void> delete() async => value = null;
}

/// One backup file in the cloud account.
class CloudBackupFile {
  final String id;
  final String name;
  final int size;
  final DateTime modified;
  const CloudBackupFile({required this.id, required this.name, required this.size, required this.modified});
}

/// Where the files go. One implementation per platform account.
abstract class CloudBackupStore {
  String get name;
  Future<bool> signIn({required bool interactive});
  Future<List<CloudBackupFile>> list();
  Future<CloudBackupFile> upload(String name, Uint8List bytes);
  Future<Uint8List> download(CloudBackupFile file);
  Future<void> delete(CloudBackupFile file);

  /// Google Drive on Android, iCloud on iOS, nothing on desktop (members there
  /// export a file; the desktop clients of Drive/iCloud can sync the folder).
  static CloudBackupStore? forPlatform() {
    if (kIsWeb) return null;
    if (Platform.isAndroid) return GoogleDriveBackupStore();
    if (Platform.isIOS) return ICloudBackupStore();
    return null;
  }
}

/// Web-type OAuth client id of the Google Cloud project — google_sign_in 7 on
/// Android needs it as `serverClientId` besides the Android client (package +
/// SHA-1). Not a secret. Baked in at build time:
///   flutter build … --dart-define=GOOGLE_SERVER_CLIENT_ID=1234-abc.apps.googleusercontent.com
/// (codemagic.yaml and release.yml pass it from the GOOGLE_SERVER_CLIENT_ID
/// variable). Empty → Google Drive backup reports itself as not configured.
const String kGoogleServerClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID', defaultValue: '');

/// Thrown when the cloud account cannot be used; the message is meant for the
/// screen, not the log.
class CloudBackupException implements Exception {
  final String message;
  const CloudBackupException(this.message);
  @override
  String toString() => message;
}

/// Google Drive, hidden per-app folder. Needs OAuth clients in the Google Cloud
/// project (Android: package + signing SHA-1; Web: its id is
/// [kGoogleServerClientId]) — see deploy/cloud-backup/README.md. The
/// `drive.appdata` scope sees only files this app created.
class GoogleDriveBackupStore implements CloudBackupStore {
  static const _scopes = [drive.DriveApi.driveAppdataScope];
  static bool _initialised = false;
  drive.DriveApi? _api;

  @override
  String get name => 'Google Drive';

  @override
  Future<bool> signIn({required bool interactive}) async {
    if (_api != null) return true;
    if (kGoogleServerClientId.isEmpty) {
      throw const CloudBackupException(
        'Google Drive backup is not configured in this build (no Google client id). '
        'See deploy/cloud-backup/README.md.',
      );
    }
    final signIn = GoogleSignIn.instance;
    try {
      if (!_initialised) {
        await signIn.initialize(serverClientId: kGoogleServerClientId);
        _initialised = true;
      }
      GoogleSignInAccount? account = await signIn.attemptLightweightAuthentication();
      if (account == null && interactive && signIn.supportsAuthenticate()) {
        account = await signIn.authenticate();
      }
      if (account == null) return false;
      var authorization = await account.authorizationClient.authorizationForScopes(_scopes);
      if (authorization == null && interactive) {
        authorization = await account.authorizationClient.authorizeScopes(_scopes);
      }
      if (authorization == null) return false;
      _api = drive.DriveApi(authorization.authClient(scopes: _scopes));
      return true;
    } on GoogleSignInException catch (e) {
      debugPrint('[cloud-backup] Google sign-in: ${e.code} ${e.description}');
      switch (e.code) {
        case GoogleSignInExceptionCode.canceled:
          return false;
        case GoogleSignInExceptionCode.clientConfigurationError:
          throw CloudBackupException(
            'Google sign-in is not set up for this app build: ${e.description ?? e.code.name}. '
            'The OAuth clients (package + SHA-1, and the Web client id) must exist in the Google Cloud project.',
          );
        default:
          throw CloudBackupException('Google sign-in failed: ${e.description ?? e.code.name}');
      }
    }
  }

  @override
  Future<List<CloudBackupFile>> list() async {
    final api = _api!;
    final res = await api.files.list(
      spaces: 'appDataFolder',
      q: "name contains '${CloudBackupService.filePrefix}'",
      $fields: 'files(id,name,size,modifiedTime)',
      pageSize: 50,
    );
    return [
      for (final f in res.files ?? const <drive.File>[])
        CloudBackupFile(
          id: f.id!,
          name: f.name ?? '',
          size: int.tryParse(f.size ?? '') ?? 0,
          modified: f.modifiedTime ?? DateTime.fromMillisecondsSinceEpoch(0),
        ),
    ];
  }

  @override
  Future<CloudBackupFile> upload(String name, Uint8List bytes) async {
    final api = _api!;
    final meta = drive.File()
      ..name = name
      ..parents = ['appDataFolder'];
    final created = await api.files.create(
      meta,
      uploadMedia: drive.Media(Stream.value(bytes), bytes.length, contentType: 'application/octet-stream'),
      $fields: 'id,name,size,modifiedTime',
    );
    return CloudBackupFile(
      id: created.id!,
      name: created.name ?? name,
      size: bytes.length,
      modified: created.modifiedTime ?? DateTime.now().toUtc(),
    );
  }

  @override
  Future<Uint8List> download(CloudBackupFile file) async {
    final media = await _api!.files.get(file.id, downloadOptions: drive.DownloadOptions.fullMedia) as drive.Media;
    final chunks = <int>[];
    await for (final c in media.stream) {
      chunks.addAll(c);
    }
    return Uint8List.fromList(chunks);
  }

  @override
  Future<void> delete(CloudBackupFile file) => _api!.files.delete(file.id);
}

/// iCloud Drive, in the app's own container (needs the iCloud capability with
/// this container id in the Apple developer account; see ios/Runner/Runner.entitlements).
class ICloudBackupStore implements CloudBackupStore {
  static const containerId = 'iCloud.zm.co.tickethost.vbank';
  static const _folder = 'backups';

  @override
  String get name => 'iCloud';

  @override
  Future<bool> signIn({required bool interactive}) async {
    // iCloud uses the device's Apple account; there is nothing to sign in to.
    // Probing the container tells us whether iCloud Drive is available.
    try {
      await ICloudStorage.gather(containerId: containerId);
      return true;
    } catch (e) {
      debugPrint('[cloud-backup] iCloud unavailable: $e');
      return false;
    }
  }

  @override
  Future<List<CloudBackupFile>> list() async {
    final files = await ICloudStorage.gather(containerId: containerId);
    return [
      for (final f in files)
        if (f.relativePath.startsWith('$_folder/') && p.basename(f.relativePath).startsWith(CloudBackupService.filePrefix))
          CloudBackupFile(
            id: f.relativePath,
            name: p.basename(f.relativePath),
            size: f.sizeInBytes,
            modified: f.contentChangeDate,
          ),
    ];
  }

  @override
  Future<CloudBackupFile> upload(String name, Uint8List bytes) async {
    final dir = await getTemporaryDirectory();
    final local = File(p.join(dir.path, name));
    await local.writeAsBytes(bytes, flush: true);
    final done = Completer<void>();
    await ICloudStorage.upload(
      containerId: containerId,
      filePath: local.path,
      destinationRelativePath: '$_folder/$name',
      onProgress: (stream) => stream.listen(
        (_) {},
        onDone: () => done.isCompleted ? null : done.complete(),
        onError: (Object e) => done.isCompleted ? null : done.completeError(e),
        cancelOnError: true,
      ),
    );
    await done.future.timeout(const Duration(minutes: 2), onTimeout: () {});
    try {
      await local.delete();
    } catch (_) {}
    return CloudBackupFile(id: '$_folder/$name', name: name, size: bytes.length, modified: DateTime.now().toUtc());
  }

  @override
  Future<Uint8List> download(CloudBackupFile file) async {
    final dir = await getTemporaryDirectory();
    final local = File(p.join(dir.path, 'restore-${file.name}'));
    final done = Completer<void>();
    await ICloudStorage.download(
      containerId: containerId,
      relativePath: file.id,
      destinationFilePath: local.path,
      onProgress: (stream) => stream.listen(
        (_) {},
        onDone: () => done.isCompleted ? null : done.complete(),
        onError: (Object e) => done.isCompleted ? null : done.completeError(e),
        cancelOnError: true,
      ),
    );
    await done.future.timeout(const Duration(minutes: 2), onTimeout: () {});
    final bytes = await local.readAsBytes();
    try {
      await local.delete();
    } catch (_) {}
    return bytes;
  }

  @override
  Future<void> delete(CloudBackupFile file) => ICloudStorage.delete(containerId: containerId, relativePath: file.id);
}
