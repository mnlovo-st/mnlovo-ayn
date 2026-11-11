-- MNLOVO SAVER — changing the username
-- • Only through saver_change_username(), and only right after an email code (the sign-in must be
--   an email OTP from the last 15 minutes).
-- • Once changed, it's locked for 90 days. Support (service role) can still change it.
-- • Any other write that tries to change the name (e.g. an old backup re-registering) keeps the
--   current one instead of failing.

alter table public.saver_accounts add column if not exists username_changed_at timestamptz;

create or replace function public.saver_guard_username()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  allowed boolean := coalesce(current_setting('saver.allow_username', true), '') = '1'
                     or coalesce(auth.role(), '') = 'service_role';
begin
  if not allowed then
    if old.username is not null and new.username is distinct from old.username then
      new.username := old.username;
    end if;
    new.username_changed_at := old.username_changed_at;
  end if;
  return new;
end;
$$;

drop trigger if exists saver_guard_username on public.saver_accounts;
create trigger saver_guard_username before update on public.saver_accounts
  for each row execute function public.saver_guard_username();

create or replace function public.saver_change_username(p_name text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  r public.saver_accounts;
  n text := btrim(coalesce(p_name, ''));
  fresh boolean;
begin
  if auth.uid() is null then
    return json_build_object('ok', false, 'error', 'auth');
  end if;
  if char_length(n) < 2 or char_length(n) > 32 then
    return json_build_object('ok', false, 'error', 'length');
  end if;
  -- the email code: this session has to come from an email OTP in the last 15 minutes
  select exists (
    select 1 from jsonb_array_elements(coalesce(auth.jwt() -> 'amr', '[]'::jsonb)) a
    where a ->> 'method' in ('otp', 'magiclink', 'email/signup')
      and to_timestamp((a ->> 'timestamp')::double precision) > now() - interval '15 minutes'
  ) into fresh;
  if not fresh then
    return json_build_object('ok', false, 'error', 'code');
  end if;
  select * into r from public.saver_accounts where user_id = auth.uid() for update;
  if not found then
    return json_build_object('ok', false, 'error', 'missing');
  end if;
  if r.username = n then
    return json_build_object('ok', false, 'error', 'same');
  end if;
  if r.username_changed_at is not null and r.username_changed_at > now() - interval '90 days' then
    return json_build_object('ok', false, 'error', 'locked', 'next_at', r.username_changed_at + interval '90 days');
  end if;
  perform set_config('saver.allow_username', '1', true);
  update public.saver_accounts
     set username = n, username_changed_at = now(), updated_at = now()
   where user_id = auth.uid();
  return json_build_object('ok', true, 'next_at', now() + interval '90 days');
end;
$$;

revoke all on function public.saver_change_username(text) from public, anon;
grant execute on function public.saver_change_username(text) to authenticated;
