-- duo-sync — Phase 3: Web Push subscriptions for browser/PWA notifications.
-- Paste into Supabase → SQL Editor → New Query → Run.

create table if not exists web_push_subscriptions (
    id          uuid primary key default gen_random_uuid(),
    user_id     uuid not null references users(id) on delete cascade,
    endpoint    text unique not null,           -- browser-specific push service URL
    p256dh      text not null,                  -- public key (base64url)
    auth        text not null,                  -- auth secret (base64url)
    user_agent  text,                           -- for debugging / UX
    created_at  timestamptz not null default now(),
    last_seen_at timestamptz not null default now()
);

create index if not exists web_push_user_idx on web_push_subscriptions (user_id);
