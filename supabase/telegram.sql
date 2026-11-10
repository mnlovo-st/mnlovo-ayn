-- MNLOVO SAVER — official Telegram bot (run once in Supabase → SQL Editor)
-- The bot token lives only here, readable by the server function (service role), never by the app.

create table if not exists public.saver_tg_config (
  id             int primary key default 1 check (id = 1),
  bot_token      text not null,
  bot_username   text not null,
  webhook_secret text not null default replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '')
);

-- One-time codes the app creates to link a Telegram chat to the signed-in user.
create table if not exists public.saver_tg_links (
  code        text primary key,
  user_id     uuid not null references auth.users(id) on delete cascade,
  created_at  timestamptz not null default now()
);

-- Where each user's posts go (private chat, groups, channels).
create table if not exists public.saver_tg_targets (
  user_id     uuid not null references auth.users(id) on delete cascade,
  chat_id     bigint not null,
  title       text not null default '',
  type        text not null default 'private',
  tg_user_id  bigint,
  enabled     boolean not null default true,
  created_at  timestamptz not null default now(),
  primary key (user_id, chat_id)
);
create index if not exists saver_tg_targets_tguser_idx on public.saver_tg_targets (tg_user_id);

-- No client policies: only the server function (service role) touches these tables.
alter table public.saver_tg_config  enable row level security;
alter table public.saver_tg_links   enable row level security;
alter table public.saver_tg_targets enable row level security;

-- v2: share with another person ("friend") links
alter table public.saver_tg_links add column if not exists kind text not null default 'self';
alter table public.saver_tg_targets add column if not exists role text not null default 'owner';
