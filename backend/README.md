# duo-sync backend

FastAPI + Postgres backend for duo-sync. Phase 1: Spotify auth and token storage.

## Local development

### 1. Create a Supabase project

1. Go to <https://supabase.com>, sign in, **New project**. Pick a name and a strong DB password — Supabase will provision a managed Postgres database.
2. In **Project Settings → Database → Connection string → URI**, copy the connection string. You'll paste it into `.env` below as `DATABASE_URL`.
3. In **SQL Editor**, click **New query**, paste the contents of `sql/0001_init.sql`, and **Run**. This creates the `users`, `spotify_tokens`, `sessions`, and `friendships` tables.

### 2. Set up the Python environment

```bash
cd backend
python3.11 -m venv .venv
source .venv/bin/activate
pip install -e ".[dev]"
```

### 3. Configure environment variables

```bash
cp .env.example .env
```

Then fill in:

- `DATABASE_URL` — from Supabase (step 1).
- `TOKEN_ENCRYPTION_KEY` — generate with:
  ```bash
  python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
  ```
- `JWT_SECRET` — generate with:
  ```bash
  python -c "import secrets; print(secrets.token_urlsafe(48))"
  ```
- `SPOTIFY_CLIENT_ID` — same Client ID your iOS app uses (`beb87efbee1d4fe89a69ab1b85b68a23`).

### 4. Run

```bash
uvicorn app.main:app --reload --port 8000
```

Open <http://localhost:8000/docs> for auto-generated Swagger UI.

### 5. Test from the iOS app

By default the iOS app calls `http://localhost:8000`. To point at a deployed backend, add `BackendBaseURL` to the auto-generated Info.plist via your xcconfig:

```
INFOPLIST_KEY_BackendBaseURL = https://duo-sync.up.railway.app
```

## Deploy to Railway

1. Go to <https://railway.app>, sign in with GitHub, **New project → Deploy from GitHub repo**. Pick this repo. Choose the **`backend/`** folder as the root if Railway asks.
2. Railway auto-detects Python via Nixpacks. The `Procfile` and `railway.json` in this folder tell it how to run.
3. In Railway → your service → **Variables**, add the same four env vars from `.env.example`:
   - `DATABASE_URL` (same Supabase URL)
   - `TOKEN_ENCRYPTION_KEY`
   - `JWT_SECRET`
   - `SPOTIFY_CLIENT_ID`
   - Optional: `APP_ENV=prod` to disable `/docs`.
4. **Settings → Networking → Generate Domain** to get a public URL like `https://duo-sync.up.railway.app`.
5. Plug that URL into the iOS app via `INFOPLIST_KEY_BackendBaseURL` in `Config/Secrets.xcconfig`.

## API surface (Phase 1)

| Method | Path | Auth | Purpose |
|---|---|---|---|
| `GET`  | `/healthz` | none | Liveness probe |
| `POST` | `/auth/spotify` | none | Exchange Spotify tokens for a backend session JWT |
| `GET`  | `/me` | Bearer | Current user profile |
| `POST` | `/me/device-token` | Bearer | Register an APNs device token for silent push |
| `DELETE` | `/me` | Bearer | Hard-delete the account |

## What's next

- **Phase 2:** poll worker (async task running inside the API process, or a separate Railway service) iterating through all `spotify_tokens` rows every 5–10 s. When a track changes, dispatch APNs silent push to every `sessions.apns_token` for that user.
- **Phase 3:** friendships endpoints (request / accept / list, "what are my friends listening to").
- **Phase 4:** recommendations — pgvector embeddings of tracks + nearest-neighbor search.
