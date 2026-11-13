-- Health Vault document storage and per-user password settings.
-- Safe to run more than once. The app accesses these tables through the
-- authenticated FastAPI backend; direct client access is restricted by RLS.

create extension if not exists pgcrypto;

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

create index if not exists idx_health_documents_user
  on public.health_documents (user_id, created_at desc);

alter table public.health_documents enable row level security;
revoke all on table public.health_documents from public, anon;
grant select, insert, update, delete on table public.health_documents to authenticated;
grant all on table public.health_documents to service_role;
drop policy if exists "health_documents_owner_access" on public.health_documents;
drop policy if exists "health_documents_user_access" on public.health_documents;
create policy "health_documents_user_access" on public.health_documents
  for all to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create table if not exists public.vault_settings (
  user_id uuid primary key references auth.users (id) on delete cascade,
  vault_password_hash text not null,
  is_vault_locked boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

alter table public.vault_settings enable row level security;
revoke all on table public.vault_settings from public, anon;
grant select, insert, update, delete on table public.vault_settings to authenticated;
grant all on table public.vault_settings to service_role;
drop policy if exists "vault_settings_owner_access" on public.vault_settings;
drop policy if exists "vault_settings_user_access" on public.vault_settings;
create policy "vault_settings_user_access" on public.vault_settings
  for all to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Files are private. Storage paths must start with the signed-in user's UUID.
insert into storage.buckets (id, name, public)
values ('health-vault', 'health-vault', false)
on conflict (id) do update set public = false;

drop policy if exists "health_vault_storage_read" on storage.objects;
drop policy if exists "health_vault_storage_write" on storage.objects;
drop policy if exists "health_vault_storage_access" on storage.objects;
create policy "health_vault_storage_access" on storage.objects
  for all to authenticated
  using (
    bucket_id = 'health-vault'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'health-vault'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
