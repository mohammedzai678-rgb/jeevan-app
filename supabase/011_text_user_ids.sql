-- Migration 011: support the app's signed local-auth IDs (u_<hash>) in
-- user-owned tables. Earlier schema versions incorrectly tied these IDs to
-- auth.users UUIDs, so valid local sessions failed with PostgreSQL 22P02.
-- Safe to run more than once; existing UUID IDs are preserved as text.

-- Remove UUID-based policies before changing column types because PostgreSQL
-- tracks their equality expressions as dependencies on those column types.
do $$
declare
  target record;
  existing_policy record;
  relation regclass;
begin
  for target in
    select * from (values
      ('profiles', 'id'),
      ('health_documents', 'user_id'),
      ('vault_settings', 'user_id'),
      ('mediscan_results', 'user_id'),
      ('symptom_checks', 'user_id'),
      ('emergency_contacts', 'user_id'),
      ('emergency_alerts', 'user_id'),
      ('device_pairings', 'user_id'),
      ('rag_documents', 'user_id')
    ) as targets(table_name, column_name)
  loop
    relation := to_regclass('public.' || target.table_name);
    if relation is not null then
      for existing_policy in select polname from pg_policy where polrelid = relation
      loop
        execute format('drop policy %I on public.%I', existing_policy.polname, target.table_name);
      end loop;
    end if;
  end loop;
end $$;

do $$
declare
  fk record;
begin
  for fk in
    select c.conname, c.conrelid::regclass as table_name
    from pg_constraint c
    where c.contype = 'f'
      and c.confrelid = 'auth.users'::regclass
      and c.conrelid in (
        select to_regclass('public.' || t.table_name)
        from unnest(array[
          'profiles',
          'health_documents',
          'vault_settings',
          'mediscan_results',
          'symptom_checks',
          'emergency_contacts',
          'emergency_alerts',
          'device_pairings',
          'rag_documents'
        ]) as t(table_name)
      )
  loop
    execute format('alter table %s drop constraint %I', fk.table_name, fk.conname);
  end loop;
end $$;

do $$
declare
  target record;
begin
  for target in
    select * from (values
      ('profiles', 'id'),
      ('health_documents', 'user_id'),
      ('vault_settings', 'user_id'),
      ('mediscan_results', 'user_id'),
      ('symptom_checks', 'user_id'),
      ('emergency_contacts', 'user_id'),
      ('emergency_alerts', 'user_id'),
      ('device_pairings', 'user_id'),
      ('rag_documents', 'user_id')
    ) as targets(table_name, column_name)
  loop
    if exists (
      select 1 from information_schema.columns
      where table_schema = 'public'
        and table_name = target.table_name
        and column_name = target.column_name
    ) then
      execute format(
        'alter table public.%I alter column %I type text using %I::text',
        target.table_name, target.column_name, target.column_name
      );
    end if;
  end loop;
end $$;

-- RLS must compare the signed subject as text; auth.uid() casts the subject
-- to UUID and therefore cannot handle the app's u_<hash> local-auth IDs.
do $$
declare
  target record;
  existing_policy record;
  relation regclass;
  policy_name text;
begin
  for target in
    select * from (values
      ('profiles', 'id'),
      ('health_documents', 'user_id'),
      ('vault_settings', 'user_id'),
      ('mediscan_results', 'user_id'),
      ('symptom_checks', 'user_id'),
      ('emergency_contacts', 'user_id'),
      ('emergency_alerts', 'user_id'),
      ('device_pairings', 'user_id'),
      ('rag_documents', 'user_id')
    ) as targets(table_name, column_name)
  loop
    relation := to_regclass('public.' || target.table_name);
    if relation is not null and exists (
      select 1 from information_schema.columns
      where table_schema = 'public'
        and table_name = target.table_name
        and column_name = target.column_name
    ) then
      for existing_policy in select polname from pg_policy where polrelid = relation
      loop
        execute format('drop policy %I on public.%I', existing_policy.polname, target.table_name);
      end loop;
      execute format('alter table public.%I enable row level security', target.table_name);
      policy_name := target.table_name || '_owner_access';
      execute format(
        'create policy %I on public.%I for all to authenticated using ((auth.jwt() ->> ''sub'') = %I) with check ((auth.jwt() ->> ''sub'') = %I)',
        policy_name, target.table_name, target.column_name, target.column_name
      );
    end if;
  end loop;
end $$;

-- Uploaded files are addressed by a first path segment equal to the JWT sub.
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
    and (storage.foldername(name))[1] = (auth.jwt() ->> 'sub')
  )
  with check (
    bucket_id = 'health-vault'
    and (storage.foldername(name))[1] = (auth.jwt() ->> 'sub')
  );
-- Jeevan sync: 2026-11-13
