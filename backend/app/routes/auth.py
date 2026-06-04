"""POST /auth/spotify — exchange Spotify tokens for a backend session JWT."""

from __future__ import annotations

import datetime as dt

from fastapi import APIRouter, Depends, HTTPException

from .. import db, spotify
from ..config import Settings, get_settings
from ..schemas import SessionOut, SpotifyAuthRequest, UserOut
from ..security import encrypt_token, issue_session_jwt

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/spotify", response_model=SessionOut)
async def sign_in_with_spotify(
    body: SpotifyAuthRequest,
    settings: Settings = Depends(get_settings),
) -> SessionOut:
    """Called by the iOS app right after it completes Spotify PKCE OAuth.

    Steps:
      1) Use the access_token to fetch the user's Spotify profile.
      2) Upsert that user into our `users` table.
      3) Encrypt the refresh token and persist alongside the access token.
      4) Issue a JWT the iOS app will use to call our other endpoints.
    """
    # 1) Profile from Spotify
    try:
        profile = await spotify.fetch_me(body.access_token)
    except spotify.SpotifyError as exc:
        raise HTTPException(401, f"Spotify rejected token: {exc}") from exc

    spotify_id = profile["id"]
    display_name = profile.get("display_name") or spotify_id
    email = profile.get("email")
    images = profile.get("images") or []
    avatar_url = images[0]["url"] if images else None

    expires_at = dt.datetime.now(dt.timezone.utc) + dt.timedelta(seconds=body.expires_in)
    encrypted_refresh = encrypt_token(body.refresh_token, settings)

    # 2 + 3) Upsert atomically
    async with db.pool().acquire() as conn:
        async with conn.transaction():
            user_row = await conn.fetchrow(
                """
                insert into users (spotify_id, display_name, email, avatar_url)
                values ($1, $2, $3, $4)
                on conflict (spotify_id) do update
                  set display_name = excluded.display_name,
                      email        = excluded.email,
                      avatar_url   = excluded.avatar_url,
                      updated_at   = now()
                returning id, spotify_id, display_name, email, avatar_url, created_at
                """,
                spotify_id, display_name, email, avatar_url,
            )
            await conn.execute(
                """
                insert into spotify_tokens (user_id, access_token, refresh_token_enc, scope, expires_at)
                values ($1, $2, $3, $4, $5)
                on conflict (user_id) do update
                  set access_token       = excluded.access_token,
                      refresh_token_enc  = excluded.refresh_token_enc,
                      scope              = excluded.scope,
                      expires_at         = excluded.expires_at,
                      updated_at         = now()
                """,
                user_row["id"], body.access_token, encrypted_refresh, body.scope, expires_at,
            )

    # 4) Session JWT
    session_token = issue_session_jwt(user_row["id"], settings)

    return SessionOut(
        session_token=session_token,
        user=UserOut(**dict(user_row)),
    )
