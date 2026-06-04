# Phase 2 — Realtime now-playing sync (free-account friendly)

This phase makes the partner's "what they're listening to" propagate to
your iPhone in near-real-time without needing a paid Apple Developer
account. The trick: instead of APNs silent push, we use **Supabase
Realtime** (Postgres replication broadcast over WebSocket).

## How it works

```
Poll worker (Railway) --upsert--> now_playing_state row
                                          │
                  Supabase Realtime publication picks up the change
                                          ▼
                       WebSocket broadcast to all subscribers
                                          │
                         ┌────────────────┴────────────────┐
                         ▼                                 ▼
                  iOS app (you)                      iOS app (partner)
                  - foreground: instant              - foreground: instant
                  - background: BGTask catches up   - background: BGTask catches up
                  - widget reload on each event
```

- **Foreground app:** instant updates (WebSocket open).
- **App backgrounded with the WebSocket still warm:** instant updates for as long as iOS keeps the socket alive (usually 30 s – 5 min after backgrounding).
- **App fully closed:** `BGTaskScheduler` wakes the app every ~15-60 minutes and refreshes the widget.
- **True real-time on lock screen with app fully closed:** requires APNs silent push, which requires a **paid** Apple Developer account ($99/yr). The code path is already wired (`PushAppDelegate`) — flip on `.p8` credentials in `.env` and it works.

## Setup steps

### 1. Apply the new SQL migrations to Supabase

Open Supabase → SQL Editor → New query, paste, run, **in this order**:

1. `sql/0002_now_playing.sql` (Phase 1 had it noted as future — apply now)
2. `sql/0003_realtime.sql`

The second one adds `now_playing_state` to the `supabase_realtime` publication and sets the Row Level Security policy.

### 2. Set the iOS app's Supabase credentials

Open Supabase → your project → **Settings → API**. Copy:

- **Project URL** (e.g. `https://abcd1234.supabase.co`)
- **anon public** API key

Add both to `Config/Secrets.xcconfig`:

```
SUPABASE_URL = https://YOUR_PROJECT_REF.supabase.co
SUPABASE_ANON_KEY = eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
INFOPLIST_KEY_SupabaseURL = $(SUPABASE_URL)
INFOPLIST_KEY_SupabaseAnonKey = $(SUPABASE_ANON_KEY)
```

### 3. Add the Supabase Swift SDK to the iOS target

In Xcode:

1. File → **Add Package Dependencies…**
2. URL: `https://github.com/supabase/supabase-swift`
3. Dependency rule: **Up to next major** from `2.0.0` (or the latest).
4. Add the `Supabase` library product, **target: duo-sync** (not the widget).

Once it builds, `RealtimeNowPlayingClient.swift` switches from its stub implementation to the real one automatically (the file is gated by `#if canImport(Supabase)`).

### 4. Enable Background capabilities

In Xcode → **duo-sync** target → **Signing & Capabilities**:

- + Capability → **Background Modes**, then check:
  - ☑ Background fetch
  - ☑ Background processing
  - ☑ Remote notifications  *(for when you eventually go paid; harmless on free)*

Add the task identifier to the xcconfig:

```
INFOPLIST_KEY_BGTaskSchedulerPermittedIdentifiers = kkaay.duo-sync.refresh
```

### 5. Restart the backend

If running locally, restart `uvicorn`. The worker now logs:

```
user=<uuid> track changed (seq=N) — Realtime auto-fires
```

…every time a song changes. With the iOS app foregrounded and signed in,
you should see in the Xcode console almost immediately after:

```
[Realtime] applied snapshot: <track name>
```

And the home/lock screen widgets refresh.

## What's not yet built (next phases)

- **Friending** — pair two accounts so each app subscribes to the partner's `user_id` channel instead of its own.
- **ML recommendations** — embed track metadata, compute the couple's shared taste vector, surface 1 daily rec.
- **APNs upgrade** — when you go paid, add `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_PRIVATE_KEY` to the backend env and lock-screen widgets update even when both apps are fully closed.

## Going paid (when you're ready)

1. Apple Developer Program → enroll (\$99/yr, ~24-48 h verification).
2. developer.apple.com → **Keys** → **+** → enable **Apple Push Notifications service (APNs)** → download the `.p8` file (one-time download).
3. Copy the Team ID from your developer membership page, the Key ID from the key detail page.
4. Set in Railway env:
   ```
   APNS_KEY_ID=ABC123XYZ
   APNS_TEAM_ID=DEF456GHI
   APNS_TOPIC=kkaay.duo-sync
   APNS_PRIVATE_KEY=-----BEGIN PRIVATE KEY-----
   MIGTAgEA...
   -----END PRIVATE KEY-----
   APNS_USE_SANDBOX=true     # false once you ship on TestFlight
   ```
5. Rebuild + redeploy. Worker logs will now show `APNs push delivered to N device(s)` on each change.
