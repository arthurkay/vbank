# Cloud backup — one-time developer setup

vBank backs members' data up to **their own** Google Drive (Android) or iCloud
(iPhone), encrypted with a backup passphrase (`lib/services/cloud_backup_service.dart`).
The code is in place; each platform needs a one-time registration by the app
publisher before sign-in works.

## Android → Google Drive

Google Sign-In on Android identifies the app by package name **and** signing
certificate. Without a matching OAuth client the sign-in dialog fails with
`DEVELOPER_ERROR` / "sign in failed".

1. Google Cloud Console → create (or pick) a project, e.g. *vBank*.
2. **APIs & Services → Library → Google Drive API → Enable.**
3. **APIs & Services → OAuth consent screen**: External, app name *vBank*,
   support e-mail, scopes: add `.../auth/drive.appdata` (non-sensitive). Publish
   the consent screen (Testing mode limits sign-ins to 100 listed test users).
4. **Credentials → Create credentials → OAuth client ID → Android**:
   * Package name: `zm.co.tickethost.vbank`
   * SHA-1: of every signing key you ship with —
     * debug: `keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android | grep SHA1`
     * release: `keytool -list -v -keystore <your-release.jks> -alias <alias> | grep SHA1`
     * Play App Signing: Play Console → Setup → App signing → *App signing key certificate* SHA-1.
   Create one Android client per SHA-1. No file has to be added to the app for
   google_sign_in 7 on Android; the match is done by package + certificate.
5. Test: Settings → Backup & Restore → Automatic backup → on. The account picker
   appears, then the Drive `appdata` consent. Files are invisible in Drive's UI
   (hidden app folder); the user can see and clear them under
   Drive → Settings → Manage apps → vBank.

## iOS → iCloud

1. Apple Developer → Certificates, Identifiers & Profiles → **Identifiers → App IDs →
   `zm.co.tickethost.vbank`** → enable **iCloud** with *CloudKit* / iCloud Documents,
   and create the container **`iCloud.zm.co.tickethost.vbank`**.
2. Xcode → Runner target → Signing & Capabilities: the repo already carries
   `ios/Runner/Runner.entitlements` (referenced from the project) with that
   container; make sure automatic signing regenerates the provisioning profile
   after the capability exists on the App ID.
3. Nothing to enter in the app: iCloud uses the device's Apple account.
   `ICloudBackupStore.containerId` must equal the container created in step 1.

## Desktop

No cloud path: members export a backup file (Backup & Restore) and can drop it
into a folder their Google Drive / iCloud desktop client syncs.

## What is stored

One `vbank-backup-<timestamp>.vbankbackup` file per run (newest 3 kept), a
`BackupEnvelope`: PBKDF2-HMAC-SHA256 + AEAD over a CBOR payload (v3) holding the
identity and signing key, group keys, groups, members and all records. Without
the passphrase the file is unreadable; Google/Apple never see plaintext.
