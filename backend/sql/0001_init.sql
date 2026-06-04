-- duo-sync — initial schema
-- Paste this into Supabase → SQL Editor → New Query → Run.

create extension if not exists "pgcrypto";

-- Users (one row per signed-in Spotify account)
create table if not exists users (
    id              uuid primary key default gen_random_uuid(),
    spotify_id      text unique not null,
    display_name    text,
    email           text,
    avatar_url      text,
    created_at      timestamptz not null default now(),
    updated_at      timestamptz not null default now()
);

create index if not exists users_spotify_id_idx on users (spotify_id);

-- Spotify access + refresh tokens (refresh token is encrypted at rest)
create table if not exists spotify_tokens (
    user_id              uuid primary key references users(id) on delete cascade,
    access_token         text not null,
    refresh_token_enc    text not null,           -- Fernet-encrypted refresh token
    scope                text,
    expires_at           timestamptz not null,
    updated_at           timestamptz not null default now()
);

-- One row per installed iOS device, for APNs silent push later
create table if not exists sessions (
    id              uuid primary key default gen_random_uuid(),
    user_id         uuid not null references users(id) on delete cascade,
    apns_token      text,
    created_at      timestamptz not null default now(),
    last_seen_at    timestamptz not null default now(),
    unique (user_id, apns_token)
);

create index if not exists sessions_user_id_idx on sessions (user_id);

-- Friendships (symmetric, stored once). We'll add friend_requests later
-- when we build the friending milestone.
create table if not exists friendships (
    user_a_id  uuid not null references users(id) on delete cascade,
    user_b_id  uuid not null references users(id) on delete cascade,
    created_at timestamptz not null default now(),
    primary key (user_a_id, user_b_id),
    check (user_a_id < user_b_id)
);
