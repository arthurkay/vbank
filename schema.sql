-- The Growth Hub - Supabase PostgreSQL Schema
-- This schema supports user management, group structure, contributions, and detailed loan tracking.

-- 1. EXTENSIONS
-- Enable the uuid-ossp extension for generating unique IDs
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 2. GROUPS TABLE -- Defines the high-level village banking group.
CREATE TABLE groups (
id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
name TEXT NOT NULL,
mission TEXT,
target_balance DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

COMMENT ON TABLE groups IS 'Main village banking groups.';

-- 3. PROFILES TABLE -- Stores metadata for each user, linked to Supabase Auth (auth.users).
CREATE TABLE profiles (
id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE, -- Links directly to the user in auth.users
full_name TEXT DEFAULT "User",
phone_number TEXT UNIQUE,
is_admin BOOLEAN DEFAULT FALSE, -- To flag the group creator/administrator
avatar_url TEXT,
updated_at TIMESTAMP WITH TIME ZONE
);

COMMENT ON TABLE profiles IS 'User profile information, secured by RLS.';

-- 4. GROUP_MEMBERS TABLE (Junction Table) -- Links profiles to groups and stores group-specific roles/status.
CREATE TABLE group_members (
id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
group_id UUID REFERENCES groups(id) ON DELETE CASCADE NOT NULL,
member_id UUID REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
role TEXT DEFAULT 'Member', -- e.g., 'Treasurer', 'Secretary', 'Member'
status TEXT DEFAULT 'Active',
joined_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

-- Ensures a member can only belong to a group once
UNIQUE (group_id, member_id)
);

COMMENT ON TABLE group_members IS 'Members associated with a specific group.';

-- 5. CONTRIBUTIONS TABLE (Savings/Deposits) -- Tracks all individual savings transactions.
CREATE TABLE contributions (
id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
group_id UUID REFERENCES groups(id) ON DELETE CASCADE NOT NULL,
member_id UUID REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
amount DECIMAL(10, 2) NOT NULL CHECK (amount > 0),
transaction_date TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

COMMENT ON TABLE contributions IS 'Records of member savings.';

-- 6. LOANS TABLE -- Tracks the principal and terms for any loan disbursed to a member.
CREATE TABLE loans (
id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
group_id UUID REFERENCES groups(id) ON DELETE CASCADE NOT NULL,
member_id UUID REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
principal_amount DECIMAL(10, 2) NOT NULL CHECK (principal_amount > 0),
interest_rate DECIMAL(5, 4) NOT NULL, -- e.g., 0.05 for 5%
disbursement_date DATE NOT NULL DEFAULT CURRENT_DATE,
term_months INTEGER NOT NULL,
next_repayment_date DATE,
status TEXT DEFAULT 'Active', -- 'Active', 'Repaid', 'Default'

-- The current outstanding balance
current_balance DECIMAL(10, 2) NOT NULL
);

COMMENT ON TABLE loans IS 'Details of loans taken by group members.';

-- 7. LOAN_REPAYMENTS TABLE -- Tracks every payment made against an outstanding loan. Essential for health checks.
CREATE TABLE loan_repayments (
id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
loan_id UUID REFERENCES loans(id) ON DELETE CASCADE NOT NULL,
amount DECIMAL(10, 2) NOT NULL CHECK (amount > 0),
payment_date TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

COMMENT ON TABLE loan_repayments IS 'Records all repayments made against a specific loan.';

-- 8. ACTIVITIES TABLE (Community Feed) -- Event log for feed updates.
CREATE TABLE activities (
id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
group_id UUID REFERENCES groups(id) ON DELETE CASCADE NOT NULL,
member_id UUID REFERENCES profiles(id) ON DELETE SET NULL, -- Null if a system event
type TEXT NOT NULL, -- 'deposit', 'loan_disbursed', 'goal_reached', 'praise'
description TEXT NOT NULL,
created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

COMMENT ON TABLE activities IS 'The main feed of group actions and announcements.';

alter table public.profiles enable row level security;

-- inserts a row into public.profiles
create function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = ''
as $$
begin
  insert into public.profiles (id, full_name, phone_number)
  values (new.id, new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'phone_number');
  return new;
end;
$$;
-- trigger the function every time a user is created
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();