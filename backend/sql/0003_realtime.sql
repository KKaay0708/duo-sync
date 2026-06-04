-- duo-sync — Phase 2b: enable Supabase Realtime broadcasts for now_playing_state.
-- Paste into Supabase → SQL Editor → New Query → Run.
--
-- Realtime publishes Postgres row changes over a WebSocket the iOS app
-- subscribes to. With this enabled, every UPSERT the poll worker does
-- becomes a real-time push to every subscribed client.

-- 1) Tell Postgres to publish full rows (vs just primary key) so the
--    Realtime event includes track_name, artist_name, etc.
alter table now_playing_state replica identity full;

-- 2) Add the table to the supabase_realtime publication. (The
--    publication is created automatically by Supabase.)
alter publication supabase_realtime add table now_playing_state;

-- 3) Row Level Security — for MVP we allow any authenticated or
--    anonymous client to read now-playing state (the user_id is a
--    UUID that's effectively a capability — you have to know it).
--    Tighten later when we wire Supabase Auth alongside our JWT.
alter table now_playing_state enable row level security;

drop policy if exists now_playing_state_read on now_playing_state;
create policy now_playing_state_read
    on now_playing_state
    for select
    to anon, authenticated
    using (true);

-- The backend writes via the service_role key, which bypasses RLS by
-- design — no INSERT/UPDATE policy needed.
