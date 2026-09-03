# Deployment Guide — vBank

How **vBank** is built, signed and published. Same pattern as `arthurkay/spark`:
store releases on **Codemagic**, desktop releases (and an optionally signed
Android APK) on **GitHub Actions**, both triggered by pushing a `v*` tag, both
signing Android with the **same keystore** through the same Gradle contract.

| Target | Pipeline | Output |
| --- | --- | --- |
| Google Play (internal track, draft) | Codemagic `android-release` | signed `.aab` (+ `.apk`, mapping) |
| TestFlight | Codemagic `ios-release` | signed `.ipa` |
| Linux / Windows / macOS | GitHub `Release desktop builds` | tar.gz / zip + Inno Setup / dmg on the GitHub release |
| Android APK on the GitHub release | GitHub `Release desktop builds` → `android` job | `vbank-<version>-android.apk` (only when keystore secrets exist) |
| Relay container | GitHub `Relay image` | `ghcr.io/arthurkay/vbank-relay` |
| Website | GitHub Pages (`docs/`) | https://arthurkay.github.io/vbank/ |

Identifiers: package / bundle id **`zm.co.tickethost.vbank`**, iCloud container
`iCloud.zm.co.tickethost.vbank`, Android keystore alias **`vbank`**.

---

## 1. One-time setup

### 1.1 Android — release keystore

```bash
keytool -genkey -v -keystore ~/vbank-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias vbank
base64 -w0 ~/vbank-release.jks > ~/vbank-release.jks.b64     # macOS: base64 -i … | tr -d '\n'
```

Keep the `.jks`, its passwords and the base64 copy in a password manager.
**Never commit them** (`*.jks`, `android/key.properties` are git-ignored). If you
use Play App Signing, this is the *upload* key; Google re-signs with the app
signing key — record **both** SHA-1s for the Google Sign-In OAuth client
(`deploy/cloud-backup/README.md`).

### 1.2 Android — Google Play service account

Google Cloud Console → enable **Google Play Android Developer API** → IAM →
Service account (e.g. `codemagic-deploy`) → JSON key. Play Console → Users and
permissions → invite the service-account e-mail with *Release to production* /
*Manage testing tracks*. The JSON goes to Codemagic as `PLAY_SERVICE_ACCOUNT_JSON`.

The app must exist in the Play Console with package `zm.co.tickethost.vbank`
and one manual upload must have been made before API uploads are accepted.

### 1.3 iOS — App Store Connect API key

App Store Connect → Users and Access → Integrations → **Generate API key**
(App Manager or Admin), download the `.p8` once, note Key ID and Issuer ID.
Register the App ID `zm.co.tickethost.vbank` in the developer portal with the
**iCloud** capability and container `iCloud.zm.co.tickethost.vbank` (needed for
automatic backups), and create the app record in App Store Connect.

Certificates and profiles: let Codemagic manage them (automatic signing via the
Developer Portal integration) — nothing to export by hand.

---

## 2. Codemagic

1. codemagic.io → Add application → GitHub → `arthurkay/vbank`. It picks up
   `codemagic.yaml` from the repo root.
2. **Teams → Codemagic.yaml settings → Android signing**: upload
   `vbank-release.jks`, enter keystore password, alias `vbank`, key password, and
   name the reference **`vbank_keystore`** (the name used in `codemagic.yaml`).
   Codemagic then injects `CM_KEYSTORE_PATH`, `CM_KEYSTORE_PASSWORD`,
   `CM_KEY_ALIAS`, `CM_KEY_PASSWORD` into the build — exactly what
   `android/app/build.gradle.kts` reads.
3. **Teams → Integrations → Developer Portal**: add the App Store Connect API
   key (`.p8`, Key ID, Issuer ID) and name it **`vBank App Store Connect`**.
4. **Teams → Variables and secrets** → group `android`:

   | Variable | Value | Secure |
   | --- | --- | --- |
   | `PLAY_SERVICE_ACCOUNT_JSON` | contents of the service-account JSON | yes |

Workflows in `codemagic.yaml`:

* `pr-checks` — analyze + unit tests on pull requests (network-tagged loopback tests excluded).
* `android-release` — `flutter build appbundle --release` (+ APK), uploads to Play **internal** track as a draft.
* `ios-release` — `flutter build ipa` with automatic signing, uploads to **TestFlight**.

Promote from internal → production and TestFlight → App Store review in the
consoles once you have checked the builds.

---

## 3. GitHub Actions

`.github/workflows/release.yml` runs on the same `v*` tag. Desktop jobs need no
secrets. To also attach a **signed Android APK** to the GitHub release (handy for
members who side-load), add these repository secrets
(Settings → Secrets and variables → Actions):

| Secret | Value |
| --- | --- |
| `KEYSTORE_BASE64` | contents of `vbank-release.jks.b64` |
| `KEYSTORE_PASSWORD` | keystore password |
| `KEY_ALIAS` | `vbank` |
| `KEY_PASSWORD` | key password |

The job decodes the keystore to a temp file and exports the same `CM_KEYSTORE_*`
variables Codemagic would, so Gradle takes the same code path. Without the
secrets the job logs "skipped" and the release simply has no APK.

---

## 4. Releasing

1. Bump `version:` in `pubspec.yaml` (`1.8.0+8` → name `1.8.0`, build 8; the
   build number must increase for every store upload).
2. Commit and push to `main`; wait for the checks.
3. Tag and push:

   ```bash
   git tag -a v1.8.0 -m "vBank 1.8.0" && git push origin v1.8.0
   ```

   → Codemagic: Play internal + TestFlight. GitHub: release page with desktop
   builds (+ APK) and a rebuilt relay image tagged `1.8.0`.
4. Test the internal/TestFlight builds, then promote in the consoles.

Local signed build for a quick check — create `android/key.properties`
(git-ignored; see the comment at the top of `android/app/build.gradle.kts`):

```properties
storeFile=/home/you/vbank-release.jks
storePassword=…
keyAlias=vbank
keyPassword=…
```

then `flutter build apk --release`.

---

## 5. Troubleshooting

| Symptom | Fix |
| --- | --- |
| Gradle: `WARNING: no release keystore … signed with the DEBUG keystore` | Neither `CM_KEYSTORE_PATH` nor `android/key.properties` present — fine locally, never distribute that APK. |
| `Keystore was tampered with, or password was incorrect` | `KEYSTORE_PASSWORD` / Codemagic keystore password wrong. |
| `No key with alias 'vbank'` | Alias mismatch — check what `keytool -list -v -keystore vbank-release.jks` prints. |
| Play upload rejected: `APK signature … does not match` | Wrong keystore for an existing app: use the original upload key or request an upload-key reset in the Play Console. |
| Google Sign-In in the app fails with `DEVELOPER_ERROR` | OAuth client SHA-1 does not match the signing key of that build (debug vs upload vs Play app signing). See `deploy/cloud-backup/README.md`. |
| Codemagic iOS: `No profiles for 'zm.co.tickethost.vbank'` | App ID not registered / Developer Portal integration missing; check the iCloud capability is on the App ID too. |
| Version already used | Increase the `+build` number in `pubspec.yaml`. |
