# vBank — DESIGN_PLAN.md vs Implementation Gap Analysis

> **Update 2026-08-25 (v1.1):** the gaps below were worked through in priority order. Resolution status per item is in the *Resolution* section at the end; the tables that follow are the original audit and remain useful as a record of *why* each change was made. DESIGN_PLAN.md §36 is now the status of record.

*Audit date: 2026-08-25. Method: every checkable requirement in DESIGN_PLAN.md (35 sections) was compared against the current `lib/`, `test/`, `android/`, `ios/` and `pubspec.yaml`, with file:line evidence. Status legend: ✅ implemented · 🟡 partial · ❌ missing · 🔀 deviates (done differently — see note).*

---

## 1. Scorecard by plan section

| § | Section | Status | One-line verdict |
|---|---|---|---|
| 1 | Project Vision | 🟡 | No server, offline-first, signed txs ✅ — but "encrypted at rest" ❌ (plain SQLite). |
| 3 | Core Principles | 🟡 | P1/P3 ✅; P2 at-rest ❌; P4 signature covers only part of the tx; P5 shadcn ❌ (Material). |
| 4 | Use cases (10) | 🟡 | All 10 reachable locally; only transactions/snapshots/joins actually sync between phones. |
| 5 | Tech stack | 🔀 | dart_ipfs, Riverpod, cryptography, app_links ✅. **Dead deps:** shadcn_flutter, sqlcipher_flutter_libs, cbor, riverpod_annotation/generator, build_runner. intl 0.20 vs 0.19. |
| 6 | Architecture | 🟡 | Service/DAO/crypto layers ✅. `DiscoveryService` and `PubSubService` exist but are never attached or used. |
| 7 | P2P networking | ✅ | Node config (bootstrap, PubSub, DHT, relay) and full `IpfsService` API present; `findProviders`/`stop` unused. |
| 8 | Discovery | ❌ | No `_vbank._tcp` mDNS; no explicit DHT `provide`; `DiscoveryService.findProviders` is called with a topic string, not a CID, and never runs. Discovery = PubSub + invite-link CID only. |
| 9 | Data flow (11 steps) | 🟡 | Steps 1–10 ✅ (encrypt → IPFS → PubSub → fetch → decrypt → verify). Step 5 DHT provide implicit; step 11 "store in SQLCipher" ❌; role-of-signer check ❌. |
| 10 | Battery strategy | ❌ | Node starts at launch and **never stops**; no 5/15-min background degradation; manual sync doesn't stop node after 60 s; no Wi-Fi gating. Periodic 5-min foreground sync ✅. |
| 11 | Encryption model | 🟡 | In-transit XChaCha20-Poly1305 with AAD-bound header ✅. At-rest SQLCipher ❌; `deriveLocalDbKey` has zero callers. |
| 12 | Key hierarchy | 🟡 | Passphrase→HKDF→group key ✅; peer ID = UUIDv5(pubkey) ✅. Private key in **plaintext SQLite**, not Keystore/Keychain ❌; device secret ❌; HKDF over a human passphrase has no stretching. |
| 13 | Roles & permissions | ❌ | Enum + `canX` helpers exist; **zero callers**. Any member can create transactions. Inbound snapshots apply role/config/roster changes from any key-holder with no signature/role check. Loan approve/reject/disburse *are* gated (service only, no UI). |
| 14 | Group lifecycle | 🟡 | Create → local → IPFS snapshot ✅. DHT publish ❌. Only `contributionAmount` collected in UI; `updateGroupConfig` uncalled; `dissolved` never set. |
| 15 | Loan lifecycle | ❌ | request/approve/reject/disburse (service) ✅. **No** loan transaction on disburse, no repayment schedule, no repayment→loan link, no `repaying/completed/defaulted`, no penalties; `maxLoanMultiplier`, `minContributionsForLoan`, `requireLoanApproval`, `hasOutstandingLoan` never consulted. Loans never sync. No approve UI. |
| 16 | Invite system | 🟡 | QR + share + `vbank://join?group&inviter&cid` ✅; passphrase-verified join ✅. `InviteService` (nonce/expiry/signature/one-use) is **dead code**; links reusable forever; `requireApproval` joins dropped; "Copy link" is a fake snackbar. |
| 17 | Owner transfer | ❌ | Model + table only. No DAO/service/UI/sync. |
| 18 | Dissolution | ❌ | Model + table only. |
| 19 | Conflict resolution | 🔀 | Tx dedup by id ✅. Group `sequenceNumber` is only bumped by uncalled `updateGroupConfig` → every snapshot is seq 0 → `>=` check always passes → **last-received-wins**. No timestamp/peerId tiebreak. `UNIQUE(group_id, seq)` makes concurrent offline txs collide → remote tx silently dropped. |
| 20 | Notifications | ❌ | Plugin init + 5 Android permissions ✅. `NotificationScheduler`/`showNotification` have **zero call sites**; 7 of 10 triggers unimplemented; `tz.local` never set; random notification IDs; `notification_schedules` table dead; Settings→Notifications tile is `onTap: () {}`. |
| 21 | Offline queue | 🔀 | `pending_transactions` table + model unused; sync runs on `transactions.synced` (2 states). No `syncing/failed`, no retry cap, no `retry_count`/`error_message`, no retry UI. |
| 22 | Key recovery | 🟡 | PIN-encrypted full backup (PBKDF2 + XChaCha20) ✅, restore applies identity + groups + group keys ✅. **But restore reads the local `app_backups` table — empty on a new device.** No QR/link/file export or import; no DHT membership check; no device revocation. `vbank://restore?backup=<id>` id is discarded. |
| 23 | Deep linking | ✅ | `app_links`, cold-start + stream, join/restore routes, Android/iOS scheme registration. Error snackbar path uses `ScaffoldMessenger.maybeOf(navigator.context)` → likely null. No https App Links. |
| 24–26 | UI system / palette / components | 🔀 | Entirely Material 3. No shadcn, no color tokens, no TextTheme scale, no fonts; seed colours fed to `fromSeed` don't produce the plan's hex values. No bottom sheets, no skeletons. |
| 27 | Screen inventory (30) | 🟡 | 15 files exist; **14 plan screens missing** (group settings/reports/dissolution/transfer, tx detail/reversal/pending, loan detail/approve/repayment, meeting detail/attendance, identity backup, notification settings, sync status). `/groups` `/transactions` `/loans` `/meetings` are routed but unreachable placeholders. |
| 28 | Data models | ✅/🔀 | All classes present, fields match. 6 models dead (Reversal, RepaymentSchedule, MemberRemoval, OwnershipTransfer, GroupDissolution, PendingTransaction). `MemberRole/MemberStatus` defined twice. `MemberStatement.transactions` missing. |
| 29 | Storage schema | 🟡 | 19 tables (plan 18; + `group_keys`). Columns match. **9 tables have no DAO and no reads/writes.** SQLCipher ❌. Schema v3 with migrations ✅. |
| 30 | Project structure | ✅ | Matches, plus extras (`sync_envelope.dart`, `group_key_*`, split model files, unused `models.dart` barrel). |
| 31 | Dependencies | 🔀 | See §5. |
| 32 | Implementation phases | 🔀 | Phases 1–4 marked "COMPLETED" in the plan overstate: loan repay, 3 list screens (stubs), notifications, invites, reports are not done. |
| 33 | Build config | 🟡 | Effective `minSdk` 24 (Flutter default), plan says 21. Release falls back to **debug keystore** if `key.properties` absent. Intent filter has no `host` restriction. iOS plist ✅. |
| 34 | Testing | 🟡 | 36 tests: crypto, envelope, deep-link, model JSON ✅. No service/loan/group tests, no conflict tests, no integration tests; `widget_test.dart` is `expect(true, isTrue)`. |
| 35 | Future considerations | — | 2 of 19 done (QR→join wiring, periodic sync); 6 partially present as service/model only. |

**Overall:** the plan is roughly **40% implemented end-to-end**. What exists is a working single-phone ledger with real crypto (signing, encrypted IPFS sync, passphrase join, PIN backups). What is missing is almost everything that makes it a *multi-party* system: permission enforcement, loan lifecycle, conflict resolution, invites with nonces, discovery, notifications, and the second half of the screens.

---

## 2. Cross-cutting patterns

1. **"Skeleton complete, wiring absent."** The codebase consistently has the *artifact* (table, model, service method, helper) without the *call site*: `canWrite` (0 callers), `InviteService` (0), `NotificationScheduler` (0), `ReportService` (0), `recordAttendance` (0), `deriveLocalDbKey` (0), `updateGroupConfig` (0), `DiscoveryService`/`PubSubService` (never attached), 9 dead tables, 6 dead models, 5 dead dependencies.
2. **Security is enforced locally, not on the wire.** Loan approval requires admin *on the approver's phone*, but loans never sync, and inbound snapshots are trusted from any key-holder. The plan's model — "every mutation signed; receiver verifies the signer's role" — is implemented only for transactions, and even there without the role part.
3. **Two things the plan mandates are not wired despite deps being present:** SQLCipher (`sqlcipher_flutter_libs`) and shadcn_flutter.
4. **The plan's "COMPLETED" markers are unreliable** — use this document, not §32, as the status of record.

---

## 3. Gaps ranked by consequence

### Tier 1 — security / data-loss (do first)

| # | Gap | Where | Why it matters |
|---|---|---|---|
| 1 | **Local DB unencrypted** | `lib/core/storage/database.dart:20` | Identity seed + all group keys in cleartext on disk. Plan §11/§12/§29. |
| 2 | **No role enforcement** | `transaction_service.dart:37`, `group_detail_screen.dart:53`, `sync_manager.dart` `_applySnapshot` | Any member can record any transaction; any key-holder can publish a snapshot that changes roles/config/roster. |
| 3 | **Restore doesn't work on a new device** | `restore_backup_screen.dart:38-47` | Reads the local `app_backups` table; there is no export/import path. Device migration (§22) is impossible. |
| 4 | **Snapshot conflict rule is last-received-wins** | `group_service.dart` `importSnapshot`; only `updateGroupConfig` bumps `sequenceNumber` | Any stale snapshot overwrites newer roster/config; removed members get re-added. |
| 5 | **Concurrent offline transactions collide and are dropped** | `database.dart` `idx_transactions_group_seq`; `transaction_dao.insertWithNextSequence` | Two phones offline both allocate seq N; the loser's tx is silently discarded on import. Needs per-author sequence or (peerId, seq) uniqueness. |
| 6 | **Invites reusable forever, no expiry** | `invite_screen.dart:49`, `InviteService` unused | Anyone who ever saw a link + passphrase can join at any time. |
| 7 | **Release signed with debug key when `key.properties` is absent** | `android/app/build.gradle.kts` | Fine for dev, must not ship. |

### Tier 2 — core features that don't exist yet

| # | Gap | Where |
|---|---|---|
| 8 | Loan lifecycle after disburse (loan tx, schedule, repayment matching, completion, default, penalties, limits) | `loan_service.dart`, dead `repayment_schedules` |
| 9 | Loans/meetings/role changes never sync between devices | `sync_envelope.dart` `SyncPayloadType` has only tx/snapshot/join |
| 10 | Notifications never scheduled or shown | `notification_scheduler.dart` — 0 callers |
| 11 | 14 missing screens; 4 placeholder screens | see §27 |
| 12 | Owner transfer, dissolution, member removal with settlement, reversals | models/tables only |
| 13 | Offline queue semantics (`failed`, retry cap, retry UI) | `pending_transactions` unused |
| 14 | Battery policy (node lifecycle, background degradation, Wi-Fi) | `sync_manager.dart`, `main.dart` |
| 15 | Discovery (`_vbank._tcp` mDNS, DHT provide/find) | `discovery_service.dart` dead |

### Tier 3 — small bugs found during the audit

- `invite_screen.dart:182-189` and `share_service.dart:29-32`: "Copy link" shows "copied!" without calling `Clipboard.setData`.
- `home_screen.dart:369`: Settings → Notifications is `onTap: () {}`.
- `main.dart:119-122`: deep-link error snackbar uses `ScaffoldMessenger.maybeOf(navigator.context)`, which sits above any Scaffold → never shows.
- `notification_service.dart`: `tz.local` never set (defaults to UTC); notification IDs are `uuid.v4().hashCode` so nothing can be cancelled.
- `user_identity.dart:3-4` vs `group.dart:138-139`: `MemberRole`/`MemberStatus` defined twice; `models.dart` barrel exports the unused copy.
- `transaction_service.signingPayload` omits `currency`, `note`, `timestamp` → those fields are mutable without invalidating the signature.
- `key_derivation.deriveGroupKey` uses `codeUnits` (UTF-16) rather than UTF-8 — works, but is a cross-platform foot-gun; and HKDF alone gives a human passphrase no brute-force resistance (the code's own comment says so).
- Backup PIN minimum is 4 digits for a payload containing the identity seed and all group keys.
- `AndroidManifest.xml`: `ACCESS_FINE/COARSE_LOCATION` requested but unused; deep-link filter has no `host`; `usesCleartextTraffic="true"`.
- Effective `minSdk` is 24, plan says 21.
- `MemberStatement.transactions` field missing (`report.dart`).
- `groups.cid` / `group_keys` exist in code but not in the plan's schema — plan needs updating.

---

## 4. Deviations worth keeping (update the plan instead)

| Deviation | Recommendation |
|---|---|
| `app_links` instead of `uni_links` (discontinued) | Keep; plan already partially updated. |
| PBKDF2 + salt + stored nonce/MAC envelope for backups (plan: bare XChaCha20 with PIN) | Keep — plan's version was unrecoverable. |
| Passphrase entered by joiner + snapshot CID in link (plan: group key "encrypted with inviter's key for recipient") | Keep — the plan's scheme needs the recipient's key before the QR exists. Document it in §16. |
| JSON `SyncEnvelope` instead of CBOR/UR encoding | **Decided (v1.2): CBOR everywhere** on the wire and in backup files (`WireCodec`); invite links stay plain URIs; legacy JSON envelopes still decode. |
| Material 3 instead of shadcn_flutter | **Decided (v1.2): shadcn_flutter.** All screens ported; `lib/ui/ui.dart` is the kit; dialogs replaced by keyboard-aware bottom sheets. |
| `transactions.synced` instead of `pending_transactions` queue | Either drop the table or implement §21 on top of it. Don't keep both. |
| Multidex removed, Java 17 desugaring kept | Keep. |

---

## 5. Suggested order of work

1. **SQLCipher** (or `sqflite_sqlcipher`) for the local DB, with the key derived from a device secret in `flutter_secure_storage`. Unblocks the "keys on disk" problem for both identity and group keys.
2. **Role enforcement**: gate `createTransaction` on `canWrite`; require snapshots to be signed by an owner/admin and verify on import; bump `sequenceNumber` on every roster/config change and implement the §19 tiebreaks.
3. **Fix the sequence-number collision**: make `sequence_number` per-author (`UNIQUE(group_id, from_peer_id, sequence_number)`) or drop the global uniqueness.
4. **Backup export/import** (QR/file) so restore works on a new device; honour `backup` id in the restore deep link.
5. **Invites**: wire `InviteService` into link generation (invite id + nonce), check expiry/one-use at join, implement `requireApproval`.
6. **Loan lifecycle** end-to-end + sync payload types for loans and meetings.
7. **Notifications** call sites; **screens** from §27 in priority order (loan approve, transaction detail, group settings, sync status).
8. Remove dead code/deps (9 tables, 6 models, 5 packages, duplicate enums) and update DESIGN_PLAN.md §12/§16/§21/§29/§32 to match reality.


---

## Resolution (v1.1)

| # | Gap | Status | Where |
|---|---|---|---|
| 1 | Local DB unencrypted | ✅ SQLCipher (`sqflite_sqlcipher`), key = HKDF(device secret in secure store); plaintext DB auto-migrated | `core/storage/database.dart`, `core/security/device_secret.dart` |
| 2 | No role enforcement | ✅ Service-layer checks on every mutation; inbound payloads require author = active owner/admin; snapshots signed & verified | `services/*`, `core/ipfs/sync_manager.dart` |
| 3 | Restore impossible on new device | ✅ File export (share sheet) + file import; group keys in payload; PIN ≥ 6 | `services/backup_service.dart`, `screens/settings/identity_backup_screen.dart`, `screens/onboarding/restore_backup_screen.dart` |
| 4 | Snapshot last-received-wins | ✅ `sequenceNumber` bumped on every metadata change; ordering seq → publishedAt → publisher id; roster replace | `GroupService.importSnapshot`, `GroupDao.bumpSequence` |
| 5 | Concurrent-offline sequence collision | ✅ Per-author sequences, `UNIQUE(group_id, author_peer_id, sequence_number)` | schema v4, `TransactionDao` |
| 6 | Invites reusable forever | ✅ Nonce + expiry + inviter signature + one-use; `requireApproval` → pending members | `services/invite_service.dart`, `SyncManager.joinGroup/_applyMemberJoin` |
| 7 | Debug keystore fallback | ⚠️ Unchanged by design (needs `android/key.properties`); warning stays loud | `android/app/build.gradle.kts` |
| 8 | Loan lifecycle after disburse | ✅ Loan tx, weekly schedule, repayment allocation, repaying/completed, penalties, default after 30 d, eligibility rules, auto-approval | `services/loan_service.dart` |
| 9 | Loans/meetings never sync | ✅ Payload types `loan`, `meeting`, `reversal` with signature verification | `sync_manager.dart`, `sync_envelope.dart` |
| 10 | Notifications never fire | ✅ Meeting/contribution/repayment/overdue scheduling, activity notifications, stable ids, preferences screen | `core/notifications/*`, `providers/notification_provider.dart` |
| 11 | 14 missing / 4 placeholder screens | ✅ 8 screens added, 3 placeholders replaced, Meetings tab added; `group_list_screen` (dead) removed | `screens/**` |
| 12 | Owner transfer / dissolution / removal / reversals | ✅ Services + UI (Group settings, Transaction detail) + sync | `services/governance_service.dart`, `GroupService` |
| 13 | Offline queue semantics | ✅ queued/syncing/synced/failed on the transaction row, 5 attempts, manual retry (Sync Status) | `TransactionDao`, `screens/settings/sync_status_screen.dart` |
| 14 | Battery policy | 🟡 Node stopped 15 min after backgrounding; foreground-only periodic sync. Wi-Fi gating and killed-app background not done | `SyncManager.pauseBackground` |
| 15 | Discovery | 🟡 DHT `findProviders` + dial per group CID; mDNS via dart_ipfs default service (no `_vbank._tcp`) | `SyncManager._discoverPeers` |
| — | Tier-3 bugs (copy link, notifications tile, deep-link snackbar, tz, duplicate enums, partial signature payload, UTF-16 KDF, 4-digit PIN, location perms, host filter) | ✅ All fixed | various |
| — | Dead deps/models/tables | ✅ riverpod_annotation/generator, build_runner, sqlcipher_flutter_libs removed (shadcn_flutter and cbor re-adopted in v1.2 and now actually used); `pending_transactions` table/model removed; all remaining tables now have DAOs/usages | `pubspec.yaml`, `lib/models`, schema v4 |

Tests: 57 (crypto, CBOR + legacy envelope, deep link, model JSON, and service-level permission / sequence / snapshot / invite / loan / dissolution tests on an in-memory DB).

## v1.2 addendum (2026-08-25)

| Item | Status |
|---|---|
| §5/§24–26 shadcn_flutter UI | ✅ Whole app ported to the Spark design system (`lib/ui/ui.dart` kit + 21 screens, Lucide icons); Material only via shadcn re-exports; theme-aware status bar; dark launch background; Material page-transition shim so dark-mode pushes don't flash light |
| Dialogs → bottom sheets | ✅ `showAppSheet` / `confirmSheet` / `promptSheet`; keyboard inset padding; back button closes sheet; verified on SM-A175F |
| §20 CBOR wire format | ✅ `WireCodec`; `SyncEnvelope` v2 + `BackupEnvelope` CBOR with legacy JSON decode |
| §12 group key derivation | ✅ Kept PBKDF2(salt = group id) by decision |
| §13 member write access | ✅ Kept read-only members by decision |
