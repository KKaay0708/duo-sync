"""Thin wrapper around the Spotify Web API used by the backend.

The iOS app does PKCE OAuth on its own and ships us the tokens; we just
need to (a) fetch the user's /me profile right after sign-in, and (b)
refresh the access token when it expires (for the future poll worker).
"""

from __future__ import annotations

from typing import Any

import httpx

SPOTIFY_API = "https://api.spotify.com/v1"
SPOTIFY_TOKEN = "https://accounts.spotify.com/api/token"


class SpotifyError(RuntimeError):
    def __init__(self, status: int, body: str):
        super().__init__(f"Spotify HTTP {status}: {body[:300]}")
        self.status = status
        self.body = body


async def fetch_me(access_token: str) -> dict[str, Any]:
    async with httpx.AsyncClient(timeout=10) as client:
        r = await client.get(
            f"{SPOTIFY_API}/me",
            headers={"Authorization": f"Bearer {access_token}"},
        )
        if r.status_code >= 300:
            raise SpotifyError(r.status_code, r.text)
        return r.json()


async def refresh_access_token(refresh_token: str, client_id: str) -> dict[str, Any]:
    """Exchanges a refresh token for a new access token (PKCE: no secret)."""
    async with httpx.AsyncClient(timeout=10) as client:
        r = await client.post(
            SPOTIFY_TOKEN,
            data={
                "grant_type": "refresh_token",
                "refresh_token": refresh_token,
                "client_id": client_id,
            },
            headers={"Content-Type": "application/x-www-form-urlencoded"},
        )
        if r.status_code >= 300:
            raise SpotifyError(r.status_code, r.text)
        return r.json()
