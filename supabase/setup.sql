-- MNLOVO AYN — Supabase setup (free plan)
-- Run this once in: Supabase Dashboard → SQL Editor → New query → Run
-- Creates a private "backups" bucket where each user can only touch their own folder.
-- Backups are encrypted on the iPhone before upload; Supabase only ever sees ciphertext.

insert into storage.buckets (id, name, public, file_size_limit)
values ('backups', 'backups', false, 10485760)  -- 10 MB per backup (photos/videos stay on the phone)
on conflict (id) do nothing;

drop policy if exists "ayn_backups_select_own" on storage.objects;
drop policy if exists "ayn_backups_insert_own" on storage.objects;
drop policy if exists "ayn_backups_update_own" on storage.objects;
drop policy if exists "ayn_backups_delete_own" on storage.objects;

create policy "ayn_backups_select_own" on storage.objects
  for select to authenticated
  using (bucket_id = 'backups' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "ayn_backups_insert_own" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'backups' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "ayn_backups_update_own" on storage.objects
  for update to authenticated
  using (bucket_id = 'backups' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'backups' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "ayn_backups_delete_own" on storage.objects
  for delete to authenticated
  using (bucket_id = 'backups' and (storage.foldername(name))[1] = auth.uid()::text);

-- Account registry (unique email, shared-phone warning): see supabase/registry.sql
