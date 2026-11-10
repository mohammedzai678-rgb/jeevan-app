-- ============================================================
-- JEEVAN MOBILE APP - DEDICATED DATABASE SCHEMA
-- Target Project: https://ywxddaejbavkxzscbxpw.supabase.co
-- Strictly for mobile app features: Health Vault, MediScan,
-- Symptom Checker, Emergency Services, Profiles, Storage
-- (Excludes all website-only tables)
-- ============================================================

-- Enable pgcrypto extension for UUID generation
create extension if not exists pgcrypto;

-- 1. PROFILES
create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  name text not null default 'User',
  email text not null default '',
  phone text,
  dob text,
  blood_group text,
  photo_url text,
  allergies text[] not null default '{}',
  emergency_contacts jsonb not null default '[]'::jsonb,
  medical_history text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);
alter table public.profiles enable row level security;
drop policy if exists "profiles_owner_access" on public.profiles;
create policy "profiles_owner_access" on public.profiles
  for all using (auth.uid() = id or auth.role() = 'authenticated')
  with check (auth.uid() = id or auth.role() = 'authenticated');

-- 2. HEALTH VAULT DOCUMENTS
create table if not exists public.health_documents (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  title text not null,
  category text not null default 'General',
  description text,
  document_date text,
  doctor_name text,
  hospital_name text,
  tags text[] not null default '{}',
  file_url text,
  file_name text,
  file_size bigint,
  file_type text,
  folder text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);
create index if not exists idx_health_documents_user on public.health_documents (user_id, created_at desc);
alter table public.health_documents enable row level security;
drop policy if exists "health_documents_owner_access" on public.health_documents;
create policy "health_documents_owner_access" on public.health_documents
  for all using (auth.uid() = user_id or auth.role() = 'authenticated')
  with check (auth.uid() = user_id or auth.role() = 'authenticated');

-- 3. VAULT SETTINGS (Password protection for Viewing, Saving, Deleting)
create table if not exists public.vault_settings (
  user_id uuid primary key references auth.users (id) on delete cascade,
  vault_password_hash text not null,
  is_vault_locked boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);
alter table public.vault_settings enable row level security;
drop policy if exists "vault_settings_owner_access" on public.vault_settings;
create policy "vault_settings_owner_access" on public.vault_settings
  for all using (auth.uid() = user_id or auth.role() = 'authenticated')
  with check (auth.uid() = user_id or auth.role() = 'authenticated');

-- 4. MEDISCAN RESULTS (Prescriptions, Diagnostics, Ingredient Scans)
create table if not exists public.mediscan_results (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  scan_type text not null, -- 'prescription', 'diagnostic', 'ingredient'
  original_image_url text,
  extracted_data jsonb default '{}'::jsonb,
  ai_analysis jsonb default '{}'::jsonb,
  confidence_score numeric,
  status text not null default 'completed',
  created_at timestamptz not null default timezone('utc', now())
);
create index if not exists idx_mediscan_user on public.mediscan_results (user_id, created_at desc);
alter table public.mediscan_results enable row level security;
drop policy if exists "mediscan_owner_access" on public.mediscan_results;
create policy "mediscan_owner_access" on public.mediscan_results
  for all using (auth.uid() = user_id or auth.role() = 'authenticated')
  with check (auth.uid() = user_id or auth.role() = 'authenticated');

-- 5. SYMPTOM CHECKS (AI Triage & Clinical Checks)
create table if not exists public.symptom_checks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  symptoms jsonb not null default '{}'::jsonb,
  body_region text not null,
  severity text not null default 'moderate',
  duration text not null default '1-2 days',
  ai_diagnosis jsonb default '{}'::jsonb,
  recommended_actions jsonb default '{}'::jsonb,
  urgency_level text not null default 'low',
  created_at timestamptz not null default timezone('utc', now())
);
create index if not exists idx_symptom_checks_user on public.symptom_checks (user_id, created_at desc);
alter table public.symptom_checks enable row level security;
drop policy if exists "symptom_checks_owner_access" on public.symptom_checks;
create policy "symptom_checks_owner_access" on public.symptom_checks
  for all using (auth.uid() = user_id or auth.role() = 'authenticated')
  with check (auth.uid() = user_id or auth.role() = 'authenticated');

-- 6. EMERGENCY CONTACTS
create table if not exists public.emergency_contacts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  phone text not null,
  relationship text not null default 'Family',
  is_primary boolean not null default false,
  created_at timestamptz not null default timezone('utc', now())
);
create index if not exists idx_emergency_contacts_user on public.emergency_contacts (user_id);
alter table public.emergency_contacts enable row level security;
drop policy if exists "emergency_contacts_owner_access" on public.emergency_contacts;
create policy "emergency_contacts_owner_access" on public.emergency_contacts
  for all using (auth.uid() = user_id or auth.role() = 'authenticated')
  with check (auth.uid() = user_id or auth.role() = 'authenticated');

-- 7. EMERGENCY ALERTS
create table if not exists public.emergency_alerts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  alert_type text not null,
  latitude numeric not null,
  longitude numeric not null,
  address text,
  status text not null default 'active',
  created_at timestamptz not null default timezone('utc', now())
);
create index if not exists idx_emergency_alerts_user on public.emergency_alerts (user_id, created_at desc);
alter table public.emergency_alerts enable row level security;
drop policy if exists "emergency_alerts_access" on public.emergency_alerts;
create policy "emergency_alerts_access" on public.emergency_alerts
  for all using (true)
  with check (auth.uid() = user_id or auth.role() = 'authenticated');

-- 8. NEARBY FACILITIES (Hospitals, Blood Banks, NGOs, Ambulance)
create table if not exists public.nearby_facilities (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  type text not null, -- 'hospital', 'blood_bank', 'ngo', 'ambulance'
  latitude numeric not null,
  longitude numeric not null,
  phone text,
  address text,
  is_available boolean default true,
  created_at timestamptz not null default timezone('utc', now())
);
alter table public.nearby_facilities enable row level security;
drop policy if exists "nearby_facilities_read" on public.nearby_facilities;
create policy "nearby_facilities_read" on public.nearby_facilities for select using (true);
drop policy if exists "nearby_facilities_write" on public.nearby_facilities;
create policy "nearby_facilities_write" on public.nearby_facilities for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');

-- 9. STORAGE BUCKET FOR HEALTH VAULT FILES
insert into storage.buckets (id, name, public)
values ('health-vault', 'health-vault', true)
on conflict (id) do nothing;

drop policy if exists "health_vault_storage_read" on storage.objects;
create policy "health_vault_storage_read" on storage.objects
  for select using (bucket_id = 'health-vault');

drop policy if exists "health_vault_storage_write" on storage.objects;
create policy "health_vault_storage_write" on storage.objects
  for all using (bucket_id = 'health-vault')
  with check (bucket_id = 'health-vault');

-- 10. REALTIME PUBLICATIONS FOR MOBILE SYNC
do $$
begin
  alter publication supabase_realtime add table public.health_documents;
exception when duplicate_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.emergency_alerts;
exception when duplicate_object then null;
end $$;
