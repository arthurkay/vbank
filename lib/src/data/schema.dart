/// The clean v1 database schema: one normalized table per aggregate, typed
/// columns, no JSON blobs.
///
/// Times are millis-since-epoch UTC integers, booleans are 0/1 integers,
/// enums are their `.name` text, keys and signatures are BLOBs. The data
/// layer's DTOs are the only code that speaks this layout; everything above
/// sees domain entities.
abstract final class VBankSchema {
  /// Current schema generation. Bumped only by migrations.
  static const int version = 1;

  /// DDL run in order on a fresh database.
  static const List<String> createStatements = [
    '''
    CREATE TABLE groups(
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      require_approval INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL,
      sequence_number INTEGER NOT NULL DEFAULT 0,
      status TEXT NOT NULL DEFAULT 'active',
      owner_signature BLOB NOT NULL,
      cid TEXT,
      contribution_amount REAL NOT NULL,
      frequency TEXT NOT NULL DEFAULT 'monthly',
      meeting_day_of_week INTEGER NOT NULL DEFAULT 0,
      meeting_time TEXT NOT NULL DEFAULT '09:00',
      max_loan_multiplier REAL NOT NULL DEFAULT 3.0,
      loan_interest_rate REAL NOT NULL DEFAULT 0.10,
      late_penalty_rate REAL NOT NULL DEFAULT 0.05,
      min_contributions_for_loan INTEGER NOT NULL DEFAULT 3,
      currency TEXT NOT NULL DEFAULT 'ZMW',
      savings_target REAL,
      require_loan_approval INTEGER NOT NULL DEFAULT 1
    )
    ''',
    '''
    CREATE TABLE members(
      peer_id TEXT NOT NULL,
      group_id TEXT NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
      name TEXT NOT NULL,
      role TEXT NOT NULL DEFAULT 'member',
      joined_at INTEGER NOT NULL,
      public_key BLOB NOT NULL,
      status TEXT NOT NULL DEFAULT 'active',
      has_outstanding_loan INTEGER NOT NULL DEFAULT 0,
      enc_key BLOB,
      PRIMARY KEY (peer_id, group_id)
    )
    ''',
    'CREATE INDEX idx_members_group ON members(group_id)',
    '''
    CREATE TABLE transactions(
      id TEXT PRIMARY KEY,
      group_id TEXT NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
      from_peer_id TEXT NOT NULL,
      to_peer_id TEXT NOT NULL,
      type TEXT NOT NULL,
      amount REAL NOT NULL,
      currency TEXT NOT NULL DEFAULT 'ZMW',
      note TEXT,
      timestamp INTEGER NOT NULL,
      sequence_number INTEGER NOT NULL,
      sender_signature BLOB NOT NULL,
      author_peer_id TEXT NOT NULL,
      loan_id TEXT,
      status TEXT NOT NULL DEFAULT 'confirmed',
      cid TEXT,
      synced INTEGER NOT NULL DEFAULT 0
    )
    ''',
    'CREATE INDEX idx_transactions_group '
    'ON transactions(group_id, sequence_number)',
    '''
    CREATE TABLE reversals(
      id TEXT PRIMARY KEY,
      original_transaction_id TEXT NOT NULL REFERENCES transactions(id),
      group_id TEXT NOT NULL,
      requested_by_peer_id TEXT NOT NULL,
      approved_by_peer_id TEXT,
      reason TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'pending',
      requested_at INTEGER NOT NULL,
      resolved_at INTEGER,
      requester_signature BLOB NOT NULL,
      approver_signature BLOB
    )
    ''',
    '''
    CREATE TABLE loans(
      id TEXT PRIMARY KEY,
      group_id TEXT NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
      borrower_peer_id TEXT NOT NULL,
      requested_amount REAL NOT NULL,
      approved_amount REAL NOT NULL DEFAULT 0,
      interest_rate REAL NOT NULL,
      term_weeks INTEGER NOT NULL,
      reason TEXT,
      status TEXT NOT NULL DEFAULT 'pending',
      requested_at INTEGER NOT NULL,
      approved_at INTEGER,
      approved_by_peer_id TEXT,
      disbursed_at INTEGER,
      completed_at INTEGER,
      defaulted_at INTEGER,
      borrower_signature BLOB NOT NULL,
      approver_signature BLOB
    )
    ''',
    'CREATE INDEX idx_loans_group ON loans(group_id)',
    '''
    CREATE TABLE schedules(
      id TEXT PRIMARY KEY,
      loan_id TEXT NOT NULL REFERENCES loans(id) ON DELETE CASCADE,
      installment_number INTEGER NOT NULL,
      expected_amount REAL NOT NULL,
      due_date INTEGER NOT NULL,
      paid_amount REAL NOT NULL DEFAULT 0,
      paid_at INTEGER,
      is_overdue INTEGER NOT NULL DEFAULT 0,
      penalty REAL NOT NULL DEFAULT 0,
      status TEXT NOT NULL DEFAULT 'pending'
    )
    ''',
    '''
    CREATE TABLE balances(
      peer_id TEXT NOT NULL,
      group_id TEXT NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
      total_contributed REAL NOT NULL DEFAULT 0,
      total_loaned REAL NOT NULL DEFAULT 0,
      total_repaid REAL NOT NULL DEFAULT 0,
      total_withdrawn REAL NOT NULL DEFAULT 0,
      total_penalties REAL NOT NULL DEFAULT 0,
      outstanding_loan REAL NOT NULL DEFAULT 0,
      net_balance REAL NOT NULL DEFAULT 0,
      last_updated INTEGER NOT NULL,
      PRIMARY KEY (peer_id, group_id)
    )
    ''',
    '''
    CREATE TABLE meetings(
      id TEXT PRIMARY KEY,
      group_id TEXT NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
      scheduled_at INTEGER NOT NULL,
      status TEXT NOT NULL DEFAULT 'scheduled',
      notes TEXT,
      total_collected REAL NOT NULL DEFAULT 0,
      completed_at INTEGER
    )
    ''',
    '''
    CREATE TABLE attendance(
      meeting_id TEXT NOT NULL REFERENCES meetings(id) ON DELETE CASCADE,
      peer_id TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'absent',
      contributed INTEGER NOT NULL DEFAULT 0,
      contribution_time INTEGER,
      PRIMARY KEY (meeting_id, peer_id)
    )
    ''',
    '''
    CREATE TABLE invites(
      id TEXT PRIMARY KEY,
      group_id TEXT NOT NULL,
      group_cid TEXT NOT NULL,
      group_topic TEXT NOT NULL,
      inviter_peer_id TEXT NOT NULL,
      inviter_name TEXT NOT NULL,
      group_key BLOB NOT NULL,
      created_at INTEGER NOT NULL,
      expires_at INTEGER NOT NULL,
      used INTEGER NOT NULL DEFAULT 0,
      nonce BLOB NOT NULL,
      inviter_signature BLOB NOT NULL
    )
    ''',
    '''
    CREATE TABLE removals(
      id TEXT PRIMARY KEY,
      group_id TEXT NOT NULL,
      removed_peer_id TEXT NOT NULL,
      removed_by_peer_id TEXT NOT NULL,
      reason TEXT NOT NULL,
      has_outstanding_loan INTEGER NOT NULL DEFAULT 0,
      outstanding_amount REAL NOT NULL DEFAULT 0,
      action TEXT NOT NULL,
      removed_at INTEGER NOT NULL,
      admin_signature BLOB NOT NULL,
      lifted INTEGER NOT NULL DEFAULT 0
    )
    ''',
    '''
    CREATE TABLE transfers(
      id TEXT PRIMARY KEY,
      group_id TEXT NOT NULL,
      from_peer_id TEXT NOT NULL,
      to_peer_id TEXT NOT NULL,
      transferred_at INTEGER NOT NULL,
      old_owner_signature BLOB NOT NULL,
      new_owner_signature BLOB NOT NULL
    )
    ''',
    '''
    CREATE TABLE dissolutions(
      id TEXT PRIMARY KEY,
      group_id TEXT NOT NULL,
      initiated_by_peer_id TEXT NOT NULL,
      initiated_at INTEGER NOT NULL,
      status TEXT NOT NULL DEFAULT 'initiating',
      all_loans_settled INTEGER NOT NULL DEFAULT 0,
      funds_distributed INTEGER NOT NULL DEFAULT 0,
      completed_at INTEGER
    )
    ''',
    '''
    CREATE TABLE backups(
      id TEXT PRIMARY KEY,
      encrypted_payload BLOB NOT NULL,
      group_ids TEXT NOT NULL DEFAULT '',
      created_at INTEGER NOT NULL,
      version INTEGER NOT NULL DEFAULT 1,
      backup_type TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE identity(
      peer_id TEXT PRIMARY KEY,
      display_name TEXT NOT NULL,
      public_key BLOB NOT NULL,
      created_at INTEGER NOT NULL
    )
    ''',
    '''
    CREATE TABLE settings(
      key TEXT PRIMARY KEY,
      value BLOB NOT NULL
    )
    ''',
  ];

  /// Tables a v1 database must have. Used to recognise our own schema.
  static const List<String> tables = [
    'groups',
    'members',
    'transactions',
    'reversals',
    'loans',
    'schedules',
    'balances',
    'meetings',
    'attendance',
    'invites',
    'removals',
    'transfers',
    'dissolutions',
    'backups',
    'identity',
    'settings',
  ];
}
