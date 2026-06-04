-- duo-sync — Phase 2: track last-known "now playing" state per user.
-- Paste into Supabase → SQL Editor → New Query → Run.

create table if not exists now_playing_state (
    user_id        uuid primary key references users(id) on delete cascade,
    track_id       text,                        -- Spotify track URI/ID, null when nothing playing
    track_name     text,
    artist_name    text,
    album_name     text,
    album_art_url  text,
    is_playing     boolean not null default false,
    progress_ms    integer,
    duration_ms    integer,
    polled_at      timestamptz not null default now(),
    -- Bumped each time the poller detects a *meaningful* change
    -- (track or play-state). Used as the silent-push payload version.
    change_seq     bigint not null default 0
);

create index if not exists now_playing_changed_idx
    on now_playing_state (polled_at desc);
