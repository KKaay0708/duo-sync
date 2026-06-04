"""Background poll worker.

Runs inside the FastAPI process (one async task). Every
``WORKER_POLL_INTERVAL`` seconds it iterates over every user with stored
Spotify tokens, calls /me/player/currently-playing on their behalf, diffs
against the last-known state, and dispatches a silent push to all of that
user's registered iOS devices whenever the track or play state changes.

If APNs isn't configured (free dev account, no key yet), the diff still
runs and DB state stays fresh — only the push step is skipped.
"""

from __future__ import annotations

import asyncio
import datetime as dt
import logging
from dataclasses import dataclass

import httpx

from . import apns, db, spotify, web_push
from .config import Settings, get_settings
from .security import decrypt_token, encrypt_token

log = logging.getLogger(__name__)


@dataclass
class UserCreds:
    user_id: str
    access_token: str
    refresh_token_plain: str
    expires_at: dt.datetime
    scope: str | None


# ---------------------------------------------------------------------------
# Public entry point
# ---------------------------------------------------------------------------


_task: asyncio.Task | None = None


async def start() -> None:
    global _task
    settings = get_settings()
    if not settings.worker_enabled:
        log.info("Worker disabled via WORKER_ENABLED=false")
        return
    if _task is not None and not _task.done():
        return
    _task = asyncio.create_task(_run(settings), name="duo-sync-poll-worker")
    log.info("Poll worker started (interval=%ss, apns=%s)",
             settings.worker_poll_interval, settings.apns_configured)


async def stop() -> None:
    global _task
    if _task is None:
        return
    _task.cancel()
    try:
        await _task
    except asyncio.CancelledError:
        pass
    _task = None


# ---------------------------------------------------------------------------
# Loop
# ---------------------------------------------------------------------------


async def _run(settings: Settings) -> None:
    while True:
        try:
            await _poll_once(settings)
        except asyncio.CancelledError:
            raise
        except Exception as exc:  # noqa: BLE001
            log.exception("Worker iteration failed: %s", exc)
        await asyncio.sleep(settings.worker_poll_interval)


async def _poll_once(settings: Settings) -> None:
    users = await _load_users()
    if not users:
        return
    # Fan out concurrently but cap parallelism so we don't crush Spotify
    # or our own DB.
    sem = asyncio.Semaphore(8)

    async def go(u: UserCreds) -> None:
        async with sem:
            await _poll_user(u, settings)

    await asyncio.gather(*(go(u) for u in users), return_exceptions=True)


# ---------------------------------------------------------------------------
# Per-user polling
# ---------------------------------------------------------------------------


async def _poll_user(creds: UserCreds, settings: Settings) -> None:
    # Refresh if access token has <60s left.
    if creds.expires_at <= dt.datetime.now(dt.timezone.utc) + dt.timedelta(seconds=60):
        try:
            refreshed = await spotify.refresh_access_token(
                creds.refresh_token_plain, settings.spotify_client_id
            )
        except spotify.SpotifyError as exc:
            log.warning("Refresh failed for user=%s: %s", creds.user_id, exc)
            return
        new_access = refreshed["access_token"]
        new_refresh = refreshed.get("refresh_token") or creds.refresh_token_plain
        new_expires = dt.datetime.now(dt.timezone.utc) + dt.timedelta(
            seconds=int(refreshed["expires_in"])
        )
        await _save_refreshed_tokens(creds.user_id, new_access, new_refresh, new_expires)
        creds.access_token = new_access
        creds.refresh_token_plain = new_refresh
        creds.expires_at = new_expires

    # Fetch currently playing.
    try:
        snap = await _fetch_currently_playing(creds.access_token)
    except spotify.SpotifyError as exc:
        # 204 No Content -> nothing playing; spotify.py raises only for ≥300.
        log.warning("currently-playing failed for user=%s: %s", creds.user_id, exc)
        return

    changed, change_seq = await _upsert_state(creds.user_id, snap)
    if changed:
        # Two delivery paths:
        #
        # 1) Supabase Realtime — happens AUTOMATICALLY because the
        #    upsert above is a Postgres row change and the
        #    now_playing_state table is in the supabase_realtime
        #    publication (see sql/0003_realtime.sql). Foreground iOS
        #    clients with an open WebSocket get the new row in <1s.
        #
        # 2) APNs silent push — wakes a backgrounded iOS app so it
        #    can refresh the widget without the user opening it.
        #    Requires a paid Apple Developer account ($99/yr) to
        #    generate a .p8 auth key. We soft-fail when missing.
        log.info("user=%s track changed (seq=%s) — Realtime auto-fires", creds.user_id, change_seq)

        # ---------- APNs (iOS, paid account only) --------------------
        tokens = await _device_tokens(creds.user_id)
        if tokens:
            sent = await apns.send_silent_push(
                tokens,
                payload={"seq": change_seq, "kind": "now_playing"},
            )
            if sent:
                log.info("user=%s APNs push delivered to %d device(s)", creds.user_id, sent)

        # ---------- Web Push (PWA / browser, free) -------------------
        web_subs = await _web_push_subs(creds.user_id)
        if web_subs and snap is not None:
            item = snap.get("item") or {}
            artists = item.get("artists") or []
            album = item.get("album") or {}
            images = album.get("images") or []
            payload = {
                "title": item.get("name") or "Now playing",
                "body": ", ".join(a.get("name", "") for a in artists),
                "icon": images[0]["url"] if images else None,
                "badge": images[0]["url"] if images else None,
                "data": {
                    "seq": change_seq,
                    "kind": "now_playing",
                    "user_id": creds.user_id,
                    "track_name": item.get("name"),
                    "url": "/",  # what to open when tapped
                },
            }
            sent = await web_push.send_push_to_many(web_subs, payload)
            if sent:
                log.info("user=%s WebPush delivered to %d subscription(s)", creds.user_id, sent)


async def _fetch_currently_playing(access_token: str) -> dict | None:
    async with httpx.AsyncClient(timeout=10) as client:
        r = await client.get(
            "https://api.spotify.com/v1/me/player/currently-playing",
            headers={"Authorization": f"Bearer {access_token}"},
        )
    if r.status_code == 204:
        return None
    if r.status_code >= 300:
        raise spotify.SpotifyError(r.status_code, r.text)
    return r.json()


# ---------------------------------------------------------------------------
# DB ops
# ---------------------------------------------------------------------------


async def _load_users() -> list[UserCreds]:
    settings = get_settings()
    async with db.pool().acquire() as conn:
        rows = await conn.fetch(
            """
            select user_id, access_token, refresh_token_enc, scope, expires_at
            from spotify_tokens
            """
        )
    out: list[UserCreds] = []
    for r in rows:
        try:
            refresh_plain = decrypt_token(r["refresh_token_enc"], settings)
        except Exception:  # noqa: BLE001
            log.warning("Could not decrypt refresh token for user=%s", r["user_id"])
            continue
        out.append(UserCreds(
            user_id=str(r["user_id"]),
            access_token=r["access_token"],
            refresh_token_plain=refresh_plain,
            expires_at=r["expires_at"],
            scope=r["scope"],
        ))
    return out


async def _save_refreshed_tokens(user_id: str, access: str, refresh: str, expires: dt.datetime) -> None:
    settings = get_settings()
    enc = encrypt_token(refresh, settings)
    async with db.pool().acquire() as conn:
        await conn.execute(
            """
            update spotify_tokens
               set access_token = $2,
                   refresh_token_enc = $3,
                   expires_at = $4,
                   updated_at = now()
             where user_id = $1
            """,
            user_id, access, enc, expires,
        )


async def _upsert_state(user_id: str, playing: dict | None) -> tuple[bool, int]:
    """Returns (changed, new_change_seq)."""
    if playing is None:
        track_id = None
        track_name = None
        artist_name = None
        album_name = None
        art_url = None
        is_playing = False
        progress_ms = None
        duration_ms = None
    else:
        item = playing.get("item") or {}
        track_id = item.get("id")
        track_name = item.get("name")
        artists = item.get("artists") or []
        artist_name = ", ".join(a.get("name", "") for a in artists)
        album = item.get("album") or {}
        album_name = album.get("name")
        images = album.get("images") or []
        art_url = images[0]["url"] if images else None
        is_playing = bool(playing.get("is_playing"))
        progress_ms = playing.get("progress_ms")
        duration_ms = item.get("duration_ms")

    async with db.pool().acquire() as conn:
        async with conn.transaction():
            existing = await conn.fetchrow(
                "select track_id, is_playing, change_seq from now_playing_state where user_id = $1",
                user_id,
            )
            changed = (
                existing is None
                or existing["track_id"] != track_id
                or existing["is_playing"] != is_playing
            )
            new_seq = (existing["change_seq"] + 1) if (existing and changed) else (
                1 if existing is None else existing["change_seq"]
            )
            await conn.execute(
                """
                insert into now_playing_state (
                    user_id, track_id, track_name, artist_name, album_name,
                    album_art_url, is_playing, progress_ms, duration_ms,
                    polled_at, change_seq
                ) values ($1,$2,$3,$4,$5,$6,$7,$8,$9, now(), $10)
                on conflict (user_id) do update set
                    track_id      = excluded.track_id,
                    track_name    = excluded.track_name,
                    artist_name   = excluded.artist_name,
                    album_name    = excluded.album_name,
                    album_art_url = excluded.album_art_url,
                    is_playing    = excluded.is_playing,
                    progress_ms   = excluded.progress_ms,
                    duration_ms   = excluded.duration_ms,
                    polled_at     = now(),
                    change_seq    = excluded.change_seq
                """,
                user_id, track_id, track_name, artist_name, album_name,
                art_url, is_playing, progress_ms, duration_ms, new_seq,
            )
    return changed, new_seq


async def _device_tokens(user_id: str) -> list[str]:
    async with db.pool().acquire() as conn:
        rows = await conn.fetch(
            "select apns_token from sessions where user_id = $1 and apns_token is not null",
            user_id,
        )
    return [r["apns_token"] for r in rows]


async def _web_push_subs(user_id: str) -> list[web_push.WebPushSubscription]:
    async with db.pool().acquire() as conn:
        rows = await conn.fetch(
            "select endpoint, p256dh, auth from web_push_subscriptions where user_id = $1",
            user_id,
        )
    return [
        web_push.WebPushSubscription(endpoint=r["endpoint"], p256dh=r["p256dh"], auth=r["auth"])
        for r in rows
    ]
