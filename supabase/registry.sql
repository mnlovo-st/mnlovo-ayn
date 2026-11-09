-- MNLOVO SAVER — account registry (run once in Supabase → SQL Editor → New query → Run)
-- • One account per email.
-- • Several accounts may share a phone number; sign-up warns and shows a masked hint (e.g. m•••e@gmail.com).
-- Phone numbers are stored only as a one-way hash, never in clear.

create table if not exists public.saver_accounts (
  user_id     uuid primary key references auth.users(id) on delete cascade,
  email       text not null unique,
  phone_hash  text not null,
  email_hint  text not null,
  created_at  timestamptz not null default now()
);
create index if not exists saver_accounts_phone_idx on public.saver_accounts (phone_hash);

alter table public.saver_accounts enable row level security;

drop policy if exists "saver_accounts_select_own" on public.saver_accounts;
drop policy if exists "saver_accounts_insert_own" on public.saver_accounts;
drop policy if exists "saver_accounts_update_own" on public.saver_accounts;

create policy "saver_accounts_select_own" on public.saver_accounts
  for select to authenticated using (user_id = auth.uid());
create policy "saver_accounts_insert_own" on public.saver_accounts
  for insert to authenticated with check (user_id = auth.uid());
create policy "saver_accounts_update_own" on public.saver_accounts
  for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Sign-up check, callable before signing in. Returns only: is the email taken, and masked hints for the phone.
create or replace function public.saver_check_signup(p_email text, p_phone_hash text)
returns json
language sql
security definer
set search_path = public
as $$
  select json_build_object(
    'email_taken', exists (select 1 from public.saver_accounts where email = lower(trim(p_email))),
    'phone_hints', coalesce((select json_agg(email_hint) from public.saver_accounts
                             where phone_hash = p_phone_hash and email <> lower(trim(p_email))), '[]'::json)
  );
$$;

revoke all on function public.saver_check_signup(text, text) from public;
grant execute on function public.saver_check_signup(text, text) to anon, authenticated;
