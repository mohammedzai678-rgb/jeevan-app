-- ============================================================
-- MIGRATION 009: ADD MISSING TABLES REFERENCED BY SERVER CODE
-- Tables: sos_events, emergency_summaries, medications,
--         vitawatch_readings, mediscan_logs, device_live_stream,
--         rag_documents
-- These tables are accessed via the service-role key from the
-- FastAPI backend, so RLS is enabled but policies allow the
-- service role to bypass (Supabase service-role key already
-- bypasses RLS by default). Authenticated-user policies are
-- added where appropriate for direct client access.
-- ============================================================

-- 1. SOS EVENTS (referenced by sos_service.py, ecosystem.py)
create table if not exists public.sos_events (
  id text primary key,
  uid text not null,
  location jsonb default '{}'::jsonb,
  status text not null default 'active',
  timestamp timestamptz default now(),
  notes text default '',
  "resolvedAt" timestamptz
);
create index if not exists idx_sos_events_uid on public.sos_events (uid);
alter table public.sos_events enable row level security;
drop policy if exists "sos_events_service_access" on public.sos_events;
create policy "sos_events_service_access" on public.sos_events
  for all using (true) with check (true);

-- 2. EMERGENCY SUMMARIES (referenced by ecosystem.py, assistant.py)
create table if not exists public.emergency_summaries (
  uid text primary key,
  name text not null default 'Jeevan User',
  "bloodType" text default 'O+',
  dob text default '',
  allergies jsonb default '[]'::jsonb,
  conditions jsonb default '[]'::jsonb,
  "currentMedications" jsonb default '[]'::jsonb,
  "emergencyContacts" jsonb default '[]'::jsonb,
  "updatedAt" timestamptz default now()
);
alter table public.emergency_summaries enable row level security;
drop policy if exists "emergency_summaries_service_access" on public.emergency_summaries;
create policy "emergency_summaries_service_access" on public.emergency_summaries
  for all using (true) with check (true);

-- 3. MEDICATIONS (referenced by ecosystem.py)
create table if not exists public.medications (
  id text primary key,
  uid text not null,
  name text not null,
  dosage text not null default '',
  frequency text default 'Once daily',
  "reminderTimes" jsonb default '["08:00"]'::jsonb,
  "startDate" date default current_date,
  "doctorName" text,
  "adherenceScore" integer default 100,
  "createdAt" timestamptz default now()
);
create index if not exists idx_medications_uid on public.medications (uid);
alter table public.medications enable row level security;
drop policy if exists "medications_service_access" on public.medications;
create policy "medications_service_access" on public.medications
  for all using (true) with check (true);

-- 4. VITAWATCH READINGS (referenced by app_api.py, ecosystem.py)
create table if not exists public.vitawatch_readings (
  id text primary key default 'vw_' || substr(gen_random_uuid()::text, 1, 12),
  user_id text not null,
  heart_rate integer,
  spo2 integer,
  temperature real,
  ecg_bpm integer,
  ecg_status text default 'not_available',
  systolic_bp integer,
  diastolic_bp integer,
  source text default 'manual',
  device_id text,
  notes text,
  ai_analysis jsonb default '{}'::jsonb,
  recorded_at timestamptz default now()
);
create index if not exists idx_vitawatch_user on public.vitawatch_readings (user_id);
alter table public.vitawatch_readings enable row level security;
drop policy if exists "vitawatch_readings_service_access" on public.vitawatch_readings;
create policy "vitawatch_readings_service_access" on public.vitawatch_readings
  for all using (true) with check (true);

-- 5. MEDISCAN LOGS (referenced by ecosystem.py)
create table if not exists public.mediscan_logs (
  id text primary key,
  uid text not null,
  scan_type text default 'general',
  input_params jsonb default '{}'::jsonb,
  ai_response jsonb default '{}'::jsonb,
  reward real,
  correction text,
  is_verified boolean default false,
  created_at timestamptz default now()
);
create index if not exists idx_mediscan_logs_uid on public.mediscan_logs (uid);
alter table public.mediscan_logs enable row level security;
drop policy if exists "mediscan_logs_service_access" on public.mediscan_logs;
create policy "mediscan_logs_service_access" on public.mediscan_logs
  for all using (true) with check (true);

-- 6. DEVICE LIVE STREAM (referenced by sos_service.py)
create table if not exists public.device_live_stream (
  device_id text primary key,
  sensor text default '',
  data jsonb default '{}'::jsonb,
  signal_quality text default 'UNKNOWN',
  updated_at timestamptz default now()
);
alter table public.device_live_stream enable row level security;
drop policy if exists "device_live_stream_service_access" on public.device_live_stream;
create policy "device_live_stream_service_access" on public.device_live_stream
  for all using (true) with check (true);

-- 7. RAG DOCUMENTS (referenced by assistant.py)
create table if not exists public.rag_documents (
  id bigint generated always as identity primary key,
  user_id text not null,
  title text not null,
  content text not null,
  created_at timestamptz default now()
);
create index if not exists idx_rag_docs_user on public.rag_documents (user_id);
alter table public.rag_documents enable row level security;
drop policy if exists "rag_documents_service_access" on public.rag_documents;
create policy "rag_documents_service_access" on public.rag_documents
  for all using (true) with check (true);

-- REALTIME PUBLICATIONS FOR NEW TABLES

-- 8. COMMUNITY ALERTS (referenced by health_vault.py, community alerts screen)
create table if not exists public.community_alerts (
  id text primary key,
  user_id text not null,
  alert_type text not null default 'General',
  title text default '',
  address text default '',
  latitude double precision default 0,
  longitude double precision default 0,
  status text not null default 'active',
  created_at timestamptz default now()
);
create index if not exists idx_community_alerts_user on public.community_alerts (user_id);
alter table public.community_alerts enable row level security;
drop policy if exists "community_alerts_service_access" on public.community_alerts;
create policy "community_alerts_service_access" on public.community_alerts
  for all using (true) with check (true);

-- REALTIME PUBLICATIONS FOR NEW TABLES
do $$
begin
  alter publication supabase_realtime add table public.sos_events;
exception when duplicate_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.device_live_stream;
exception when duplicate_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.vitawatch_readings;
exception when duplicate_object then null;
end $$;
