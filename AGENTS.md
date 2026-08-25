# vBank — AI Agent Guide

This document provides comprehensive guidance for AI agents working on the vBank codebase. Read this file completely before making any changes.

---

## Project Overview

vBank is a distributed village banking application built with Flutter. It enables groups of people (typically in rural communities) to manage collective savings, loans, and contributions without relying on a central server. Data is stored locally on each member's device and synchronized peer-to-peer over the public IPFS network.

### Core Principles

1. **No central server** — all data lives on member devices
2. **Encrypted by default** — all data encrypted at rest (local) and in transit (IPFS)
3. **Offline-first** — the app must function without internet; sync is opportunistic
4. **Audit trail** — every transaction is signed and immutable
5. **Minimal, clean UI** — shadcn_flutter design system, no unnecessary complexity

---

## Tech Stack

| Layer | Technology | Purpose |
|-------|-----------|---------|
| Framework | Flutter (Dart) | Cross-platform mobile app |
| P2P / Discovery | dart_ipfs | IPFS node — DHT, Bitswap, PubSub, mDNS |
| Local Storage | SQLCipher (SQLite) | Encrypted local database |
| State Management | Riverpod | Reactive state management |
| Crypto | XChaCha20-Poly1305 | Symmetric encryption |
| Crypto | Ed25519 | Digital signatures |
| Crypto | HKDF-SHA256 | Key derivation |
| UI | shadcn_flutter | Design system (New York style) |
| Notifications | flutter_local_notifications | Local scheduled notifications |
| Timezone | timezone | Correct notification scheduling |
| Encoding | cbor | Compact binary encoding for invite payloads |
| Target Platforms | Android 10+, iOS 15+ | Mobile-only |

---

## Architecture

### How Peer-to-Peer Works

The app uses the public IPFS network for peer discovery and data exchange. Each member's device runs a lightweight IPFS node (via dart_ipfs) that connects to standard IPFS bootstrap nodes.

```
┌─────────────────────────────────────────────────────┐
│                   PUBLIC IPFS NETWORK                │
│  Bootstrap Nodes (run by Protocol Labs)              │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐          │
│  │ Node A   │  │ Node B   │  │ Node C   │  ...      │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘          │
│       └──────────────┼──────────────┘                │
│              Kademlia DHT (peer + content routing)    │
└──────────────────────┬──────────────────────────────┘
                       │
        ┌──────────────┼──────────────┐
   ┌────▼────┐   ┌────▼────┐   ┌────▼────┐
   │Member A │   │Member B │   │Member C │
   │Phone    │   │Phone    │   │Phone    │
   │dart_ipfs│   │dart_ipfs│   │dart_ipfs│
   └─────────┘   └─────────┘   └─────────┘
```

### Two Discovery Mechanisms

| When | Method | How |
|------|--------|-----|
| Same Wi-Fi (village meeting) | mDNS | Devices broadcast `_vbank._tcp` on LAN, find each other instantly |
| Different networks | DHT | Publish provider records for group CID, query DHT to find providers |

### Data Flow

1. Member creates a transaction locally
2. Transaction is signed with Ed25519 private key
3. Transaction is encrypted with group symmetric key (XChaCha20-Poly1305)
4. Encrypted data is added to IPFS, gets a CID
5. CID is pinned locally and published as provider record to DHT
6. CID is broadcast via PubSub to group topic
7. Other members receive PubSub message, fetch CID via Bitswap, decrypt, store locally

### Mobile Battery Strategy

The IPFS node does NOT run continuously. It follows a sync window pattern:

```
App State          IPFS Node State
─────────────────────────────────
Foreground         Full P2P (DHT, Bitswap, PubSub active)
Background (5min)  Reduce connections
Background (15min) Offline (local only)
Killed             Offline (local Hive data only)

Manual "Sync"      Full P2P for 60s → sync → stop
```

---

## Encryption Model

### Key Hierarchy

```
Group Passphrase (e.g. "village-savings-2026")
    │
    ├──► HKDF-SHA256 ──► Group Symmetric Key (32 bytes)
    │                       ├── Encrypts all data before IPFS
    │                       └── Shared by all group members
    │
    └──► HKDF-SHA256 ──► Local DB Key (32 bytes)
                            └── Encrypts local SQLite (per-device)

Each Member also has:
    ├── Ed25519 Keypair
    │   ├── Private key → stored in Android Keystore / iOS Keychain
    │   └── Public key → shared with group (for signature verification)
    │
    └── Device Secret (random, 32 bytes)
        └── Stored in secure storage, never leaves device
```

### Encrypt Before IPFS

```
plaintext (JSON) + Ed25519 signature
    │
    ▼
XChaCha20-Poly1305 encrypt with group key
    │
    ▼
ciphertext → added to IPFS → CID
```

### Decrypt From IPFS

```
CID → fetch ciphertext
    │
    ▼
XChaCha20-Poly1305 decrypt with group key
    │
    ▼
plaintext (JSON) + Ed25519 signature → verify signature
```

### Local Storage

SQLCipher encrypts the entire SQLite database file using ChaCha20-Poly1305. The encryption key is derived from the group symmetric key + a device-specific secret.

---

## Permission Model

```
┌─────────────────────────────────────────────────┐
│  GROUP ROLES                                     │
│                                                  │
│  owner ──── Created the group                    │
│            ├── Full admin rights                 │
│            ├── Can add/remove admins             │
│            ├── Can transfer ownership            │
│            ├── Can dissolve group                │
│            └── Cannot be removed                  │
│                                                  │
│  admin ──── Promoted by owner                    │
│            ├── Read + Write                      │
│            ├── Can create transactions           │
│            ├── Can approve loans (if enabled)    │
│            ├── Can manage meetings               │
│            └── Can be demoted by owner            │
│                                                  │
│  member ─── Joined via invite                    │
│            ├── Read-only                         │
│            ├── Can view transactions             │
│            ├── Can view balances                 │
│            ├── Can request loans                 │
│            ├── Can make repayments               │
│            └── Cannot create/edit transactions   │
└─────────────────────────────────────────────────┘
```

### Permission Functions

```dart
bool canWrite(MemberRole role) =>
    role == MemberRole.owner || role == MemberRole.admin;

bool canManageMembers(MemberRole role) =>
    role == MemberRole.owner || role == MemberRole.admin;

bool canPromote(MemberRole role) => role == MemberRole.owner;
bool canDemote(MemberRole role) => role == MemberRole.owner;
bool canRemove(MemberRole role) => role == MemberRole.owner;
bool canDissolve(MemberRole role) => role == MemberRole.owner;
```

### Enforcement

Every transaction and mutation is signed. The receiver verifies the signer's role before accepting. If a non-admin tries to create a transaction, other nodes reject it.

---

## Loan Lifecycle

```
1. MEMBER requests loan
   └── Creates LoanRequest with borrower signature
   └── Submits to group

2. ADMIN reviews (if requireLoanApproval = true)
   └── Approves → LoanRequest.status = approved
   └── Rejects → LoanRequest.status = rejected
   └── Can approve different amount than requested

3. DISBURSEMENT
   └── Admin marks as disbursed
   └── Transaction created: loan amount from group fund to borrower
   └── RepaymentSchedule generated (installments based on termWeeks)
   └── Borrower's outstandingLoan updated

4. REPAYMENT
   └── Member makes repayment transaction
   └── Matching installment updated
   └── outstandingLoan reduced
   └── When all installments paid → LoanRequest.status = completed

5. DEFAULT
   └── If installment overdue past grace period
   └── Penalty applied (latePenaltyRate * expectedAmount)
   └── LoanRequest.status = defaulted
```

---

## Invite System

### Two Share Methods

| Method | Format | When to use |
|--------|--------|-------------|
| QR Code | `vbank://join?<CBOR payload>` | In person |
| Share Link | `https://vbank.app/join/<IPFS-CID>` | WhatsApp, SMS, email |

### Invite Payload (CBOR-encoded)

```
├── groupId: string
├── groupCid: string (IPFS CID of group metadata)
├── groupTopic: string (PubSub topic name)
├── inviterPeerId: string
├── inviterName: string
├── groupKey: bytes (32-byte symmetric key, encrypted)
├── expiresAt: timestamp (default: 7 days)
└── nonce: bytes (prevents replay)
```

### One-Use Enforcement

Each invite has a unique nonce. On first use, the invite is consumed (marked in group metadata). Subsequent attempts are rejected.

### Optional Approval Mode

When `requireApproval = true` on a group, new member requests go to a pending state requiring admin approval. Default is `false` (instant join).

---

## Group Owner Transfer

```
1. Owner selects new owner from admins
2. Confirms transfer with PIN/biometric
3. Old owner signs OwnershipTransfer
4. New owner signs OwnershipTransfer
5. Old owner role → admin
6. New owner role → owner
7. Group metadata updated, signed by old owner
8. All members notified
```

---

## Group Dissolution

```
1. Owner initiates dissolution
2. System checks: all loans settled? pending reversals resolved?
3. All members notified: "Group is being dissolved"
4. Contribution collection stopped
5. Final fund distribution calculated
6. Distribution transactions created
7. Group status → dissolved
8. Group data remains in IPFS (read-only archive)
```

---

## Conflict Resolution

```
Every Group and Transaction has a sequenceNumber.
When syncing:
  1. Compare sequence numbers
  2. Higher sequence wins (last-write-wins)
  3. If equal, compare timestamps
  4. If still equal, compare peerId (lexicographic — deterministic)

For transactions:
  - Transactions are immutable once signed
  - No conflict — they're append-only
  - Only group metadata (members, config) can conflict
```

---

## Notification System

### Notification Triggers

| Trigger | When | Method |
|---------|------|--------|
| Meeting reminder | 24h before meeting | `zonedSchedule` |
| Contribution due | Day of meeting | `zonedSchedule` |
| Loan repayment due | 3 days before due date | `zonedSchedule` |
| Loan overdue | On overdue date | `zonedSchedule` |
| New transaction | Sync receives new tx | `show()` (immediate) |
| Member joined | New member joins group | `show()` (immediate) |
| Member removed | Member is removed | `show()` (immediate) |
| Loan approved | Admin approves loan | `show()` (immediate) |
| Loan rejected | Admin rejects loan | `show()` (immediate) |
| Periodic sync | Every 6 hours | `periodicallyShow` |

### Android Permissions Required

```xml
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" />
<uses-permission android:name="android.permission.USE_EXACT_ALARM" />
<uses-permission android:name="android.permission.WAKE_LOCK" />
```

### Key Scheduling Pattern

```dart
// Daily notification at specific time — fires even in Doze mode
await flutterLocalNotificationsPlugin.zonedSchedule(
  id,
  title: title,
  body: body,
  scheduledDate: tz.TZDateTime.now(tz.local).add(Duration(...)),
  notificationDetails,
  androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
  matchDateTimeComponents: DateTimeComponents.time, // repeats daily
);
```

---

## Offline Transaction Queue

```
1. Transaction created → added to pending_transactions table
2. Status: queued
3. When IPFS node starts sync:
   ├── Status → syncing
   ├── Add to IPFS, publish to DHT
   ├── Broadcast via PubSub
   ├── On success → status = synced, synced = 1
   └── On failure → status = failed, retryCount++
4. Max retries: 5, then manual retry prompt
```

---

## Key Recovery & Device Migration

### Backup

1. User creates identity backup
2. Private key encrypted with user's PIN (XChaCha20-Poly1305)
3. Encrypted payload exported as QR code, shareable link, or file
4. Backup stored in `app_backups` table

### Restore

1. On new device → "Restore from backup"
2. Scan QR or import file
3. Enter PIN to decrypt
4. Keypair restored
5. Group memberships verified via DHT
6. Old device remains functional (no automatic revocation)
7. User can manually revoke old device from group settings

---

## Data Models

### UserIdentity

```dart
class UserIdentity {
  String peerId;           // Ed25519 public key (IPFS peerId)
  String displayName;
  Uint8List publicKey;
  DateTime createdAt;
  // Private key stored in Android Keystore / iOS Keychain
}
```

### Group

```dart
class Group {
  String id;
  String name;
  GroupConfig config;
  List<Member> members;
  List<String> inviteCids;
  bool requireApproval;    // Default: false
  DateTime createdAt;
  int sequenceNumber;      // Incremented on every mutation
  GroupStatus status;      // active | dissolved
  Uint8List ownerSignature;
}

enum GroupStatus { active, dissolved }
```

### GroupConfig

```dart
class GroupConfig {
  String groupId;
  double contributionAmount;
  ContributionFrequency frequency;   // weekly | biweekly | monthly
  int meetingDayOfWeek;               // 0=Sunday
  TimeOfDay meetingTime;
  double maxLoanMultiplier;           // e.g. 3x total contributions
  double loanInterestRate;            // e.g. 0.10 = 10%
  double latePenaltyRate;             // e.g. 0.05 = 5% per week overdue
  int minContributionsForLoan;
  String currency;                    // Default: "ZMW" (Zambian Kwacha)
  double? savingsTarget;
  bool requireLoanApproval;           // Default: true
}

enum ContributionFrequency { weekly, biweekly, monthly }
```

### Member

```dart
class Member {
  String peerId;
  String name;
  MemberRole role;           // owner | admin | member
  DateTime joinedAt;
  Uint8List publicKey;
  MemberStatus status;       // active | suspended | removed
  bool hasOutstandingLoan;
}

enum MemberRole { owner, admin, member }
enum MemberStatus { active, suspended, removed }
```

### Transaction

```dart
class Transaction {
  String id;                 // UUID v7
  String groupId;
  String fromPeerId;
  String toPeerId;           // or "group" for contributions
  TransactionType type;
  double amount;
  String currency;           // Default: "ZMW"
  String? note;
  DateTime timestamp;
  int sequenceNumber;
  Uint8List senderSignature;
  TransactionStatus status;  // confirmed | reversed
}

enum TransactionType {
  contribution,    // Member pays into group
  loan,            // Member borrows from group
  repayment,       // Member pays back loan
  withdrawal,      // Member takes out their contribution
  fee,             // Group fee
  penalty,         // Late payment penalty
  reversal,        // Reversal of a previous transaction
}

enum TransactionStatus { confirmed, reversed }
```

### TransactionReversal

```dart
class TransactionReversal {
  String id;
  String originalTransactionId;
  String groupId;
  String requestedByPeerId;
  String? approvedByPeerId;
  String reason;
  ReversalStatus status;       // pending | approved | rejected
  DateTime requestedAt;
  DateTime? resolvedAt;
  Uint8List requesterSignature;
  Uint8List? approverSignature;
}

enum ReversalStatus { pending, approved, rejected }
```

### LoanRequest

```dart
class LoanRequest {
  String id;
  String groupId;
  String borrowerPeerId;
  double requestedAmount;
  double approvedAmount;
  double interestRate;
  int termWeeks;
  String? reason;
  LoanStatus status;
  DateTime requestedAt;
  DateTime? approvedAt;
  String? approvedByPeerId;
  DateTime? disbursedAt;
  DateTime? completedAt;
  DateTime? defaultedAt;
  Uint8List borrowerSignature;
  Uint8List? approverSignature;
}

enum LoanStatus {
  pending,       // Requested, awaiting approval
  approved,      // Admin approved
  rejected,      // Admin rejected
  disbursed,     // Funds disbursed to borrower
  repaying,      // Repayments in progress
  completed,     // All repayments made
  defaulted,     // Overdue past grace period
}
```

### RepaymentSchedule

```dart
class RepaymentSchedule {
  String id;
  String loanId;
  int installmentNumber;
  double expectedAmount;
  DateTime dueDate;
  double paidAmount;
  DateTime? paidAt;
  bool isOverdue;
  double penalty;
  RepaymentStatus status;    // pending | paid | overdue | waived
}

enum RepaymentStatus { pending, paid, overdue, waived }
```

### Balance

```dart
class Balance {
  String peerId;
  String groupId;
  double totalContributed;
  double totalLoaned;
  double totalRepaid;
  double totalWithdrawn;
  double totalPenalties;
  double outstandingLoan;
  double netBalance;
  DateTime lastUpdated;
}
```

### Meeting

```dart
class Meeting {
  String id;
  String groupId;
  DateTime scheduledAt;
  MeetingStatus status;      // scheduled | in_progress | completed | cancelled
  List<Attendance> attendance;
  String? notes;
  double totalCollected;
  DateTime? completedAt;
}

class Attendance {
  String peerId;
  MeetingAttendanceStatus status;  // present | absent | excused
  bool contributed;
  DateTime? contributionTime;
}

enum MeetingStatus { scheduled, in_progress, completed, cancelled }
enum MeetingAttendanceStatus { present, absent, excused }
```

### Invite

```dart
class Invite {
  String id;
  String groupId;
  String groupCid;
  String groupTopic;
  String inviterPeerId;
  String inviterName;
  Uint8List groupKey;        // Encrypted with inviter's key for recipient
  DateTime createdAt;
  DateTime expiresAt;        // Default: 7 days
  bool used;                 // One-use only
  Uint8List nonce;           // Prevents replay
  Uint8List inviterSignature;
}
```

### MemberRemoval

```dart
class MemberRemoval {
  String id;
  String groupId;
  String removedPeerId;
  String removedByPeerId;
  String reason;
  bool hasOutstandingLoan;
  double outstandingAmount;
  RemovalAction action;      // suspend | remove | settle_and_remove
  DateTime removedAt;
  Uint8List adminSignature;
}

enum RemovalAction { suspend, remove, settle_and_remove }
```

### PendingTransaction (Offline Queue)

```dart
class PendingTransaction {
  String id;
  Transaction transaction;
  PendingStatus status;      // queued | syncing | synced | failed
  int retryCount;
  DateTime createdAt;
  DateTime? lastAttemptAt;
  String? errorMessage;
}

enum PendingStatus { queued, syncing, synced, failed }
```

### OwnershipTransfer

```dart
class OwnershipTransfer {
  String id;
  String groupId;
  String fromPeerId;
  String toPeerId;
  DateTime transferredAt;
  Uint8List oldOwnerSignature;
  Uint8List newOwnerSignature;
}
```

### GroupDissolution

```dart
class GroupDissolution {
  String id;
  String groupId;
  String initiatedByPeerId;
  DateTime initiatedAt;
  DissolutionStatus status;
  bool allLoansSettled;
  bool fundsDistributed;
  DateTime? completedAt;
}

enum DissolutionStatus {
  initiating, settling_loans, distributing_funds, completed
}
```

### Currency

```dart
class CurrencyConfig {
  static const Map<String, CurrencyInfo> supported = {
    'ZMW': CurrencyInfo(
      symbol: 'ZK',
      name: 'Zambian Kwacha',
      decimals: 2,
      default_: true,
    ),
    'KES': CurrencyInfo(symbol: 'KSh', name: 'Kenyan Shilling', decimals: 0),
    'UGX': CurrencyInfo(symbol: 'UGX', name: 'Ugandan Shilling', decimals: 0),
    'TZS': CurrencyInfo(symbol: 'TSh', name: 'Tanzanian Shilling', decimals: 0),
    'USD': CurrencyInfo(symbol: r'$', name: 'US Dollar', decimals: 2),
    'NGN': CurrencyInfo(symbol: '₦', name: 'Nigerian Naira', decimals: 0),
    'ZAR': CurrencyInfo(symbol: 'R', name: 'South African Rand', decimals: 2),
    'GHS': CurrencyInfo(symbol: 'GH₵', name: 'Ghanaian Cedi', decimals: 2),
  };

  static CurrencyInfo get defaultCurrency => supported['ZMW']!;
}

class CurrencyInfo {
  final String symbol;
  final String name;
  final int decimals;
  final bool default_;

  const CurrencyInfo({
    required this.symbol,
    required this.name,
    required this.decimals,
    this.default_ = false,
  });
}
```

### AppBackup

```dart
class AppBackup {
  String id;
  Uint8List encryptedPayload;  // All local data, encrypted with user's passphrase
  List<String> groupIds;
  DateTime createdAt;
  int version;
  BackupType type;              // full | selective
}

enum BackupType { full, selective }
```

### IdentityBackup

```dart
class IdentityBackup {
  Uint8List encryptedPrivateKey;  // Encrypted with user's PIN (XChaCha20-Poly1305)
  String peerId;
  DateTime backedUpAt;
  String backupVersion;
}
```

### GroupReport

```dart
class GroupReport {
  String groupId;
  DateTimePeriod period;
  double totalContributions;
  double totalLoansDisbursed;
  double totalLoansRepaid;
  double totalPenalties;
  double groupFundBalance;
  int totalMeetings;
  int totalTransactions;
  List<MemberStatement> memberStatements;
}
```

### MemberStatement

```dart
class MemberStatement {
  String peerId;
  String memberName;
  double totalContributed;
  double totalLoaned;
  double totalRepaid;
  double outstandingBalance;
  List<Transaction> transactions;
}
```

---

## UI Design System

### Package

`shadcn_flutter` (New York style, standalone ecosystem — no Material required).

### Color Palette

| Token | Light | Dark | Usage |
|-------|-------|------|-------|
| primary | #10B981 (emerald) | #34D399 | CTAs, active states, balance positive |
| destructive | #EF4444 (red) | #EF4444 | Delete, negative balance, errors |
| warning | #F59E0B (amber) | #FBBF24 | Pending transactions |
| muted | #F4F4F5 | #27272A | Backgrounds, secondary surfaces |
| border | #E4E4E7 | #27272A | Dividers, card borders |
| foreground | #09090B | #FAFAFA | Primary text |
| mutedForeground | #71717A | #A1A1AA | Secondary text, labels |

### Typography Scale

| Style | Size | Weight | Usage |
|-------|------|--------|-------|
| h1 | 30px | Bold | Screen titles |
| h2 | 24px | Semibold | Section headers |
| h3 | 20px | Semibold | Card titles |
| body | 16px | Regular | Body text |
| small | 14px | Regular | Secondary text |
| muted | 12px | Regular | Labels, timestamps |

### Component Mapping

| shadcn Component | vBank Usage |
|------------------|-------------|
| Card | Group cards, transaction items, balance summary |
| Button | Primary CTAs, icon buttons |
| Input | Amount input, name input, search |
| Badge | Transaction type, member role, sync status |
| Avatar | Member avatars (initials fallback) |
| Dialog | Confirm actions, approval prompts |
| BottomSheet | Create transaction, invite options |
| Separator | Dividers between items |
| Tabs | Group detail (transactions / members / settings) |
| Toast | Success/error notifications |
| Tooltip | Icon hints |
| CircularProgress | Loading states |
| Skeleton | Loading placeholders |

---

## Project Structure

```
vBank/
├── lib/
│   ├── main.dart
│   ├── app.dart
│   │
│   ├── core/
│   │   ├── ipfs/
│   │   │   ├── ipfs_service.dart          # Node lifecycle
│   │   │   ├── ipfs_config.dart           # Mobile-optimized config
│   │   │   └── sync_manager.dart          # Online/offline sync windows
│   │   ├── crypto/
│   │   │   ├── identity.dart              # Ed25519 keypair (Keystore/Keychain)
│   │   │   ├── signing.dart               # Transaction signing/verification
│   │   │   ├── encryption.dart            # XChaCha20-Poly1305
│   │   │   └── key_derivation.dart        # HKDF-SHA256
│   │   ├── deeplink/
│   │   │   ├── deeplink_handler.dart      # Handle vbank://join?...
│   │   │   └── link_generator.dart        # Generate vbank.app/join/<CID>
│   │   ├── notifications/
│   │   │   ├── notification_service.dart
│   │   │   └── notification_scheduler.dart
│   │   └── storage/
│   │       ├── database.dart              # SQLCipher setup
│   │       ├── group_dao.dart
│   │       ├── member_dao.dart
│   │       ├── transaction_dao.dart
│   │       ├── balance_dao.dart
│   │       ├── loan_dao.dart
│   │       ├── meeting_dao.dart
│   │       ├── invite_dao.dart
│   │       └── backup_dao.dart
│   │
│   ├── models/
│   │   ├── user_identity.dart
│   │   ├── group.dart
│   │   ├── group_config.dart
│   │   ├── member.dart
│   │   ├── transaction.dart
│   │   ├── transaction_reversal.dart
│   │   ├── loan.dart
│   │   ├── repayment_schedule.dart
│   │   ├── balance.dart
│   │   ├── meeting.dart
│   │   ├── attendance.dart
│   │   ├── invite.dart
│   │   ├── member_removal.dart
│   │   ├── ownership_transfer.dart
│   │   ├── group_dissolution.dart
│   │   ├── pending_transaction.dart
│   │   ├── app_backup.dart
│   │   └── currency.dart
│   │
│   ├── services/
│   │   ├── group_service.dart
│   │   ├── transaction_service.dart
│   │   ├── loan_service.dart
│   │   ├── balance_service.dart
│   │   ├── invite_service.dart
│   │   ├── meeting_service.dart
│   │   ├── discovery_service.dart         # mDNS + DHT
│   │   ├── pubsub_service.dart
│   │   ├── report_service.dart
│   │   └── backup_service.dart
│   │
│   ├── providers/                         # Riverpod providers
│   │   ├── ipfs_provider.dart
│   │   ├── auth_provider.dart
│   │   ├── group_provider.dart
│   │   ├── transaction_provider.dart
│   │   ├── loan_provider.dart
│   │   ├── balance_provider.dart
│   │   ├── meeting_provider.dart
│   │   └── notification_provider.dart
│   │
│   ├── screens/
│   │   ├── onboarding/
│   │   │   ├── welcome_screen.dart
│   │   │   ├── create_account_screen.dart
│   │   │   └── restore_backup_screen.dart
│   │   ├── home/
│   │   │   └── home_screen.dart
│   │   ├── group/
│   │   │   ├── group_list_screen.dart
│   │   │   ├── group_detail_screen.dart
│   │   │   ├── create_group_screen.dart
│   │   │   ├── group_settings_screen.dart
│   │   │   ├── group_reports_screen.dart
│   │   │   ├── group_dissolution_screen.dart
│   │   │   └── ownership_transfer_screen.dart
│   │   ├── member/
│   │   │   ├── member_list_screen.dart
│   │   │   ├── member_detail_screen.dart
│   │   │   └── member_removal_screen.dart
│   │   ├── transaction/
│   │   │   ├── transaction_list_screen.dart
│   │   │   ├── transaction_detail_screen.dart
│   │   │   ├── create_transaction_screen.dart
│   │   │   ├── reversal_request_screen.dart
│   │   │   └── pending_transactions_screen.dart
│   │   ├── loan/
│   │   │   ├── loan_list_screen.dart
│   │   │   ├── loan_detail_screen.dart
│   │   │   ├── request_loan_screen.dart
│   │   │   ├── approve_loan_screen.dart
│   │   │   └── repayment_screen.dart
│   │   ├── meeting/
│   │   │   ├── meeting_list_screen.dart
│   │   │   ├── meeting_detail_screen.dart
│   │   │   └── attendance_screen.dart
│   │   ├── invite/
│   │   │   ├── invite_screen.dart
│   │   │   └── join_group_screen.dart
│   │   ├── reports/
│   │   │   ├── group_summary_screen.dart
│   │   │   └── member_statement_screen.dart
│   │   ├── settings/
│   │   │   ├── settings_screen.dart
│   │   │   ├── identity_backup_screen.dart
│   │   │   └── notification_settings_screen.dart
│   │   └── sync/
│   │       └── sync_status_screen.dart
│   │
│   └── widgets/
│       ├── qr_scanner.dart
│       ├── qr_display.dart
│       ├── share_button.dart
│       ├── balance_card.dart
│       ├── transaction_tile.dart
│       ├── transaction_detail_sheet.dart
│       ├── member_list_tile.dart
│       ├── loan_card.dart
│       ├── meeting_card.dart
│       ├── sync_status_indicator.dart
│       ├── currency_text.dart
│       ├── role_badge.dart
│       └── empty_state.dart
│
├── pubspec.yaml
├── android/
│   └── app/src/main/AndroidManifest.xml
├── ios/
│   └── Runner/Info.plist
└── test/
```

---

## Dependencies

```yaml
dependencies:
  flutter:
    sdk: flutter

  # UI
  shadcn_flutter: ^0.0.51

  # IPFS / P2P
  dart_ipfs: ^1.11.7

  # Local storage (encrypted)
  sqflite: ^2.3.0
  sqlcipher_flutter_libs: ^0.6.0

  # State management
  flutter_riverpod: ^2.5.0
  riverpod_annotation: ^2.3.0

  # Crypto
  cryptography: ^2.7.0

  # Notifications
  flutter_local_notifications: ^18.0.0
  timezone: ^0.9.4

  # QR & Sharing
  flutter_qrcode: ^4.0.0
  mobile_scanner: ^5.0.0
  share_plus: ^10.0.0
  url_launcher: ^6.2.0

  # Deep linking
  app_links: ^7.0.0

  # Encoding
  cbor: ^5.0.0

  # Utils
  uuid: ^4.0.0
  intl: ^0.19.0
  path_provider: ^2.1.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  build_runner: ^2.4.0
  riverpod_generator: ^2.4.0
```

---

## Local Storage Schema (SQLCipher)

All tables are encrypted via SQLCipher ChaCha20-Poly1305.

```sql
CREATE TABLE user_identity (
    peer_id TEXT PRIMARY KEY,
    display_name TEXT NOT NULL,
    public_key BLOB NOT NULL,
    created_at INTEGER NOT NULL
);

CREATE TABLE groups (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    data BLOB NOT NULL,
    config_data BLOB NOT NULL,
    cid TEXT,
    require_approval INTEGER DEFAULT 0,
    status TEXT DEFAULT 'active',
    created_at INTEGER NOT NULL,
    sequence_number INTEGER DEFAULT 0
);

CREATE TABLE members (
    peer_id TEXT NOT NULL,
    group_id TEXT NOT NULL REFERENCES groups(id),
    name TEXT NOT NULL,
    role TEXT DEFAULT 'member',
    status TEXT DEFAULT 'active',
    public_key BLOB NOT NULL,
    joined_at INTEGER NOT NULL,
    has_outstanding_loan INTEGER DEFAULT 0,
    PRIMARY KEY (peer_id, group_id)
);

CREATE TABLE transactions (
    id TEXT PRIMARY KEY,
    group_id TEXT NOT NULL REFERENCES groups(id),
    from_peer_id TEXT NOT NULL,
    to_peer_id TEXT NOT NULL,
    type TEXT NOT NULL,
    amount REAL NOT NULL,
    currency TEXT DEFAULT 'ZMW',
    note TEXT,
    timestamp INTEGER NOT NULL,
    sequence_number INTEGER NOT NULL,
    sender_signature BLOB NOT NULL,
    status TEXT DEFAULT 'confirmed',
    cid TEXT,
    synced INTEGER DEFAULT 0
);

CREATE TABLE transaction_reversals (
    id TEXT PRIMARY KEY,
    original_transaction_id TEXT NOT NULL REFERENCES transactions(id),
    group_id TEXT NOT NULL,
    requested_by_peer_id TEXT NOT NULL,
    approved_by_peer_id TEXT,
    reason TEXT NOT NULL,
    status TEXT DEFAULT 'pending',
    requested_at INTEGER NOT NULL,
    resolved_at INTEGER,
    requester_signature BLOB NOT NULL,
    approver_signature BLOB
);

CREATE TABLE loans (
    id TEXT PRIMARY KEY,
    group_id TEXT NOT NULL REFERENCES groups(id),
    borrower_peer_id TEXT NOT NULL,
    requested_amount REAL NOT NULL,
    approved_amount REAL,
    interest_rate REAL NOT NULL,
    term_weeks INTEGER NOT NULL,
    reason TEXT,
    status TEXT DEFAULT 'pending',
    requested_at INTEGER NOT NULL,
    approved_at INTEGER,
    approved_by_peer_id TEXT,
    disbursed_at INTEGER,
    completed_at INTEGER,
    defaulted_at INTEGER,
    borrower_signature BLOB NOT NULL,
    approver_signature BLOB
);

CREATE TABLE repayment_schedules (
    id TEXT PRIMARY KEY,
    loan_id TEXT NOT NULL REFERENCES loans(id),
    installment_number INTEGER NOT NULL,
    expected_amount REAL NOT NULL,
    due_date INTEGER NOT NULL,
    paid_amount REAL DEFAULT 0,
    paid_at INTEGER,
    is_overdue INTEGER DEFAULT 0,
    penalty REAL DEFAULT 0,
    status TEXT DEFAULT 'pending'
);

CREATE TABLE balances (
    peer_id TEXT NOT NULL,
    group_id TEXT NOT NULL REFERENCES groups(id),
    total_contributed REAL DEFAULT 0,
    total_loaned REAL DEFAULT 0,
    total_repaid REAL DEFAULT 0,
    total_withdrawn REAL DEFAULT 0,
    total_penalties REAL DEFAULT 0,
    outstanding_loan REAL DEFAULT 0,
    net_balance REAL DEFAULT 0,
    last_updated INTEGER NOT NULL,
    PRIMARY KEY (peer_id, group_id)
);

CREATE TABLE meetings (
    id TEXT PRIMARY KEY,
    group_id TEXT NOT NULL REFERENCES groups(id),
    scheduled_at INTEGER NOT NULL,
    status TEXT DEFAULT 'scheduled',
    notes TEXT,
    total_collected REAL DEFAULT 0,
    completed_at INTEGER
);

CREATE TABLE attendance (
    meeting_id TEXT NOT NULL REFERENCES meetings(id),
    peer_id TEXT NOT NULL,
    status TEXT DEFAULT 'absent',
    contributed INTEGER DEFAULT 0,
    contribution_time INTEGER,
    PRIMARY KEY (meeting_id, peer_id)
);

CREATE TABLE invites (
    id TEXT PRIMARY KEY,
    group_id TEXT NOT NULL REFERENCES groups(id),
    cid TEXT,
    used INTEGER DEFAULT 0,
    created_at INTEGER NOT NULL,
    expires_at INTEGER NOT NULL
);

CREATE TABLE member_removals (
    id TEXT PRIMARY KEY,
    group_id TEXT NOT NULL,
    removed_peer_id TEXT NOT NULL,
    removed_by_peer_id TEXT NOT NULL,
    reason TEXT NOT NULL,
    has_outstanding_loan INTEGER DEFAULT 0,
    outstanding_amount REAL DEFAULT 0,
    action TEXT NOT NULL,
    removed_at INTEGER NOT NULL,
    admin_signature BLOB NOT NULL
);

CREATE TABLE pending_transactions (
    id TEXT PRIMARY KEY,
    transaction_data BLOB NOT NULL,
    status TEXT DEFAULT 'queued',
    retry_count INTEGER DEFAULT 0,
    created_at INTEGER NOT NULL,
    last_attempt_at INTEGER,
    error_message TEXT
);

CREATE TABLE ownership_transfers (
    id TEXT PRIMARY KEY,
    group_id TEXT NOT NULL,
    from_peer_id TEXT NOT NULL,
    to_peer_id TEXT NOT NULL,
    transferred_at INTEGER NOT NULL,
    old_owner_signature BLOB NOT NULL,
    new_owner_signature BLOB NOT NULL
);

CREATE TABLE group_dissolutions (
    id TEXT PRIMARY KEY,
    group_id TEXT NOT NULL,
    initiated_by_peer_id TEXT NOT NULL,
    initiated_at INTEGER NOT NULL,
    status TEXT DEFAULT 'initiating',
    all_loans_settled INTEGER DEFAULT 0,
    funds_distributed INTEGER DEFAULT 0,
    completed_at INTEGER
);

CREATE TABLE app_backups (
    id TEXT PRIMARY KEY,
    encrypted_payload BLOB NOT NULL,
    created_at INTEGER NOT NULL,
    version INTEGER DEFAULT 1,
    backup_type TEXT NOT NULL
);

CREATE TABLE node_config (
    key TEXT PRIMARY KEY,
    value BLOB NOT NULL
);

CREATE TABLE notification_schedules (
    id TEXT PRIMARY KEY,
    group_id TEXT,
    notification_type TEXT NOT NULL,
    scheduled_at INTEGER NOT NULL,
    payload TEXT,
    is_active INTEGER DEFAULT 1
);
```
