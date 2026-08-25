# vBank — Complete Design Plan & Architecture Document

> **Version:** 1.0
> **Date:** August 2026
> **Status:** v1.1 — implemented per this document; deviations are marked **[v1.1]** inline and summarised in §36.

---

## Table of Contents

1. [Project Vision](#1-project-vision)
2. [Problem Statement](#2-problem-statement)
3. [Core Principles & Constraints](#3-core-principles--constraints)
4. [Target Users & Use Cases](#4-target-users--use-cases)
5. [Tech Stack Decisions](#5-tech-stack-decisions)
6. [Architecture Overview](#6-architecture-overview)
7. [Peer-to-Peer Networking Model](#7-peer-to-peer-networking-model)
8. [Discovery Mechanisms](#8-discovery-mechanisms)
9. [Data Flow](#9-data-flow)
10. [Mobile Battery Strategy](#10-mobile-battery-strategy)
11. [Encryption Model](#11-encryption-model)
12. [Key Hierarchy](#12-key-hierarchy)
13. [Permission & Role Model](#13-permission--role-model)
14. [Group Lifecycle](#14-group-lifecycle)
15. [Loan Lifecycle](#15-loan-lifecycle)
16. [Invite System](#16-invite-system)
17. [Group Owner Transfer](#17-group-owner-transfer)
18. [Group Dissolution](#18-group-dissolution)
19. [Conflict Resolution](#19-conflict-resolution)
20. [Notification System](#20-notification-system)
21. [Offline Transaction Queue](#21-offline-transaction-queue)
22. [Key Recovery & Device Migration](#22-key-recovery--device-migration)
23. [Deep Linking](#23-deep-linking)
24. [UI Design System](#24-ui-design-system)
25. [Color Palette & Typography](#25-color-palette--typography)
26. [Component Mapping](#26-component-mapping)
27. [Screen Inventory](#27-screen-inventory)
28. [Data Models](#28-data-models)
29. [Local Storage Schema](#29-local-storage-schema)
30. [Project Structure](#30-project-structure)
31. [Dependencies](#31-dependencies)
32. [Implementation Phases](#32-implementation-phases)
33. [Build Configuration](#33-build-configuration)
34. [Testing Strategy](#34-testing-strategy)
35. [Future Considerations](#35-future-considerations)

---

## 1. Project Vision

vBank is a **distributed village banking application** built with Flutter. It enables groups of people — typically in rural communities in Southern and East Africa — to manage collective savings, loans, and contributions **without relying on a central server**. All data lives on member devices and synchronizes peer-to-peer over the public IPFS network.

The application is designed to work where traditional banking infrastructure is absent or unreliable. It models the real-world rotating savings and credit association (ROSCA) / village banking model that communities already practice, but adds digital record-keeping, audit trails, and automated loan tracking.

### Key Differentiators

- **No central server** — there is no company, cloud service, or database that holds user data. The app is a tool, not a service.
- **No internet dependency** — the app works fully offline. Sync is opportunistic and non-blocking.
- **Encrypted by default** — every piece of data is encrypted both at rest (on device) and in transit (over IPFS).
- **Immutable audit trail** — every transaction is cryptographically signed and cannot be altered after creation.
- **Community-owned** — the group (not a platform) controls membership, rules, and funds.

---

## 2. Problem Statement

In many rural communities across Zambia, Kenya, Uganda, Tanzania, Nigeria, South Africa, and Ghana, people participate in village banking groups (called different names in different regions). These groups:

- Collect regular contributions from members
- Lend money from the collective fund to members who need it
- Charge interest on loans to grow the fund
- Hold regular meetings to collect contributions and discuss group business

Currently, these groups rely on:
- Physical notebooks for record-keeping (easily lost, damaged, or tampered with)
- Cash handling with no digital trail
- Memory and trust for loan tracking
- A designated treasurer who holds all records (single point of failure/corruption)

vBank solves these problems by putting a cryptographic, immutable, peer-synchronized ledger on every member's phone.

---

## 3. Core Principles & Constraints

### Non-Negotiable Principles

1. **No central server** — all data lives on member devices. No cloud, no database, no company server.
2. **Encrypted by default** — all data encrypted at rest (local SQLCipher) and in transit (XChaCha20-Poly1305 before IPFS).
3. **Offline-first** — the app must function 100% without internet. Sync is opportunistic.
4. **Audit trail** — every transaction is signed with Ed25519 and immutable once created.
5. **Minimal, clean UI** — shadcn_flutter design system (New York style), no unnecessary complexity. The app must be usable by people with limited smartphone experience.

### Technical Constraints

- **Target platforms:** Android 10+ and iOS 15+ (mobile only)
- **Default currency:** Zambian Kwacha (ZMW), with support for 8 African currencies
- **P2P network:** Public IPFS network (no private/relay servers)
- **Local storage:** SQLCipher (encrypted SQLite)
- **No server-side logic** — all business logic runs on device

---

## 4. Target Users & Use Cases

### Primary Users

- **Village banking group members** in rural Southern/East Africa
- **Group owners/admins** who manage groups of 5-50 members
- **Members** who contribute, borrow, and repay

### Primary Use Cases

1. **Create a group** — Owner sets up a new savings group with contribution amount, frequency, and rules
2. **Join a group** — New member scans a QR code or clicks a share link to join
3. **Record a contribution** — Admin records a member's cash contribution at a meeting
4. **Request a loan** — Member borrows from the group fund
5. **Approve a loan** — Admin reviews and approves/rejects a loan request
6. **Make a repayment** — Member repays part or all of their loan
7. **View balances** — Any member can see their contribution history and outstanding balance
8. **Track meetings** — Schedule meetings, record attendance, collect contributions
9. **Sync data** — When online, sync transactions to other group members via IPFS
10. **Backup/restore** — Back up identity to a QR code, restore on a new device

---

## 5. Tech Stack Decisions

| Layer | Technology | Rationale |
|-------|-----------|-----------|
| Framework | **Flutter (Dart)** | Cross-platform mobile, single codebase, strong P2P library ecosystem |
| P2P / Discovery | **dart_ipfs** (^1.11.7) | Full IPFS node in Dart — DHT, Bitswap, PubSub, mDNS |
| Local Storage | **SQLCipher** via `sqflite_sqlcipher` | Encrypted SQLite; key derived from a per-install device secret in the platform secure store **[v1.1]** |
| State Management | **Riverpod** (^2.5.0) | Reactive, compile-safe, supports providers and families |
| Symmetric Crypto | **XChaCha20-Poly1305** (via `cryptography`) | Modern AEAD, 192-bit nonce prevents birthday attacks |
| Asymmetric Crypto | **Ed25519** (via `cryptography`) | Fast signatures, small keys, used by IPFS natively |
| Key Derivation | **HKDF-SHA256** (via `cryptography`) | Standard, secure, derives multiple keys from one passphrase |
| UI | **shadcn_flutter** (^0.0.51) | Clean, minimal design system (New York style) |
| Notifications | **flutter_local_notifications** (^18.0.0) | Scheduled notifications, Doze mode support |
| Timezone | **timezone** (^0.9.4) | Correct notification scheduling across timezones |
| QR Generation | **qr_flutter** (^4.1.0) | QR code rendering for invites |
| QR Scanning | **mobile_scanner** (^5.0.0) | Camera-based QR scanning |
| Sharing | **share_plus** (^10.0.0) | Native share sheet for invite links |
| Deep Linking | **app_links** (^7.0.0) | Handle `vbank://` URI scheme (replaced deprecated `uni_links`) |
| UUIDs | **uuid** (^4.0.0) | UUID v4 for all entity IDs |
| Date Formatting | **intl** (^0.19.0) | Locale-aware date/number formatting |

### Packages NOT Used (and Why)

- **Hive** — replaced by SQLCipher (we need relational queries, not key-value)
- **firebase_*** — no central server by design
- **dio/http** — no API calls; all data is local or IPFS
- **uni_links** — deprecated, replaced with `app_links`

---

## 6. Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                    PRESENTATION LAYER                     │
│  Screens (Flutter widgets) ← Riverpod Providers          │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐   │
│  │Onboarding│ │  Groups  │ │Loans/    │ │ Settings │   │
│  │          │ │          │ │Meetings  │ │          │   │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘   │
└───────────────────────┬─────────────────────────────────┘
                        │
┌───────────────────────▼─────────────────────────────────┐
│                    SERVICE LAYER                          │
│  GroupService, TransactionService, LoanService,          │
│  BalanceService, InviteService, MeetingService,          │
│  BackupService, ReportService                            │
└──────────┬──────────────────────────┬───────────────────┘
           │                          │
┌──────────▼──────────┐  ┌───────────▼───────────────────┐
│   STORAGE LAYER      │  │      P2P LAYER                │
│  SQLCipher (DAOs)    │  │  IPFS Service                  │
│  ┌────────────────┐  │  │  Sync Manager                  │
│  │ group_dao      │  │  │  Discovery Service (DHT)       │
│  │ member_dao     │  │  │  PubSub Service                │
│  │ transaction_dao│  │  │                                │
│  │ balance_dao    │  │  └───────────────────────────────┘
│  │ loan_dao       │  │
│  │ meeting_dao    │  │
│  │ invite_dao     │  │
│  │ backup_dao     │  │
│  └────────────────┘  │
└──────────────────────┘
           │
┌──────────▼──────────────────────────────────────────────┐
│                    CRYPTO LAYER                           │
│  Identity (Ed25519 keypair)                              │
│  Signing (Ed25519 sign/verify)                           │
│  Encryption (XChaCha20-Poly1305)                         │
│  Key Derivation (HKDF-SHA256)                            │
└─────────────────────────────────────────────────────────┘
```

---

## 7. Peer-to-Peer Networking Model

The app uses the **public IPFS network** for peer discovery and data exchange. Each member's device runs a lightweight IPFS node (via `dart_ipfs`) that connects to standard IPFS bootstrap nodes.

### Network Topology

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

### IPFS Node Configuration

Each device runs a full `IPFSNode` from `dart_ipfs` with the following configuration:

- **Bootstrap peers:** Protocol Labs default bootstrap nodes
- **PubSub:** Enabled for real-time group messaging
- **DHT:** Enabled for content and peer routing
- **Content routing:** Enabled for finding providers
- **Circuit relay:** Enabled for NAT traversal
- **Offline mode:** Disabled (we want P2P connectivity)

### IPFS Service API

The `IpfsService` wraps the `dart_ipfs` `IPFSNode` and exposes:

| Method | Purpose |
|--------|---------|
| `start()` | Start the IPFS node, connect to bootstrap peers |
| `stop()` | Gracefully stop the node |
| `addData(Uint8List)` | Add data to IPFS, return CID |
| `getData(String cid)` | Retrieve data by CID |
| `findProviders(String cid)` | Find peers hosting a CID |
| `pin(String cid)` | Pin content to prevent garbage collection |
| `subscribe(String topic)` | Subscribe to a PubSub topic |
| `publish(String topic, String message)` | Publish to a PubSub topic |

---

## 8. Discovery Mechanisms

### Two Discovery Methods

| When | Method | How |
|------|--------|-----|
| **Same Wi-Fi** (village meeting) | **mDNS** | Devices broadcast `_vbank._tcp` on LAN, find each other instantly |
| **Different networks** (remote sync) | **DHT** | Publish provider records for group CID, query DHT to find providers |

### mDNS Discovery

When devices are on the same local network (e.g., at a weekly village meeting), mDNS provides instant, zero-configuration peer discovery. The app broadcasts a `_vbank._tcp` service type.

### DHT Discovery

For cross-network sync, the app uses the Kademlia DHT built into IPFS:

1. When a group is created, its metadata is added to IPFS (getting a CID)
2. The CID is published as a provider record to the DHT
3. Other group members query the DHT for that CID to find providers
4. Once providers are found, Bitswap is used to exchange data

---

## 9. Data Flow

### Transaction Creation & Sync

```
1. Member creates a transaction locally
   │
2. Transaction is signed with Ed25519 private key
   │
3. Transaction is encrypted with group symmetric key (XChaCha20-Poly1305)
   │
4. Encrypted data is added to IPFS → gets a CID
   │
5. CID is pinned locally and published as provider record to DHT
   │
6. CID is broadcast via PubSub to group topic
   │
7. Other members receive PubSub message
   │
8. Fetch CID via Bitswap
   │
9. Decrypt with group symmetric key
   │
10. Verify Ed25519 signature
    │
11. Store locally in SQLCipher
```

### Data Immutability

- **Transactions** are immutable once signed. They are append-only. **[v1.1]** Sequence numbers are per *(group, author)*, so two admins working offline never collide; the DB enforces `UNIQUE(group_id, author_peer_id, sequence_number)`.
- **Group metadata** (members, config) can change but uses sequence numbers for conflict resolution.
- Every mutation is signed by the author. Other nodes verify the signer's role before accepting. **[v1.1]** Enforced in the service layer (`GroupService.requireWriter/requireOwner`, `TransactionService._requireWriter`, `LoanService._requireActiveAdmin`) and on inbound data in `SyncManager` (`_requireRemoteWriter`, signed snapshots).

---

## 10. Mobile Battery Strategy

The IPFS node does **NOT** run continuously. It follows a sync window pattern to preserve battery:

```
App State          IPFS Node State
─────────────────────────────────
Foreground         Full P2P (DHT, Bitswap, PubSub active)
Background (5min)  Reduce connections
Background (15min) Offline (local only)
Killed             Offline (local Hive data only)

Manual "Sync"      Full P2P for 60s → sync → stop
```

### Sync Manager

The `SyncManager` orchestrates sync windows:

- **Manual sync:** User taps "Sync Now" → IPFS starts → syncs pending transactions → stops after 60 seconds
- **Periodic sync:** Configurable interval (default 5 minutes when app is in foreground)
- **Sync states:** idle → syncing → idle (or error)

### Offline Transaction Queue

When offline (IPFS node stopped), transactions are queued locally:

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

## 11. Encryption Model

### Encryption Before IPFS

```
plaintext (JSON) + Ed25519 signature
    │
    ▼
XChaCha20-Poly1305 encrypt with group key
    │
    ▼
ciphertext → added to IPFS → CID
```

### Decryption From IPFS

```
CID → fetch ciphertext
    │
    ▼
XChaCha20-Poly1305 decrypt with group key
    │
    ▼
plaintext (JSON) + Ed25519 signature → verify signature
```

### Local Storage Encryption

SQLCipher encrypts the entire SQLite database file. **[v1.1]** The key is `HKDF-SHA256(device secret, info="vbank-local-db")` — the device secret is 32 random bytes kept in the Android Keystore-backed secure store / iOS Keychain (`flutter_secure_storage`). It is *not* derived from a group key: one device holds many groups, and the group keys themselves are rows inside the encrypted database. Existing plaintext databases are migrated in place with `sqlcipher_export` on first launch.

---

## 12. Key Hierarchy

```
Group Passphrase (e.g. "village-savings-2026")   [set by the owner at creation;
    │                                             shared with members out-of-band]
    └──► PBKDF2-HMAC-SHA256(salt = group id, 100k) ──► Group Symmetric Key (32 bytes)  [v1.1]
                            ├── Encrypts all data before IPFS (SyncEnvelope)
                            └── Same on every member's device

Device Secret (random 32 bytes, secure store, never leaves device)
    └──► HKDF-SHA256 ──► Local DB Key (32 bytes)                                       [v1.1]
                            └── SQLCipher key for local SQLite

Each Member also has:
    ├── Ed25519 Keypair
    │   ├── Private key (32-byte seed) → stored in the SQLCipher-encrypted DB  [v1.1]
    │   └── Public key → shared with group (for signature verification)
    │
    └── Device Secret (random, 32 bytes)
        └── Stored in secure storage, never leaves device
```

### Key Derivation Implementation

- **[v1.1]** Group key: PBKDF2-HMAC-SHA256, 100 000 iterations, salt = `vbank-group:<groupId>` (public, unique per group). A human passphrase is low-entropy, so it is stretched rather than expanded with HKDF. Runs off the UI isolate.
- Local DB key: HKDF-SHA256, 32-byte output, zero nonce, info `vbank-local-db`, input = device secret.
- Backups: PBKDF2-HMAC-SHA256 with a random 16-byte salt stored in the backup envelope (see §22).

### Ed25519 Keypair

- Generated per-device on account creation
- Private key never leaves the device
- Public key shared with group members
- Peer ID derived from public key (UUID v5 hash)

---

## 13. Permission & Role Model

### Three Roles

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

## 14. Group Lifecycle

### Group Creation

1. Owner creates account (generates Ed25519 keypair)
2. Owner creates group with name, contribution amount, frequency
3. Group config stored locally in SQLCipher
4. Group metadata added to IPFS (gets CID)
5. CID published to DHT

### Group Configuration

| Field | Description | Default |
|-------|-------------|---------|
| `groupId` | UUID v4 | — |
| `contributionAmount` | Amount per contribution | Required |
| `frequency` | weekly / biweekly / monthly | weekly |
| `meetingDayOfWeek` | 0=Sunday through 6=Saturday | 0 |
| `meetingTime` | Time of day for meetings | "09:00" |
| `maxLoanMultiplier` | Max loan as multiple of contributions | 3.0 |
| `loanInterestRate` | Interest rate (0.10 = 10%) | 0.10 |
| `latePenaltyRate` | Penalty per week overdue (0.05 = 5%) | 0.05 |
| `minContributionsForLoan` | Min contributions before loan eligibility | 3 |
| `currency` | Currency code | "ZMW" |
| `savingsTarget` | Optional savings goal | null |
| `requireLoanApproval` | Whether loans need admin approval | true |

---

## 15. Loan Lifecycle

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

### Loan Statuses

| Status | Meaning |
|--------|---------|
| `pending` | Requested, awaiting admin approval |
| `approved` | Admin approved the loan |
| `rejected` | Admin rejected the loan |
| `disbursed` | Funds disbursed to borrower |
| `repaying` | Repayments in progress |
| `completed` | All repayments made |
| `defaulted` | Overdue past grace period |

### Loan Fields

- `requestedAmount` — What the borrower asked for
- `approvedAmount` — What was actually approved (may differ)
- `interestRate` — e.g., 0.10 for 10%
- `termWeeks` — Number of weeks to repay
- `reason` — Optional reason for loan

### Repayment Schedule

Each loan generates a `RepaymentSchedule` with installments:
- `installmentNumber` — Sequential number
- `expectedAmount` — How much is due
- `dueDate` — When payment is due
- `paidAmount` — How much has been paid
- `penalty` — Late penalty applied
- `status` — pending / paid / overdue / waived

---

## 16. Invite System

### Two Share Methods

| Method | Format | When to use |
|--------|--------|-------------|
| QR Code | `vbank://join?group=<ID>&inviter=<PEER_ID>&cid=<SNAPSHOT_CID>&invite=<INVITE_ID>&n=<NONCE>` **[v1.1]** | In person |
| Share Link | Same URI, shared via WhatsApp/SMS/email | Remote |

**[v1.1]** The link never contains key material. The joiner enters the group passphrase (told to them by the inviter), derives the group key, fetches and decrypts the snapshot at `cid` — success proves the passphrase — validates the invite against the roster's copy of the inviter's key, then announces a signed `memberJoin`. Admin devices verify the invite (nonce, expiry, one-use), add the member (as `pending` if `requireApproval`), mark the invite used and republish the snapshot.

### Invite Flow

1. Owner/admin opens invite screen
2. App generates QR code with invite URI
3. New member scans QR code (or receives link)
4. App processes the URI, adds member to group
5. Member's public key and identity are stored locally

### Invite Payload

Plain URI (see table above). **[v1.2]** The invite link itself stays a plain URI (QR-friendly); everything that goes over IPFS/PubSub and into backup files is CBOR (`lib/core/codec/wire_codec.dart`). Signatures are computed over canonical JSON strings because CBOR re-encoding is not byte-stable across implementations.

### One-Use Enforcement

Each invite has a unique 16-byte nonce, a 7-day expiry and the inviter's Ed25519 signature. Invites travel inside the (signed, encrypted) group snapshot; on first use every admin marks it used and the flag propagates monotonically through snapshots. Subsequent attempts are rejected.

### Optional Approval Mode

When `requireApproval = true` on a group, new member requests go to a pending state requiring admin approval. Default is `false` (instant join).

---

## 17. Group Owner Transfer

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

### OwnershipTransfer Model

- `fromPeerId` — Current owner
- `toPeerId` — New owner
- `oldOwnerSignature` — Signed by current owner
- `newOwnerSignature` — Signed by new owner (confirms acceptance)

---

## 18. Group Dissolution

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

### Dissolution Statuses

| Status | Meaning |
|--------|---------|
| `initiating` | Owner has started the process |
| `settling_loans` | Checking/collecting outstanding loans |
| `distributing_funds` | Calculating and distributing final balances |
| `completed` | Group fully dissolved |

---

## 19. Conflict Resolution

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

### Why This Works

- **Transactions** are signed and immutable. There's no "overwriting" a transaction — they're append-only.
- **Group metadata** changes (adding members, changing config) use sequence numbers. The highest sequence number wins.
- **Deterministic tiebreaking** via peerId ensures all devices converge to the same state without coordination.

---

## 20. Notification System

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

## 21. Offline Transaction Queue

### Queue States

**[v1.1]** Queue state lives on the `transactions` row (`sync_status`, `sync_attempts`, `last_sync_attempt_at`, `last_sync_error`); the separate `pending_transactions` table was dropped.

| State | Meaning |
|-------|---------|
| `queued` | Transaction created, waiting for sync |
| `syncing` | IPFS node is processing this transaction |
| `synced` | Successfully added to IPFS |
| `failed` | Sync failed, will retry |

### Retry Logic

- **Max retries:** 5
- After 5 failures, show manual retry prompt
- Retry count and last attempt time tracked
- Error message stored for debugging

---

## 22. Key Recovery & Device Migration

### Backup Flow

1. User creates identity backup
2. Private key encrypted with user's PIN (XChaCha20-Poly1305)
3. Encrypted payload exported as a file (`.vbankbackup`) via the share sheet **[v1.1]** — a full backup is too large for a QR code
4. Backup stored in `app_backups` table

### Restore Flow

1. On new device → "Restore from backup"
2. Import the backup file (or pick one stored on this phone) **[v1.1]**
3. Enter PIN to decrypt
4. Keypair restored
5. Group memberships verified on the next sync (snapshots re-fetched via PubSub/DHT)
6. Old device remains functional (no automatic revocation)
7. User can manually revoke old device from group settings

### Backup Service API

| Method | Purpose |
|--------|---------|
| `createIdentityBackup(privateKey, peerId, pin)` | Encrypt and create identity backup |
| `createFullBackup(passphrase)` | Full app data backup |
| `decryptBackup(encryptedPayload, passphrase)` | Decrypt a backup |
| `getAllBackups()` | List all stored backups |
| `deleteBackup(id)` | Remove a backup |

---

## 23. Deep Linking

### URI Scheme

```
vbank://join?group=<groupId>&inviter=<peerId>
vbank://restore?backup=<backupId>
```

### Implementation

- **Package:** `app_links` (replaced deprecated `uni_links`)
- **Handler:** `DeepLinkHandler` class manages link stream
- **Initial link:** Processed on app start (cold launch)
- **Stream link:** Processed when app is already running

### Deep Link Types

| Type | Trigger | Action |
|------|---------|--------|
| `joinGroup` | `vbank://join?group=...&inviter=...` | Navigate to join group screen |
| `restoreBackup` | `vbank://restore?backup=...` | Navigate to restore backup screen |
| `unknown` | Any other `vbank://` link | Log and ignore |
| `error` | Malformed link | Show error |

---

## 24. UI Design System

### Package

`shadcn_flutter` (New York style, standalone ecosystem — no Material required).

### Design Principles

1. **Minimal** — no unnecessary decoration or animation
2. **Functional** — every element serves a purpose
3. **Accessible** — large touch targets, clear labels
4. **Consistent** — same patterns throughout the app
5. **Culturally appropriate** — no Western-centric assumptions in UI copy

---

## 25. Color Palette & Typography

### Color Tokens

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

---

## 26. Component Mapping

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
| Tabs | Group detail (transactions / members / loans) |
| Toast | Success/error notifications |
| Tooltip | Icon hints |
| CircularProgressIndicator | Loading states |
| Skeleton | Loading placeholders |

---

## 27. Screen Inventory

### Onboarding Flow

| Screen | Purpose |
|--------|---------|
| `welcome_screen` | Landing page — Create Account or Restore Backup |
| `create_account_screen` | Enter display name, generate keypair |
| `restore_backup_screen` | Scan QR or import file, enter PIN |

### Main App

| Screen | Purpose |
|--------|---------|
| `home_screen` | 4-tab navigation: Groups, Transactions, Meetings, Settings |

### Group Screens

| Screen | Purpose |
|--------|---------|
| `group_list_screen` | List all groups (embedded in home) |
| `create_group_screen` | Name, contribution amount, frequency |
| `group_detail_screen` | 4 tabs: Overview, Transactions, Members, Loans |
| `group_settings_screen` | Edit config, manage members |
| `group_reports_screen` | Group financial reports |
| `group_dissolution_screen` | Dissolve group workflow |
| `ownership_transfer_screen` | Transfer ownership to another admin |

### Transaction Screens

| Screen | Purpose |
|--------|---------|
| `transaction_list_screen` | List transactions for a group |
| `transaction_detail_screen` | Full transaction details |
| `create_transaction_screen` | Type selector, amount, note |
| `reversal_request_screen` | Request transaction reversal |
| `pending_transactions_screen` | View offline queue status |

### Loan Screens

| Screen | Purpose |
|--------|---------|
| `loan_list_screen` | List loans for a group |
| `loan_detail_screen` | Loan details, repayment schedule |
| `request_loan_screen` | Amount, term, reason |
| `approve_loan_screen` | Admin approve/reject |
| `repayment_screen` | Make a repayment |

### Meeting Screens

| Screen | Purpose |
|--------|---------|
| `meeting_list_screen` | List meetings for a group |
| `meeting_detail_screen` | Meeting details, attendance |
| `attendance_screen` | Mark attendance, record contributions |

### Invite Screens

| Screen | Purpose |
|--------|---------|
| `invite_screen` | QR code display, share link, copy code |
| `join_group_screen` | QR scanner, manual code entry |

### Other Screens

| Screen | Purpose |
|--------|---------|
| `settings_screen` | Notifications, backup, sync, logout |
| `identity_backup_screen` | Create/ manage identity backups |
| `notification_settings_screen` | Configure notification preferences |
| `sync_status_screen` | View sync state and history |

---

## 28. Data Models

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
  String id;                          // UUID v4
  String name;
  GroupConfig config;
  List<Member> members;
  List<String> inviteCids;
  bool requireApproval;               // Default: false
  DateTime createdAt;
  int sequenceNumber;                 // Incremented on every mutation
  GroupStatus status;                 // active | dissolved
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
  String meetingTime;                 // "09:00"
  double maxLoanMultiplier;           // e.g. 3x total contributions
  double loanInterestRate;            // e.g. 0.10 = 10%
  double latePenaltyRate;             // e.g. 0.05 = 5% per week overdue
  int minContributionsForLoan;
  String currency;                    // Default: "ZMW"
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
  String id;                 // UUID v4
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

enum MeetingStatus { scheduled, inProgress, completed, cancelled }
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
    'ZMW': CurrencyInfo(symbol: 'ZK', name: 'Zambian Kwacha', decimals: 2, default_: true),
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

## 29. Local Storage Schema

All tables are encrypted via SQLCipher ChaCha20-Poly1305.

### user_identity
```sql
CREATE TABLE user_identity (
    peer_id TEXT PRIMARY KEY,
    display_name TEXT NOT NULL,
    public_key BLOB NOT NULL,
    created_at INTEGER NOT NULL
);
```

### groups
```sql
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
```

### members
```sql
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
```

### transactions
```sql
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
```

### transaction_reversals
```sql
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
```

### loans
```sql
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
```

### repayment_schedules
```sql
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
```

### balances
```sql
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
```

### meetings
```sql
CREATE TABLE meetings (
    id TEXT PRIMARY KEY,
    group_id TEXT NOT NULL REFERENCES groups(id),
    scheduled_at INTEGER NOT NULL,
    status TEXT DEFAULT 'scheduled',
    notes TEXT,
    total_collected REAL DEFAULT 0,
    completed_at INTEGER
);
```

### attendance
```sql
CREATE TABLE attendance (
    meeting_id TEXT NOT NULL REFERENCES meetings(id),
    peer_id TEXT NOT NULL,
    status TEXT DEFAULT 'absent',
    contributed INTEGER DEFAULT 0,
    contribution_time INTEGER,
    PRIMARY KEY (meeting_id, peer_id)
);
```

### invites
```sql
CREATE TABLE invites (
    id TEXT PRIMARY KEY,
    group_id TEXT NOT NULL REFERENCES groups(id),
    cid TEXT,
    used INTEGER DEFAULT 0,
    created_at INTEGER NOT NULL,
    expires_at INTEGER NOT NULL
);
```

### member_removals
```sql
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
```

### pending_transactions
```sql
CREATE TABLE pending_transactions (
    id TEXT PRIMARY KEY,
    transaction_data BLOB NOT NULL,
    status TEXT DEFAULT 'queued',
    retry_count INTEGER DEFAULT 0,
    created_at INTEGER NOT NULL,
    last_attempt_at INTEGER,
    error_message TEXT
);
```

### ownership_transfers
```sql
CREATE TABLE ownership_transfers (
    id TEXT PRIMARY KEY,
    group_id TEXT NOT NULL,
    from_peer_id TEXT NOT NULL,
    to_peer_id TEXT NOT NULL,
    transferred_at INTEGER NOT NULL,
    old_owner_signature BLOB NOT NULL,
    new_owner_signature BLOB NOT NULL
);
```

### group_dissolutions
```sql
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
```

### app_backups
```sql
CREATE TABLE app_backups (
    id TEXT PRIMARY KEY,
    encrypted_payload BLOB NOT NULL,
    created_at INTEGER NOT NULL,
    version INTEGER DEFAULT 1,
    backup_type TEXT NOT NULL
);
```

### node_config
```sql
CREATE TABLE node_config (
    key TEXT PRIMARY KEY,
    value BLOB NOT NULL
);
```

### notification_schedules
```sql
CREATE TABLE notification_schedules (
    id TEXT PRIMARY KEY,
    group_id TEXT,
    notification_type TEXT NOT NULL,
    scheduled_at INTEGER NOT NULL,
    payload TEXT,
    is_active INTEGER DEFAULT 1
);
```

---

## 30. Project Structure

```
vBank/
├── lib/
│   ├── main.dart                          # App entry point, Riverpod, routing
│   │
│   ├── core/
│   │   ├── ipfs/
│   │   │   ├── ipfs_service.dart          # IPFS node lifecycle (dart_ipfs)
│   │   │   ├── sync_manager.dart          # Online/offline sync windows
│   │   │   ├── discovery_service.dart     # DHT peer discovery
│   │   │   └── pubsub_service.dart        # PubSub messaging
│   │   ├── crypto/
│   │   │   ├── identity.dart              # Ed25519 keypair (Keystore/Keychain)
│   │   │   ├── signing.dart               # Transaction signing/verification
│   │   │   ├── encryption.dart            # XChaCha20-Poly1305
│   │   │   └── key_derivation.dart        # HKDF-SHA256
│   │   ├── deeplink/
│   │   │   ├── deeplink_handler.dart      # Handle vbank:// URI scheme
│   │   │   └── share_service.dart         # Share invite links
│   │   ├── notifications/
│   │   │   ├── notification_service.dart  # Local notification init
│   │   │   └── notification_scheduler.dart # Scheduled notifications
│   │   └── storage/
│   │       ├── database.dart              # SQLCipher setup, 18 tables
│   │       ├── user_identity_dao.dart
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
│   │   ├── group.dart                     # Group, GroupConfig, Member, enums
│   │   ├── transaction.dart               # Transaction, TransactionType
│   │   ├── loan.dart                      # LoanRequest, LoanStatus
│   │   ├── meeting.dart                   # Meeting, Attendance
│   │   ├── invite.dart                    # Invite
│   │   ├── balance.dart                   # Balance
│   │   ├── report.dart                    # GroupReport, MemberStatement
│   │   ├── app_backup.dart                # AppBackup, IdentityBackup
│   │   └── currency.dart                  # CurrencyConfig, 8 currencies
│   │
│   ├── services/
│   │   ├── group_service.dart             # Group CRUD, member management
│   │   ├── transaction_service.dart       # Transaction creation, balance updates
│   │   ├── loan_service.dart              # Loan lifecycle management
│   │   ├── balance_service.dart           # Balance queries
│   │   ├── invite_service.dart            # Invite creation, usage tracking
│   │   ├── meeting_service.dart           # Meeting management, attendance
│   │   ├── backup_service.dart            # Encrypted backup/restore
│   │   └── report_service.dart            # Group financial reports
│   │
│   ├── providers/                         # Riverpod providers
│   │   ├── auth_provider.dart             # Auth state, identity management
│   │   ├── group_provider.dart            # Group list, selected group
│   │   ├── transaction_provider.dart      # Transaction list per group
│   │   ├── loan_provider.dart             # Loan list per group
│   │   ├── meeting_provider.dart          # Meeting list per group
│   │   ├── balance_provider.dart          # Balance queries
│   │   ├── ipfs_provider.dart             # IPFS, sync, discovery, PubSub
│   │   └── notification_provider.dart     # Notification service/scheduler
│   │
│   ├── screens/
│   │   ├── onboarding/
│   │   │   ├── welcome_screen.dart
│   │   │   ├── create_account_screen.dart
│   │   │   └── restore_backup_screen.dart
│   │   ├── home/
│   │   │   └── home_screen.dart           # 4-tab: Groups, Txns, Meetings, Settings
│   │   ├── group/
│   │   │   ├── group_list_screen.dart
│   │   │   ├── create_group_screen.dart
│   │   │   └── group_detail_screen.dart   # 4-tab: Overview, Txns, Members, Loans
│   │   ├── transaction/
│   │   │   ├── transaction_list_screen.dart
│   │   │   └── create_transaction_screen.dart
│   │   ├── loan/
│   │   │   ├── loan_list_screen.dart
│   │   │   └── request_loan_screen.dart
│   │   ├── meeting/
│   │   │   └── meeting_list_screen.dart
│   │   └── invite/
│   │       ├── invite_screen.dart         # QR code + share link
│   │       └── join_group_screen.dart     # QR scanner + manual entry
│   │
│   └── widgets/
│       ├── balance_card.dart
│       ├── transaction_tile.dart
│       ├── role_badge.dart
│       ├── empty_state.dart
│       ├── currency_text.dart
│       └── sync_status_indicator.dart
│
├── pubspec.yaml
├── android/
│   ├── app/
│   │   ├── build.gradle.kts              # minSdk 21, desugaring, multiDex
│   │   └── src/main/AndroidManifest.xml  # Permissions, deep links, P2P
│   └── build.gradle.kts
├── ios/
│   └── Runner/Info.plist                 # URL scheme, local network, Bonjour
├── AGENTS.md                             # AI agent guide
└── DESIGN_PLAN.md                        # This document
```

---

## 31. Dependencies

```yaml
dependencies:
  flutter:
    sdk: flutter

  # State Management
  flutter_riverpod: ^2.5.0
  riverpod_annotation: ^2.3.0

  # P2P / IPFS
  dart_ipfs: ^1.11.7

  # Local Storage (Encrypted)
  sqflite: ^2.3.0
  sqlcipher_flutter_libs: ^0.6.0

  # Cryptography
  cryptography: ^2.7.0

  # Notifications
  flutter_local_notifications: ^18.0.0
  timezone: ^0.9.4

  # QR & Sharing
  qr_flutter: ^4.1.0
  mobile_scanner: ^5.0.0
  share_plus: ^10.0.0
  url_launcher: ^6.2.0

  # Deep Linking
  app_links: ^7.0.0

  # Utilities
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

## 32. Implementation Phases

### Phase 1 — Crypto Core, Database, Models (COMPLETED)

**Crypto layer:**
- `key_derivation.dart` — HKDF-SHA256 key derivation
- `encryption.dart` — XChaCha20-Poly1305 encrypt/decrypt
- `signing.dart` — Ed25519 sign/verify
- `identity.dart` — Peer ID generation from public key
- `currency.dart` — 8 currencies, ZMW default

**Database:**
- `database.dart` — SQLCipher setup with 18 tables
- 8 DAO files for all entities

**Models:**
- 15+ model files with JSON serialization
- All enums, data classes, factory constructors

### Phase 2 — Services (COMPLETED)

**Core services:**
- `group_service.dart` — Group CRUD, member management, role checks
- `transaction_service.dart` — Transaction creation, balance updates
- `loan_service.dart` — Full loan lifecycle (request → approve → disburse → repay)
- `balance_service.dart` — Balance queries and initialization
- `invite_service.dart` — Invite creation with signing, one-use enforcement
- `meeting_service.dart` — Meeting management, attendance tracking

**P2P services:**
- `ipfs_service.dart` — Real dart_ipfs node lifecycle (start/stop/add/get/pin)
- `sync_manager.dart` — Sync window management, transaction syncing
- `discovery_service.dart` — DHT-based peer discovery
- `pubsub_service.dart` — PubSub topic subscription and messaging

**Other services:**
- `backup_service.dart` — Encrypted backup creation and restoration
- `report_service.dart` — Group financial report generation
- `notification_service.dart` — Local notification initialization
- `notification_scheduler.dart` — Scheduled notification management

### Phase 3 — UI Screens & Widgets (COMPLETED)

**Onboarding:**
- Welcome screen with Create Account / Restore Backup
- Create Account with name input
- Restore Backup with PIN entry

**Home:**
- 4-tab navigation (Groups, Transactions, Meetings, Settings)
- Groups tab with group list, create button, sync indicator
- Transactions tab with recent transactions per group
- Meetings tab with upcoming meetings per group
- Settings tab with profile, backup, sync, logout

**Group:**
- Group list with pull-to-refresh
- Create group with name and amount
- Group detail with 4 tabs (Overview, Transactions, Members, Loans)

**Transaction:**
- Transaction list per group
- Create transaction with type selector, amount, note

**Loan:**
- Loan list per group
- Request loan with amount, term, reason

**Meeting:**
- Meeting list per group

**Invite:**
- Invite screen with QR code, share link, copy
- Join group with QR scanner, manual entry

### Phase 4 — App Shell, Providers, Routing (COMPLETED)

- `main.dart` — Riverpod ProviderScope, `ShadcnApp` with `VBankTheme` (light/dark), 19 routes each wrapped in a `DrawerOverlay` sheet layer
- All providers wired to services with proper disposal
- Deep link handler initialized on app start
- Notification service initialized on app start

### Phase 5 — Build Configuration (COMPLETED)

- Android: `minSdk 21`, desugaring enabled, multiDex enabled
- Android: P2P/networking/camera/notification permissions
- Android: `vbank://` deep link intent filter
- iOS: Camera, local network, Bonjour (`_vbank._tcp`), URL scheme
- Replaced deprecated `uni_links` with `app_links`

### Build Status

```
flutter analyze → No issues found
flutter build apk --debug → ✓ Built successfully
```

---

## 33. Build Configuration

### Android (`android/app/build.gradle.kts`)

```kotlin
android {
    namespace = "com.vbank.vbank"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.vbank.vbank"
        minSdk = flutter.minSdkVersion  // 24 on Flutter 3.41 [v1.1]
        targetSdk = flutter.targetSdkVersion
        multiDexEnabled = true
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
```

### Android Permissions (`AndroidManifest.xml`)

```xml
<!-- Networking / P2P -->
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
<uses-permission android:name="android.permission.CHANGE_NETWORK_STATE" />
<uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE" />

<!-- Notifications -->
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" />
<uses-permission android:name="android.permission.USE_EXACT_ALARM" />
<uses-permission android:name="android.permission.WAKE_LOCK" />

<!-- Camera (QR scanning) -->
<uses-permission android:name="android.permission.CAMERA" />

<!-- Deep links -->
<intent-filter>
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <data android:scheme="vbank" android:host="join" />
    <data android:scheme="vbank" android:host="restore" />
</intent-filter>
```

### iOS (`Info.plist`)

- `NSCameraUsageDescription` — QR code scanning
- `NSLocalNetworkUsageDescription` — IPFS P2P networking
- `NSBonjourServices` — `_vbank._tcp` (mDNS discovery)
- `CFBundleURLTypes` — `vbank://` URL scheme

---

## 34. Testing Strategy

### Unit Tests (Planned)

- **Crypto:** Key derivation, encrypt/decrypt, sign/verify
- **Services:** Group creation, transaction creation, loan lifecycle
- **Models:** JSON serialization/deserialization
- **Conflict resolution:** Sequence number comparison logic

### Integration Tests (Planned)

- **Full transaction flow:** Create → sign → encrypt → store → sync
- **Loan lifecycle:** Request → approve → disburse → repay → complete
- **Invite flow:** Create → encode → decode → join
- **Backup/restore:** Create backup → decrypt → verify

### Manual Testing (Current)

- App builds and runs on Android emulator/device
- Onboarding flow works (create account, navigate to home)
- Group creation works
- Transaction creation works
- QR code generation works

---

## 35. Future Considerations

### Short Term

- [ ] Wire QR scanner to actual invite processing
- [ ] Implement full meeting attendance flow
- [ ] Add loan approval screen for admins
- [ ] Add transaction detail screen
- [ ] Implement group settings screen
- [ ] Add transaction reversal flow

### Medium Term

- [ ] Implement group dissolution flow
- [ ] Add ownership transfer flow
- [ ] Build financial reports screen
- [ ] Add member removal with loan settlement
- [ ] Implement notification scheduling for meetings/loans
- [ ] Add periodic background sync

### Long Term

- [ ] IPNS for mutable group metadata
- [ ] Multi-device sync (same identity, multiple phones)
- [ ] Group fund savings targets with progress tracking
- [ ] Export reports as PDF
- [ ] Multi-language support (Bemba, Nyanja, Swahili, etc.)
- [ ] iOS build and App Store deployment
- [ ] Accessibility improvements (screen reader support)

---

*This document captures the complete design plan for vBank as discussed and implemented. It serves as the authoritative reference for the application's architecture, features, and implementation status.*


---

## 36. v1.1 Implementation Notes

Status of record as of 2026-08-25. See `planning/PLAN_GAP_ANALYSIS.md` for the audit that drove these changes.

**Implemented in v1.1**
- SQLCipher local DB with device-secret-derived key; automatic migration of pre-v1.1 plaintext databases.
- Role enforcement in every mutating service call and on all inbound sync payloads; signed group snapshots; `sequenceNumber` bumped on every metadata change with §19 tie-breaks (timestamp, then publisher id).
- Per-author transaction sequence numbers; transaction signatures cover every field; `author_peer_id` recorded.
- Invites with nonce, expiry, inviter signature, one-use; `requireApproval` join workflow (`pending` members approved in Group settings).
- Full loan lifecycle: eligibility (min contributions, max multiplier, single open loan), approve/reject/disburse (creates the loan transaction + weekly repayment schedule), repayments applied to installments, `repaying`/`completed`, overdue penalties (`latePenaltyRate × installment`), default after 30 days overdue. Auto-approval when `requireLoanApproval = false`.
- Sync payload types: `transaction`, `groupSnapshot`, `memberJoin`, `loan`, `meeting`, `reversal`.
- Offline queue semantics on the transaction row (queued/syncing/synced/failed, 5 attempts, manual retry in Sync Status).
- Notifications wired: meeting reminder (24 h) + contribution due, repayment due (3 d) + overdue per installment, activity notifications for inbound changes; stable ids; preferences screen.
- Backups: PIN ≥ 6, file export/import, group keys included; restore works on a fresh device.
- Screens added: group settings (config, members, approvals, transfer, dissolve), group reports, loan detail (approve/reject/disburse/repay + schedule), transaction detail (+ reversals), meeting detail (attendance/complete), sync status, notification settings, backup & restore. Group detail gained a Meetings tab; placeholder list screens replaced.
- Ownership transfer (owner signs, new owner's device countersigns on next snapshot), dissolution (blocked by open loans/reversals; pays out net balances), member removal with loan write-off, transaction reversals (request/approve with signatures).
- Battery: node stopped 15 min after the app is backgrounded; periodic sync only in foreground.
- Discovery: DHT `findProviders` on each group's snapshot CID + dial; mDNS is provided by dart_ipfs's own service (`_ipfs-discovery._udp`), not a custom `_vbank._tcp`.

**v1.4 (2026-08-26) - search and filters on long lists**
- `FilterableList<T>` + `SearchField` + `FilterOption<T>` in `lib/ui/ui.dart`: case-insensitive substring search over a per-item haystack, scrollable filter chips, an "N of M" counter while narrowed, a "No matches" state naming the query, and the search field hidden until a list reaches `minItemsForSearch` (default 6).
- Wired into: home Activity (type filters incl. Reversed), home Groups (search), home Meetings (search), group Transactions / Members / Loans / Meetings tabs, the standalone transaction / loan / meeting list screens, and the group-settings roster (inline search, since that page is itself a ListView).
- Search haystacks resolve peer ids to member names via the group roster (`txHaystack` in `home_screen.dart`), so searching a member's name finds every entry involving them.
- Covered by `test/filterable_list_test.dart` (5 widget tests: narrowing, case-insensitivity/amount match, empty state, chip+query combination, hidden search on short lists).

**v1.3 (2026-08-25) - Spark design system, website, store assets**
- The shadcn UI now follows the **Spark design system** (`../o-systems/spark`): zinc light/dark theme (no brand colour; red/green/orange as semantic accents only), **Lucide icons throughout** (no Material `Icons`), muted radius-12 `Panel`/`ListRow` surfaces, borderless text fields, `.small.semiBold.muted` section labels, page padding 20, `SurfaceCard` toasts, Spark-style filter chips (`Segmented`/`FilterChip`) in place of `Tabs`, and an animated welcome screen.
- Bottom navigation gives each destination an equal-width cell (`Expanded` + `NavigationBarAlignment.spaceEvenly`) so icons sit on even centres; the transactions tab is labelled "Activity" because a quarter of a 384 dp screen only fits ~8 characters.
- Derived data now refreshes after local writes: `dataVersionProvider` (lib/providers/data_version.dart) is bumped by transaction, loan, meeting and dissolution flows, and `balanceProvider`/`groupBalancesProvider` watch it alongside `syncTickProvider`.
- `docs/` is a standalone GitHub Pages site (landing page, full user guide, privacy policy, terms of use including Apple's required EULA clauses) deployed by `.github/workflows/pages.yml`; `docs/store/` holds Play (1080x1920), App Store 6.7" (1290x2796) and 6.5" (1284x2778) screenshot sets plus a 1024x500 feature graphic, all derived from real device captures.

**v1.2 (2026-08-25) — UI and wire-format decisions**
- UI ported to **shadcn_flutter** (0.0.53) using the **Spark design system** (`../o-systems/spark`): zinc light/dark theme (radius 0.5, no brand colour; red/green/orange as semantic accents), Lucide icons, borderless text fields on muted radius-12 panels, `.small.semiBold.muted` section labels, page padding 20, `SurfaceCard` toasts. `lib/ui/ui.dart` is the kit (`VBankTheme`, `AppPage`, `Panel`, `ListRow`, `StatCard`, `StatusBadge`, `Segmented`/`FilterChip`, `SimpleSelect`, `ActionMenu`, …). No screen imports `flutter/material.dart`; only `MaterialPageRoute` (re-exported by shadcn) is used. `VBankTheme.pageTransitionShim` (installed via `ShadcnApp.builder`, so it reads the live theme) sets the status-bar icon style *and* a Material `Theme` whose `colorScheme.surface` + `ZoomPageTransitionsBuilder(backgroundColor:)` match the shadcn background — without it Flutter's Material page transitions composite each entering route over `ThemeData.fallback()`'s light surface, washing every push light-grey in dark mode. The Android launch background is `@color/launch_background` (white / `#09090B` in night mode) so cold start has no white flash either.
- **No dialogs.** Every confirmation/prompt/form is a keyboard-aware bottom sheet (`showAppSheet`, `confirmSheet`, `promptSheet`): the sheet pads by `MediaQuery.viewInsets`, scrolls, caps at 90 % height, and the Android back button closes the sheet (each route is wrapped in a `DrawerOverlay`; pushed screens use `pushScreen`). Toasts (`showMessage`) replace SnackBars.
- **CBOR on the wire**: `SyncEnvelope` v2 and `BackupEnvelope` are CBOR maps with binary nonce/MAC/ciphertext; the encrypted payload bodies are CBOR too. v1 JSON/base64 envelopes are still decoded for compatibility. Invite links remain plain URIs.

**Deliberate deviations (kept)**
- Group key uses PBKDF2-HMAC-SHA256 (100k, salt = `vbank-group:<groupId>`) instead of HKDF — confirmed by Arthur; DB key derives from a device secret rather than a group key.
- Members are read-only; owner/admins record all transactions (§13) — confirmed.
- Sequence numbers are per author, not per group.
- `pending_transactions` table removed; `group_keys` table added; `author_peer_id`, `loan_id`, sync columns added to `transactions`.

**Not done**
- Wi-Fi-only sync gating; background execution when the app is killed (would need WorkManager/foreground service).
- `_vbank._tcp` mDNS advertisement.
- Multi-language, PDF export, savings-target progress, IPNS (§35).
