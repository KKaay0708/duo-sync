# duo-sync web

Next.js 15 PWA that gets you back on the iPhone lock screen on a **free Apple Developer account**. The catch: instead of a pinned widget/Live Activity, you get a Web Push notification every time the watched user's song changes — banner pops on the lock screen with album art + track name.

## Local development

```bash
cd web
npm install
cp .env.example .env.local
# fill in the env vars (see below)
npm run dev
```

Open <http://127.0.0.1:3000>. Note: Web Push **does not work on `localhost`** in some browsers — to test pushes locally, use `http://127.0.0.1:3000` (Chrome treats it as secure for service workers).

## Required env vars

| Var | Where to find it |
|---|---|
| `NEXT_PUBLIC_BACKEND_URL` | URL of your FastAPI backend (`http://localhost:8000` for dev, your Railway URL in prod). |
| `NEXT_PUBLIC_SUPABASE_URL` | Supabase → Settings → API → Project URL. |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Supabase → Settings → API → anon public key. |
| `NEXT_PUBLIC_SPOTIFY_CLIENT_ID` | Your Spotify dashboard app's Client ID. |
| `NEXT_PUBLIC_SPOTIFY_REDIRECT_URI` | `http://127.0.0.1:3000/auth/callback` for dev. Add this **exact** URI to your Spotify app's Redirect URIs list. |
| `NEXT_PUBLIC_VAPID_PUBLIC_KEY` | Generated — see below. **Must match** the `VAPID_PUBLIC_KEY` set on the backend. |

## Generating VAPID keys (one-time)

VAPID is the signing scheme for Web Push. You generate a key pair, keep the private key on the backend, publish the public key to the browser.

```bash
# In the backend venv:
python -c "from py_vapid import Vapid01; v=Vapid01(); v.generate_keys(); \
  print('PRIVATE:', v.private_pem().decode()); \
  print('PUBLIC :', v.public_key_urlsafe_base64().decode())"
```

Or use the in-browser tool at <https://vapidkeys.com/>.

Then:

- Set `VAPID_PRIVATE_KEY`, `VAPID_PUBLIC_KEY`, and `VAPID_SUBJECT=mailto:you@example.com` in `backend/.env`.
- Set `NEXT_PUBLIC_VAPID_PUBLIC_KEY` to the **same public key** in `web/.env.local`.

The public key in the browser MUST match the private key on the server, or push subscriptions will be rejected.

## Apply the new SQL migration

In Supabase → SQL Editor → New query → paste `backend/sql/0004_web_push.sql` → Run.

## Add icons

You need two PNGs in `web/public/`:
- `icon-192.png` (192×192)
- `icon-512.png` (512×512)

These show up as the app icon on iPhone home screen and inside push notifications. You can drop any logo in for now — they'll be picked up automatically.

## End-to-end flow

1. User opens `https://your-domain` (or `http://127.0.0.1:3000` locally) in Safari/Chrome.
2. Login page → "Log in with Spotify" → standard PKCE OAuth → returns to `/auth/callback`.
3. Callback exchanges code for Spotify tokens, POSTs them to `/auth/spotify`, gets a JWT, redirects to `/`.
4. Dashboard subscribes to Supabase Realtime for that user's `now_playing_state` row and renders the card live.
5. User taps **"Enable lock-screen notifications"** → browser asks for permission → on yes, the service worker is registered + a push subscription is created + posted to `/me/web-push-subscription`.
6. Backend poll worker is already polling Spotify. On a song change, it dispatches a Web Push to every subscription registered for that user.
7. iPhone receives the push → service worker shows a lock-screen notification with album art and the new song title.

## iPhone install instructions (give these to your partner)

1. Open the deployed URL in **Safari** (not Chrome — Web Push on iOS only works for Safari PWAs).
2. Tap the **Share** icon (the square with an arrow pointing up).
3. Scroll down → **Add to Home Screen** → **Add**.
4. Open the app from the new home-screen icon (this is required — pushes only work on PWAs launched from home screen on iOS).
5. Log in with Spotify.
6. Tap **Enable lock-screen notifications** → grant permission.
7. Done. Every time their watched user changes a song, the iPhone lock screen lights up.

## Deploy

### Vercel (web)

1. Push to GitHub.
2. <https://vercel.com> → Add New → Project → import the repo.
3. **Root Directory:** `web`.
4. Framework preset auto-detected as Next.js.
5. Add all `NEXT_PUBLIC_*` env vars from `.env.example`.
6. Deploy. You'll get a `https://YOUR_APP.vercel.app` URL.
7. Add `https://YOUR_APP.vercel.app/auth/callback` to your Spotify dashboard's Redirect URIs.
8. Update `NEXT_PUBLIC_SPOTIFY_REDIRECT_URI` in Vercel env vars accordingly.

### Railway (backend)

Already documented in `backend/README.md`. After this phase, also set:

- `VAPID_PUBLIC_KEY`
- `VAPID_PRIVATE_KEY`
- `VAPID_SUBJECT`

Then restart the Railway service.
