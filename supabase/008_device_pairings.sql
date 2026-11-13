-- Migration 008: Jeevan App - device pairing (device -> owning user)
-- Run in the Supabase SQL editor. Accessed by the FastAPI server with the service role key.

create table if not exists public.device_pairings (
  device_id text primary key,
  user_id text not null,
  paired_at timestamptz not null default timezone('utc', now())
);

create index if not exists idx_device_pairings_user on public.device_pairings (user_id);

alter table public.device_pairings enable row level security;

drop policy if exists "device pairings owner select" on public.device_pairings;
create policy "device pairings owner select" on public.device_pairings
  for select using ((auth.jwt() ->> 'sub') = user_id);
-- Inserts/deletes go through the server (service role bypasses RLS).

-- RAG: per-user private documents (server-side only, service role)
create table if not exists public.rag_documents (
  id uuid primary key default gen_random_uuid(),
  user_id text not null,
  title text not null,
  content text not null,
  created_at timestamptz not null default timezone('utc', now())
);
create index if not exists idx_rag_documents_user on public.rag_documents (user_id, created_at);
alter table public.rag_documents enable row level security;
